--[[---------------------------------------------------------------------------
Radios and voice (server).

Radio state per player: transmit channel, listened channels, push-to-talk.
A radio works when the holder carries a radio item allowed for the channel.
Range: inside the short range radios always work; beyond it both the sender's
and the receiver's sector need a working comms subsystem
(SiteVeil.Facility.subsystemHealth). Degraded comms garble text.

Voice: local proximity (cached spatial grid, rebuilt every
C.Voice.updateInterval) plus radio voice for players holding push-to-talk.
PlayerCanHearPlayersVoice only performs table lookups.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Comms = SV.Comms
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local Roles = SV.Roles
local Inv = SV.Inv

Comms.radio = Comms.radio or {}  -- ply -> {tx = id, listen = {[id] = true}, ptt = bool}

local function radioItemFor(ply, ch)
    if Inv.has(ply, ch.item) then return ch.item end
    return nil
end

--- Whether ply may transmit on / listen to a channel. Returns ok, reason.
function Comms.canUse(ply, ch, listenOnly)
    if not ch then return false, "неизвестный канал" end
    local char = ply.SVChar
    if not char or Roles.isSCP(ply) then return false, "нет рации" end
    local role = Roles.ofPlayer(ply)
    if not radioItemFor(ply, ch) then
        -- A Chaos radio can listen to intercepted channels.
        if listenOnly and Inv.has(ply, "radio_chaos") and U.contains(C.Radio.chaosIntercept, ch.id) then return true end
        return false, "нет подходящей рации"
    end
    if not Comms.roleAllowed(ch, role, char.division) then return false, "канал вам недоступен" end
    return true
end

function Comms.state(ply)
    local st = Comms.radio[ply]
    if not st then
        st = {listen = {}, ptt = false}
        Comms.radio[ply] = st
    end
    return st
end

function Comms.publish(ply)
    local st = Comms.state(ply)
    local channels = {}
    for _, ch in ipairs(C.Radio.channels) do
        local canTx = Comms.canUse(ply, ch)
        local canRx = canTx or Comms.canUse(ply, ch, true)
        if canRx then
            channels[#channels + 1] = {id = ch.id, name = ch.name, freq = ch.freq, tx = canTx, listen = st.listen[ch.id] == true}
        end
    end
    SV.Sync.setFor(ply, "self", "radio", {tx = st.tx, channels = channels, ptt = st.ptt})
end

--- Re-validates channels after a spawn or an inventory change. Default
--- channels are applied once per life, as soon as a suitable radio is held
--- (the kit may be issued after this hook runs).
function Comms.refresh(ply, newLife)
    local st = Comms.state(ply)
    if newLife then st.needDefaults = true end
    for id in pairs(st.listen) do
        if not Comms.canUse(ply, Comms.channels[id], true) then st.listen[id] = nil end
    end
    if st.needDefaults then
        local any = false
        for _, ch in ipairs(C.Radio.channels) do
            if ch.default and Comms.canUse(ply, ch) then
                st.listen[ch.id] = true
                any = true
            end
        end
        if any then st.needDefaults = nil end
    end
    if st.tx and not Comms.canUse(ply, Comms.channels[st.tx]) then st.tx = nil end
    if not st.tx then
        for _, ch in ipairs(C.Radio.channels) do
            if ch.id ~= "common" and Comms.canUse(ply, ch) then st.tx = ch.id break end
        end
        if not st.tx and Comms.canUse(ply, Comms.channels.common) then st.tx = "common" end
    end
    if st.ptt and not st.tx then st.ptt = false end
    Comms.publish(ply)
end

hook.Add("SiteVeil.RoleSpawn", "SiteVeil.Comms", function(ply) Comms.refresh(ply, true) end)
hook.Add("SiteVeil.InventoryChanged", "SiteVeil.Comms", function(ply) Comms.refresh(ply, false) end)
hook.Add("PlayerDisconnected", "SiteVeil.Comms", function(ply)
    Comms.radio[ply] = nil
    if Comms.broadcasting then Comms.broadcasting[ply] = nil end
end)
hook.Add("PlayerDeath", "SiteVeil.Comms", function(ply)
    local st = Comms.radio[ply]
    if st then st.ptt = false end
end)

--[[---------------------------------------------------------------------------
Infrastructure dependency
---------------------------------------------------------------------------]]
function Comms.sectorHealth(ply)
    local fac = SV.Facility
    if not fac or not fac.subsystemHealth then return 1 end
    local sector = fac.sectorOf and fac.sectorOf(ply)
    return fac.subsystemHealth(sector, "comms")
end

--- Quality of a link between two radios in [0, 1].
function Comms.linkQuality(from, to)
    if U.within(from, to, C.Radio.shortRange) then return 1 end
    return math.min(Comms.sectorHealth(from), Comms.sectorHealth(to))
end

--- Deterministic garbling: the same message is garbled the same way for the
--- same receiver so repeated reads do not reveal the original.
function Comms.garble(text, quality, seed)
    if quality >= C.Radio.garbleFrom then return text end
    if quality < C.Radio.silentBelow then return "*помехи*" end
    local loss = (C.Radio.garbleFrom - quality) / C.Radio.garbleFrom
    local out = {}
    local i = 0
    for word in string.gmatch(text, "%S+") do
        i = i + 1
        local h = U.hash(seed .. ":" .. i) % 1000 / 1000
        out[#out + 1] = h < loss and "…" or word
    end
    return table.concat(out, " ")
end

--[[---------------------------------------------------------------------------
Text transmissions
---------------------------------------------------------------------------]]
local msgCounter = 0

function Comms.transmit(ply, text, channelId)
    local st = Comms.state(ply)
    local ch = Comms.channels[channelId or st.tx or ""]
    if not ch then return false, "Канал не выбран (F4 → Связь)." end
    local ok, reason = Comms.canUse(ply, ch)
    if not ok then return false, "Рация: " .. reason .. "." end
    if Comms.sectorHealth(ply) < C.Radio.silentBelow then
        DarkRP.notify(ply, 3, 4, "Связь в секторе не работает: сообщение услышат только рядом (до " .. C.Radio.shortRange .. " ед.).")
    end
    msgCounter = msgCounter + 1
    local prefix = "[" .. ch.name .. "] " .. SV.Chars.displayName(ply)
    local col = SV.Comms.divisionColor(ply)
    local recipients = 0
    for _, other in ipairs(player.GetAll()) do
        if other.SVChar and other:Alive() then
            local ost = Comms.radio[other]
            if other == ply or (ost and ost.listen[ch.id] and Comms.canUse(other, ch, true)) then
                local q = other == ply and 1 or Comms.linkQuality(ply, other)
                local shown = Comms.garble(text, q, msgCounter .. ":" .. other:EntIndex())
                DarkRP.talkToPerson(other, col, prefix, Color(170, 220, 255), shown, ply)
                if other ~= ply then recipients = recipients + 1 end
            end
        end
    end
    -- People standing next to the speaker hear the spoken words.
    for _, other in ipairs(player.GetAll()) do
        if other ~= ply and other.SVChar and U.within(ply, other, C.Radio.localHearDistance) then
            local ost = Comms.radio[other]
            if not (ost and ost.listen[ch.id]) then
                DarkRP.talkToPerson(other, col, SV.Chars.displayName(ply) .. " (в рацию)", color_white, text, ply)
            end
        end
    end
    SV.Bus.emit("comms.radio", {ply = ply, channel = ch.id, text = text, recipients = recipients})
    SV.Audit.log("chat", "radio", ply, nil, {channel = ch.id, text = text})
    return true
end

--[[---------------------------------------------------------------------------
Radio settings
---------------------------------------------------------------------------]]
Net.handle("comms.channel", function(ply, id)
    local ch = Comms.channels[id]
    local ok, reason = Comms.canUse(ply, ch)
    if not ok then return false, "Канал недоступен: " .. tostring(reason) end
    local st = Comms.state(ply)
    st.tx = id
    st.listen[id] = true
    Comms.publish(ply)
    return true, "Передача на канале «" .. ch.name .. "»."
end)

Net.handle("comms.listen", function(ply, id, on)
    local ch = Comms.channels[id]
    if not ch then return false, "Неизвестный канал." end
    if on then
        local ok, reason = Comms.canUse(ply, ch, true)
        if not ok then return false, "Канал недоступен: " .. tostring(reason) end
    end
    Comms.state(ply).listen[id] = on or nil
    Comms.publish(ply)
end)

Net.handle("comms.ptt", function(ply, on)
    local st = Comms.state(ply)
    if on then
        local ch = Comms.channels[st.tx or ""]
        if not ch or not Comms.canUse(ply, ch) or not ply:Alive() then
            st.ptt = false
            return false, "Рация недоступна."
        end
    end
    if st.ptt ~= on then
        st.ptt = on
        if on then ply:EmitSound(C.Sounds.radioOn, 45) else ply:EmitSound(C.Sounds.radioOff, 45) end
        Comms.publish(ply)
    end
end)

--[[---------------------------------------------------------------------------
Voice
---------------------------------------------------------------------------]]
local canHearLocal = {}  -- listener -> talker -> true

-- Hearing is symmetric: each pair is traced once.
local function checkPair(p, o, pos, distSqr, done)
    if o == p or done[o] and done[o][p] ~= nil then return end
    local v, w = pos[p], pos[o]
    local hear = v:DistToSqr(w) <= distSqr
    if hear and C.Voice.roomCheck then
        hear = not util.TraceLine({start = v, endpos = w, mask = MASK_SOLID_BRUSHONLY}).Hit
    end
    done[p] = done[p] or {}
    done[p][o] = hear
    if hear then
        canHearLocal[p][o] = true
        canHearLocal[o][p] = true
    end
end

local function rebuildVoice()
    local cell = C.Voice.distance
    local distSqr = cell * cell
    local grid, pos, cells, done = {}, {}, {}, {}
    canHearLocal = {}
    for _, p in ipairs(player.GetHumans()) do
        if p:Alive() and p.SVChar then
            local v = p:EyePos()
            pos[p] = v
            local gx, gy = math.floor(v.x / cell), math.floor(v.y / cell)
            local key = gx .. ":" .. gy
            grid[key] = grid[key] or {}
            table.insert(grid[key], p)
            cells[p] = {gx, gy}
            canHearLocal[p] = {}
        end
    end
    for p in pairs(pos) do
        local gx, gy = cells[p][1], cells[p][2]
        for dx = -1, 1 do
            for dy = -1, 1 do
                for _, o in ipairs(grid[(gx + dx) .. ":" .. (gy + dy)] or {}) do
                    checkPair(p, o, pos, distSqr, done)
                end
            end
        end
    end
end
Comms.rebuildVoice = rebuildVoice

timer.Create("SiteVeil.Comms.Voice", C.Voice.updateInterval, 0, function()
    SV.Perf.time("comms.voice", rebuildVoice)
end)

local mute = {scp173 = true, scp096 = true}

--- Facility-wide voice broadcast (intercom and similar addons): talker is
--- heard by everybody with a character until untilTime (nil stops it).
Comms.broadcasting = Comms.broadcasting or {}
function Comms.setBroadcast(ply, untilTime)
    Comms.broadcasting[ply] = untilTime
end

function GM:PlayerCanHearPlayersVoice(listener, talker)
    if not talker:Alive() or not talker.SVChar or not listener.SVChar then return false end
    local b = Comms.broadcasting[talker]
    if b and CurTime() < b then return true, false end
    local role = Roles.ofPlayer(talker)
    if role and mute[role.id] then return false end
    local local_ = canHearLocal[listener]
    if local_ and local_[talker] then return true, true end
    local st = Comms.radio[talker]
    if st and st.ptt and st.tx then
        local lst = Comms.radio[listener]
        if lst and lst.listen[st.tx] and listener:Alive() then
            local q = Comms.linkQuality(talker, listener)
            if q >= C.Radio.silentBelow then return true, false end
        end
    end
    return false
end

SV.Perf.registry("comms.radios", function() return U.count(Comms.radio) end)

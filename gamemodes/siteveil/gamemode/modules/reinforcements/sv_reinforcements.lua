--[[---------------------------------------------------------------------------
Reinforcement waves (server).

Queue: players join with a character of the wave's division (from the
character screen while in the lobby, or MTF garrison on shift). A wave takes
up to `size` queued players in order, deploys them in the wave roles at the
reinforcement points of the wave's group (validated positions, role spawn
as fallback) and announces the arrival. MTF stand down after the facility
has been calm for recallAfter seconds; Chaos withdraws after its lifetime.
Wave members who die return to their base role (MTF garrison) or to the
character screen (Chaos).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Reinf = SV.Reinforcements
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local R = C.Reinforcements
local Roles = SV.Roles
local Chars = SV.Chars
local Facility = SV.Facility

Reinf.queue = Reinf.queue or {mtf = {}, chaos = {}}   -- kind -> list of {ply, charId, since}
Reinf.pending = Reinf.pending or {}                  -- kind -> {at, by}
Reinf.lastWave = Reinf.lastWave or {}                -- kind -> CurTime
Reinf.waves = Reinf.waves or {}                      -- kind -> count this shift
Reinf.members = Reinf.members or {}                  -- ply -> {kind, since}
Reinf.calmSince = Reinf.calmSince or nil

local function publish()
    local out = {}
    for kind, cfg in pairs(R) do
        out[kind] = {queued = #Reinf.queue[kind], pending = Reinf.pending[kind] and Reinf.pending[kind].at or nil,
            active = 0, name = cfg.name}
    end
    for _, m in pairs(Reinf.members) do out[m.kind].active = out[m.kind].active + 1 end
    SV.Sync.set("reinforcements", "waves", out)
end

local function queueIndex(kind, ply)
    for i, e in ipairs(Reinf.queue[kind]) do
        if e.ply == ply then return i end
    end
end

local function anyLockdown()
    for _, f in pairs(Facility.flags or {}) do
        if f.lockdown then return true end
    end
    return false
end

local function stateAllows(cfg)
    local st = Facility.stateId()
    if cfg.states[st] then return true end
    return cfg.states.lockdown == true and anyLockdown()
end

function Reinf.waveSize(kind)
    local s = R[kind].size
    return math.min(s.base + math.floor(U.onlineCount() / s.perPlayers), s.max)
end

--- Why a wave of kind cannot be sent now (nil = can).
function Reinf.blockedReason(kind)
    local cfg = R[kind]
    if not cfg then return "неизвестное подкрепление" end
    if Reinf.pending[kind] then return "подкрепление уже в пути" end
    if U.onlineCount() < cfg.minOnline then return "мало игроков на сервере" end
    if not stateAllows(cfg) then return "обстановка не требует подкрепления" end
    local last = Reinf.lastWave[kind]
    if last and CurTime() - last < cfg.cooldown then return "следующая группа через " .. U.formatDuration(cfg.cooldown - (CurTime() - last)) end
    if (Reinf.waves[kind] or 0) >= cfg.perShift then return "лимит групп за смену" end
    if #Reinf.queue[kind] == 0 then return "нет бойцов в очереди" end
    return nil
end

--[[---------------------------------------------------------------------------
Queue
---------------------------------------------------------------------------]]
Net.handle("reinf.queue", function(ply, kind, charId)
    local cfg = R[kind]
    if not cfg then return false, "Неизвестное подкрепление." end
    if queueIndex("mtf", ply) or queueIndex("chaos", ply) then return false, "Вы уже в очереди." end
    if Reinf.members[ply] then return false, "Вы уже в составе группы." end
    if ply.SVChar then
        -- On shift: only MTF garrison may queue with their current character.
        if ply.SVChar.division ~= cfg.division or Roles.ofPlayer(ply).reinforcement then return false, "Встаньте в очередь с экрана персонажей." end
        charId = ply.SVChar.id
    else
        local char = Chars.loadById(charId)
        if not char or char.steamid ~= ply:SteamID64() or char.division ~= cfg.division then return false, "Нужен персонаж подразделения «" .. cfg.name .. "»." end
        if Chars.active[charId] then return false, "Персонаж уже используется." end
    end
    table.insert(Reinf.queue[kind], {ply = ply, charId = charId, since = CurTime()})
    publish()
    return true, "Вы в очереди подкрепления (" .. #Reinf.queue[kind] .. ")."
end)

Net.handle("reinf.leave", function(ply)
    for kind in pairs(R) do
        local i = queueIndex(kind, ply)
        if i then
            table.remove(Reinf.queue[kind], i)
            publish()
            return true, "Вы вышли из очереди."
        end
    end
    return false, "Вы не в очереди."
end)

local function dropFromQueues(ply)
    for kind in pairs(R) do
        local i = queueIndex(kind, ply)
        if i then table.remove(Reinf.queue[kind], i) end
    end
end

--[[---------------------------------------------------------------------------
Deployment
---------------------------------------------------------------------------]]
local function arrivalPos(cfg, ply, i)
    local points = SV.MapCfg.findPoints("reinforcement", {group = cfg.group})
    if #points == 0 then return nil end
    local p = points[(i - 1) % #points + 1]
    local pos = DarkRP.findEmptyPos(SV.MapCfg.toVec(p.pos), {ply}, 300, 30, Vector(16, 16, 64))
    if SV.SCP.validDestination(pos) then return pos end
    return nil
end

local function deploy(kind)
    local cfg = R[kind]
    local pending = Reinf.pending[kind]
    Reinf.pending[kind] = nil
    if not stateAllows(cfg) and cfg.called then
        publish()
        return
    end
    local size = Reinf.waveSize(kind)
    local sent = {}
    local led = false
    while #sent < size and #Reinf.queue[kind] > 0 do
        local e = table.remove(Reinf.queue[kind], 1)
        local ply = e.ply
        if IsValid(ply) then
            -- The first member whose rank allows it leads the wave.
            local char = ply.SVChar or Chars.loadById(e.charId)
            local lead = Roles.get(cfg.roles.lead)
            local role = Roles.get(cfg.roles.member)
            if not led and char and char.rank >= lead.minRank then role = lead end
            local ok
            if ply.SVChar and ply.SVChar.id == e.charId then
                ok = Chars.canTakeRole(ply, role, {reinforcement = true, ignoreQuota = true}) and Chars.assignRole(ply, role, {reason = "reinforcement", reinforcement = true})
            elseif not ply.SVChar then
                ok = Chars.select(ply, e.charId, {role = role, reinforcement = true})
            end
            if ok and role == lead then led = true end
            if ok then
                if not ply:Alive() then ply:Spawn() end
                local pos = arrivalPos(cfg, ply, #sent + 1)
                if pos then ply:SetPos(pos) end
                Reinf.members[ply] = {kind = kind, since = CurTime()}
                sent[#sent + 1] = ply
                DarkRP.notify(ply, 0, 10, cfg.name .. ": вы прибыли на объект. " .. (kind == "mtf" and "Задача — восстановить содержание." or "Задача — добыть сведения и ресурсы."))
            end
        end
    end
    if #sent > 0 then
        Reinf.lastWave[kind] = CurTime()
        Reinf.waves[kind] = (Reinf.waves[kind] or 0) + 1
        if kind == "mtf" then
            Facility.announce("На объект прибыла группа " .. cfg.name .. " (" .. #sent .. " чел.).", nil, "info")
        else
            Facility.announce("Периметр: зафиксирован неопознанный транспорт.", nil, "alert")
        end
    end
    SV.Audit.log("reinforcements", "deploy", pending and pending.by, nil, {kind = kind, count = #sent})
    SV.Bus.emit("reinforcements.deployed", {kind = kind, count = #sent, by = pending and pending.by})
    publish()
end

function Reinf.call(kind, by)
    local why = Reinf.blockedReason(kind)
    if why then return false, "Подкрепление недоступно: " .. why .. "." end
    local cfg = R[kind]
    Reinf.pending[kind] = {at = CurTime() + cfg.delay, by = by}
    timer.Create("SiteVeil.Reinf." .. kind, cfg.delay, 1, function() deploy(kind) end)
    for _, e in ipairs(Reinf.queue[kind]) do
        if IsValid(e.ply) then DarkRP.notify(e.ply, 0, 8, cfg.name .. ": вылет через " .. cfg.delay .. " с.") end
    end
    SV.Audit.log("reinforcements", "call", by, nil, {kind = kind})
    publish()
    return true, cfg.name .. ": группа прибудет через " .. cfg.delay .. " с."
end

Net.handle("reinf.call", function(ply, kind)
    local cfg = R[kind]
    if not cfg or not cfg.called then return false, "Это подкрепление нельзя вызвать." end
    if not (Roles.hasFlag(ply, "callReinforcements") or SV.Admin.isOnDuty(ply)) then return false, "Нет полномочий вызывать подкрепление." end
    return Reinf.call(kind, ply)
end)

--[[---------------------------------------------------------------------------
Wave end
---------------------------------------------------------------------------]]
local function standDown(ply, reason)
    local m = Reinf.members[ply]
    if not m then return end
    Reinf.members[ply] = nil
    if not IsValid(ply) or not ply.SVChar then return end
    local cfg = R[m.kind]
    if m.kind == "mtf" then
        local base = Roles.get(Roles.getDivision("mtf").defaultRole)
        Chars.assignRole(ply, base, {system = true, reason = reason, respawn = ply:Alive()})
    else
        DarkRP.notify(ply, 3, 8, cfg.name .. ": ячейка покидает объект.")
        Chars.unload(ply, reason)
    end
    publish()
end
Reinf.standDown = standDown

hook.Add("PlayerDeath", "SiteVeil.Reinforcements", function(ply)
    if Reinf.members[ply] then
        timer.Simple(0, function() standDown(ply, "reinforcement death") end)
    end
end)

hook.Add("PlayerDisconnected", "SiteVeil.Reinforcements", function(ply)
    Reinf.members[ply] = nil
    dropFromQueues(ply)
    publish()
end)

-- Leaving the lobby with another character takes the player out of the queue.
hook.Add("SiteVeil.CharacterLoaded", "SiteVeil.Reinforcements", function(ply, char)
    for kind in pairs(R) do
        local i = queueIndex(kind, ply)
        if i and Reinf.queue[kind][i].charId ~= char.id then table.remove(Reinf.queue[kind], i) end
    end
end)

hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.Reinforcements", function(ply)
    Reinf.members[ply] = nil
end)

timer.Create("SiteVeil.Reinforcements", 5, 0, function()
    local calm = Facility.stateId() == "normal" or Facility.stateId() == "recovery"
    if calm then
        Reinf.calmSince = Reinf.calmSince or CurTime()
    else
        Reinf.calmSince = nil
    end
    for ply, m in pairs(Reinf.members) do
        local cfg = R[m.kind]
        if not IsValid(ply) then
            Reinf.members[ply] = nil
        elseif m.kind == "mtf" and Reinf.calmSince and CurTime() - Reinf.calmSince >= cfg.recallAfter then
            DarkRP.notify(ply, 0, 6, cfg.name .. ": обстановка стабилизирована, группа возвращается в гарнизон.")
            standDown(ply, "recall")
        elseif cfg.lifetime and CurTime() - m.since >= cfg.lifetime then
            standDown(ply, "withdraw")
        end
    end
end)

-- Chaos arrives on its own: at most once per shift, with a chance per breach/evacuation.
SV.Bus.on("facility.stateChanged", "reinforcements", function(data)
    local cfg = R.chaos
    if not cfg.states[data.to] then return end
    local rng = SV.RNG.new(SV.RNG.seedFor("chaos.wave", SV.Shift.id * 10 + (Reinf.waves.chaos or 0)))
    if not Reinf.blockedReason("chaos") and rng:chance(cfg.chance) then Reinf.call("chaos", nil) end
end)

SV.Bus.on("shift.started", "reinforcements", function()
    Reinf.waves = {}
end)

SV.Perf.registry("reinforcements.members", function() return U.count(Reinf.members) end)

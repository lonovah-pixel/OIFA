--[[---------------------------------------------------------------------------
Intercom (server).

A terminal of kind "intercom" (map point kind "terminal", terminal=intercom).
Voice: the speaker is heard by everyone on shift for voiceTime seconds while
staying at the terminal (Comms.setBroadcast). Text: an announcement in the
facility banner. Works only with power and a working comms subsystem in the
terminal's sector. Facility-wide and personal cooldowns; everything audited.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Intercom = SV.Intercom
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Intercom
local Facility = SV.Facility

Intercom.speaker = Intercom.speaker or nil   -- {ply, terminal, untilTime}
Intercom.lastAt = Intercom.lastAt or -1e9

local function publish()
    local s = Intercom.speaker
    SV.Sync.set("intercom", "air", s and {name = SV.Chars.displayName(s.ply), untilTime = s.untilTime} or nil)
end

--- Why ply cannot use the intercom at ent now (nil = can).
function Intercom.blockedReason(ply, ent)
    local ok, why = SV.Terminals.canUse(ply, ent, "intercom", true)
    if not ok then return why end
    local sector = Facility.sectorAt(ent:GetPos())
    if not Facility.subsystemOk(sector, "comms") then return "линии связи сектора неисправны" end
    if Intercom.speaker then return "эфир занят" end
    local now = CurTime()
    local admin = SV.Admin.isOnDuty(ply)
    if not admin and now - Intercom.lastAt < K.cooldown then
        return "эфир освободится через " .. math.ceil(K.cooldown - (now - Intercom.lastAt)) .. " с"
    end
    if not admin and ply.SVIntercomAt and now - ply.SVIntercomAt < K.personalCooldown then
        return "ваше следующее обращение через " .. math.ceil(K.personalCooldown - (now - ply.SVIntercomAt)) .. " с"
    end
    return nil
end

local function stop(reason)
    local s = Intercom.speaker
    if not s then return end
    Intercom.speaker = nil
    if IsValid(s.ply) then
        SV.Comms.setBroadcast(s.ply, nil)
        DarkRP.notify(s.ply, 0, 4, "Интерком: эфир завершён" .. (reason and (" (" .. reason .. ")") or "") .. ".")
    end
    publish()
end
Intercom.stop = stop

function Intercom.startVoice(ply, ent)
    local why = Intercom.blockedReason(ply, ent)
    if why then return false, "Интерком недоступен: " .. why .. "." end
    local now = CurTime()
    Intercom.speaker = {ply = ply, terminal = ent, untilTime = now + K.voiceTime}
    Intercom.lastAt = now
    ply.SVIntercomAt = now
    SV.Comms.setBroadcast(ply, now + K.voiceTime)
    Facility.announce("ИНТЕРКОМ: в эфире " .. SV.Chars.displayName(ply) .. ".", nil, "info")
    SV.Audit.log("intercom", "voice", ply, nil, {terminal = SV.Terminals.key(ent)})
    SV.Bus.emit("intercom.broadcast", {ply = ply, mode = "voice"})
    publish()
    return true, "Вы в эфире " .. K.voiceTime .. " с. Оставайтесь у терминала."
end

function Intercom.sendText(ply, ent, text)
    text = U.cleanText(text, K.textMax)
    if U.utf8len(text) < 3 then return false, "Текст обращения пуст." end
    local why = Intercom.blockedReason(ply, ent)
    if why then return false, "Интерком недоступен: " .. why .. "." end
    local now = CurTime()
    Intercom.lastAt = now
    ply.SVIntercomAt = now
    Facility.announce("ИНТЕРКОМ (" .. SV.Chars.displayName(ply) .. "): " .. text, nil, "info")
    SV.Audit.log("intercom", "text", ply, nil, {text = text})
    SV.Bus.emit("intercom.broadcast", {ply = ply, mode = "text", text = text})
    return true
end

Net.handle("intercom.voice", function(ply, ent) return Intercom.startVoice(ply, ent) end)
Net.handle("intercom.text", function(ply, ent, text) return Intercom.sendText(ply, ent, text) end)
Net.handle("intercom.stop", function(ply)
    if not Intercom.speaker or Intercom.speaker.ply ~= ply then return false, "Вы не в эфире." end
    stop()
    return true
end)

timer.Create("SiteVeil.Intercom", 0.5, 0, function()
    local s = Intercom.speaker
    if not s then return end
    if not IsValid(s.ply) or not s.ply:Alive() then
        stop("говорящий выбыл")
    elseif CurTime() >= s.untilTime then
        stop()
    elseif not IsValid(s.terminal) or not U.within(s.ply, s.terminal, K.stayRadius) then
        stop("вы отошли от терминала")
    elseif not Facility.subsystemOk(Facility.sectorAt(s.terminal:GetPos()), "comms") then
        stop("связь прервалась")
    end
end)

hook.Add("PlayerDisconnected", "SiteVeil.Intercom", function(ply)
    if Intercom.speaker and Intercom.speaker.ply == ply then stop() end
end)

Facility.registerTerminal("intercom", {
    name = "Интерком", req = {clearance = K.clearance, tags = K.tags}, power = 0.5,
    open = function(ply, ent)
        Net.send(ply, "intercom.open", {ent = ent:EntIndex(), blocked = Intercom.blockedReason(ply, ent), voiceTime = K.voiceTime,
            textMax = K.textMax})
    end,
})

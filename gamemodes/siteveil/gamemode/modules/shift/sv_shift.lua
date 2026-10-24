--[[---------------------------------------------------------------------------
Shift cycle (server).

Persistent: current shift id and its start time (sv_settings). After a restart
the running shift continues if it has not expired; otherwise a new one starts.
Emits bus event "shift.started" {id, previous} and "shift.ending" {id}.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Shift = SV.Shift
local C = SV.Config

local Settings = SV.Settings

local function publish()
    SV.Sync.set("shift", "id", Shift.id)
    SV.Sync.set("shift", "endsAt", Shift.endsAt)
    SV.Sync.set("shift", "length", C.Shift.length)
end

function Shift.start(reason)
    local previous = Shift.id
    Shift.id = previous + 1
    Shift.startedAt = os.time()
    Shift.endsAt = Shift.startedAt + C.Shift.length
    Shift.warned = false
    Settings.set("shift.id", Shift.id)
    Settings.set("shift.startedAt", Shift.startedAt)
    publish()
    SV.Log.info("смена %d начата (%s)", Shift.id, reason or "таймер")
    SV.Audit.log("system", "shift.start", nil, nil, {id = Shift.id, reason = reason})
    SV.Bus.emit("shift.started", {id = Shift.id, previous = previous})
    if previous > 0 then
        DarkRP.notifyAll(0, 8, "Началась новая смена №" .. Shift.id .. ". Лимиты задач и наград обновлены.")
    end
end

function Shift.init()
    Shift.id = tonumber(Settings.get("shift.id", 0)) or 0
    Shift.startedAt = tonumber(Settings.get("shift.startedAt", 0)) or 0
    Shift.endsAt = Shift.startedAt + C.Shift.length
    if Shift.id == 0 or os.time() >= Shift.endsAt then
        Shift.start(Shift.id == 0 and "первый запуск" or "смена истекла во время простоя")
    else
        publish()
        SV.Log.info("продолжается смена %d", Shift.id)
    end
end

hook.Add("SiteVeil.DatabaseReady", "SiteVeil.Shift", Shift.init)

timer.Create("SiteVeil.Shift", 5, 0, function()
    if Shift.id == 0 then return end
    local now = os.time()
    if not Shift.warned and now >= Shift.endsAt - C.Shift.warnBefore then
        Shift.warned = true
        SV.Bus.emit("shift.ending", {id = Shift.id})
        DarkRP.notifyAll(0, 8, "Смена завершится через " .. SV.Util.formatDuration(Shift.endsAt - now) .. ".")
    end
    if now >= Shift.endsAt then Shift.start("таймер") end
end)

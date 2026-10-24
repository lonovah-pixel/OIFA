--[[---------------------------------------------------------------------------
Diagnostics: timings of expensive operations, network counters and
registries of active objects. Exposed through `sv_perf` (server console /
admins) and the admin panel. Values are measurements of the running server,
nothing here is an estimate.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Perf = SV.Perf or {}
local Perf = SV.Perf

Perf.timings = Perf.timings or {}    -- name -> {count, total, max, windowCount, windowTotal}
Perf.counters = Perf.counters or {}  -- name -> {total, window}
Perf.registries = Perf.registries or {} -- name -> function() return count end
Perf.windowStart = Perf.windowStart or SysTime()
Perf.lastWindow = Perf.lastWindow or {}

function Perf.record(name, seconds)
    local t = Perf.timings[name]
    if not t then
        t = {count = 0, total = 0, max = 0, wCount = 0, wTotal = 0, wMax = 0}
        Perf.timings[name] = t
    end
    t.count = t.count + 1
    t.total = t.total + seconds
    if seconds > t.max then t.max = seconds end
    t.wCount = t.wCount + 1
    t.wTotal = t.wTotal + seconds
    if seconds > t.wMax then t.wMax = seconds end
end

--- Measures fn(...) and returns its results.
function Perf.time(name, fn, ...)
    local started = SysTime()
    local results = {fn(...)}
    Perf.record(name, SysTime() - started)
    return unpack(results)
end

function Perf.count(name, amount)
    local c = Perf.counters[name]
    if not c then
        c = {total = 0, window = 0}
        Perf.counters[name] = c
    end
    amount = amount or 1
    c.total = c.total + amount
    c.window = c.window + amount
end

--- Registers a function returning the number of active objects of a kind.
function Perf.registry(name, fn)
    Perf.registries[name] = fn
end

--- Closes the current measurement window (every 60 s) so per-minute rates
--- are available.
function Perf.rollWindow()
    local now = SysTime()
    local length = math.max(now - Perf.windowStart, 0.001)
    local snapshot = {length = length, timings = {}, counters = {}}
    for name, t in pairs(Perf.timings) do
        snapshot.timings[name] = {count = t.wCount, avgMs = t.wCount > 0 and t.wTotal / t.wCount * 1000 or 0, maxMs = t.wMax * 1000}
        t.wCount, t.wTotal, t.wMax = 0, 0, 0
    end
    for name, c in pairs(Perf.counters) do
        snapshot.counters[name] = {perSecond = c.window / length, window = c.window}
        c.window = 0
    end
    Perf.lastWindow = snapshot
    Perf.windowStart = now
end

function Perf.report()
    local lines = {}
    local w = Perf.lastWindow
    table.insert(lines, string.format("Окно измерений: %.0f с", w.length or 0))
    table.insert(lines, "-- Активные объекты")
    for _, name in ipairs(SV.Util.keys(Perf.registries)) do
        local ok, n = pcall(Perf.registries[name])
        table.insert(lines, string.format("  %-32s %s", name, ok and tostring(n) or "ошибка"))
    end
    table.insert(lines, "-- Длительность операций (последнее окно)")
    for _, name in ipairs(SV.Util.keys(w.timings or {})) do
        local t = w.timings[name]
        table.insert(lines, string.format("  %-32s n=%-6d avg=%.3f мс max=%.3f мс", name, t.count, t.avgMs, t.maxMs))
    end
    table.insert(lines, "-- Счётчики (последнее окно)")
    for _, name in ipairs(SV.Util.keys(w.counters or {})) do
        local c = w.counters[name]
        table.insert(lines, string.format("  %-32s %.2f/с (%d)", name, c.perSecond, c.window))
    end
    return lines
end

timer.Create("SiteVeil.Perf.Window", 60, 0, Perf.rollWindow)

if SERVER then
    concommand.Add("sv_perf", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        for _, line in ipairs(Perf.report()) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
    end)
end

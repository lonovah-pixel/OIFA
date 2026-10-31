--[[---------------------------------------------------------------------------
Drills (server).

Started by staff with declareAlert (or an admin on duty) in the normal
facility state, at most once per cooldown, on populated servers. Every
person on shift at the start takes part. "evac": reach any evac zone in
time; "muster": reach the checkpoint nearest to the organiser. Results are
announced; those who made it get experience. A real incident (state change,
SCP breach) cancels the drill without results.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Drills = SV.Drills
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Drills
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local Roles = SV.Roles

Drills.active = Drills.active or nil
Drills.lastAt = Drills.lastAt or -1e9

local function publish()
    local d = Drills.active
    SV.Sync.set("drill", "state", d and {kind = d.kind, name = K.kinds[d.kind].name, text = K.kinds[d.kind].text, endsAt = d.endsAt,
        pos = d.pos and {math.Round(d.pos.x), math.Round(d.pos.y), math.Round(d.pos.z)} or nil, total = U.count(d.people)} or nil)
end

local function authorized(ply)
    if SV.Admin.isOnDuty(ply) then return true end
    for _, f in ipairs(K.flags) do if Roles.hasFlag(ply, f) then return true end end
    return false
end

function Drills.blockedReason(kind, by)
    if not K.kinds[kind] then return "неизвестный вид учений" end
    if Drills.active then return "учения уже идут" end
    if Facility.stateId() ~= "normal" then return "комплекс не в штатном режиме" end
    if SV.SCP.anyBreached() then return "объект вне камеры" end
    if U.onlineCount() < K.minOnline then return "мало сотрудников на смене" end
    if CurTime() - Drills.lastAt < K.cooldown and not SV.Admin.isOnDuty(by) then
        return "следующие учения через " .. U.formatDuration(K.cooldown - (CurTime() - Drills.lastAt))
    end
    if kind == "evac" and #MapCfg.zones("evac") == 0 then return "на карте нет шлюзов эвакуации" end
    if kind == "muster" and #MapCfg.points("checkpoint") == 0 then return "на карте нет постов" end
    return nil
end

local function nearestCheckpoint(pos)
    local best, bestD
    for _, p in ipairs(MapCfg.points("checkpoint")) do
        local v = MapCfg.toVec(p.pos)
        local d = v:DistToSqr(pos)
        if not bestD or d < bestD then best, bestD = v, d end
    end
    return best
end

function Drills.start(kind, by)
    local why = Drills.blockedReason(kind, by)
    if why then return false, "Учения невозможны: " .. why .. "." end
    local def = K.kinds[kind]
    local people = {}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p.SVChar and not Roles.isSCP(p) and not Roles.isLobby(p) and p ~= by then people[p] = false end
    end
    Drills.active = {kind = kind, by = by, people = people, startedAt = CurTime(), endsAt = CurTime() + def.time,
        pos = kind == "muster" and nearestCheckpoint(by:GetPos()) or nil}
    Facility.announce("УЧЕБНАЯ ТРЕВОГА: " .. def.name .. ". " .. def.text .. " Время — " .. def.time .. " с.", "alarmLocal", "alert")
    SV.Audit.log("drills", "start", by, nil, {kind = kind, people = U.count(people)})
    publish()
    return true
end

local function reached(d, p)
    if d.kind == "evac" then return MapCfg.zoneAt(p:GetPos(), "evac") ~= nil end
    return p:GetPos():DistToSqr(d.pos) <= K.kinds.muster.radius * K.kinds.muster.radius
end

local function finish(cancelled, reason)
    local d = Drills.active
    if not d then return end
    Drills.active = nil
    Drills.lastAt = CurTime()
    publish()
    if cancelled then
        Facility.announce("Учения отменены: " .. reason .. ".", nil, "info")
        SV.Audit.log("drills", "cancel", nil, nil, {reason = reason})
        return
    end
    local total, ok, timeSum = 0, 0, 0
    for p, t in pairs(d.people) do
        if IsValid(p) then
            total = total + 1
            if t then
                ok = ok + 1
                timeSum = timeSum + t
                SV.Chars.addXP(p, K.xp, "task")
                SV.Net.send(p, "drill.result", {ok = true, seconds = math.Round(t)})
            else
                SV.Net.send(p, "drill.result", {ok = false})
            end
        end
    end
    if IsValid(d.by) and total > 0 and ok * 2 >= total then SV.Chars.addXP(d.by, K.leaderXP, "task") end
    Facility.announce(string.format("Учения завершены: успели %d из %d%s.", ok, total, ok > 0 and string.format(", среднее время %d с", math.Round(timeSum / ok)) or ""),
        nil, "info")
    SV.Audit.log("drills", "finish", d.by, nil, {ok = ok, total = total})
    SV.Bus.emit("drill.finished", {ply = d.by, ok = ok, total = total})
end
Drills.finish = finish

timer.Create("SiteVeil.Drills", 1, 0, function()
    local d = Drills.active
    if not d then return end
    if Facility.stateId() ~= "normal" or SV.SCP.anyBreached() then
        finish(true, "реальный инцидент")
        return
    end
    for p, t in pairs(d.people) do
        if IsValid(p) and p:Alive() and not t and reached(d, p) then
            d.people[p] = CurTime() - d.startedAt
            SV.Net.send(p, "drill.reached", {seconds = math.Round(d.people[p])})
        end
    end
    if CurTime() >= d.endsAt then finish(false) end
end)

Net.handle("drill.start", function(ply, kind)
    if not authorized(ply) then return false, "Учения объявляет командование." end
    return Drills.start(kind, ply)
end)

Net.handle("drill.cancel", function(ply)
    if not authorized(ply) then return false, "Нет полномочий." end
    if not Drills.active then return false, "Учения не идут." end
    finish(true, "решение " .. SV.Chars.displayName(ply))
    return true
end)

--[[---------------------------------------------------------------------------
"Директор напряжения" (server).

Every decisionInterval seconds the director may start one event from
C.DirectorEvents. It keeps a tension value fed by incidents (breaches,
injuries, alerts ...) and decaying over time; above tensionMax it waits.
Events are announced to the divisions that can solve them, show a task,
have a time limit, a reward on success and a consequence on failure. An
event is withdrawn without consequences when nobody who could solve it is
on shift any more. Choices use the seeded generator (reproducible).

Admin: sv_director 0|1, admin panel (toggle, per-event switches, force,
cancel). Every start and end is written to sv_director_log and the audit.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Director = SV.Director
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local D = C.Director
local Roles = SV.Roles
local Facility = SV.Facility
local MapCfg = SV.MapCfg

Director.defs = {}
for _, e in ipairs(C.DirectorEvents) do Director.defs[e.id] = e end

Director.active = Director.active or {}       -- run id -> run
Director.lastStart = Director.lastStart or {}  -- event id -> CurTime
Director.tension = Director.tension or 0
Director.nextDecision = Director.nextDecision or nil
Director.lastAny = Director.lastAny or -1e9
Director.runs = Director.runs or 0

local enabledConvar = CreateConVar("sv_director", "1", FCVAR_ARCHIVE, "SITE-VEIL: tension director (0 = off)")

DB.registerMigrations("director", {
    {1, "director log", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_director_log (id INTEGER PRIMARY KEY AUTOINCREMENT, event TEXT NOT NULL,
            sector TEXT, started_at INTEGER NOT NULL, ended_at INTEGER, outcome TEXT, solvers TEXT, seed INTEGER)]])
    end},
})

--[[---------------------------------------------------------------------------
Switches
---------------------------------------------------------------------------]]
function Director.enabled()
    return D.enabled and enabledConvar:GetBool() and SV.Settings.get("director.enabled", true) ~= false
end

function Director.eventEnabled(id)
    local off = SV.Settings.get("director.disabled", {})
    return not (istable(off) and off[id])
end

function Director.setEventEnabled(id, on)
    local off = SV.Settings.get("director.disabled", {})
    if not istable(off) then off = {} end
    off[id] = (not on) or nil
    SV.Settings.set("director.disabled", off)
end

--[[---------------------------------------------------------------------------
Tension
---------------------------------------------------------------------------]]
for event, amount in pairs(D.tension) do
    SV.Bus.on(event, "director.tension", function(data)
        if event == "facility.alertChanged" and data and data.on == false then return end
        Director.tension = math.min(Director.tension + amount, 100)
    end)
end

--[[---------------------------------------------------------------------------
Context and solvers
---------------------------------------------------------------------------]]
local function onShift(p)
    return IsValid(p) and p:Alive() and p.SVChar ~= nil and not Roles.isSCP(p) and not Roles.isLobby(p)
end

local function canSolve(p, def)
    if not onShift(p) then return false end
    for _, s in ipairs(def.solvers) do
        if s.flag and Roles.hasFlag(p, s.flag) then return true end
        if s.division and p.SVChar.division == s.division then return true end
    end
    return false
end
Director.canSolve = canSolve

local function solverCount(def)
    -- Any one solver group satisfied is enough.
    for _, s in ipairs(def.solvers) do
        local n = 0
        for _, p in ipairs(player.GetAll()) do
            if onShift(p) and ((s.flag and Roles.hasFlag(p, s.flag)) or (s.division and p.SVChar.division == s.division)) then n = n + 1 end
        end
        if n >= (s.min or 1) then return true end
    end
    return false
end
Director.hasSolvers = solverCount

local function buildContext()
    local ctx = {online = U.onlineCount(), divisions = {}, anyBreached = SV.SCP.anyBreached(), state = Facility.stateId()}
    for _, p in ipairs(player.GetAll()) do
        if onShift(p) then ctx.divisions[p.SVChar.division] = (ctx.divisions[p.SVChar.division] or 0) + 1 end
    end
    return ctx
end

local function sectorBusy(sector)
    for _, run in pairs(Director.active) do
        if sector and run.sector == sector then return true end
    end
    return false
end

--- Why an event cannot start now (nil when it can).
function Director.blockedReason(def, ctx, ignoreTiming)
    if not Director.eventEnabled(def.id) then return "отключено" end
    if ctx.online < math.max(def.minOnline or 0, D.minOnline) then return "мало игроков" end
    for _, run in pairs(Director.active) do
        if run.def.id == def.id then return "уже идёт" end
    end
    if not ignoreTiming then
        local last = Director.lastStart[def.id]
        if last and CurTime() - last < def.cooldown then return "перезарядка" end
    end
    if not solverCount(def) then return "некому решить" end
    if def.condition and not def.condition(ctx) then return "условие не выполнено" end
    return nil
end

--[[---------------------------------------------------------------------------
Event kinds: prepare (choose target), apply (effect after warning),
check (solved?), fail (consequence)
---------------------------------------------------------------------------]]
local kinds = {}

local function pickPoint(run, kinds_, preferDivision)
    local list = {}
    for _, kind in ipairs(kinds_) do
        for _, p in ipairs(MapCfg.points(kind)) do
            local pos = MapCfg.toVec(p.pos)
            local sector = Facility.sectorAt(pos)
            if not sectorBusy(sector) then list[#list + 1] = {pos = pos, sector = sector, id = p.id} end
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.id < b.id end)
    if preferDivision then
        -- Points closest to players of that division first.
        local best, bestD
        for _, c in ipairs(list) do
            for _, pl in ipairs(player.GetAll()) do
                if onShift(pl) and pl.SVChar.division == preferDivision then
                    local d = pl:GetPos():DistToSqr(c.pos)
                    if not bestD or d < bestD then best, bestD = c, d end
                end
            end
        end
        if best then return best end
    end
    return list[run.rng:int(1, #list)]
end

kinds.fault = {
    prepare = function(run)
        local candidates = {}
        for _, sub in ipairs(run.def.params.subsystems) do
            for _, n in ipairs(Facility.nodesIn(nil, sub)) do
                if n.health >= 70 and not n.fault and not sectorBusy(n.sector) then candidates[#candidates + 1] = n end
            end
        end
        if #candidates == 0 then return false end
        local n = candidates[run.rng:int(1, #candidates)]
        run.node = n
        run.sector = n.sector
        run.pos = n.pos
        return true
    end,
    apply = function(run)
        Facility.damageNode(run.node, run.def.params.damage, run.def.params.fault, "director")
        Facility.recompute()
    end,
    check = function(run)
        return run.node.health >= 90 and not run.node.fault
    end,
    fail = function(run)
        local f = run.def.fail or {}
        if f.damage then
            Facility.damageNode(run.node, f.damage, f.fault, "director")
            Facility.recompute()
        end
    end,
}

kinds.containment = {
    prepare = function(run)
        local list = {}
        for id, st in pairs(SV.SCP.state) do
            if not st.breached and (st.stage == "stable" or st.stage == "signs") and not sectorBusy(SV.SCP.cellSector(id)) then list[#list + 1] = id end
        end
        table.sort(list)
        if #list == 0 then return false end
        run.scp = list[run.rng:int(1, #list)]
        run.sector = SV.SCP.cellSector(run.scp)
        run.pos = SV.SCP.cellCenter(run.scp)
        run.taskText = run.def.text .. " (" .. SV.SCP.defs[run.scp].name .. ")"
        return true
    end,
    apply = function(run)
        SV.SCP.adjustIntegrity(run.scp, run.def.params.integrity, "director")
        local ply = SV.SCP.playerOf(run.scp)
        if ply then DarkRP.notify(ply, 0, 8, "Вы ощущаете слабину в условиях содержания.") end
    end,
    check = function(run) return run.solvedBy ~= nil end,
    success = function(run) SV.SCP.adjustIntegrity(run.scp, run.def.params.recover, "director") end,
    fail = function(run) SV.SCP.adjustIntegrity(run.scp, run.def.params.failIntegrity, "director") end,
}

kinds.callout = {
    prepare = function(run)
        local c = pickPoint(run, run.def.params.points, run.def.params.preferDivision)
        if not c then return false end
        run.pos, run.sector = c.pos, c.sector
        run.progress = 0
        return true
    end,
    apply = function() end,
    tick = function(run)
        local near
        for _, p in ipairs(player.GetAll()) do
            if canSolve(p, run.def) and p:GetPos():DistToSqr(run.pos) <= D.calloutRadius * D.calloutRadius then
                near = p
                break
            end
        end
        if near then
            run.progress = run.progress + D.tick
            run.helpers[near] = true
        end
    end,
    check = function(run) return run.progress >= run.def.params.hold end,
    fail = function(run)
        local f = run.def.fail or {}
        if f.alert and run.sector then Facility.setAlert(run.sector, nil, true, run.def.name) end
        if f.budget then SV.Supply.adjustBudget(f.budgetDivision, f.budget, "Директор: " .. run.def.name, nil, true) end
    end,
}

-- Events defined by addons: def.custom = {prepare(run) -> bool, apply(run),
-- check(run) -> bool, tick(run), success(run), fail(run)}; run.sector and
-- run.pos are set by prepare.
kinds.custom = {
    prepare = function(run) return run.def.custom.prepare(run) end,
    apply = function(run) if run.def.custom.apply then run.def.custom.apply(run) end end,
    tick = function(run) if run.def.custom.tick then run.def.custom.tick(run) end end,
    check = function(run) return run.def.custom.check(run) == true end,
    success = function(run) if run.def.custom.success then run.def.custom.success(run) end end,
    fail = function(run) if run.def.custom.fail then run.def.custom.fail(run) end end,
}

--- Adds an event to the catalogue (addons). Same fields as config/sv_director.lua.
function Director.registerEvent(def)
    assert(isstring(def.id) and kinds[def.kind], "director event needs an id and a known kind")
    if Director.defs[def.id] then
        for i, e in ipairs(C.DirectorEvents) do
            if e.id == def.id then table.remove(C.DirectorEvents, i) break end
        end
    end
    def.solvers = def.solvers or {}
    def.cooldown = def.cooldown or 1200
    def.duration = def.duration or 300
    def.weight = def.weight or 1
    table.insert(C.DirectorEvents, def)
    Director.defs[def.id] = def
end

kinds.supply = {
    prepare = kinds.callout.prepare,
    apply = function() end,
    tick = kinds.callout.tick,
    check = kinds.callout.check,
    success = function(run)
        for _, s in ipairs(run.def.params.stock) do SV.Supply.addStock(s[1], s[2], s[3]) end
    end,
}

--[[---------------------------------------------------------------------------
Publishing and lifecycle
---------------------------------------------------------------------------]]
local function publish()
    local list = {}
    for id, run in pairs(Director.active) do
        local divs = {}
        for _, s in ipairs(run.def.solvers) do divs[#divs + 1] = s.division or s.flag end
        list[#list + 1] = {
            id = id, name = run.def.name, text = run.taskText or run.def.text, solvers = divs, warning = run.phase == "warn",
            pos = run.pos and {math.Round(run.pos.x, -1), math.Round(run.pos.y, -1), math.Round(run.pos.z, -1)} or nil,
            endsAt = run.endsAt, progress = run.percent or (run.progress and run.def.params and run.def.params.hold and math.floor(run.progress / run.def.params.hold * 100)) or nil,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    SV.Sync.set("director", "events", list)
end

local function notifySolvers(def, text, kind)
    for _, p in ipairs(player.GetAll()) do
        if canSolve(p, def) then DarkRP.notify(p, kind or 3, 8, text) end
    end
end

local function finish(run, outcome)
    Director.active[run.id] = nil
    local def = run.def
    local solvers = {}
    if outcome == "success" then
        local k = kinds[def.kind]
        if k.success then k.success(run) end
        local reward = def.reward or {}
        local people = {}
        for p in pairs(run.helpers) do
            if IsValid(p) and p.SVChar then people[#people + 1] = p end
        end
        for _, p in ipairs(people) do
            solvers[#solvers + 1] = p.SVChar.name
            if reward.xp then SV.Chars.addXP(p, reward.xp, D.xpSource) end
        end
        if reward.budget and reward.division then SV.Supply.adjustBudget(reward.division, reward.budget, "Директор: " .. def.name) end
        notifySolvers(def, def.name .. ": задача выполнена.", 0)
    elseif outcome == "failed" then
        local k = kinds[def.kind]
        if k.fail then k.fail(run) end
        notifySolvers(def, def.name .. ": время вышло. " .. ((def.fail and def.fail.text) or "Последствия наступили."), 1)
    elseif outcome == "withdrawn" then
        notifySolvers(def, def.name .. ": задача снята.", 3)
    end
    DB.query("UPDATE sv_director_log SET ended_at = ?, outcome = ?, solvers = ? WHERE id = ?", os.time(), outcome, DB.encode(solvers), run.logId)
    SV.Audit.log("director", "end", nil, nil, {event = def.id, outcome = outcome, solvers = solvers})
    SV.Bus.emit("director.ended", {event = def.id, outcome = outcome, run = run.id})
    publish()
end
Director.finish = finish

--- Starts an event. force skips timing and tension checks (admin).
function Director.start(id, force)
    local def = Director.defs[id]
    if not def then return false, "Неизвестное событие." end
    local ctx = buildContext()
    local why = Director.blockedReason(def, ctx, force)
    if why then return false, "Событие недоступно: " .. why .. "." end
    if not force and #U.keys(Director.active) >= D.maxActive then return false, "Достигнут предел одновременных событий." end
    Director.runs = Director.runs + 1
    local seed = SV.RNG.seedFor("director", Director.runs)
    local run = {id = Director.runs, def = def, rng = SV.RNG.new(seed), seed = seed, helpers = {}, startedAt = CurTime()}
    if not kinds[def.kind].prepare(run) then return false, "Нет подходящего места для события." end
    run.phase = (def.warn or 0) > 0 and "warn" or "active"
    run.applyAt = CurTime() + (def.warn or 0)
    run.endsAt = run.applyAt + def.duration
    DB.query("INSERT INTO sv_director_log (event, sector, started_at, seed) VALUES (?, ?, ?, ?)", def.id, run.sector, os.time(), seed)
    run.logId = DB.lastInsertId()
    Director.active[run.id] = run
    Director.lastStart[def.id] = CurTime()
    Director.lastAny = CurTime()
    if run.phase == "warn" then
        notifySolvers(def, "Предупреждение: " .. def.warnText, 3)
    else
        kinds[def.kind].apply(run)
        notifySolvers(def, def.name .. ": " .. (run.taskText or def.text), 1)
    end
    SV.Audit.log("director", "start", nil, nil, {event = def.id, sector = run.sector, seed = seed, forced = force or nil})
    SV.Bus.emit("director.started", {event = def.id, run = run.id, sector = run.sector})
    publish()
    return true, "Событие запущено: " .. def.name .. "."
end

local function tickRun(run)
    local now = CurTime()
    local def = run.def
    local k = kinds[def.kind]
    if not solverCount(def) then
        finish(run, "withdrawn")
        return
    end
    if run.phase == "warn" then
        if now >= run.applyAt then
            run.phase = "active"
            k.apply(run)
            notifySolvers(def, def.name .. ": " .. (run.taskText or def.text), 1)
            publish()
        end
        return
    end
    if k.tick then k.tick(run) end
    if k.check(run) then
        finish(run, "success")
    elseif now >= run.endsAt then
        finish(run, "failed")
    elseif k.tick then
        publish()
    end
end

-- Containment events are solved by an inspection or a procedure.
local function containmentAction(data)
    for _, run in pairs(Director.active) do
        if run.def.kind == "containment" and run.phase == "active" and data.scp == run.scp and IsValid(data.ply) then
            run.solvedBy = data.ply
            run.helpers[data.ply] = true
        end
    end
end
SV.Bus.on("containment.inspected", "director", containmentAction)
SV.Bus.on("containment.procedure", "director", containmentAction)

-- Repairs count the engineer as the solver of a fault event.
SV.Bus.on("node.repaired", "director", function(data)
    for _, run in pairs(Director.active) do
        if run.node == data.node and IsValid(data.ply) then run.helpers[data.ply] = true end
    end
end)

local function decide()
    local now = CurTime()
    if not Director.nextDecision then Director.nextDecision = now + D.firstDelay end
    if now < Director.nextDecision then return end
    Director.nextDecision = now + D.decisionInterval
    if not Director.enabled() then return end
    if #U.keys(Director.active) >= D.maxActive then return end
    if now - Director.lastAny < D.globalCooldown then return end
    if Director.tension >= D.tensionMax then return end
    local ctx = buildContext()
    local weights = {}
    for _, def in ipairs(C.DirectorEvents) do
        if not Director.blockedReason(def, ctx) then
            -- Calm facility: livelier events are more likely.
            weights[def.id] = def.weight * (1 + (D.tensionMax - Director.tension) / D.tensionMax)
        end
    end
    local rng = SV.RNG.new(SV.RNG.seedFor("director.decision", math.floor(now)))
    local pick = rng:weighted(weights)
    if pick then Director.start(pick) end
end

timer.Create("SiteVeil.Director", D.tick, 0, function()
    SV.Perf.time("director.tick", function()
        for _, run in pairs(Director.active) do tickRun(run) end
        decide()
    end)
end)

timer.Create("SiteVeil.Director.Tension", 10, 0, function()
    Director.tension = math.max(Director.tension - D.tensionDecay, 0)
end)

SV.Bus.on("shift.started", "director", function()
    Director.nextDecision = CurTime() + D.firstDelay
end)

--[[---------------------------------------------------------------------------
Admin interface
---------------------------------------------------------------------------]]
function Director.statusView()
    local ctx = buildContext()
    local events = {}
    for _, def in ipairs(C.DirectorEvents) do
        local last = Director.lastStart[def.id]
        events[#events + 1] = {id = def.id, name = def.name, kind = def.kind, enabled = Director.eventEnabled(def.id),
            blocked = Director.blockedReason(def, ctx), cooldownLeft = last and math.max(math.ceil(def.cooldown - (CurTime() - last)), 0) or 0}
    end
    local active = {}
    for id, run in pairs(Director.active) do
        active[#active + 1] = {id = id, name = run.def.name, phase = run.phase, sector = run.sector, left = math.max(math.ceil(run.endsAt - CurTime()), 0)}
    end
    local history = DB.query("SELECT event, sector, started_at, outcome FROM sv_director_log ORDER BY id DESC LIMIT 15") or {}
    for _, h in ipairs(history) do
        h.when = U.clockString(tonumber(h.started_at))
        h.name = Director.defs[h.event] and Director.defs[h.event].name or h.event
        h.started_at = nil
    end
    return {enabled = Director.enabled(), convar = enabledConvar:GetBool(), tension = math.Round(Director.tension), events = events, active = active,
        history = history, nextIn = Director.nextDecision and math.max(math.ceil(Director.nextDecision - CurTime()), 0) or nil}
end

local function adminOk(ply)
    if not SV.Admin.can(ply, "SiteVeil_Admin") then return false, "Нет прав." end
    return true
end

Net.handle("director.status", function(ply)
    local ok, why = adminOk(ply)
    if not ok then return false, why end
    Net.send(ply, "director.status", Director.statusView())
end)

Net.handle("director.toggle", function(ply, on)
    local ok, why = adminOk(ply)
    if not ok then return false, why end
    SV.Settings.set("director.enabled", on)
    SV.Audit.log("admin", "director.toggle", ply, nil, {on = on})
    if not on then
        for _, run in pairs(Director.active) do finish(run, "withdrawn") end
    end
    Net.send(ply, "director.status", Director.statusView())
    return true, on and "Директор включён." or "Директор выключен, активные события сняты."
end)

Net.handle("director.event", function(ply, id, on)
    local ok, why = adminOk(ply)
    if not ok then return false, why end
    if not Director.defs[id] then return false, "Неизвестное событие." end
    Director.setEventEnabled(id, on)
    SV.Audit.log("admin", "director.event", ply, nil, {event = id, on = on})
    Net.send(ply, "director.status", Director.statusView())
    return true
end)

Net.handle("director.force", function(ply, id)
    local ok, why = adminOk(ply)
    if not ok then return false, why end
    SV.Audit.log("admin", "director.force", ply, nil, {event = id})
    local started, msg = Director.start(id, true)
    Net.send(ply, "director.status", Director.statusView())
    return started, msg
end)

Net.handle("director.cancel", function(ply, runId)
    local ok, why = adminOk(ply)
    if not ok then return false, why end
    local run = Director.active[runId]
    if not run then return false, "Событие не найдено." end
    SV.Audit.log("admin", "director.cancel", ply, nil, {event = run.def.id})
    finish(run, "withdrawn")
    Net.send(ply, "director.status", Director.statusView())
    return true
end)

SV.Perf.registry("director.active", function() return U.count(Director.active) end)

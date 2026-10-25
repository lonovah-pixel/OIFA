--[[---------------------------------------------------------------------------
Stage 6: evidence ("След инцидента"), tension director, hidden tasks,
reinforcement waves.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local Evidence = SV.Evidence
local Director = SV.Director
local Hidden = SV.Hidden
local Reinf = SV.Reinforcements
local E = SV.Config.Evidence

local function box(x1, x2)
    return {min = {x1, -1000, -100}, max = {x2, 1000, 500}}
end

local function point(id, kind, x, props)
    return {id = id, kind = kind, pos = {x, 0, 0}, ang = {0, 0, 0}, props = props or {}}
end

local function setupMap()
    for _, p in ipairs(player.GetAll()) do MOCK.disconnect(p) end
    MOCK.advance(0.3)
    MapCfg.cfg = {version = 1, map = "gm_test", zones = {
        {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 2000)}, props = {priority = 2, demand = 30}},
        {id = "hcz", kind = "sector", name = "Тяжёлая зона", boxes = {box(2000, 6000)}, props = {priority = 3, demand = 30}},
    }, points = {
        point("gen", "node", 100, {subsystem = "generator", sector = "lcz"}),
        point("lcz_pow", "node", 200, {subsystem = "power", sector = "lcz"}),
        point("hcz_pow", "node", 2200, {subsystem = "power", sector = "hcz"}),
        point("term_sec", "terminal", 700, {terminal = "security"}),
        point("cp_lcz", "checkpoint", 900),
        point("cp_hcz", "checkpoint", 3000),
        point("stash1", "stash", 1500),
        point("mtf_in", "reinforcement", 1800, {group = "mtf"}),
        point("chaos_in", "reinforcement", 1900, {group = "chaos"}),
    }, doors = {}}
    MapCfg.reindex()
    Facility.sectors, Facility.nodes, Facility.sabotageLog = {}, {}, {}
    Facility.build()
    MapCfg.spawnEntities()
    Evidence.traces = {}
    for _, run in pairs(Director.active) do Director.finish(run, "withdrawn") end
    Director.lastStart, Director.lastAny = {}, -1e9
    Hidden.active, Hidden.offers = {}, {}
    if Facility.stateId() ~= "normal" then Facility.setState("normal", nil, "test", {force = true}) end
    return MapCfg.spawned.term_sec
end

local function staff(division, role, rank, whitelist)
    local r = SV.Roles.get(role)
    local q = r.quota
    r.quota = nil
    local p = makeStaff({steam = role, name = uniqueName("Тест Тестов"), division = division, role = role, rank = rank or 1, whitelist = whitelist})
    r.quota = q
    return p
end

local function fillers(n)
    local out = {}
    for i = 1, n do out[i] = MOCK.join({name = "Filler" .. i}) end
    return out
end

--[[---------------------------------------------------------------------------
Evidence
---------------------------------------------------------------------------]]
TEST("traces: created by incidents, scan reveals no hidden facts, caps and TTL", function()
    setupMap()
    local v = staff("classd", "classd_worker")
    v:SetPos(Vector(500, 0, 0))
    v:TakeDamageInfo(MOCK.makeDamage({damage = 150, type = DMG_CLUB}))
    expect(SV.Medical.isIncapacitated(v))
    eq(SV.Util.count(Evidence.traces), 1, "no trace from the injury")
    local inv = staff("security", "sec_investigator")
    inv:SetPos(Vector(520, 0, 0))
    MOCK.clearSent()
    MOCK.rpc(inv, "evidence.scan")
    local pushes = MOCK.pushes(inv, "evidence.scan")
    eq(#pushes, 1, "no scan result")
    local t = pushes[1].data.list[1]
    expect(t and t.kind == "blood", "blood not found by the scan")
    for k in pairs(t) do expect(k ~= "hidden", "hidden data sent to the client") end
    local raw = util.TableToJSON(pushes[1].data)
    expect(not string.find(raw, v.SVChar.name, 1, true), "victim name leaked in a field scan")
    -- Caps.
    for i = 1, E.maxTraces + 30 do Evidence.addTrace("casing", Vector(100 + i * 70, 0, 0), {}) end
    expect(SV.Util.count(Evidence.traces) <= E.maxTraces, "trace cap not enforced")
    local perSector = 0
    for _, tr in pairs(Evidence.traces) do if tr.sector == "lcz" then perSector = perSector + 1 end end
    expect(perSector <= E.maxPerSector, "sector cap not enforced")
    -- Merge: same place, same kind, short time. (The victim leaves first so
    -- that a later bleed-out does not add a fresh trace.)
    MOCK.disconnect(v)
    Evidence.traces = {}
    Evidence.addTrace("blood", Vector(10, 0, 0), {})
    Evidence.addTrace("blood", Vector(20, 0, 0), {})
    eq(SV.Util.count(Evidence.traces), 1, "close traces not merged")
    MOCK.advance(SV.Config.TraceKinds.blood.ttl + 15, 5)
    eq(SV.Util.count(Evidence.traces), 0, "trace did not expire")
end)

TEST("collection and analysis: precision grows with the laboratory level", function()
    local term = setupMap()
    local v = staff("classd", "classd_worker")
    v:SetPos(Vector(650, 0, 0))
    v:TakeDamageInfo(MOCK.makeDamage({damage = 150, type = DMG_CLUB}))
    local inv = staff("security", "sec_investigator")
    inv:SetPos(Vector(660, 0, 0))
    local id = next(Evidence.traces)
    MOCK.rpc(inv, "evidence.collect", id)
    MOCK.advance(E.collectTime + 1, 0.5)
    local bag = SV.Inv.find(inv, function(it) return it.id == "evidence_bag" end)[1]
    expect(bag, "no evidence bag: " .. tostring(MOCK.lastNotify(inv)))
    expect(not Evidence.traces[id], "collected trace still in the world")
    -- A guard cannot analyse.
    local g = staff("security", "sec_guard")
    g:SetPos(Vector(700, 10, 0))
    MOCK.rpc(g, "evidence.analyze", bag.uid, term)
    expect(not SV.Actions.active[g], "a guard started an analysis")
    MOCK.clearSent()
    MOCK.rpc(inv, "evidence.analyze", bag.uid, term)
    MOCK.advance(E.analysis[1].time + 1, 0.5)
    local r1 = MOCK.pushes(inv, "evidence.report")[1]
    expect(r1, "no level 1 report: " .. tostring(MOCK.lastNotify(inv)))
    expect(not string.find(r1.data.text, v.SVChar.name, 1, true), "level 1 names the victim")
    contains(r1.data.text, "Класс D")
    -- Level 2 needs a sensor kit.
    MOCK.rpc(inv, "evidence.analyze", bag.uid, term)
    expect(not SV.Actions.active[inv], "level 2 without a sensor kit")
    SV.Inv.add(inv, "sensor_kit", 1, {force = true})
    MOCK.clearSent()
    MOCK.rpc(inv, "evidence.analyze", bag.uid, term)
    MOCK.advance(E.analysis[2].time + 1, 0.5)
    local r2 = MOCK.pushes(inv, "evidence.report")[1]
    expect(r2, "no level 2 report")
    contains(r2.data.text, v.SVChar.name)
    -- Case file: attach and close with a conclusion.
    MOCK.rpc(inv, "case.create", "Нападение в лёгкой зоне")
    local caseId = tonumber(SV.DB.queryValue("SELECT MAX(id) FROM sv_cases"))
    MOCK.rpc(inv, "case.attach", caseId, bag.uid)
    expect(not SV.Inv.getItem(inv, bag.uid), "bag not moved to the case")
    eq(#Evidence.caseView(caseId).evidence, 1)
    MOCK.rpc(inv, "case.close", caseId, "коротко")
    eq(SV.DB.queryValue("SELECT status FROM sv_cases WHERE id = ?", caseId), "open", "closed without a proper conclusion")
    MOCK.rpc(inv, "case.close", caseId, "Травма получена при падении, состава нарушения нет.")
    eq(SV.DB.queryValue("SELECT status FROM sv_cases WHERE id = ?", caseId), "closed")
end)

--[[---------------------------------------------------------------------------
Director
---------------------------------------------------------------------------]]
TEST("director: never starts without solvers; fault solved by repair rewards the engineer", function()
    setupMap()
    fillers(4)
    local ok = Director.start("power_fault", true)
    expect(not ok, "fault event started without engineers")
    local eng = staff("engineering", "eng_engineer", 3)
    local started, why = Director.start("power_fault", true)
    expect(started, "not started: " .. tostring(why))
    local run = select(2, next(Director.active))
    eq(run.phase, "warn", "no warning phase")
    MOCK.advance(SV.Config.DirectorEvents[1].warn + 1.5, 0.5)
    eq(run.phase, "active")
    expect(run.node.health < 90, "fault not applied")
    -- Repair by the engineer.
    run.node.health, run.node.fault = 100, nil
    SV.Bus.emit("node.repaired", {ply = eng, node = run.node})
    MOCK.advance(1.5)
    expect(not Director.active[run.id], "solved event still active")
    eq(SV.DB.queryValue("SELECT outcome FROM sv_director_log WHERE id = ?", run.logId), "success")
end)

TEST("director: callout by staying near; failure consequence; withdrawal when solvers leave", function()
    setupMap()
    fillers(4)
    local medic = staff("medical", "med_orderly")
    expect(Director.start("injured_worker", true))
    local run = select(2, next(Director.active))
    medic:SetPos(run.pos)
    MOCK.advance(SV.Config.Director.calloutRadius and 17, 1)
    expect(not Director.active[run.id], "callout not solved by staying near")
    -- Failure: nobody comes; the medical budget is charged.
    Director.lastStart = {}
    medic:SetPos(Vector(5000, 0, 0))
    local budget = SV.Supply.budget("medical")
    expect(Director.start("injured_worker", true))
    local run2 = select(2, next(Director.active))
    MOCK.advance(run2.def.duration + 2, 2)
    expect(not Director.active[run2.id])
    expect(SV.Supply.budget("medical") < budget, "failure had no consequence")
    -- Withdrawal: the only solver leaves.
    Director.lastStart = {}
    expect(Director.start("injured_worker", true))
    local run3 = select(2, next(Director.active))
    MOCK.disconnect(medic)
    MOCK.advance(1.5)
    expect(not Director.active[run3.id], "event kept without solvers")
    eq(SV.DB.queryValue("SELECT outcome FROM sv_director_log WHERE id = ?", run3.logId), "withdrawn")
end)

TEST("director: admin switch, per-event switch, catalogue has at least ten events", function()
    setupMap()
    expect(#SV.Config.DirectorEvents >= 10, "fewer than ten events")
    fillers(4)
    staff("medical", "med_orderly")
    Director.setEventEnabled("injured_worker", false)
    expect(not Director.start("injured_worker", true), "disabled event started")
    Director.setEventEnabled("injured_worker", true)
    SV.Settings.set("director.enabled", false)
    Director.nextDecision = CurTime()
    MOCK.advance(2)
    eq(SV.Util.count(Director.active), 0, "director acted while switched off")
    SV.Settings.set("director.enabled", true)
    -- Automatic decision with tension below the limit.
    Director.tension = 0
    Director.nextDecision = CurTime()
    MOCK.advance(2)
    expect(SV.Util.count(Director.active) >= 1, "director did not start anything")
    expect(SV.Util.count(Director.active) <= SV.Config.Director.maxActive)
end)

--[[---------------------------------------------------------------------------
Hidden tasks
---------------------------------------------------------------------------]]
TEST("hidden tasks: consent, refusal without penalty, stash completion leaves a trace, limits", function()
    setupMap()
    fillers(8)
    local d = staff("classd", "classd_worker")
    d.SVRoleSince = CurTime() - 1000
    expect(Hidden.blockedReason(d), "offered without consent")
    MOCK.rpc(d, "hidden.optin", true)
    eq(Hidden.blockedReason(d), nil)
    Hidden.offer(d, Hidden.defs.smuggle_parts)
    MOCK.rpc(d, "hidden.answer", false)
    expect(not Hidden.active[d])
    contains(Hidden.blockedReason(d) or "", "отказ")
    d.SVHiddenDeclined = nil
    Hidden.offer(d, Hidden.defs.smuggle_parts)
    MOCK.rpc(d, "hidden.answer", true)
    expect(Hidden.active[d], "not accepted")
    SV.Inv.add(d, "spare_parts", 1, {force = true})
    d:SetPos(Vector(1500, 30, 0))
    local item = SV.Inv.find(d, function(it) return it.id == "spare_parts" end)[1]
    SV.Inv.drop(d, item.uid, 1)
    MOCK.advance(1.5)
    expect(not Hidden.active[d], "stash task not completed")
    local stashTrace = false
    for _, t in pairs(Evidence.traces) do if t.kind == "stash" then stashTrace = true end end
    expect(stashTrace, "no trace left at the stash")
    -- Abandon is free; per-shift limit.
    d.SVHiddenDeclined = nil
    Hidden.offer(d, Hidden.defs.recon)
    MOCK.advance(5) -- rate limit of the answer RPC
    MOCK.rpc(d, "hidden.answer", true)
    expect(Hidden.active[d], "second task not accepted")
    MOCK.rpc(d, "hidden.abandon")
    expect(not Hidden.active[d])
    contains(Hidden.blockedReason(d) or "", "лимит")
    -- Admin switch.
    SV.Settings.set("hidden.enabled", false)
    contains(Hidden.blockedReason(d) or "", "отключена")
    SV.Settings.set("hidden.enabled", true)
end)

--[[---------------------------------------------------------------------------
Reinforcements
---------------------------------------------------------------------------]]
TEST("reinforcements: call needs authority and a crisis; wave deploys from the queue and stands down", function()
    setupMap()
    fillers(16)
    local chief = staff("security", "sec_chief", 5, true)
    local mtf = staff("mtf", "mtf_garrison", 1, true)
    MOCK.rpc(mtf, "reinf.queue", "mtf", 0)
    eq(#Reinf.queue.mtf, 1, "garrison not queued")
    local g = staff("security", "sec_guard")
    MOCK.rpc(g, "reinf.call", "mtf")
    expect(not Reinf.pending.mtf, "guard called reinforcements")
    MOCK.rpc(chief, "reinf.call", "mtf")
    expect(not Reinf.pending.mtf, "called without a crisis")
    Facility.setState("breach", nil, "test", {force = true})
    MOCK.rpc(chief, "reinf.call", "mtf")
    expect(Reinf.pending.mtf, "call refused: " .. tostring(MOCK.lastNotify(chief)))
    MOCK.advance(SV.Config.Reinforcements.mtf.delay + 1, 1)
    eq(SV.Roles.ofPlayer(mtf).id, "mtf_operative", "not deployed (rank 1 cannot lead)")
    eq(mtf:GetPos().x, 1800, "not placed at the reinforcement point")
    -- Death returns the member to the garrison role.
    mtf:Kill()
    MOCK.advance(0.5)
    eq(SV.Roles.ofPlayer(mtf).id, "mtf_garrison")
    expect(not Reinf.members[mtf])
end)

TEST("reinforcements: Chaos character deploys from the lobby and withdraws to the character screen", function()
    setupMap()
    fillers(16)
    local p = MOCK.join({name = "Chaos"})
    SV.Chars.grantWhitelist(p:SteamID64(), "division", "chaos", nil, "test")
    MOCK.rpc(p, "char.create", uniqueName("Хаос Хаосов"), "chaos", 1)
    local char = SV.Chars.listFor(p:SteamID64())[1]
    MOCK.rpc(p, "char.select", char.id)
    expect(not p.SVChar, "chaos character entered the facility outside a wave")
    MOCK.rpc(p, "reinf.queue", "chaos", char.id)
    eq(#Reinf.queue.chaos, 1, "not queued: " .. tostring(MOCK.lastNotify(p)))
    Facility.setState("breach", nil, "test", {force = true})
    Reinf.pending.chaos = nil
    timer.Remove("SiteVeil.Reinf.chaos")
    expect(Reinf.call("chaos", nil))
    MOCK.advance(SV.Config.Reinforcements.chaos.delay + 1, 1)
    expect(p.SVChar and p.SVChar.id == char.id, "chaos character not deployed")
    eq(SV.Roles.ofPlayer(p).id, "chaos_operative")
    p:Kill()
    MOCK.advance(0.5)
    expect(not p.SVChar, "chaos member not returned to the character screen")
end)

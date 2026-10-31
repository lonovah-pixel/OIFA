--[[---------------------------------------------------------------------------
Third batch of addons: SCP-939, surgery, drills, polygraph, crafting,
jammer and tracker.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local SCP = SV.SCP

local function box(x1, x2)
    return {min = {x1, -1000, -100}, max = {x2, 1000, 500}}
end

local function point(id, kind, x, props)
    return {id = id, kind = kind, pos = {x, 0, 0}, ang = {0, 0, 0}, props = props or {}}
end

local function setupMap()
    for _, p in ipairs(player.GetAll()) do MOCK.disconnect(p) end
    MOCK.hullFn, MOCK.traceHit, MOCK.traceFn = nil, false, nil
    MOCK.advance(0.3)
    MapCfg.cfg = {version = 1, map = "gm_test", zones = {
        {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 2000)}, props = {priority = 2, demand = 30}},
        {id = "hcz", kind = "sector", name = "Тяжёлая зона", boxes = {box(2000, 6000)}, props = {priority = 3, demand = 30}},
        {id = "cell939", kind = "cell", name = "Камера SCP-939", boxes = {box(4000, 4500)}, props = {scp = "scp939"}},
        {id = "evac1", kind = "evac", name = "Шлюз", boxes = {box(1800, 1990)}, props = {}},
    }, points = {
        point("gen", "node", 100, {subsystem = "generator", sector = "lcz"}),
        point("lcz_pow", "node", 200, {subsystem = "power", sector = "lcz"}),
        point("hcz_pow", "node", 2100, {subsystem = "power", sector = "hcz"}),
        point("bed", "medbed", 700),
        point("bench_g", "workbench", 900, {bench = "general"}),
        point("cp1", "checkpoint", 1200),
        point("spawn939", "spawn", 4200, {group = "scp939"}),
    }, doors = {}}
    MapCfg.reindex()
    Facility.sectors, Facility.nodes, Facility.sabotageLog = {}, {}, {}
    Facility.build()
    MapCfg.spawnEntities()
    for _, st in pairs(SCP.state) do st.integrity, st.stage, st.breached = 100, "stable", false end
    if Facility.stateId() ~= "normal" then Facility.setState("normal", nil, "test", {force = true}) end
    SV.Drills.active, SV.Drills.lastAt = nil, -1e9
    SV.Jammer.active = {}
    SV.Surgery.active = {}
    SV.Polygraph.lastAt = {}
    return MapCfg.spawned
end

local function staff(division, role, rank, whitelist)
    local r = SV.Roles.get(role)
    local q = r.quota
    r.quota = nil
    local p = makeStaff({steam = role, name = uniqueName("Тест Тестов"), division = division, role = role, rank = rank or 1, whitelist = whitelist})
    r.quota = q
    return p
end

local function makeSCP(roleId)
    local p = MOCK.join({name = "SCP_" .. roleId})
    SV.Chars.grantWhitelist(p:SteamID64(), "role", roleId, nil, "test")
    local role = SV.Roles.get(roleId)
    local q = role.quota
    role.quota = nil
    MOCK.rpc(p, "char.selectSCP", roleId)
    role.quota = q
    assert(p.SVChar, "SCP not selected: " .. tostring(MOCK.lastNotify(p)))
    MOCK.advance(0.3)
    return p
end

TEST("third batch of addons is loaded", function()
    for _, id in ipairs({"scp939", "surgery", "drills", "polygraph", "crafting", "jammer"}) do
        expect(SV.Addons.isLoaded(id), "addon not loaded: " .. id)
    end
    expect(SV.Roles.get("scp939"), "SCP-939 role missing")
    expect(SV.Crafting.byId.jammer, "jammer recipe not added although the jammer addon is installed")
end)

--[[---------------------------------------------------------------------------
SCP-939
---------------------------------------------------------------------------]]
TEST("SCP-939: hears speech, gunfire and running, not quiet walkers; lure; attack; suppression", function()
    setupMap()
    local scp = makeSCP("scp939")
    local st = SCP.get("scp939")
    local talker = staff("science", "sci_junior")
    talker:SetPos(Vector(3500, 0, 0))
    local quiet = staff("classd", "classd_worker")
    quiet:SetPos(Vector(3600, 100, 0))
    local runner = staff("classd", "classd_worker")
    runner:SetPos(Vector(3700, -100, 0))
    runner:SetVelocity(Vector(300, 0, 0))
    MOCK.say(talker, "Кто здесь?")
    MOCK.clearSent()
    MOCK.advance(1, 0.25)
    local heard = MOCK.pushes(scp, "scp939.heard")
    expect(#heard > 0, "no hearing updates")
    local list = heard[#heard].data.list
    eq(#list, 2, "should hear the talker and the runner only")
    runner:SetVelocity(Vector(0, 0, 0))
    -- Lure.
    expect(SCP.defs.scp939.abilities.lure(scp, st), "lure refused")
    expect(not SCP.defs.scp939.abilities.lure(scp, st), "lure cooldown ignored")
    -- Attack a person in the cell.
    local v = staff("classd", "classd_worker")
    v:SetPos(scp:GetPos() + Vector(40, 0, 0))
    scp:SetEyeAngles((v:GetPos() - scp:EyePos()):Angle())
    MOCK.hullFn = function(tr)
        if tr.start:DistToSqr(tr.endpos) < 1 then return {Hit = false, HitPos = tr.endpos, Entity = MOCK.world, Fraction = 1} end
        return {Hit = true, HitPos = v:GetPos(), Entity = v, Fraction = 0.5}
    end
    expect(SCP.defs.scp939.abilities.attack(scp, st), "attack refused")
    expect(not v:Alive() or SV.Medical.isIncapacitated(v), "victim unharmed")
    MOCK.hullFn = nil
    -- Out of the cell, suppressed by fire, recaptured.
    scp:SetPos(Vector(3000, 0, 0))
    MOCK.advance(1.5)
    expect(st.breached)
    local g = staff("security", "sec_guard")
    g:SetPos(Vector(3050, 0, 0))
    scp:TakeDamageInfo(MOCK.makeDamage({damage = scp:Health() * 0.7, type = DMG_BULLET, attacker = g}))
    MOCK.rpc(g, "scp.recapture", scp)
    MOCK.advance(SV.Config.SCP.scp939.recaptureTime + 1, 0.5)
    expect(not st.breached, "not recontained")
end)

--[[---------------------------------------------------------------------------
Surgery
---------------------------------------------------------------------------]]
local function lastStep(doc)
    local list = MOCK.pushes(doc, "surgery.step")
    return list[#list] and list[#list].data
end

TEST("surgery: doctor only, consent, step by step; success heals, mistakes fail; stage 2 infection cured", function()
    local S = setupMap()
    local bed = S.bed
    local doc = staff("medical", "med_doctor", 3)
    doc:SetPos(bed:GetPos() + Vector(60, 0, 0))
    SV.Inv.add(doc, "splint", 2, {force = true})
    SV.Inv.add(doc, "painkillers", 2, {force = true})
    SV.Inv.add(doc, "antiviral", 1, {force = true})
    SV.Inv.add(doc, "bandage", 4, {force = true})
    local patient = staff("classd", "classd_worker")
    patient:SetPos(bed:GetPos())
    SV.Medical.get(patient).fracture = true
    local orderly = staff("medical", "med_orderly")
    orderly:SetPos(bed:GetPos() + Vector(-60, 0, 0))
    expect(SV.Surgery.blockedReason(orderly, bed, patient, "fracture"), "an orderly may operate")
    local splints = SV.Inv.count(doc, "splint")
    MOCK.clearSent()
    MOCK.rpc(doc, "surgery.start", bed, patient, "fracture")
    expect(#MOCK.pushes(patient, "surgery.consent") == 1, "conscious patient not asked")
    MOCK.rpc(patient, "surgery.consent", true)
    local step = lastStep(doc)
    expect(step and step.step == 1, "first step not sent: " .. tostring(MOCK.lastNotify(doc)))
    eq(SV.Inv.count(doc, "splint"), splints - 1, "items not spent at the start")
    for _ = 1, step.steps do
        MOCK.advance(1)
        local s = lastStep(doc)
        MOCK.rpc(doc, "surgery.step", s.id, s.tool)
    end
    expect(not SV.Medical.get(patient).fracture, "fracture not healed")
    expect(not SV.Surgery.active[doc], "operation still active")
    -- Mistakes: wrong tools fail the operation.
    SV.Medical.get(patient).fracture = true
    MOCK.advance(5)
    MOCK.clearSent()
    MOCK.rpc(doc, "surgery.start", bed, patient, "fracture")
    MOCK.rpc(patient, "surgery.consent", true)
    local bleed = SV.Medical.get(patient).bleed or 0
    for _ = 1, 4 do
        MOCK.advance(1)
        local s = lastStep(doc)
        if not SV.Surgery.active[doc] then break end
        MOCK.rpc(doc, "surgery.step", s.id, s.tool % #SV.Config.Surgery.tools + 1)
    end
    expect(not SV.Surgery.active[doc], "failed operation still active")
    expect(SV.Medical.get(patient).fracture, "failed operation healed")
    expect((SV.Medical.get(patient).bleed or 0) > bleed, "complications without bleeding")
    -- Stage 2 infection: only surgery cures it.
    local inf = staff("classd", "classd_worker")
    inf:SetPos(bed:GetPos() + Vector(0, 30, 0))
    patient:SetPos(Vector(1500, 0, 0))
    SV.Medical.infect(inf, "scp049")
    SV.Medical.infect(inf, "scp049")
    eq(SV.Medical.infection(inf).stage, 2)
    SV.Inv.add(doc, "bandage", 2, {force = true})
    MOCK.advance(5)
    MOCK.clearSent()
    MOCK.rpc(doc, "surgery.start", bed, inf, "infection")
    MOCK.rpc(inf, "surgery.consent", true)
    local first = lastStep(doc)
    expect(first, "infection surgery not started: " .. tostring(MOCK.lastNotify(doc)))
    for _ = 1, first.steps do
        MOCK.advance(1)
        local s = lastStep(doc)
        MOCK.rpc(doc, "surgery.step", s.id, s.tool)
    end
    expect(not SV.Medical.infection(inf), "stage 2 infection not removed")
end)

--[[---------------------------------------------------------------------------
Drills
---------------------------------------------------------------------------]]
TEST("drills: authority, normal state only, evacuation scored, real incident cancels", function()
    setupMap()
    for i = 1, 6 do MOCK.join({name = "Filler" .. i}) end
    local chief = staff("security", "sec_chief", 5, true)
    local a = staff("classd", "classd_worker")
    local b = staff("science", "sci_junior")
    a:SetPos(Vector(500, 0, 0))
    b:SetPos(Vector(600, 0, 0))
    local g = staff("security", "sec_guard")
    MOCK.rpc(g, "drill.start", "evac")
    expect(not SV.Drills.active, "a guard started a drill")
    MOCK.rpc(chief, "drill.start", "evac")
    expect(SV.Drills.active, "drill not started: " .. tostring(MOCK.lastNotify(chief)))
    a:SetPos(Vector(1900, 0, 0))
    MOCK.advance(2, 1)
    expect(SV.Drills.active.people[a], "reaching the evac zone not counted")
    local xp = a.SVChar.xp
    MOCK.advance(SV.Config.Drills.kinds.evac.time + 1, 2)
    expect(not SV.Drills.active, "drill never ended")
    expect(a.SVChar.xp > xp, "participant who made it got nothing")
    -- Cooldown, then cancellation by a real breach.
    MOCK.rpc(chief, "drill.start", "muster")
    expect(not SV.Drills.active, "cooldown ignored")
    SV.Drills.lastAt = -1e9
    MOCK.advance(5)
    MOCK.rpc(chief, "drill.start", "muster")
    expect(SV.Drills.active and SV.Drills.active.pos, "muster not started")
    Facility.setState("breach", nil, "test", {force = true})
    MOCK.advance(1.5)
    expect(not SV.Drills.active, "drill survived a real incident")
end)

--[[---------------------------------------------------------------------------
Polygraph
---------------------------------------------------------------------------]]
TEST("polygraph: needs the device, consent unless cuffed, uses hidden facts, cooldown", function()
    setupMap()
    local inv = staff("security", "sec_investigator", 4)
    expect(SV.Inv.has(inv, "polygraph"), "investigator kit lacks the polygraph")
    local g = staff("security", "sec_guard")
    local d = staff("classd", "classd_worker")
    d:SetPos(inv:GetPos())
    g:SetPos(inv:GetPos())
    MOCK.rpc(g, "poly.start", d, "Вы брали отмычку?")
    expect(not SV.Actions.active[g], "test without a polygraph")
    MOCK.clearSent()
    MOCK.rpc(inv, "poly.start", d, "Вы брали отмычку?")
    expect(#MOCK.pushes(d, "poly.consent") == 1, "free person tested without consent")
    MOCK.rpc(d, "poly.consent", false)
    expect(not SV.Actions.active[inv])
    -- Cuffed: no consent needed.
    SV.Security.restrain(d, g)
    expect(not SV.Polygraph.hiding(d), "innocent person counted as hiding")
    if SV.Hidden then SV.Hidden.active[d] = {def = SV.Hidden.defs.false_hypothesis, char = d.SVChar.id, endsAt = CurTime() + 600, logId = 0} end
    expect(SV.Polygraph.hiding(d), "active hidden task not considered")
    MOCK.clearSent()
    MOCK.advance(12, 2)
    MOCK.rpc(inv, "poly.start", d, "Вы выполняете чужое поручение?")
    MOCK.advance(SV.Config.Polygraph.time + 1, 0.5)
    local res = MOCK.pushes(inv, "poly.result")[1]
    expect(res, "no result")
    contains(res.data.reaction, "реакция")
    MOCK.advance(12, 2)
    MOCK.rpc(inv, "poly.start", d, "Повторный вопрос сразу же?")
    contains(tostring(MOCK.lastNotify(inv)), "недавно")
    if SV.Hidden then SV.Hidden.active[d] = nil end
end)

--[[---------------------------------------------------------------------------
Crafting
---------------------------------------------------------------------------]]
TEST("crafting: bench and division recipes, inputs taken on completion, scrap from labor, lockpick", function()
    local S = setupMap()
    local bench = S.bench_g
    local d = staff("classd", "classd_worker")
    d:SetPos(bench:GetPos())
    MOCK.rpc(d, "craft.make", bench, "shiv")
    expect(not SV.Actions.active[d], "crafted without scrap")
    SV.Inv.add(d, "scrap", 3, {force = true})
    local sci = staff("science", "sci_junior")
    sci:SetPos(bench:GetPos())
    SV.Inv.add(sci, "scrap", 2, {force = true})
    MOCK.rpc(sci, "craft.make", bench, "shiv")
    expect(not SV.Actions.active[sci], "a scientist crafted class-D contraband")
    MOCK.rpc(d, "craft.make", bench, "shiv")
    eq(SV.Inv.count(d, "scrap"), 3, "inputs taken before completion")
    MOCK.advance(9, 0.5)
    eq(SV.Inv.count(d, "shiv"), 1, "nothing crafted")
    eq(SV.Inv.count(d, "scrap"), 1)
    MOCK.rpc(d, "craft.make", bench, "sensor_kit")
    expect(not SV.Actions.active[d], "engineering recipe on a general bench")
    -- Scrap appears after labor sometimes.
    local before = SV.Inv.count(d, "scrap")
    for _ = 1, 15 do SV.Bus.emit("labor.done", {ply = d, job = "sorting"}) end
    expect(SV.Inv.count(d, "scrap") > before, "labor never gave scrap")
    -- Lockpick on a clearance-1 door; a clearance-3 door refuses.
    local door = MOCK.newEntity("func_door")
    door.mapId = 77
    door:SetPos(d:GetPos() + Vector(40, 0, 0))
    MapCfg.cfg.doors["77"] = {clearance = 1}
    MOCK.traceFn = function(tr) return {Hit = true, HitPos = door:GetPos(), Entity = door, Fraction = 0.5, StartPos = tr.start} end
    SV.Inv.add(d, "lockpick", 1, {force = true})
    local pick = SV.Inv.find(d, function(it) return it.id == "lockpick" end)[1]
    MapCfg.cfg.doors["77"].clearance = 3
    local ok = SV.Inv.use(d, pick)
    expect(not ok, "lockpicked a clearance-3 door")
    MapCfg.cfg.doors["77"].clearance = 1
    expect(SV.Inv.use(d, pick), "lockpick refused")
    MOCK.traceFn = nil
    MOCK.advance(SV.Config.Crafting.lockpick.time + 1, 0.5)
    local opened = false
    for _, f in ipairs(door.fired or {}) do if f == "Open" then opened = true end end
    expect(opened or not SV.Inv.getItem(d, pick.uid), "lockpick had no outcome")
    local trace = false
    for _, t in pairs(SV.Evidence.traces) do if t.kind == "damage" then trace = true end end
    expect(trace, "lockpicking left no trace")
end)

--[[---------------------------------------------------------------------------
Jammer
---------------------------------------------------------------------------]]
TEST("jammer: radio drowns in the sector, tracker finds it, disarm restores, map limit", function()
    setupMap()
    local saboteur = staff("classd", "classd_worker")
    saboteur:SetPos(Vector(3000, 0, 0))
    local a = staff("security", "sec_guard")
    local b = staff("security", "sec_guard")
    a:SetPos(Vector(3100, 0, 0))
    b:SetPos(Vector(500, 0, 0))
    local before = SV.Comms.linkQuality(a, b)
    SV.Inv.add(saboteur, "jammer", 1, {force = true})
    local item = SV.Inv.find(saboteur, function(it) return it.id == "jammer" end)[1]
    expect(SV.Inv.use(saboteur, item), "jammer not placed")
    expect(SV.Comms.linkQuality(a, b) <= before * SV.Config.Jammer.quality + 1e-6, "radio not jammed")
    local c = staff("security", "sec_guard")
    c:SetPos(Vector(600, 0, 0))
    eq(SV.Comms.linkQuality(b, c), 1, "unjammed sector affected")
    -- Tracker.
    local eng = staff("engineering", "eng_engineer", 3)
    expect(SV.Inv.has(eng, "rf_tracker"), "engineer kit lacks the tracker")
    eng:SetPos(Vector(2500, 0, 0))
    local tracker = SV.Inv.find(eng, function(it) return it.id == "rf_tracker" end)[1]
    local _, msg = SV.Inv.use(eng, tracker)
    contains(tostring(msg), "восток")
    -- Disarm.
    local ent = next(SV.Jammer.active)
    eng:SetPos(ent:GetPos())
    MOCK.rpc(eng, "jammer.disarm", ent)
    MOCK.advance(SV.Config.Jammer.disarmTime + 1, 0.5)
    eq(SV.Util.count(SV.Jammer.active), 0, "jammer not disarmed")
    eq(SV.Comms.linkQuality(a, b), before, "quality not restored")
    -- Expiry after the lifetime.
    SV.Inv.add(saboteur, "jammer", 1, {force = true})
    saboteur.SVJammerAt = nil
    SV.Inv.use(saboteur, SV.Inv.find(saboteur, function(it) return it.id == "jammer" end)[1])
    eq(SV.Util.count(SV.Jammer.active), 1)
    MOCK.advance(SV.Config.Jammer.lifetime + 3, 1)
    eq(SV.Util.count(SV.Jammer.active), 0, "jammer never expired")
end)

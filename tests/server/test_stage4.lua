--[[---------------------------------------------------------------------------
Stage 4: medicine, security, knowledge, SCP framework and SCP-173/106/049/096.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local SCP = SV.SCP
local Medical = SV.Medical
local Security = SV.Security
local M = SV.Config.Medical
local SC = SV.Config.SCP

local function box(x1, x2, y1, y2)
    return {min = {x1, y1 or -1000, -100}, max = {x2, y2 or 1000, 500}}
end

local function point(id, kind, x, props, y)
    return {id = id, kind = kind, pos = {x, y or 0, 0}, ang = {0, 0, 0}, props = props or {}}
end

-- Light zone with a lab, heavy zone with four cells.
local function setupMap(extraZones, extraPoints)
    -- Isolation: players left over by an earlier (failed) test leave first.
    for _, p in ipairs(player.GetAll()) do MOCK.disconnect(p) end
    MOCK.hullFn, MOCK.traceHit = nil, false
    MOCK.advance(0.3)
    local zones = {
        {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 2000)}, props = {priority = 2, demand = 30}},
        {id = "hcz", kind = "sector", name = "Тяжёлая зона", boxes = {box(2000, 6000)}, props = {priority = 3, demand = 30}},
        {id = "cell173", kind = "cell", name = "Камера SCP-173", boxes = {box(2100, 2500)}, props = {scp = "scp173"}},
        {id = "cell106", kind = "cell", name = "Камера SCP-106", boxes = {box(2600, 3000)}, props = {scp = "scp106"}},
        {id = "cell049", kind = "cell", name = "Камера SCP-049", boxes = {box(3100, 3500)}, props = {scp = "scp049"}},
        {id = "cell096", kind = "cell", name = "Камера SCP-096", boxes = {box(3600, 4000)}, props = {scp = "scp096"}},
        {id = "lab", kind = "testchamber", name = "Лаборатория", boxes = {box(500, 900)}, props = {}},
    }
    local points = {
        point("gen", "node", 100, {subsystem = "generator", sector = "lcz"}),
        point("lcz_pow", "node", 200, {subsystem = "power", sector = "lcz"}),
        point("hcz_pow", "node", 2050, {subsystem = "power", sector = "hcz"}),
        point("hcz_vent", "node", 2060, {subsystem = "ventilation", sector = "hcz"}),
        point("term_research", "terminal", 700, {terminal = "research"}),
        point("panel173", "panel", 2450, {scp = "scp173"}),
        point("spawn173", "spawn", 2300, {group = "scp173"}),
        point("spawn106", "spawn", 2800, {group = "scp106"}),
        point("spawn049", "spawn", 3300, {group = "scp049"}),
        point("spawn096", "spawn", 3800, {group = "scp096"}),
    }
    for _, z in ipairs(extraZones or {}) do zones[#zones + 1] = z end
    for _, p in ipairs(extraPoints or {}) do points[#points + 1] = p end
    MapCfg.cfg = {version = 1, map = "gm_test", zones = zones, points = points, doors = {}}
    MapCfg.reindex()
    Facility.sectors = {}
    Facility.nodes = {}
    Facility.sabotageLog = {}
    Facility.build()
    MapCfg.spawnEntities()
    for id, st in pairs(SCP.state) do
        st.integrity, st.stage, st.breached, st.procCooldown, st.incident = 100, "stable", false, {}, nil
        if id == "scp096" then st.data.mode, st.data.targets, st.data.bagged = "calm", {}, nil end
    end
end

local function staff(division, role, rank, opts)
    opts = opts or {}
    -- Population quotas are not under test here.
    local r = SV.Roles.get(role)
    local q = r.quota
    r.quota = nil
    local p = makeStaff({steam = opts.steam or role, name = uniqueName(opts.name or "Тест Тестов"), division = division, role = role, rank = rank or 1,
        whitelist = opts.whitelist})
    r.quota = q
    return p
end

--- Joins a player and selects an SCP profile (quota lifted for the test).
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

local function face(p, pos)
    local dir = pos - p:EyePos()
    p:SetEyeAngles(dir:Angle())
end

-- Sweeping hull traces hit ent; point traces (free-space checks) stay clear.
local function hullHits(ent)
    MOCK.hullFn = function(tr)
        if tr.start:DistToSqr(tr.endpos) < 1 then return {Hit = false, StartSolid = false, HitPos = tr.endpos, Entity = MOCK.world, Fraction = 1} end
        return {Hit = true, StartSolid = false, HitPos = ent:GetPos(), Entity = ent, Fraction = 0.5}
    end
end

local function damage(p, amount, kind, attacker)
    p:TakeDamageInfo(MOCK.makeDamage({damage = amount, type = kind or DMG_BULLET, attacker = attacker}))
end

local function retire(...)
    for _, p in ipairs({...}) do
        if IsValid(p) then MOCK.disconnect(p) end
    end
    MOCK.advance(0.2)
end

--[[---------------------------------------------------------------------------
Medicine
---------------------------------------------------------------------------]]
TEST("ordinary damage incapacitates instead of killing; bleed-out ends in death", function()
    setupMap()
    local d = staff("classd", "classd_worker")
    damage(d, 150)
    expect(d:Alive(), "died from ordinary damage")
    expect(Medical.isIncapacitated(d), "not incapacitated")
    eq(d:Health(), 1)
    expect(SV.Move.has(d, "down"), "no movement restriction while down")
    -- Actions are blocked while down.
    MOCK.rpc(d, "sec.surrender")
    expect(not d.SVSurrendered, "incapacitated player used an action")
    MOCK.advance(M.bleedoutTime + 5, 1)
    expect(not d:Alive(), "bleed-out did not end in death")
    retire(d)
end)

TEST("give up is possible only after the waiting time", function()
    setupMap()
    local d = staff("classd", "classd_worker")
    damage(d, 150, DMG_CLUB)
    expect(Medical.isIncapacitated(d))
    MOCK.rpc(d, "med.giveup")
    expect(d:Alive(), "gave up immediately")
    MOCK.advance(M.giveUpAfter + 1, 1)
    MOCK.rpc(d, "med.giveup")
    expect(not d:Alive(), "give up did not work")
    retire(d)
end)

TEST("lethal head shot kills; finishing an incapacitated body kills", function()
    setupMap()
    local a = staff("classd", "classd_worker")
    hook.Run("ScalePlayerDamage", a, HITGROUP_HEAD, MOCK.makeDamage({}))
    damage(a, 120)
    expect(not a:Alive(), "head shot did not kill")
    local b = staff("classd", "classd_worker")
    damage(b, 150, DMG_CLUB)
    expect(Medical.isIncapacitated(b))
    damage(b, 20, DMG_CLUB)
    expect(not b:Alive(), "finishing blow did not kill")
    retire(a, b)
end)

TEST("medic stabilises, doctor revives; resources are spent", function()
    setupMap()
    local patient = staff("classd", "classd_worker")
    local doc = staff("medical", "med_doctor", 3)
    doc:SetPos(patient:GetPos())
    damage(patient, 150) -- heavy bleeding
    expect(Medical.isIncapacitated(patient))
    local tq = SV.Inv.count(doc, "tourniquet")
    local ok, why = Medical.treat(doc, patient, "tourniquet")
    expect(ok, "treat refused: " .. tostring(why))
    MOCK.advance(5, 0.5)
    eq(SV.Inv.count(doc, "tourniquet"), tq - 1, "tourniquet not spent")
    expect(Medical.get(patient).down.stabilised, "not stabilised")
    ok, why = Medical.treat(doc, patient, "stimulant")
    expect(ok, "revive refused: " .. tostring(why))
    MOCK.advance(5, 0.5)
    expect(not Medical.isIncapacitated(patient), "not revived")
    eq(patient:Health(), M.reviveHealth)
    eq(SV.Inv.count(doc, "stimulant"), 0, "stimulant not spent")
    -- A stimulant cannot be used by an orderly.
    local orderly = staff("medical", "med_orderly")
    SV.Inv.add(orderly, "stimulant", 1, {force = true})
    local ok2 = Medical.treat(orderly, patient, "stimulant")
    expect(not ok2, "orderly used a doctor-only treatment")
    retire(patient, doc, orderly)
end)

TEST("baton stun is temporary", function()
    setupMap()
    local d = staff("classd", "classd_worker")
    local g = staff("security", "sec_guard")
    for _ = 1, M.stunHits do Medical.stunHit(d, g) end
    expect(Medical.isStunned(d), "not stunned")
    MOCK.advance(M.stunTime + 1, 0.5)
    expect(not Medical.isStunned(d), "stun did not end")
    expect(not SV.Move.has(d, "stun"), "movement restriction remained")
    retire(d, g)
end)

--[[---------------------------------------------------------------------------
Security
---------------------------------------------------------------------------]]
TEST("restraint: rights, instant on surrender, automatic release after the maximum", function()
    setupMap()
    local d = staff("classd", "classd_worker")
    local sci = staff("science", "sci_junior")
    local g = staff("security", "sec_guard")
    d:SetPos(Vector(100, 0, 0))
    sci:SetPos(Vector(110, 0, 0))
    g:SetPos(Vector(120, 0, 0))
    MOCK.rpc(sci, "sec.restrain", d)
    expect(not Security.restrained[d], "scientist restrained someone")
    MOCK.rpc(d, "sec.surrender")
    expect(d.SVSurrendered)
    MOCK.rpc(g, "sec.restrain", d)
    expect(Security.restrained[d], "surrendered target not cuffed")
    expect(SV.Move.has(d, "restrained"))
    MOCK.advance(SV.Config.Security.restrainMax + 2, 1)
    expect(not Security.restrained[d], "restraint not released automatically")
    -- Grace period: immediate re-restraint refused.
    MOCK.rpc(d, "sec.surrender")
    MOCK.rpc(g, "sec.restrain", d)
    expect(not Security.restrained[d], "re-restrained during the grace period")
    retire(d, sci, g)
end)

TEST("search and confiscation are logged; id card cannot be confiscated", function()
    setupMap()
    local d = staff("classd", "classd_worker")
    local g = staff("security", "sec_guard")
    d:SetPos(Vector(100, 0, 0))
    g:SetPos(Vector(120, 0, 0))
    SV.Inv.add(d, "shiv", 1, {force = true})
    MOCK.rpc(g, "sec.search", d)
    expect(not g.SVSearching, "searched a free person")
    MOCK.rpc(d, "sec.surrender")
    MOCK.rpc(g, "sec.search", d)
    MOCK.advance(SV.Config.Security.searchTime + 1, 0.5)
    expect(g.SVSearching and g.SVSearching.target == d, "search not completed")
    local shiv = SV.Inv.find(d, function(it) return it.id == "shiv" end)[1]
    MOCK.rpc(g, "sec.confiscate", d, shiv.uid, "Холодное оружие")
    expect(SV.Inv.has(g, "shiv"), "item not confiscated")
    eq(tonumber(SV.DB.queryValue("SELECT COUNT(*) FROM sv_confiscations WHERE item_id = 'shiv'")), 1)
    local card = SV.Inv.find(d, function(it) return it.id == "id_card" end)[1]
    if SV.Config.Items.id_card.noConfiscate then
        MOCK.rpc(g, "sec.confiscate", d, card.uid, "тест")
        expect(SV.Inv.getItem(d, card.uid), "id card confiscated")
    end
    retire(d, g)
end)

TEST("detention: reason required, limit by rank, ends by itself, resumes after reconnect", function()
    setupMap()
    local d = staff("classd", "classd_worker", 1, {steam = "Detainee"})
    local g = staff("security", "sec_guard")
    d:SetPos(Vector(100, 0, 0))
    g:SetPos(Vector(120, 0, 0))
    MOCK.rpc(d, "sec.surrender")
    MOCK.rpc(g, "sec.restrain", d)
    MOCK.rpc(g, "sec.detain", d, 5, "")
    expect(not Security.detained[d], "detained without a reason")
    MOCK.rpc(g, "sec.detain", d, 600, "Нападение на охрану")
    expect(Security.detained[d], "not detained")
    local left = Security.detained[d].untilTime - CurTime()
    expect(left <= SV.Config.Security.detainMax * 60 + 1, "limit not applied: " .. left)
    expect(not Security.restrained[d], "detainee still cuffed")
    -- Reconnect: the remaining time stays with the character.
    local charId = d.SVChar.id
    MOCK.disconnect(d)
    MOCK.advance(0.5)
    local d2 = MOCK.join({name = "Detainee", steamid = d:SteamID64()})
    MOCK.rpc(d2, "char.select", charId)
    MOCK.advance(1, 0.25)
    expect(Security.detained[d2], "detention not resumed after reconnect")
    MOCK.advance(SV.Config.Security.detainMax * 60 + 5, 5)
    expect(not Security.detained[d2], "detention never ended")
    retire(d2, g)
end)

--[[---------------------------------------------------------------------------
Knowledge
---------------------------------------------------------------------------]]
TEST("restricted dossier text is never sent without clearance", function()
    setupMap()
    local d = staff("classd", "classd_worker")
    local view = SV.Knowledge.view(d, "scp173", "personal")
    for _, s in ipairs(view.sections) do
        if s.clearance > 0 then
            expect(s.locked and s.text == nil, "restricted section " .. s.id .. " leaked")
        end
    end
    -- Even "terminal" mode uses the real card clearance.
    local sci = staff("science", "sci_researcher", 3)
    local tv = SV.Knowledge.view(sci, "scp173", "terminal")
    for _, s in ipairs(tv.sections) do
        if s.clearance > 2 then expect(s.text == nil, "section above clearance 2 leaked: " .. s.id) end
        if s.clearance <= 2 then expect(s.text ~= nil, "allowed section hidden: " .. s.id) end
    end
    -- The RPC from far away falls back to personal mode.
    MOCK.clearSent()
    MOCK.rpc(sci, "know.open", "scp173", MapCfg.spawned.term_research)
    local pushes = MOCK.pushes(sci, "know.view")
    expect(#pushes == 1, "no dossier view")
    eq(pushes[1].data.mode, "personal")
    retire(d, sci)
end)

--[[---------------------------------------------------------------------------
SCP framework and SCP-173
---------------------------------------------------------------------------]]
TEST("SCP-173: server-side observation freezes it; blink opens a window", function()
    setupMap()
    local scp = makeSCP("scp173")
    expect(SCP.inCell("scp173", scp:GetPos()), "SCP-173 not in its cell")
    local obs = staff("security", "sec_guard")
    obs:SetPos(Vector(2150, 0, 0))
    face(obs, scp:GetPos() + Vector(0, 0, 36))
    MOCK.advance(0.3)
    expect(SV.Move.has(scp, "173"), "not frozen while observed")
    expect(SCP.S173.isObserved())
    -- Looking away.
    obs:SetEyeAngles(Angle(0, 180, 0))
    MOCK.advance(0.5)
    expect(not SV.Move.has(scp, "173"), "still frozen without observers")
    -- Walls block observation (opaque trace).
    face(obs, scp:GetPos() + Vector(0, 0, 36))
    MOCK.traceHit = true
    MOCK.advance(0.5)
    expect(not SV.Move.has(scp, "173"), "observed through a wall")
    MOCK.traceHit = false
    MOCK.advance(0.3)
    expect(SV.Move.has(scp, "173"))
    SCP.S173.forceBlink(obs, 1)
    MOCK.advance(0.4)
    expect(not SV.Move.has(scp, "173"), "blinking observer still counted")
    retire(scp, obs)
end)

TEST("SCP-173: attack only when unobserved; recapture needs observers", function()
    setupMap()
    local scp = makeSCP("scp173")
    local victim = staff("classd", "classd_worker")
    victim:SetPos(scp:GetPos() + Vector(40, 0, 0))
    victim:SetEyeAngles(Angle(0, 0, 0)) -- looks away
    face(scp, victim:GetPos())
    hullHits(victim)
    local def = SCP.defs.scp173
    local watcher = staff("security", "sec_guard")
    watcher:SetPos(Vector(2150, 0, 0))
    face(watcher, scp:GetPos() + Vector(0, 0, 36))
    MOCK.advance(0.3)
    expect(not def.abilities.attack(scp, SCP.state.scp173), "attacked while observed")
    watcher:SetEyeAngles(Angle(0, 90, 0))
    MOCK.advance(0.5)
    expect(def.abilities.attack(scp, SCP.state.scp173), "attack refused while unobserved")
    expect(not victim:Alive() or Medical.isIncapacitated(victim), "victim unharmed")
    MOCK.hullFn = nil

    -- Breach by leaving the cell, then recapture.
    scp:SetPos(Vector(1500, 0, 0))
    MOCK.advance(1.5)
    expect(SCP.state.scp173.breached, "leaving the cell is not a breach")
    local mtf = staff("mtf", "mtf_garrison", 1, {whitelist = true})
    mtf:SetPos(Vector(1550, 0, 0))
    MOCK.rpc(mtf, "scp.recapture", scp)
    expect(not SV.Actions.active[mtf], "recapture started without observers")
    local o1 = staff("security", "sec_guard")
    local o2 = staff("security", "sec_guard")
    o1:SetPos(Vector(1300, 0, 0))
    o2:SetPos(Vector(1300, 50, 0))
    face(o1, scp:GetPos() + Vector(0, 0, 36))
    face(o2, scp:GetPos() + Vector(0, 0, 36))
    SCP.S173.forceBlink(o1, 0) SCP.S173.forceBlink(o2, 0)
    MOCK.rpc(mtf, "scp.recapture", scp)
    expect(SV.Actions.active[mtf], "recapture not started: " .. tostring(MOCK.lastNotify(mtf)))
    -- Keep both observers open-eyed during the action.
    for _ = 1, SC.scp173.recaptureTime * 2 + 2 do
        SCP.S173.forceBlink(o1, 0) SCP.S173.forceBlink(o2, 0)
        MOCK.advance(0.5, 0.1)
    end
    expect(not SCP.state.scp173.breached, "not recontained")
    expect(SCP.inCell("scp173", scp:GetPos()), "not returned to the cell")
    retire(scp, victim, watcher, mtf, o1, o2)
end)

TEST("containment stages: conditions degrade integrity, unplayed SCP makes an incident", function()
    setupMap()
    local st = SCP.state.scp173
    expect(not SCP.playerOf("scp173"), "SCP-173 still played")
    Facility.nodes.hcz_pow.health = 0
    Facility.recompute()
    expect(not Facility.devicePowered("hcz", "containment"), "containment still powered")
    -- Few players online: degradation is slowed (population factor), not stopped.
    MOCK.advance(SC.tick * 60, 1)
    expect(st.integrity < 75 and st.stage ~= "stable", "integrity did not degrade: " .. st.integrity)
    st.integrity = 5
    SCP.adjustIntegrity("scp173", 0, "test")
    eq(st.stage, "escape")
    MOCK.advance(SC.unplayedIncidentDelay + SC.tick + 1, 1)
    expect(st.incident, "no incident for the unplayed SCP")
    expect(not st.breached, "unplayed SCP breached")
    Facility.nodes.hcz_pow.health = 100
    Facility.recompute()
end)

--[[---------------------------------------------------------------------------
SCP-106
---------------------------------------------------------------------------]]
TEST("SCP-106: pocket without a pocket zone is simulated and always ends", function()
    setupMap()
    local v = staff("classd", "classd_worker")
    v:SetPos(Vector(2700, 0, 0))
    expect(SCP.S106.sendToPocket(v, nil), "not sent")
    expect(SCP.S106.inPocket(v))
    expect(SV.Move.has(v, "pocket"), "fallback pocket does not hold the victim")
    MOCK.advance(SC.scp106.pocketFallback + 1, 0.5)
    expect(not SCP.S106.inPocket(v), "victim stuck in the pocket")
    expect(not SV.Move.has(v, "pocket"))
    expect(v:Alive())
    retire(v)
end)

TEST("SCP-106: pocket zone with exits; expelled at the limit; death and disconnect clear", function()
    setupMap({{id = "pocket", kind = "pocket", name = "Карман", boxes = {box(7000, 7600)}, props = {}}},
        {point("pexit", "pocket_exit", 7550), point("emerge1", "emergence", 1500)})
    local v = staff("classd", "classd_worker")
    v:SetPos(Vector(2700, 0, 0))
    expect(SCP.S106.sendToPocket(v, nil))
    expect(MapCfg.zoneContains(MapCfg.zone("pocket"), v:GetPos()), "not inside the pocket zone")
    -- Walking to the exit point.
    v:SetPos(Vector(7540, 0, 0))
    MOCK.advance(1)
    expect(not SCP.S106.inPocket(v), "exit point did not work")
    eq(v:GetPos().x, 1500, "not placed at the emergence point")
    -- Staying: expelled after pocketMax, health never below the floor.
    expect(SCP.S106.sendToPocket(v, nil))
    MOCK.advance(SC.scp106.pocketMax + 1, 1)
    expect(not SCP.S106.inPocket(v), "not expelled after the maximum")
    expect(v:Alive(), "pocket killed the victim")
    -- Disconnect inside.
    local w = staff("classd", "classd_worker")
    expect(SCP.S106.sendToPocket(w, nil))
    MOCK.disconnect(w)
    MOCK.advance(0.5)
    expect(not SCP.S106.pocket[w], "disconnected victim kept")
    retire(v)
end)

TEST("SCP-106: phase destination is validated; bullets barely hurt; retreat recontains", function()
    setupMap()
    local scp = makeSCP("scp106")
    local st = SCP.state.scp106
    local door = MOCK.newEntity("func_door")
    door:SetPos(scp:GetPos() + Vector(120, 0, 0))
    face(scp, door:GetPos())
    hullHits(door)
    expect(not SCP.defs.scp106.abilities.phase(scp, st), "phased while containment holds")
    st.integrity = 5
    SCP.adjustIntegrity("scp106", 0)
    -- Solid destination.
    MOCK.hullFn = function(tr)
        if tr.start:DistToSqr(tr.endpos) < 1 then return {Hit = true, StartSolid = true, HitPos = tr.endpos, Entity = MOCK.world, Fraction = 0} end
        return {Hit = true, StartSolid = false, HitPos = door:GetPos(), Entity = door, Fraction = 0.5}
    end
    local before = scp:GetPos()
    expect(not SCP.defs.scp106.abilities.phase(scp, st), "phased into solid")
    eq(scp:GetPos().x, before.x)
    hullHits(door)
    expect(SCP.defs.scp106.abilities.phase(scp, st), "phase refused: " .. tostring(MOCK.lastNotify(scp)))
    expect(scp:GetPos().x > door:GetPos().x, "not behind the door")
    MOCK.hullFn = nil
    MOCK.advance(1.5)
    expect(st.breached, "phasing out of the cell is not a breach")
    local hp = scp:Health()
    damage(scp, 100)
    eq(scp:Health(), hp - 30, "bullet factor not applied")
    damage(scp, scp:Health(), DMG_CLUB)
    MOCK.advance(0.5)
    expect(scp:Alive(), "SCP-106 died instead of retreating")
    expect(not st.breached, "retreat did not recontain")
    retire(scp)
end)

--[[---------------------------------------------------------------------------
SCP-049
---------------------------------------------------------------------------]]
TEST("SCP-049: touch infects, hazmat protects, infection progresses", function()
    setupMap()
    local scp = makeSCP("scp049")
    local st = SCP.state.scp049
    local v = staff("classd", "classd_worker")
    v:SetPos(scp:GetPos() + Vector(40, 0, 0))
    face(scp, v:GetPos())
    hullHits(v)
    local touch = SCP.defs.scp049.abilities.touch
    expect(touch(scp, st))
    eq(Medical.infection(v).stage, 1)
    local h = staff("science", "sci_junior")
    h:SetPos(scp:GetPos() + Vector(40, 0, 0))
    SV.Inv.add(h, "hazmat", 1, {force = true})
    local item = SV.Inv.find(h, function(it) return it.id == "hazmat" end)[1]
    item.data.worn = true
    hullHits(h)
    st.nextTouch = 0
    touch(scp, st)
    expect(not Medical.infection(h), "hazmat did not protect")
    MOCK.hullFn = nil
    MOCK.advance(SC.scp049.stageTime + 6, 1)
    eq(Medical.infection(v).stage, 2, "infection did not progress")
    retire(scp, v, h)
end)

TEST("SCP-049: cure creates a limited SCP-049-2 that returns to its character", function()
    setupMap()
    local scp = makeSCP("scp049")
    local st = SCP.state.scp049
    local v = staff("classd", "classd_worker")
    local charId = v.SVChar.id
    v:SetPos(scp:GetPos() + Vector(40, 0, 0))
    face(scp, v:GetPos())
    hullHits(v)
    damage(v, 150, DMG_CLUB)
    expect(Medical.isIncapacitated(v))
    expect(SCP.defs.scp049.abilities.touch(scp, st))
    MOCK.advance(SC.scp049.cureTime + 1, 0.2)
    MOCK.hullFn = nil
    eq(SV.Roles.ofPlayer(v).id, "scp0492", "not converted")
    expect(v:Alive(), "instance not spawned")
    eq(v.SVChar.id, charId, "character changed")
    eq(SCP.S049.instanceCount(), 1)
    -- Same character cannot be converted again soon.
    SCP.S049.cured[charId] = CurTime()
    -- Instance dies: sample drops, role returns.
    local worldBefore = SV.Util.count(SV.Inv.world)
    v:Kill()
    MOCK.advance(0.5)
    eq(SCP.S049.instanceCount(), 0)
    expect(SV.Util.count(SV.Inv.world) > worldBefore, "no tissue sample dropped")
    eq(SV.Roles.ofPlayer(v).id, "classd_worker", "role not restored")
    retire(scp, v)
end)

TEST("SCP-049: instance limit and timeout; suppression enables recapture", function()
    setupMap()
    local scp = makeSCP("scp049")
    local st = SCP.state.scp049
    local victims = {}
    for i = 1, 3 do
        local v = staff("classd", "classd_worker")
        damage(v, 150, DMG_CLUB)
        victims[i] = v
    end
    SCP.S049.convert(victims[1], scp)
    SCP.S049.convert(victims[2], scp)
    MOCK.advance(0.5)
    local cap = SCP.S049.maxInstances()
    expect(SCP.S049.instanceCount() <= cap, "instance limit exceeded")
    local ok = SCP.S049.canConvert(victims[3])
    if SCP.S049.instanceCount() >= cap then expect(not ok, "limit not enforced") end
    MOCK.advance(SC.scp049.instanceTime + 2, 1)
    eq(SCP.S049.instanceCount(), 0, "instances did not time out")
    -- Suppression and recapture.
    scp:SetPos(Vector(1500, 0, 0))
    MOCK.advance(1.5)
    expect(st.breached)
    local g = staff("security", "sec_guard")
    g:SetPos(Vector(1550, 0, 0))
    MOCK.rpc(g, "scp.recapture", scp)
    expect(not SV.Actions.active[g], "recapture without suppression")
    damage(scp, scp:Health() * 0.7, DMG_BULLET, g)
    expect(st.data.suppressedUntil and st.data.suppressedUntil > CurTime(), "not suppressed")
    MOCK.rpc(g, "scp.recapture", scp)
    expect(SV.Actions.active[g], "recapture not started: " .. tostring(MOCK.lastNotify(g)))
    MOCK.advance(SC.scp049.recaptureTime + 1, 0.5)
    expect(not st.breached, "not recontained")
    retire(scp, g, victims[1], victims[2], victims[3])
end)

--[[---------------------------------------------------------------------------
SCP-096
---------------------------------------------------------------------------]]
TEST("SCP-096: face seen -> rage; target death -> calming -> exhausted -> calm", function()
    setupMap()
    local scp = makeSCP("scp096")
    local st = SCP.state.scp096
    eq(st.data.mode, "calm")
    local v = staff("classd", "classd_worker")
    v:SetPos(scp:GetPos() + Vector(300, 0, 0))
    face(v, scp:EyePos())
    face(scp, v:EyePos())
    MOCK.advance(0.5)
    expect(SCP.S096.isTarget(v), "face check did not add the target")
    eq(st.data.mode, "triggered")
    MOCK.advance(SC.scp096.triggerTime + 0.5)
    eq(st.data.mode, "rage")
    -- Non-targets are not attacked.
    local other = staff("classd", "classd_worker")
    other:SetPos(scp:GetPos() + Vector(40, 0, 0))
    other:SetEyeAngles(Angle(0, 0, 0))
    v:SetEyeAngles(Angle(0, 0, 0))
    face(scp, other:GetPos())
    hullHits(other)
    expect(not SCP.defs.scp096.abilities.attack(scp, st), "attacked a non-target")
    expect(other:Alive() and not Medical.isIncapacitated(other))
    v:Kill()
    MOCK.hullFn = nil
    MOCK.advance(0.5)
    eq(st.data.mode, "calming", "rage did not end after the target died")
    MOCK.advance(SC.scp096.calmingTime + 0.5)
    eq(st.data.mode, "exhausted")
    MOCK.advance(SC.scp096.exhaustedTime + 0.5)
    eq(st.data.mode, "calm")
    retire(scp, v, other)
end)

TEST("SCP-096: rage is time-limited, disconnect removes targets, bag recaptures", function()
    setupMap()
    local scp = makeSCP("scp096")
    local st = SCP.state.scp096
    local v = staff("classd", "classd_worker")
    v:SetPos(Vector(500, 0, 0))
    v:SetEyeAngles(Angle(0, 180, 0))
    expect(SCP.S096.addTarget(v, "test"))
    MOCK.advance(SC.scp096.triggerTime + 0.5)
    eq(st.data.mode, "rage")
    MOCK.advance(SC.scp096.rageMax + 1, 1)
    expect(st.data.mode ~= "rage", "rage never ended")
    expect(not SCP.S096.isTarget(v), "target kept after the rage ended")
    -- Disconnect of the only target ends the rage at once.
    MOCK.advance(SC.scp096.exhaustedTime + SC.scp096.calmingTime + 1, 1)
    local w = staff("classd", "classd_worker")
    w:SetPos(Vector(500, 0, 0))
    w:SetEyeAngles(Angle(0, 180, 0))
    expect(SCP.S096.addTarget(w, "test"))
    MOCK.advance(SC.scp096.triggerTime + 0.5)
    MOCK.disconnect(w)
    MOCK.advance(0.5)
    eq(st.data.mode, "calming", "disconnect did not remove the target")
    MOCK.advance(SC.scp096.calmingTime + 0.5)
    -- Out of the cell in exhaustion: bag recapture.
    scp:SetPos(Vector(1500, 0, 0))
    MOCK.advance(1.5)
    expect(st.breached)
    local g = staff("mtf", "mtf_garrison", 1, {whitelist = true})
    g:SetPos(Vector(1540, 0, 0))
    MOCK.rpc(g, "scp.recapture", scp)
    expect(not SV.Actions.active[g], "recapture without a bag")
    SV.Inv.add(g, "head_bag", 1, {force = true})
    MOCK.rpc(g, "scp.recapture", scp)
    expect(SV.Actions.active[g], "bag recapture not started: " .. tostring(MOCK.lastNotify(g)))
    MOCK.advance(SC.scp096.bagTime + 1, 0.5)
    expect(not st.breached, "not recontained")
    expect(st.data.bagged, "no bag")
    -- Bagged: seeing it does not trigger.
    local x = staff("classd", "classd_worker")
    expect(not SCP.S096.addTarget(x, "test"), "bagged 096 triggered")
    retire(scp, v, g, x)
end)

TEST("SCP-096: unplayed object takes the strain instead of raging", function()
    setupMap()
    local st = SCP.state.scp096
    local v = staff("classd", "classd_worker")
    local before = st.integrity
    expect(not SCP.S096.addTarget(v, "experiment"))
    expect(st.integrity < before, "integrity unchanged")
    retire(v)
end)

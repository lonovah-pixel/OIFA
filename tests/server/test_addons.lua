--[[---------------------------------------------------------------------------
SITE-VEIL addons shipped in addons/: intercom, decontamination, tesla gates,
CCTV, SCP-999, scoreboard.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local SCP = SV.SCP

local function box(x1, x2)
    return {min = {x1, -1000, -100}, max = {x2, 1000, 500}}
end

local function point(id, kind, x, props, ang)
    return {id = id, kind = kind, pos = {x, 0, 0}, ang = ang or {0, 0, 0}, props = props or {}}
end

local function setupMap()
    for _, p in ipairs(player.GetAll()) do MOCK.disconnect(p) end
    MOCK.hullFn, MOCK.traceHit = nil, false
    MOCK.advance(0.3)
    MapCfg.cfg = {version = 1, map = "gm_test", zones = {
        {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 2000)}, props = {priority = 2, demand = 30}},
        {id = "hcz", kind = "sector", name = "Тяжёлая зона", boxes = {box(2000, 6000)}, props = {priority = 3, demand = 30}},
        {id = "cell096", kind = "cell", name = "Камера SCP-096", boxes = {box(4000, 4500)}, props = {scp = "scp096"}},
        {id = "cell999", kind = "cell", name = "Камера SCP-999", boxes = {box(5000, 5500)}, props = {scp = "scp999"}},
    }, points = {
        point("gen", "node", 100, {subsystem = "generator", sector = "lcz"}),
        point("lcz_pow", "node", 200, {subsystem = "power", sector = "lcz"}),
        point("lcz_com", "node", 300, {subsystem = "comms", sector = "lcz"}),
        point("hcz_pow", "node", 2100, {subsystem = "power", sector = "hcz"}),
        point("hcz_sec", "node", 2200, {subsystem = "security", sector = "hcz"}),
        point("t_intercom", "terminal", 500, {terminal = "intercom"}),
        point("t_cctv", "terminal", 700, {terminal = "cctv"}),
        point("tesla1", "tesla", 3000, {name = "Коридор Б"}),
        point("cam_hall", "camera", 3500, {name = "Коридор у камеры 096"}),
        point("cam_cell", "camera", 4100, {name = "Камера 096"}),
        point("spawn096", "spawn", 4300, {group = "scp096"}),
        point("spawn999", "spawn", 5300, {group = "scp999"}),
    }, doors = {}}
    MapCfg.reindex()
    Facility.sectors, Facility.nodes, Facility.sabotageLog = {}, {}, {}
    Facility.build()
    MapCfg.spawnEntities()
    for id, st in pairs(SCP.state) do
        st.integrity, st.stage, st.breached, st.procCooldown = 100, "stable", false, {}
        if id == "scp096" then st.data.mode, st.data.targets, st.data.bagged, st.data.maskedUntil = "calm", {}, nil, nil end
    end
    if Facility.stateId() ~= "normal" then Facility.setState("normal", nil, "test", {force = true}) end
    for sector in pairs(Facility.flags) do Facility.flags[sector] = nil end
    SV.Intercom.lastAt = -1e9
    SV.Decon.active, SV.Decon.lastAt = nil, {}
    SV.Tesla.disabledUntil, SV.Tesla.lastDisable = {}, {}
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

local function face(p, pos)
    p:SetEyeAngles((pos - p:EyePos()):Angle())
end

TEST("addons extend the gamemode through its API", function()
    for _, id in ipairs({"intercom", "decontamination", "tesla", "cctv", "scp999", "scoreboard"}) do
        expect(SV.Addons.isLoaded(id), "addon not loaded: " .. id)
    end
    expect(SV.Roles.get("scp999") and SV.Roles.get("scp999").team, "SCP-999 role or DarkRP job missing")
    expect(SV.Config.Items.sweets, "item from addon config missing")
    expect(SV.Config.Dossiers.scp999, "dossier missing")
    expect(SV.Research.protocols.p999_mood, "research protocol not registered")
    expect(MapCfg.pointKinds.tesla and MapCfg.pointKinds.camera and MapCfg.terminalKinds.intercom and MapCfg.terminalKinds.cctv, "map kinds missing")
    local report = MapCfg.validate(MapCfg.cfg)
    for _, e in ipairs(report.errors) do expect(not string.find(e, "неизвестный тип", 1, true), e) end
    local st = SV.Admin.status()
    expect(#st.addons >= 6, "admin status does not list addons")
end)

--[[---------------------------------------------------------------------------
Intercom
---------------------------------------------------------------------------]]
TEST("intercom: card clearance, facility-wide voice, stays at the terminal, cooldowns", function()
    local S = setupMap()
    local term = S.t_intercom
    local guard = staff("security", "sec_guard")
    guard:SetPos(term:GetPos())
    MOCK.rpc(guard, "intercom.voice", term)
    expect(not SV.Intercom.speaker, "clearance 1 used the intercom")
    local officer = staff("security", "sec_officer", 3)
    officer:SetPos(term:GetPos())
    local far = staff("classd", "classd_worker")
    far:SetPos(Vector(5800, 900, 0))
    expect(not GAMEMODE:PlayerCanHearPlayersVoice(far, officer), "heard without the intercom")
    MOCK.rpc(officer, "intercom.voice", term)
    expect(SV.Intercom.speaker, "voice broadcast refused: " .. tostring(MOCK.lastNotify(officer)))
    expect(GAMEMODE:PlayerCanHearPlayersVoice(far, officer), "broadcast not heard facility-wide")
    -- Leaving the terminal ends it.
    officer:SetPos(Vector(1500, 0, 0))
    MOCK.advance(1)
    expect(not SV.Intercom.speaker, "broadcast continued away from the terminal")
    expect(not GAMEMODE:PlayerCanHearPlayersVoice(far, officer))
    -- Cooldown for everybody.
    officer:SetPos(term:GetPos())
    MOCK.advance(5)
    MOCK.rpc(officer, "intercom.text", term, "Проверка связи")
    contains(tostring(MOCK.lastNotify(officer)), "эфир освободится")
    MOCK.advance(SV.Config.Intercom.personalCooldown + 1, 5)
    MOCK.clearSent()
    MOCK.rpc(officer, "intercom.text", term, "Проверка связи")
    local ann = MOCK.pushes(far, "facility.announce")
    expect(#ann == 1, "text broadcast not delivered")
    contains(ann[1].data.text, "Проверка связи")
    -- Broken comms block it.
    MOCK.advance(SV.Config.Intercom.personalCooldown + 1, 5)
    Facility.nodes.lcz_com.health = 10
    Facility.recompute()
    expect(SV.Intercom.blockedReason(officer, term), "intercom works with broken comms")
end)

--[[---------------------------------------------------------------------------
Decontamination
---------------------------------------------------------------------------]]
TEST("decontamination: authority, warning, lockdown and gas for the unprotected, end", function()
    setupMap()
    local guard = staff("security", "sec_guard")
    MOCK.rpc(guard, "decon.start", "hcz")
    expect(not SV.Decon.active, "guard ordered decontamination")
    local chief = staff("security", "sec_chief", 5, true)
    chief:SetPos(Vector(500, 0, 0))
    local d = staff("classd", "classd_worker")
    d:SetPos(Vector(3000, 0, 0))
    local masked = staff("engineering", "eng_tech")
    masked:SetPos(Vector(3100, 0, 0))
    SV.Inv.add(masked, "gas_mask", 1, {force = true})
    SV.Inv.find(masked, function(it) return it.id == "gas_mask" end)[1].data.worn = true
    MOCK.rpc(chief, "decon.start", "hcz")
    expect(SV.Decon.active and SV.Decon.active.phase == "warn", "not ordered: " .. tostring(MOCK.lastNotify(chief)))
    expect(not Facility.isLockedDown("hcz"), "sector locked during the warning")
    MOCK.advance(SV.Config.Decontamination.warnTime + 1, 0.5)
    eq(SV.Decon.active.phase, "gas")
    expect(Facility.isLockedDown("hcz"), "sector not locked during the gas")
    MOCK.advance(10, 0.5)
    expect(d:Health() < 100 or SV.Medical.isIncapacitated(d), "unprotected person unharmed")
    eq(masked:Health(), 100, "gas mask did not protect")
    eq(chief:Health(), 100, "person outside the sector harmed")
    MOCK.advance(SV.Config.Decontamination.duration, 1)
    expect(not SV.Decon.active, "decontamination never ended")
    expect(not Facility.isLockedDown("hcz"), "lockdown not lifted")
    -- Cooldown, and cancel during the warning.
    MOCK.rpc(chief, "decon.start", "hcz")
    expect(not SV.Decon.active, "sector cooldown ignored")
    MOCK.advance(5)
    MOCK.rpc(chief, "decon.start", "lcz")
    expect(SV.Decon.active, "second sector refused")
    MOCK.advance(2)
    MOCK.rpc(chief, "decon.cancel", "lcz")
    expect(not SV.Decon.active, "not cancelled")
end)

--[[---------------------------------------------------------------------------
Tesla gates
---------------------------------------------------------------------------]]
TEST("tesla: strikes outsiders, spares cleared staff, needs power, can be switched off", function()
    local S = setupMap()
    expect(IsValid(S.tesla1) and SV.Tesla.gates[S.tesla1], "gate entity not registered")
    local mtf = staff("mtf", "mtf_garrison", 1, true)
    mtf:SetPos(Vector(3000, 20, 0))
    MOCK.advance(2, 0.2)
    eq(mtf:Health(), 100, "gate struck cleared staff")
    mtf:SetPos(Vector(1000, 0, 0))
    local d = staff("classd", "classd_worker")
    d:SetPos(Vector(3000, 20, 0))
    MOCK.advance(SV.Config.Tesla.charge + 0.5, 0.2)
    expect(d:Health() < 100 or SV.Medical.isIncapacitated(d), "outsider not struck")
    -- No power: no discharge.
    local d2 = staff("classd", "classd_worker")
    Facility.nodes.hcz_pow.health = 0
    Facility.recompute()
    d2:SetPos(Vector(3000, -20, 0))
    MOCK.advance(3, 0.2)
    eq(d2:Health(), 100, "unpowered gate struck")
    Facility.nodes.hcz_pow.health = 100
    Facility.recompute()
    -- Switched off by an authorized officer only.
    local guard = staff("security", "sec_guard")
    MOCK.rpc(guard, "tesla.disable", "hcz", 60)
    expect(not SV.Tesla.disabledUntil.hcz, "guard switched the gates off")
    MOCK.rpc(mtf, "tesla.disable", "hcz", 200)
    local left = (SV.Tesla.disabledUntil.hcz or 0) - CurTime()
    expect(left > 0 and left <= SV.Config.Tesla.disableMax, "disable not applied or not clamped: " .. left)
    MOCK.advance(3, 0.2)
    eq(d2:Health(), 100, "disabled gate struck")
end)

--[[---------------------------------------------------------------------------
CCTV
---------------------------------------------------------------------------]]
TEST("cctv: view from the monitor, stop when leaving; SCP-096's face on screen, masking", function()
    local S = setupMap()
    local term = S.t_cctv
    local op = staff("security", "sec_guard")
    op:SetPos(term:GetPos())
    MOCK.rpc(op, "cctv.view", term, 1)
    expect(SV.Cctv.viewers[op], "view refused: " .. tostring(MOCK.lastNotify(op)))
    eq(op:GetViewEntity(), S.cam_cell, "view entity not set (cameras ordered by point id)")
    op:SetPos(Vector(1500, 0, 0))
    MOCK.advance(0.5)
    expect(not SV.Cctv.viewers[op], "viewing continued away from the monitor")
    eq(op:GetViewEntity(), op)
    -- SCP-096 in its cell, facing the hall camera.
    local scp = makeSCP("scp096")
    scp:SetPos(Vector(4200, 0, 0))
    local hall = S.cam_hall
    hall:SetAngles((scp:EyePos() - hall:GetPos()):Angle())
    face(scp, hall:GetPos())
    op:SetPos(term:GetPos())
    MOCK.rpc(op, "cctv.view", term, 2)
    eq(op:GetViewEntity(), hall)
    MOCK.advance(0.5)
    expect(SV.SCP.S096.isTarget(op), "face on a monitor did not make a target")
    MOCK.disconnect(scp)
    MOCK.advance(0.5)
    -- Masked camera inside the cell does not show the face.
    local scp2 = makeSCP("scp096")
    scp2:SetPos(Vector(4300, 0, 0))
    local inCell = S.cam_cell
    inCell:SetAngles((scp2:EyePos() - inCell:GetPos()):Angle())
    face(scp2, inCell:GetPos())
    SCP.get("scp096").data.maskedUntil = CurTime() + 600
    local op2 = staff("security", "sec_guard")
    op2:SetPos(term:GetPos())
    MOCK.rpc(op2, "cctv.view", term, 1)
    MOCK.advance(0.5)
    expect(not SV.SCP.S096.isTarget(op2), "masked in-cell camera showed the face")
end)

--[[---------------------------------------------------------------------------
SCP-999
---------------------------------------------------------------------------]]
TEST("SCP-999: hug heals but does not revive; calms SCP-096; minor breach; sweets recapture", function()
    setupMap()
    local scp = makeSCP("scp999")
    local st = SCP.get("scp999")
    expect(SCP.inCell("scp999", scp:GetPos()), "SCP-999 not in its cell")
    local v = staff("classd", "classd_worker")
    v:SetPos(scp:GetPos() + Vector(40, 0, 0))
    v:SetHealth(50)
    face(scp, v:GetPos())
    MOCK.hullFn = function(tr)
        if tr.start:DistToSqr(tr.endpos) < 1 then return {Hit = false, HitPos = tr.endpos, Entity = MOCK.world, Fraction = 1} end
        return {Hit = true, HitPos = v:GetPos(), Entity = v, Fraction = 0.5}
    end
    local hug = SCP.defs.scp999.abilities.hug
    expect(hug(scp, st), "hug refused")
    eq(v:Health(), 50 + SV.Config.SCP.scp999.heal)
    v:TakeDamageInfo(MOCK.makeDamage({damage = 150, type = DMG_CLUB}))
    st.nextHug = 0
    expect(not hug(scp, st), "hug revived an incapacitated person")
    MOCK.hullFn = nil
    -- Calm a raging SCP-096 nearby.
    local p096 = makeSCP("scp096")
    SCP.authorize("scp096", 600) -- escorted out of its cell for the test
    p096:SetPos(scp:GetPos() + Vector(100, 0, 0))
    local w = staff("classd", "classd_worker")
    w:SetPos(Vector(500, 0, 0))
    SCP.S096.addTarget(w, "test")
    MOCK.advance(SV.Config.SCP.scp096.triggerTime + 0.5)
    eq(SCP.get("scp096").data.mode, "rage")
    expect(SCP.defs.scp999.abilities.calm(scp, st), "calm refused")
    eq(SCP.get("scp096").data.mode, "calming")
    MOCK.disconnect(p096)
    -- Leaving the cell is a minor breach: local alert only.
    scp:SetPos(Vector(1500, 0, 0))
    MOCK.advance(1.5)
    expect(st.breached, "not breached")
    eq(Facility.stateId(), "normal", "harmless object started a facility breach")
    expect(Facility.hasAlert("hcz") or Facility.hasAlert("lcz"), "no local alert")
    -- Sweets bring it back.
    local sci = staff("science", "sci_junior")
    sci:SetPos(Vector(1540, 0, 0))
    MOCK.rpc(sci, "scp.recapture", scp)
    expect(not SV.Actions.active[sci], "recapture without sweets")
    SV.Inv.add(sci, "sweets", 2, {force = true})
    MOCK.rpc(sci, "scp.recapture", scp)
    MOCK.advance(SV.Config.SCP.scp999.recaptureTime + 1, 0.5)
    expect(not st.breached, "not recontained")
    eq(SV.Inv.count(sci, "sweets"), 1, "sweets not spent")
end)

--[[---------------------------------------------------------------------------
Scoreboard (shared row logic; the panel itself is covered by the client smoke test)
---------------------------------------------------------------------------]]
TEST("scoreboard: strangers hidden from players, details only for admins", function()
    setupMap()
    local viewer = staff("security", "sec_guard")
    local admin = MOCK.join({name = "AdminViewer", admin = true})
    local chaos = MOCK.join({name = "ChaosGuy"})
    chaos:setDarkRPVar("sv_div", "chaos")
    chaos:setDarkRPVar("rpname", "Тайный Агент")
    local row = SV.Scoreboard.row(viewer, chaos)
    eq(row.group, "_unknown")
    eq(row.name, "Неизвестный")
    expect(row.steam == nil, "steam name shown to a player")
    local arow = SV.Scoreboard.row(admin, chaos)
    eq(arow.group, "chaos")
    eq(arow.name, "Тайный Агент")
    expect(arow.steam, "admin does not see the steam name")
    local own = SV.Scoreboard.row(viewer, viewer)
    eq(own.group, "security")
    expect(own.rank and own.number, "rank or number missing")
    local lobby = SV.Scoreboard.row(viewer, admin)
    eq(lobby.group, "_lobby")
end)

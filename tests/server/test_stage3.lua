--[[---------------------------------------------------------------------------
Stage 3: infrastructure, facility states, engineering, map configuration.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local F = SV.Config.Facility

local function box(x1, x2)
    return {min = {x1, -1000, -100}, max = {x2, 1000, 500}}
end

-- Two sectors next to each other, nodes in both, one generator.
local function setupMap()
    MapCfg.cfg = {
        version = 1, map = "gm_test", zones = {
            {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 2000)}, props = {priority = 1, demand = 40}},
            {id = "hcz", kind = "sector", name = "Тяжёлая зона", boxes = {box(2000, 4000)}, props = {priority = 3, demand = 40}},
            {id = "evac1", kind = "evac", name = "Шлюз эвакуации", boxes = {box(5000, 5500)}, props = {}},
        },
        points = {
            {id = "gen", kind = "node", pos = {100, 0, 0}, ang = {0, 0, 0}, props = {subsystem = "generator", sector = "lcz"}},
            {id = "lcz_pow", kind = "node", pos = {200, 0, 0}, ang = {0, 0, 0}, props = {subsystem = "power", sector = "lcz"}},
            {id = "lcz_com", kind = "node", pos = {300, 0, 0}, ang = {0, 0, 0}, props = {subsystem = "comms", sector = "lcz"}},
            {id = "lcz_vent", kind = "node", pos = {400, 0, 0}, ang = {0, 0, 0}, props = {subsystem = "ventilation", sector = "lcz"}},
            {id = "hcz_pow", kind = "node", pos = {2200, 0, 0}, ang = {0, 0, 0}, props = {subsystem = "power", sector = "hcz"}},
            {id = "hcz_sec", kind = "node", pos = {2300, 0, 0}, ang = {0, 0, 0}, props = {subsystem = "security", sector = "hcz"}},
            {id = "term_infra", kind = "terminal", pos = {500, 0, 0}, ang = {0, 0, 0}, props = {terminal = "infrastructure"}},
        },
        doors = {},
    }
    MapCfg.reindex()
    Facility.sectors = {}
    Facility.nodes = {}
    Facility.sabotageLog = {}
    Facility.build()
    MapCfg.spawnEntities()
end

local function engineer(name, rank)
    local p = makeStaff({steam = name, name = uniqueName("Инна Инженерова"), division = "engineering", rank = rank or 3, role = "eng_engineer"})
    return p
end

TEST("model built from map config", function()
    setupMap()
    eq(SV.Util.count(Facility.sectors), 2)
    eq(SV.Util.count(Facility.nodes), 6)
    eq(Facility.power("lcz"), 1)
    expect(IsValid(MapCfg.spawned.gen), "node entity not spawned")
    expect(IsValid(MapCfg.spawned.term_infra), "terminal not spawned")
end)

TEST("generator damage starves the low-priority sector, backup takes over", function()
    setupMap()
    Facility.nodes.gen.health = 40 -- capacity drops below total demand (80)
    Facility.recompute()
    eq(Facility.power("lcz"), 1, "high priority sector lost power")
    local hcz = Facility.sectors.hcz
    expect(hcz.alloc < 1, "low priority sector still fully allocated")
    expect(hcz.backup, "backup did not start")
    eq(Facility.power("hcz"), F.backupLevel)
    local fuel = hcz.fuel
    MOCK.advance(10, 1)
    expect(hcz.fuel < fuel, "backup does not burn fuel")
    hcz.fuel = 0
    Facility.recompute()
    expect(Facility.power("hcz") < F.backupLevel, "backup without fuel")
end)

TEST("shed sector gets no power; priorities can be changed only by engineers", function()
    setupMap()
    local term = MapCfg.spawned.term_infra
    local tech = makeStaff({steam = "Tech", name = "Тихон Техников", division = "engineering"})
    tech:SetPos(term:GetPos())
    MOCK.rpc(tech, "infra.priority", term, "hcz", 0)
    eq(Facility.sectors.hcz.priority, 3, "technician without powerControl changed priority")
    local eng = engineer("Eng1")
    eng:SetPos(term:GetPos())
    MOCK.rpc(eng, "infra.priority", term, "hcz", 0)
    eq(Facility.sectors.hcz.priority, 0)
    eq(Facility.power("hcz"), 0)
    expect(not Facility.devicePowered("hcz", "doors"))
end)

TEST("doors depend on power and the security subsystem", function()
    setupMap()
    local door = MOCK.newEntity("func_door")
    door.mapId = 900
    door:SetPos(Vector(2500, 0, 0))
    MapCfg.cfg.doors["900"] = {name = "Шлюз ТЗС", clearance = 0, sector = "hcz"}
    local d = makeStaff({steam = "DoorD", name = "Дарья Проходова", division = "classd"})
    d:SetPos(door:GetPos())
    hook.Run("PlayerUse", d, door)
    expect(SV.Access.openDoors[door], "powered door did not open")
    SV.Access.openDoors[door] = nil
    MOCK.advance(1)
    Facility.nodes.hcz_sec.health = 5
    Facility.recompute()
    hook.Run("PlayerUse", d, door)
    expect(not SV.Access.openDoors[door], "door opened with failed controller")
    contains(MOCK.lastNotify(d), "нет питания")
end)

TEST("diagnose, repair with parts, events feed tasks and recovery", function()
    setupMap()
    local eng = engineer("Eng2")
    eng:SetPos(Vector(2200, 0, 0))
    local node = Facility.nodes.hcz_pow
    node.health = 30
    node.fault = "short"
    expect(SV.Tasks.accept(eng, "eng_repair"))
    local ent = MapCfg.spawned.hcz_pow
    MOCK.rpc(eng, "infra.action", ent, "repair")
    -- repair needs parts: engineer kit has 3 spare parts, short needs 2
    MOCK.advance(F.repairBase + 2 * F.repairPerSeverity + 1)
    expect(node.health > 99, "node not repaired: " .. tostring(MOCK.lastNotify(eng)))
    eq(node.fault, nil)
    eq(SV.Inv.count(eng, "spare_parts"), 1)
    eq(eng.SVChar.data.tasks.active.eng_repair.progress, 1)
    MOCK.rpc(eng, "infra.action", ent, "repair")
    contains(MOCK.lastNotify(eng), "исправен")
end)

TEST("repair requires the tool and parts", function()
    setupMap()
    local d = makeStaff({steam = "NotEng", name = "Наум Неинженеров", division = "classd"})
    d:SetPos(Vector(2200, 0, 0))
    Facility.nodes.hcz_pow.health = 20
    MOCK.rpc(d, "infra.action", MapCfg.spawned.hcz_pow, "repair")
    contains(MOCK.lastNotify(d), "инструмент")
    local eng = engineer("Eng1")
    eng:SetPos(Vector(2200, 0, 0))
    SV.Inv.take(eng, "spare_parts", SV.Inv.count(eng, "spare_parts"))
    MOCK.rpc(eng, "infra.action", MapCfg.spawned.hcz_pow, "repair")
    contains(MOCK.lastNotify(eng), "запчастей")
end)

TEST("bypass works temporarily, then the node fails", function()
    setupMap()
    local eng = engineer("Eng1")
    eng:SetPos(Vector(200, 0, 0))
    local node = Facility.nodes.lcz_pow
    node.health = 20
    MOCK.rpc(eng, "infra.action", MapCfg.spawned.lcz_pow, "bypass")
    MOCK.advance(F.bypassTime + 1)
    expect(node.health >= F.bypassHealth - 1, "bypass did not restore health")
    expect(node.bypassUntil, "no bypass timer")
    MOCK.advance(F.bypassDuration + 5, 1)
    expect(node.health <= 10, "bypass did not fail")
    eq(node.fault, "short")
end)

TEST("sabotage limits: cooldown, generator preparation and floor", function()
    setupMap()
    local saboteur = makeStaff({steam = "Sab", name = "Савва Диверсантов", division = "engineering"})
    saboteur:SetPos(Vector(400, 0, 0))
    local vent = Facility.nodes.lcz_vent
    MOCK.rpc(saboteur, "infra.action", MapCfg.spawned.lcz_vent, "sabotage")
    MOCK.advance(F.sabotage.time + 1)
    expect(vent.health < 60, "sabotage had no effect")
    eq(vent.fault, "tamper")
    saboteur:SetPos(Vector(200, 0, 0))
    MOCK.advance(5)
    MOCK.rpc(saboteur, "infra.action", MapCfg.spawned.lcz_pow, "sabotage")
    contains(MOCK.lastNotify(saboteur), "недавно")
    -- generator: first step only prepares
    MOCK.advance(F.sabotage.cooldown + 1, 1)
    saboteur:SetPos(Vector(100, 0, 0))
    local gen = Facility.nodes.gen
    local before = gen.health
    MOCK.rpc(saboteur, "infra.action", MapCfg.spawned.gen, "sabotage")
    MOCK.advance(F.sabotage.time + 1)
    expect(gen.prepared, "generator not prepared")
    expect(gen.health > before - 20, "generator destroyed in one step")
    -- the window limit (2 per 15 min) now blocks the second step
    MOCK.advance(F.sabotage.cooldown + 1, 1)
    MOCK.rpc(saboteur, "infra.action", MapCfg.spawned.gen, "sabotage")
    contains(MOCK.lastNotify(saboteur), "слишком много")
    expect(gen.health >= F.sabotage.generatorFloor)
end)

TEST("broken comms garble radio across sectors", function()
    setupMap()
    local a = makeStaff({steam = "RadA", name = "Радий Передатчиков", division = "security"})
    local b = makeStaff({steam = "RadB", name = "Роза Приёмникова", division = "security"})
    a:SetPos(Vector(300, 0, 0)) b:SetPos(Vector(3000, 0, 0))
    MOCK.advance(1.5) -- sector tracking
    expect(SV.Comms.linkQuality(a, b) > 0.9)
    Facility.nodes.lcz_com.health = 25
    expect(SV.Comms.linkQuality(a, b) < SV.Config.Radio.garbleFrom, "radio not degraded")
    b:SetPos(Vector(500, 0, 0))
    eq(SV.Comms.linkQuality(a, b), 1, "short range should work")
end)

TEST("ventilation contamination hurts unmasked players only", function()
    setupMap()
    local vent = Facility.nodes.lcz_vent
    vent.fault = "contamination"
    vent.health = 50
    local p = makeStaff({steam = "Breath", name = "Вадим Дышащий", division = "engineering"})
    local q = makeStaff({steam = "Mask", name = "Мария Противогазова", division = "engineering"})
    p:SetPos(Vector(600, 0, 0)) q:SetPos(Vector(650, 0, 0))
    SV.Inv.add(q, "gas_mask", 1)
    local mask = SV.Inv.find(q, function(it) return it.id == "gas_mask" end)[1]
    SV.Inv.use(q, mask)
    local damaged = {}
    hook.Add("EntityTakeDamage", "test.contam", function(ent, dmg) if dmg:GetDamageType() == DMG_NERVEGAS then damaged[ent] = true end end)
    MOCK.advance(9, 1)
    hook.Remove("EntityTakeDamage", "test.contam")
    expect(Facility.sectors.lcz.contaminated, "sector not contaminated")
    expect(damaged[p], "unmasked player not hurt")
    expect(not damaged[q], "masked player hurt")
end)

TEST("facility states: authority, cooldown, breach blocks recovery", function()
    setupMap()
    MOCK.advance(F.stateCooldown + 1)
    local guard = makeStaff({steam = "StGuard", name = "Степан Постов", division = "security"})
    local ok, msg = Facility.setState("breach", guard, "тест")
    expect(not ok)
    contains(msg, "полномочий")
    SV.Chars.grantWhitelist(guard:SteamID64(), "role", "sec_chief", nil, "test")
    guard.SVChar.rank = 5
    expect(SV.Chars.assignRole(guard, SV.Roles.get("sec_chief"), {reason = "test"}))
    ok = Facility.setState("breach", guard, "SCP-173 вне камеры")
    expect(ok, "chief could not declare breach")
    eq(Facility.stateId(), "breach")
    ok, msg = Facility.setState("recovery", guard, "")
    expect(not ok, "no cooldown")
    MOCK.advance(F.stateCooldown + 1)
    SV.SCP = SV.SCP or {}
    local saved = SV.SCP.breachedCount
    SV.SCP.breachedCount = function() return 1 end
    ok, msg = Facility.setState("recovery", guard, "")
    expect(not ok)
    contains(msg, "вне камер")
    SV.SCP.breachedCount = function() return 0 end
    ok = Facility.setState("recovery", guard, "")
    expect(ok)
    MOCK.advance(F.recoveryMaxTime + 5, 1)
    eq(Facility.stateId(), "normal", "recovery did not end automatically")
    SV.SCP.breachedCount = saved
end)

TEST("automatic breach and recovery from SCP events", function()
    setupMap()
    Facility.state = {id = "normal", since = CurTime(), reason = ""}
    SV.SCP = SV.SCP or {}
    local saved = SV.SCP.breachedCount
    SV.SCP.breachedCount = function() return 1 end
    SV.Bus.emit("scp.breached", {name = "SCP-173"})
    eq(Facility.stateId(), "breach")
    SV.SCP.breachedCount = function() return 0 end
    SV.Bus.emit("scp.recontained", {name = "SCP-173"})
    eq(Facility.stateId(), "recovery")
    SV.SCP.breachedCount = saved
end)

TEST("lockdown duration, extension limit, evacuation lifts lockdowns, evac credit", function()
    setupMap()
    Facility.state = {id = "normal", since = -1000, reason = ""}
    Facility.flags = {}
    expect(Facility.setLockdown("hcz", nil, true, "тест"))
    expect(Facility.isLockedDown("hcz"))
    expect(Facility.setLockdown("hcz", nil, true, "продление"))
    local ok = Facility.setLockdown("hcz", nil, true, "ещё")
    expect(not ok, "unlimited extensions")
    MOCK.advance(F.lockdownMax + 3, 1)
    expect(not Facility.isLockedDown("hcz"), "lockdown did not expire")
    Facility.setLockdown("hcz", nil, true, "снова")
    Facility.setState("breach", nil, "тест", {force = true})
    Facility.state.since = -1000
    Facility.setState("evacuation", nil, "тест", {force = true})
    expect(not Facility.isLockedDown("hcz"), "evacuation kept lockdown")
    local p = makeStaff({steam = "Evac", name = "Эвелина Уходящая", division = "science"})
    p:SetPos(Vector(5200, 0, 0))
    local xp = p.SVChar.xp
    MOCK.advance(3)
    eq(p.SVChar.xp, xp + F.evacuationXP)
    MOCK.advance(3)
    eq(p.SVChar.xp, xp + F.evacuationXP, "evacuation credited twice")
end)

TEST("terminal requires power and access", function()
    setupMap()
    local term = MapCfg.spawned.term_infra
    local d = makeStaff({steam = "TermD", name = "Тамара Терминалова", division = "classd"})
    d:SetPos(term:GetPos())
    local ok = SV.Terminals.canUse(d, term, "infrastructure", true)
    expect(not ok, "class D used the infrastructure terminal")
    local eng = engineer("Eng1")
    eng:SetPos(term:GetPos())
    expect(SV.Terminals.canUse(eng, term, "infrastructure", true))
    Facility.sectors.lcz.priority = 0
    Facility.recompute()
    ok = SV.Terminals.canUse(eng, term, "infrastructure", true)
    expect(not ok, "unpowered terminal works")
end)

TEST("map editor: rights, server-side positions, sanitised door config, save/reload", function()
    setupMap()
    local user = MOCK.join({name = "User"})
    MOCK.rpc(user, "mapcfg.addPoint", "spawn", {group = "any"}, false)
    expect(#user.SVViolations >= 1, "non-admin edit not flagged")
    local admin = MOCK.join({name = "Root", superadmin = true})
    MOCK.rpc(admin, "mapcfg.addPoint", "spawn", {group = "any"}, false)
    contains(MOCK.lastNotify(admin), "дежурства")
    SV.Admin.setDuty(admin, true)
    admin:SetPos(Vector(123, 45, 6))
    local n = #MapCfg.cfg.points
    MOCK.rpc(admin, "mapcfg.addPoint", "spawn", {group = "security", evil = "x"}, false)
    eq(#MapCfg.cfg.points, n + 1)
    local p = MapCfg.cfg.points[#MapCfg.cfg.points]
    eq(p.pos[1], 123)
    eq(p.props.group, "security")
    eq(p.props.evil, nil, "unknown prop kept")

    local door = MOCK.newEntity("func_door")
    door.mapId = 77
    MOCK.rpc(admin, "mapcfg.setDoor", door, {clearance = 99, policy = "weird", tags = {"armory", "nope"}, name = "Оружейная"})
    local cfg = MapCfg.cfg.doors["77"]
    eq(cfg.clearance, 5)
    eq(cfg.policy, "card")
    eq(#cfg.tags, 1)

    MOCK.rpc(admin, "mapcfg.command", "save")
    expect(file.Exists("siteveil/maps/gm_test.json", "DATA"), "config not saved")
    MapCfg.cfg = nil
    MapCfg.load()
    eq(MapCfg.source, "data")
    eq(MapCfg.cfg.doors["77"].clearance, 5)
    expect(MapCfg.point(p.id), "point lost after reload")
end)

TEST("zone creation needs both corners, validation catches broken data", function()
    local admin = MOCK.join({name = "Root2", superadmin = true})
    SV.Admin.setDuty(admin, true)
    MOCK.rpc(admin, "mapcfg.addZone", "sector", "new_sector", "Новый", {})
    contains(MOCK.lastNotify(admin), "угла")
    admin.SVMapCorners = {{0, 0, 0}, {800, 800, 0}}
    MOCK.rpc(admin, "mapcfg.addZone", "sector", "new_sector", "Новый", {priority = 2})
    expect(MapCfg.zone("new_sector"), "zone not created")
    local z = MapCfg.zone("new_sector")
    eq(z.boxes[1].max[3], 160, "flat box not raised")

    local broken = {version = 1, zones = {{id = "a", kind = "sector", boxes = {{min = {10, 0, 0}, max = {0, 10, 10}}}, props = {}},
        {id = "a", kind = "nope", boxes = {}, props = {}}}, points = {{id = "p", kind = "node", pos = {0, 0, 0}, props = {subsystem = "x", sector = "zz"}}}, doors = {["999"] = {clearance = 9}}}
    local r = MapCfg.validate(broken)
    expect(#r.errors >= 6, "validation missed errors: " .. #r.errors)
end)

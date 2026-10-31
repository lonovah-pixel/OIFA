--[[---------------------------------------------------------------------------
Records the server's answers for every window of the client so that the
client smoke test (tests/client) can replay real payloads through the
client handlers. Runs last among the server tests (file name).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local MapCfg = SV.MapCfg
local Facility = SV.Facility

local function box(x1, x2)
    return {min = {x1, -1000, -100}, max = {x2, 1000, 500}}
end

local function point(id, kind, x, props)
    return {id = id, kind = kind, pos = {x, 0, 0}, ang = {0, 0, 0}, props = props or {}}
end

local function staff(division, role, rank, whitelist)
    local r = SV.Roles.get(role)
    local q = r.quota
    r.quota = nil
    local p = makeStaff({steam = role, name = uniqueName("Тест Тестов"), division = division, role = role, rank = rank or 1, whitelist = whitelist})
    r.quota = q
    return p
end

TEST("record window payloads", function()
    MapCfg.cfg = {version = 1, map = "gm_test", zones = {
        {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 4000)}, props = {priority = 2, demand = 30}},
        {id = "cell173", kind = "cell", name = "Камера", boxes = {box(3000, 3500)}, props = {scp = "scp173"}},
    }, points = {
        point("gen", "node", 100, {subsystem = "generator", sector = "lcz"}),
        point("pow", "node", 120, {subsystem = "power", sector = "lcz"}),
        point("t_research", "terminal", 500, {terminal = "research"}),
        point("t_security", "terminal", 500, {terminal = "security"}),
        point("t_medical", "terminal", 500, {terminal = "medical"}),
        point("t_records", "terminal", 500, {terminal = "records"}),
        point("t_infra", "terminal", 500, {terminal = "infrastructure"}),
        point("t_logistics", "terminal", 500, {terminal = "logistics"}),
        point("panel173", "panel", 500, {scp = "scp173"}),
        point("t_intercom", "terminal", 500, {terminal = "intercom"}),
        point("t_cctv", "terminal", 500, {terminal = "cctv"}),
        point("cam1", "camera", 900, {name = "Камера 1"}),
    }, doors = {}}
    MapCfg.reindex()
    Facility.sectors, Facility.nodes = {}, {}
    Facility.build()
    MapCfg.spawnEntities()
    local S = MapCfg.spawned
    local director = staff("administration", "adm_director", 5, true)
    director:SetPos(Vector(500, 30, 0))
    director.admin = true
    local inv = staff("security", "sec_investigator", 4)
    inv:SetPos(Vector(510, 0, 0))
    local doc = staff("medical", "med_doctor", 3)
    doc:SetPos(Vector(520, 0, 0))
    local eng = staff("engineering", "eng_engineer", 3)
    eng:SetPos(Vector(530, 0, 0))
    local sci = staff("science", "sci_senior", 4)
    sci:SetPos(Vector(500, -20, 0))
    SV.Inv.add(inv, "evidence_bag", 1, {force = true, data = {evidence = 1, title = "Улика №1"}})

    local function use(p, ent) SV.Terminals.use(p, ent) end
    use(sci, S.t_research)
    MOCK.advance(1)
    MOCK.rpc(sci, "research.history", S.t_research)
    use(inv, S.t_security)
    MOCK.rpc(inv, "case.list")
    use(doc, S.t_medical)
    use(sci, S.t_records)
    MOCK.rpc(sci, "know.list")
    use(eng, S.t_infra)
    eng:SetPos(Vector(110, 0, 0))
    MOCK.rpc(eng, "infra.node", S.gen)
    eng:SetPos(Vector(530, 0, 0))
    use(eng, S.t_logistics)
    MOCK.rpc(sci, "scp.panel", S.panel173)
    MOCK.rpc(doc, "med.examine", eng)
    MOCK.rpc(eng, "facility.status")
    MOCK.rpc(eng, "char.roles")
    MOCK.rpc(eng, "access.cards")
    MOCK.rpc(eng, "sec.checkId", doc)
    local card = SV.Inv.find(eng, function(it) return it.id == "id_card" end)[1]
    if card then MOCK.rpc(eng, "inv.inspect", card.uid) end
    use(director, S.t_intercom)
    use(director, S.t_cctv)
    SV.Admin.setDuty(director, true)
    MOCK.rpc(director, "admin.status")
    MOCK.rpc(director, "director.status")
    MOCK.rpc(director, "access.log", S.t_research)
    for _, ev in ipairs({"research.protocols", "research.history", "evidence.terminal", "case.list", "med.terminal", "know.terminal", "know.list",
        "infra.overview", "infra.node", "supply.overview", "scp.panel", "med.report", "facility.status", "char.roles", "admin.status", "director.status", "intercom.open", "cctv.open"}) do
        expect(MOCK.pushSamples[ev], "no payload recorded for " .. ev)
    end
end)

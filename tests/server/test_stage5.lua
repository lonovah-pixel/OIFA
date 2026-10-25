--[[---------------------------------------------------------------------------
Stage 5: "Исследования с неизвестным результатом".
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local Research = SV.Research
local SCP = SV.SCP

local function box(x1, x2)
    return {min = {x1, -1000, -100}, max = {x2, 1000, 500}}
end

local function setupMap()
    for _, p in ipairs(player.GetAll()) do MOCK.disconnect(p) end
    MOCK.advance(0.3)
    MapCfg.cfg = {version = 1, map = "gm_test", zones = {
        {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 2000)}, props = {priority = 2, demand = 30}},
        {id = "hcz", kind = "sector", name = "Тяжёлая зона", boxes = {box(2000, 6000)}, props = {priority = 3, demand = 30}},
        {id = "cell173", kind = "cell", name = "Камера SCP-173", boxes = {box(2100, 2500)}, props = {scp = "scp173"}},
        {id = "lab", kind = "testchamber", name = "Лаборатория", boxes = {box(500, 900)}, props = {}},
    }, points = {
        {id = "gen", kind = "node", pos = {100, 0, 0}, ang = {0, 0, 0}, props = {subsystem = "generator", sector = "lcz"}},
        {id = "term", kind = "terminal", pos = {700, 0, 0}, ang = {0, 0, 0}, props = {terminal = "research"}},
    }, doors = {}}
    MapCfg.reindex()
    Facility.sectors, Facility.nodes, Facility.sabotageLog = {}, {}, {}
    Facility.build()
    MapCfg.spawnEntities()
    Research.lastRun = {}
    for id, exp in pairs(Research.active) do Research.active[id] = nil exp.status = "cancelled" end
    Research.byPlayer = {}
    for _, st in pairs(SCP.state) do st.breached, st.integrity, st.stage = false, 100, "stable" end
    return MapCfg.spawned.term
end

local function staff(division, role, rank)
    local p = makeStaff({steam = role, name = uniqueName("Тест Тестов"), division = division, role = role, rank = rank or 1})
    p:SetPos(Vector(700, 40, 0))
    return p
end

-- Research XP granted to each character (other XP sources are ignored).
local researchXP = {}
local addXP = SV.Chars.addXP
SV.Chars.addXP = function(p, amount, source, ...)
    if source == "research" and p.SVChar then researchXP[p.SVChar.id] = (researchXP[p.SVChar.id] or 0) + amount end
    return addXP(p, amount, source, ...)
end

local function xpOf(p)
    return researchXP[p.SVChar.id] or 0
end

--- Runs all steps of the player's experiment, each by the given performer.
local function runSteps(exp, performers)
    for i = 1, #exp.protocol.steps do
        local p = performers[i] or exp.lead
        MOCK.rpc(p, "research.step", exp.id)
        expect(SV.Actions.active[p], "step " .. i .. " not started: " .. tostring(MOCK.lastNotify(p)))
        MOCK.advance(exp.protocol.steps[i].time + 0.5, 0.5)
    end
end

TEST("only researchers lead; protocol needs its subject; full run is recorded and replayable", function()
    local term = setupMap()
    local junior = staff("science", "sci_junior")
    MOCK.rpc(junior, "research.create", term, "pao_echo")
    expect(not Research.byPlayer[junior], "junior researcher created an experiment")

    local lead = staff("science", "sci_researcher", 3)
    MOCK.rpc(lead, "research.create", term, "pao_echo")
    local exp = Research.byPlayer[lead]
    expect(exp, "experiment not created: " .. tostring(MOCK.lastNotify(lead)))
    MOCK.rpc(lead, "research.start")
    eq(exp.status, "draft", "started without the subject item")
    SV.Inv.add(lead, "ao_echo", 1, {force = true})
    MOCK.rpc(lead, "research.start")
    eq(exp.status, "running", "not started: " .. tostring(MOCK.lastNotify(lead)))
    local xp = xpOf(lead)
    runSteps(exp, {})
    expect(not Research.active[exp.id], "experiment still active")
    local row = SV.DB.queryRow("SELECT * FROM sv_experiments WHERE id = ?", exp.id)
    eq(row.status, "completed")
    expect(row.seed and row.weights and row.outcome, "roll not recorded")
    -- Replay of the stored roll gives the stored outcome.
    local pick = SV.RNG.new(tonumber(row.seed)):weighted(SV.DB.decode(row.weights))
    eq(pick, row.outcome, "replay differs")
    expect(xpOf(lead) > xp, "no reward")
    -- Cooldown: the protocol cannot be repeated at once.
    MOCK.rpc(lead, "research.create", term, "pao_echo")
    expect(not Research.byPlayer[lead], "protocol repeated during its cooldown")
end)

TEST("anti-farm: second run in the same shift gives no reward; weights fall with repetition", function()
    local term = setupMap()
    local lead = staff("science", "sci_researcher", 3)
    SV.Inv.add(lead, "ao_echo", 1, {force = true})
    local function run()
        Research.lastRun = {}
        MOCK.rpc(lead, "research.create", term, "pao_echo")
        local exp = Research.byPlayer[lead]
        expect(exp, "not created: " .. tostring(MOCK.lastNotify(lead)))
        local w = Research.weights(exp, Research.buildContext(exp))
        MOCK.rpc(lead, "research.start")
        runSteps(exp, {})
        return w
    end
    local w1 = run()
    local xp = xpOf(lead)
    local w2 = run()
    eq(xpOf(lead), xp, "rewarded twice in one shift")
    expect(w2.data < w1.data, "data weight did not fall with repetition")
    expect(w2.none > w1.none, "'no result' weight did not grow with repetition")
end)

TEST("dangerous protocol needs approval by someone else who is on shift", function()
    local term = setupMap()
    local lead = staff("science", "sci_researcher", 3)
    MOCK.rpc(lead, "research.create", term, "p049_tissue")
    -- Clearance 3 protocol: a researcher (clearance 2) cannot lead it.
    expect(not Research.byPlayer[lead], "clearance not checked")
    local senior = staff("science", "sci_senior", 4)
    MOCK.rpc(senior, "research.create", term, "p049_tissue")
    local exp = Research.byPlayer[senior]
    expect(exp, "not created: " .. tostring(MOCK.lastNotify(senior)))
    expect(not exp.approved)
    MOCK.rpc(senior, "research.requestApproval")
    eq(exp.status, "draft", "approval requested with no approver on shift")
    local other = staff("science", "sci_senior", 4)
    other:SetPos(Vector(1500, 0, 0))
    MOCK.rpc(senior, "research.requestApproval")
    eq(exp.status, "pending")
    MOCK.rpc(senior, "research.approve", exp.id, true, "")
    expect(not exp.approved, "approved own experiment")
    MOCK.rpc(other, "research.approve", exp.id, true, "Согласовано")
    expect(exp.approved, "approval failed")
    MOCK.rpc(senior, "research.cancel")
    expect(not Research.active[exp.id])
end)

TEST("critical step: losing a participant is an emergency; a clean step allows abort", function()
    local term = setupMap()
    local lead = staff("science", "sci_researcher", 3)
    local d = staff("classd", "classd_worker")
    SV.Inv.add(lead, "ao_liquid", 1, {force = true})
    MOCK.rpc(lead, "research.create", term, "pao_liquid")
    local exp = Research.byPlayer[lead]
    MOCK.rpc(lead, "research.invite", d)
    MOCK.rpc(d, "research.join", exp.id, true)
    eq(Research.byPlayer[d], exp, "invitation not accepted")
    MOCK.rpc(lead, "research.start")
    eq(exp.status, "running", "not started: " .. tostring(MOCK.lastNotify(lead)))
    MOCK.rpc(lead, "research.step", exp.id)
    MOCK.advance(exp.protocol.steps[1].time + 0.5, 0.5)
    -- Step 2 ("contact") is performed by class D and is critical.
    MOCK.rpc(lead, "research.step", exp.id)
    expect(not SV.Actions.active[lead], "lead performed a class D step")
    MOCK.rpc(d, "research.step", exp.id)
    expect(SV.Actions.active[d], "class D step not started")
    MOCK.disconnect(d)
    MOCK.advance(1)
    expect(not Research.active[exp.id], "experiment continued")
    eq(SV.DB.queryValue("SELECT status FROM sv_experiments WHERE id = ?", exp.id), "emergency")
end)

TEST("breach of the subject aborts; disconnect of the lead in a draft cancels", function()
    local term = setupMap()
    local lead = staff("science", "sci_researcher", 3)
    -- p173_blink is in the cell of SCP-173 and needs approval; check abort path on breach.
    MOCK.rpc(lead, "research.create", term, "p173_blink")
    local exp = Research.byPlayer[lead]
    expect(exp, "not created: " .. tostring(MOCK.lastNotify(lead)))
    SCP.breach("scp173", "test")
    expect(not Research.active[exp.id], "experiment survived the breach")
    SCP.state.scp173.breached = false
    Research.lastRun = {}
    SV.Inv.add(lead, "ao_echo", 1, {force = true})
    MOCK.rpc(lead, "research.create", term, "pao_echo")
    local e2 = Research.byPlayer[lead]
    expect(e2)
    MOCK.disconnect(lead)
    MOCK.advance(0.5)
    expect(not Research.active[e2.id], "draft kept after the lead left")
end)

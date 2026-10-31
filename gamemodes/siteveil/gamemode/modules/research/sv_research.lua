--[[---------------------------------------------------------------------------
"Исследования с неизвестным результатом" (server).

Lifecycle of an experiment:
  draft ──(approval for danger >= 3)──▶ approved ──start──▶ running(step 1..n)
     │                                                        │      │
     └──cancel                                  abort / failure      └──▶ completed
                                                        │
                                       critical step ──▶ emergency (incident roll)

The outcome is rolled once on completion from weights that depend on the
protocol, equipment (quality), participants, environment and safety measures
(risk) and on repetition (diminishing returns). The roll uses a seeded
generator; the seed and the weights are stored so the result can be
reproduced (sv_research_replay <id>).

Anti-farm: protocol cooldown, diminishing returns over two hours, rewards
once per character per protocol per shift, discoveries once ever.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Research = SV.Research
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local Roles = SV.Roles
local Inv = SV.Inv

Research.protocols = {}
for _, p in ipairs(C.Protocols) do Research.protocols[p.id] = p end

--- Adds a research protocol (addons). Same fields as config/sv_protocols.lua.
function Research.registerProtocol(p)
    assert(isstring(p.id) and isstring(p.subject) and istable(p.outcomes) and istable(p.steps), "invalid protocol")
    if Research.protocols[p.id] then
        for i, x in ipairs(C.Protocols) do
            if x.id == p.id then table.remove(C.Protocols, i) break end
        end
    end
    p.participants = p.participants or {}
    p.equipment = p.equipment or {}
    table.insert(C.Protocols, p)
    Research.protocols[p.id] = p
end

Research.active = Research.active or {}      -- id -> experiment
Research.byPlayer = Research.byPlayer or {}  -- ply -> experiment
Research.lastRun = Research.lastRun or {}    -- protocol -> CurTime of last completion

DB.registerMigrations("research", {
    {1, "experiments", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_experiments (
            id INTEGER PRIMARY KEY AUTOINCREMENT, protocol TEXT NOT NULL, subject TEXT NOT NULL, status TEXT NOT NULL,
            lead_char INTEGER, lead_name TEXT, participants TEXT, equipment TEXT, safety TEXT, environment TEXT,
            approved_by TEXT, seed INTEGER, weights TEXT, quality REAL, risk REAL, outcome TEXT, outcome_name TEXT,
            notes TEXT, created_at INTEGER NOT NULL, started_at INTEGER, finished_at INTEGER)]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_experiments_protocol ON sv_experiments (protocol, finished_at)")
        DB.query([[CREATE TABLE IF NOT EXISTS sv_experiment_rewards (char_id INTEGER NOT NULL, protocol TEXT NOT NULL,
            shift INTEGER NOT NULL, PRIMARY KEY (char_id, protocol, shift))]])
    end},
})

hook.Add("SiteVeil.DatabaseReady", "SiteVeil.Research", function()
    DB.query("UPDATE sv_experiments SET status = 'interrupted', notes = 'Перезапуск сервера', finished_at = ? WHERE status IN ('draft', 'pending', 'approved', 'running')", os.time())
end)

--[[---------------------------------------------------------------------------
Helpers
---------------------------------------------------------------------------]]
local function categoryOf(ply)
    local char = ply.SVChar
    if not char then return {} end
    local div = char.division
    local cats = {any = true}
    if div == "classd" then cats.classd = true else cats.staff = true end
    if div == "science" then cats.science = true end
    if div == "security" or div == "mtf" then cats.security = true end
    if div == "medical" then cats.medical = true end
    if div == "engineering" then cats.engineering = true end
    return cats
end

local function dossierOf(subject)
    local scpOrItem = string.match(subject, "^sample:(.+)$") or subject
    if scpOrItem == "scp0492" then return "scp049" end
    return scpOrItem
end

local function subjectAvailable(exp, protocol)
    local subject = protocol.subject
    local sampleOf = string.match(subject, "^sample:(.+)$")
    if sampleOf then
        for _, p in ipairs(exp.participantList) do
            for _, item in ipairs(Inv.find(p, function(it) return it.id == "sample" and it.data.scp == sampleOf end)) do
                return true, p, item
            end
        end
        return false, "нужен образец (" .. sampleOf .. ") у одного из участников"
    end
    if SV.SCP.defs[subject] then return true end
    if C.Items[subject] then
        for _, p in ipairs(exp.participantList) do
            if Inv.has(p, subject) then return true, p end
        end
        return false, "объект исследования (" .. C.Items[subject].name .. ") должен быть у участника"
    end
    return false, "неизвестный объект"
end

local function inZone(exp, ply)
    local protocol = exp.protocol
    if protocol.zone == "cell" then
        return SV.SCP.inCell(protocol.subject, ply:GetPos())
    end
    if not IsValid(exp.terminal) then return false end
    local tz = SV.MapCfg.zoneAt(exp.terminal:GetPos(), "testchamber")
    if tz and SV.MapCfg.zoneContains(tz, ply:GetPos()) then return true end
    return U.within(ply, exp.terminal, 700)
end

local function refreshParticipants(exp)
    local list = {}
    for _, p in ipairs(exp.members) do
        if IsValid(p) and p:Alive() and p.SVChar then list[#list + 1] = p end
    end
    exp.participantList = list
end

--- Context used by environment checks, safety checks and outcome effects.
local function buildContext(exp)
    refreshParticipants(exp)
    local ctx = {lead = exp.lead, participants = {}, byCategory = {classd = {}, security = {}, science = {}, medical = {}, engineering = {}, staff = {}, any = {}},
        approved = exp.approved, sector = exp.sector, experiment = exp}
    for _, p in ipairs(exp.participantList) do
        if inZone(exp, p) then
            ctx.participants[#ctx.participants + 1] = p
            for cat in pairs(categoryOf(p)) do table.insert(ctx.byCategory[cat], p) end
        end
    end
    return ctx
end
Research.buildContext = buildContext

--- Assigns participants to requirement slots. Returns ok, missing text.
local function requirementsMet(protocol, ctx)
    local used = {}
    local missing = {}
    for _, req in ipairs(protocol.participants) do
        local got = 0
        for _, p in ipairs(ctx.byCategory[req.category] or {}) do
            if got >= req.min then break end
            if not used[p] then
                used[p] = true
                got = got + 1
            end
        end
        if got < req.min then missing[#missing + 1] = req.label .. " (" .. got .. "/" .. req.min .. ")" end
    end
    if #missing > 0 then return false, "не хватает: " .. table.concat(missing, ", ") end
    return true
end

local function equipmentStatus(protocol, ctx)
    local function holderOf(itemId, n)
        for _, p in ipairs(ctx.participants) do
            if Inv.has(p, itemId, n) then return p end
        end
    end
    local missing = {}
    for itemId, n in pairs(protocol.equipment.required or {}) do
        if not holderOf(itemId, n) then missing[#missing + 1] = C.Items[itemId].name end
    end
    for itemId, n in pairs(protocol.equipment.consumed or {}) do
        if itemId ~= "sample" and not holderOf(itemId, n) then missing[#missing + 1] = C.Items[itemId].name end
    end
    local optional, quality = {}, 0
    for itemId, bonus in pairs(protocol.equipment.optional or {}) do
        local have = holderOf(itemId, 1) ~= nil
        optional[#optional + 1] = {id = itemId, name = C.Items[itemId].name, have = have, bonus = bonus}
        if have then quality = quality + bonus end
    end
    table.sort(optional, function(a, b) return a.id < b.id end)
    return #missing == 0, missing, optional, quality, holderOf
end

local function environmentStatus(protocol, ctx)
    local list, risk, blocked = {}, 0, nil
    for _, env in ipairs(protocol.environment or {}) do
        local ok = env.check(ctx) == true
        list[#list + 1] = {id = env.id, text = env.text, ok = ok}
        if not ok then
            risk = risk + (env.riskIfNot or 0)
            if env.required then blocked = env.text end
        end
    end
    return list, risk, blocked
end

local function safetyStatus(protocol, ctx)
    local list, reduction = {}, 0
    for _, s in ipairs(protocol.safety or {}) do
        local ok = s.check(ctx) == true
        list[#list + 1] = {id = s.id, name = s.name, ok = ok}
        if ok then reduction = reduction + s.risk end
    end
    return list, reduction
end

local function approverOnline(exp)
    for _, p in ipairs(player.GetAll()) do
        if p ~= exp.lead and (Roles.hasFlag(p, "approveExperiments") or SV.Admin.isOnDuty(p)) and p.SVChar then return true end
    end
    return false
end

local function needsApproval(protocol)
    return protocol.danger >= 3
end

local function runsRecently(protocolId)
    return tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_experiments WHERE protocol = ? AND status = 'completed' AND finished_at > ?",
        protocolId, os.time() - 7200)) or 0
end

--- Final weights for the outcome roll. Returns weights table, quality, risk.
function Research.weights(exp, ctx)
    local protocol = exp.protocol
    local _, _, _, quality = equipmentStatus(protocol, ctx)
    local extra = math.max(#ctx.participants - 1, 0) * 0.05
    quality = quality + math.min(extra, 0.2)
    local leadChar = IsValid(exp.lead) and exp.lead.SVChar
    if leadChar then quality = quality + (leadChar.rank - 1) * 0.03 end
    local _, envRisk = environmentStatus(protocol, ctx)
    local _, safety = safetyStatus(protocol, ctx)
    local risk = math.Clamp(0.1 * protocol.danger + envRisk - safety, 0, 1.5)
    local n = runsRecently(protocol.id)
    local dossierId = dossierOf(protocol.subject)
    local scpId = SV.SCP.defs[dossierId] and dossierId or (protocol.subject == "scp096" and "scp096" or nil)
    local weights = {}
    for _, o in ipairs(protocol.outcomes) do
        local w = o.weight
        if o.kind == "data" then w = w * (1 + quality) * (0.6 ^ n)
        elseif o.kind == "partial" then w = w * (1 + quality * 0.5) * (0.8 ^ n)
        elseif o.kind == "discovery" then
            w = w * (1 + quality) * (0.6 ^ n)
            if o.unlock and ((scpId and SV.SCP.hasUnlock(scpId, o.unlock)) or SV.SCP.hasUnlock("global", o.unlock)) then w = 0 end
        elseif o.kind == "incident" then w = w * (0.5 + risk)
        elseif o.kind == "none" then w = w * math.max(1 - quality * 0.5, 0.3) * (1 + 0.15 * n) end
        weights[o.id] = math.max(w, 0)
    end
    return weights, quality, risk
end

--[[---------------------------------------------------------------------------
Views
---------------------------------------------------------------------------]]
local function riskText(risk)
    if risk >= 0.9 then return "очень высокий" end
    if risk >= 0.6 then return "высокий" end
    if risk >= 0.3 then return "умеренный" end
    return "низкий"
end

function Research.view(exp)
    local protocol = exp.protocol
    local ctx = buildContext(exp)
    local okPeople, missingPeople = requirementsMet(protocol, ctx)
    local okEq, missingEq, optional = equipmentStatus(protocol, ctx)
    local env, _, blocked = environmentStatus(protocol, ctx)
    local safety = safetyStatus(protocol, ctx)
    local okSubject, subjectWhy = subjectAvailable(exp, protocol)
    local _, _, risk = Research.weights(exp, ctx)
    local members = {}
    for _, p in ipairs(exp.members) do
        if IsValid(p) then members[#members + 1] = {name = SV.Chars.displayName(p), inZone = inZone(exp, p), lead = p == exp.lead, ent = p:EntIndex()} end
    end
    local steps = {}
    for i, s in ipairs(protocol.steps) do
        steps[#steps + 1] = {name = s.name, by = s.by, time = s.time, critical = s.critical, done = exp.step and i < exp.step, current = exp.step == i}
    end
    return {
        id = exp.id, protocol = protocol.id, name = protocol.name, desc = protocol.desc, danger = protocol.danger, status = exp.status,
        approved = exp.approved, approvedBy = exp.approvedBy, needsApproval = needsApproval(protocol), approverOnline = approverOnline(exp),
        members = members, steps = steps, step = exp.step,
        people = {ok = okPeople, text = missingPeople}, equipment = {ok = okEq, missing = missingEq, optional = optional},
        environment = env, environmentBlocked = blocked, safety = safety, subject = {ok = okSubject, text = subjectWhy},
        risk = riskText(risk), lead = IsValid(exp.lead) and SV.Chars.displayName(exp.lead) or "—",
    }
end

local function pushState(exp)
    local v = Research.view(exp)
    for _, p in ipairs(exp.members) do
        if IsValid(p) then Net.send(p, "research.state", v) end
    end
end
Research.pushState = pushState

--[[---------------------------------------------------------------------------
Protocol availability
---------------------------------------------------------------------------]]
function Research.canLead(ply, protocol)
    if not Roles.hasFlag(ply, "leadExperiments") and not SV.Admin.isOnDuty(ply) then return false, "руководят научные сотрудники со званием от «Исследователь»" end
    if SV.Access.clearance(ply) < protocol.clearance then return false, "нужен допуск " .. protocol.clearance end
    if Research.byPlayer[ply] then return false, "вы уже участвуете в эксперименте" end
    for _, e in pairs(Research.active) do
        if e.protocol.id == protocol.id then return false, "протокол уже выполняется" end
    end
    local last = Research.lastRun[protocol.id]
    if last and CurTime() - last < protocol.cooldown then
        return false, "повтор протокола через " .. U.formatDuration(protocol.cooldown - (CurTime() - last))
    end
    if SV.SCP.defs[protocol.subject] and SV.SCP.get(protocol.subject).breached then return false, "объект вне камеры" end
    return true
end

Net.handle("research.protocols", function(ply, ent)
    if not SV.Terminals.canUse(ply, ent, "research") then return false end
    local list = {}
    for _, p in ipairs(C.Protocols) do
        local ok, why = Research.canLead(ply, p)
        local reqs = {}
        for _, r in ipairs(p.participants) do reqs[#reqs + 1] = r.label .. " ×" .. r.min end
        local eq = {}
        for itemId, n in pairs(p.equipment.required or {}) do eq[#eq + 1] = C.Items[itemId].name .. " ×" .. n end
        list[#list + 1] = {id = p.id, name = p.name, desc = p.desc, danger = p.danger, clearance = p.clearance, approval = needsApproval(p),
            participants = reqs, equipment = eq, ok = ok, reason = why}
    end
    local pending = {}
    if Roles.hasFlag(ply, "approveExperiments") or SV.Admin.isOnDuty(ply) then
        for id, e in pairs(Research.active) do
            if e.status == "pending" and e.lead ~= ply then
                pending[#pending + 1] = {id = id, name = e.protocol.name, lead = IsValid(e.lead) and SV.Chars.displayName(e.lead) or "—", danger = e.protocol.danger}
            end
        end
    end
    Net.send(ply, "research.protocols", {ent = ent:EntIndex(), list = list, pending = pending, current = Research.byPlayer[ply] and Research.byPlayer[ply].id or nil})
end)

--[[---------------------------------------------------------------------------
Lifecycle
---------------------------------------------------------------------------]]
local function addMember(exp, ply)
    for _, p in ipairs(exp.members) do if p == ply then return end end
    table.insert(exp.members, ply)
    Research.byPlayer[ply] = exp
end

local function removeMember(exp, ply)
    for i, p in ipairs(exp.members) do
        if p == ply then table.remove(exp.members, i) break end
    end
    if Research.byPlayer[ply] == exp then Research.byPlayer[ply] = nil end
end

local function record(exp, extra)
    local ctx = exp.lastCtx or buildContext(exp)
    local participants = {}
    for _, p in ipairs(exp.members) do
        if IsValid(p) and p.SVChar then participants[#participants + 1] = {id = p.SVChar.id, name = p.SVChar.name} end
    end
    local _, _, optional = equipmentStatus(exp.protocol, ctx)
    local env = environmentStatus(exp.protocol, ctx)
    local safety = safetyStatus(exp.protocol, ctx)
    DB.query([[UPDATE sv_experiments SET status = ?, participants = ?, equipment = ?, safety = ?, environment = ?, approved_by = ?,
        seed = ?, weights = ?, quality = ?, risk = ?, outcome = ?, outcome_name = ?, notes = ?, started_at = ?, finished_at = ? WHERE id = ?]],
        exp.status, DB.encode(participants), DB.encode(optional), DB.encode(safety), DB.encode(env), exp.approvedBy,
        exp.seed, exp.weights and DB.encode(exp.weights) or nil, exp.quality, exp.risk, extra and extra.outcome, extra and extra.outcomeName,
        extra and extra.notes, exp.startedAt, os.time(), exp.id)
end

local function close(exp)
    for _, p in ipairs({unpack(exp.members)}) do
        removeMember(exp, p)
        if IsValid(p) then Net.send(p, "research.closed", {id = exp.id}) end
    end
    Research.active[exp.id] = nil
    if exp.subjectNotes then exp.subjectNotes = nil end
end

function Research.create(ply, ent, protocolId)
    if not SV.Terminals.canUse(ply, ent, "research") then return false end
    local protocol = Research.protocols[protocolId]
    if not protocol then return false, "Протокол не найден." end
    local ok, why = Research.canLead(ply, protocol)
    if not ok then return false, "Нельзя начать: " .. why .. "." end
    DB.query("INSERT INTO sv_experiments (protocol, subject, status, lead_char, lead_name, created_at) VALUES (?, ?, 'draft', ?, ?, ?)",
        protocol.id, protocol.subject, ply.SVChar.id, ply.SVChar.name, os.time())
    local id = DB.lastInsertId()
    local exp = {id = id, protocol = protocol, lead = ply, terminal = ent, sector = SV.Facility.sectorAt(ent:GetPos()), status = "draft",
        members = {}, approved = not needsApproval(protocol), createdAt = CurTime()}
    Research.active[id] = exp
    addMember(exp, ply)
    SV.Audit.log("research", "create", ply, nil, {id = id, protocol = protocol.id})
    pushState(exp)
    return true, "Эксперимент №" .. id .. " создан. Пригласите участников."
end

Net.handle("research.create", function(ply, ent, protocolId) return Research.create(ply, ent, protocolId) end)

Net.handle("research.invite", function(ply, target)
    local exp = Research.byPlayer[ply]
    if not exp or exp.lead ~= ply then return false, "Вы не руководите экспериментом." end
    if exp.status == "running" then return false, "Эксперимент уже идёт." end
    if not IsValid(target) or not target:IsPlayer() or not target.SVChar or target == ply then return false, "Выберите сотрудника." end
    if SV.Roles.isSCP(target) then return false, "Объект SCP не участвует как сотрудник." end
    if Research.byPlayer[target] then return false, "Сотрудник уже участвует в эксперименте." end
    if not U.within(ply, target, 400) then return false, "Сотрудник слишком далеко." end
    exp.invites = exp.invites or {}
    exp.invites[target] = CurTime() + 60
    Net.send(target, "research.invite", {id = exp.id, name = exp.protocol.name, lead = SV.Chars.displayName(ply), danger = exp.protocol.danger})
    return true, "Приглашение отправлено."
end)

Net.handle("research.join", function(ply, id, accept)
    local exp = Research.active[id]
    if not exp or not exp.invites or not exp.invites[ply] or exp.invites[ply] < CurTime() then return false, "Приглашение недействительно." end
    exp.invites[ply] = nil
    if not accept then
        if IsValid(exp.lead) then DarkRP.notify(exp.lead, 1, 4, SV.Chars.displayName(ply) .. " отказался участвовать.") end
        return true
    end
    if Research.byPlayer[ply] then return false, "Вы уже участвуете в эксперименте." end
    if exp.status == "running" then return false, "Эксперимент уже идёт." end
    addMember(exp, ply)
    pushState(exp)
    return true, "Вы участвуете в эксперименте №" .. id .. "."
end)

Net.handle("research.leave", function(ply)
    local exp = Research.byPlayer[ply]
    if not exp then return false, "Вы не участвуете в эксперименте." end
    if exp.lead == ply then return false, "Руководитель отменяет или прерывает эксперимент." end
    if exp.status == "running" then
        Research.participantLost(exp, ply, "участник покинул эксперимент")
    else
        removeMember(exp, ply)
        pushState(exp)
    end
    return true
end)

Net.handle("research.cancel", function(ply)
    local exp = Research.byPlayer[ply]
    if not exp or exp.lead ~= ply then return false, "Вы не руководите экспериментом." end
    if exp.status == "running" then return false, "Эксперимент идёт: используйте аварийное прекращение." end
    exp.status = "cancelled"
    record(exp, {notes = "Отменён руководителем"})
    close(exp)
    return true, "Эксперимент отменён."
end)

Net.handle("research.requestApproval", function(ply)
    local exp = Research.byPlayer[ply]
    if not exp or exp.lead ~= ply then return false, "Вы не руководите экспериментом." end
    if exp.approved then return false, "Согласование не требуется или уже получено." end
    if not approverOnline(exp) then return false, "На смене нет сотрудника с правом согласования опасных экспериментов." end
    exp.status = "pending"
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and (Roles.hasFlag(p, "approveExperiments") or SV.Admin.isOnDuty(p)) then
            DarkRP.notify(p, 0, 8, "Запрошено согласование эксперимента №" .. exp.id .. ": " .. exp.protocol.name .. " (исследовательский терминал).")
        end
    end
    pushState(exp)
    return true, "Запрос на согласование отправлен."
end)

Net.handle("research.approve", function(ply, id, approve, note)
    local exp = Research.active[id]
    if not exp or exp.status ~= "pending" then return false, "Запрос не найден." end
    if not (Roles.hasFlag(ply, "approveExperiments") or SV.Admin.isOnDuty(ply)) then return false, "Нет полномочий." end
    if exp.lead == ply then return false, "Нельзя согласовать собственный эксперимент." end
    note = U.cleanText(note, 200)
    if approve then
        exp.approved = true
        exp.approvedBy = ply.SVChar and ply.SVChar.name or ply:SteamName()
        exp.status = "draft"
    else
        exp.status = "draft"
        exp.rejected = note
    end
    SV.Audit.log("research", approve and "approve" or "reject", ply, IsValid(exp.lead) and exp.lead or nil, {id = id, note = note})
    SV.Bus.emit("experiment.decided", {ply = ply, id = id, approved = approve})
    if IsValid(exp.lead) then DarkRP.notify(exp.lead, approve and 0 or 1, 8, "Эксперимент №" .. id .. (approve and " согласован." or (" не согласован: " .. note))) end
    pushState(exp)
    return true, approve and "Эксперимент согласован." or "В согласовании отказано."
end)

--- Validates everything needed to start. Returns ok, reason, ctx.
local function readyToStart(exp)
    local protocol = exp.protocol
    local ctx = buildContext(exp)
    if needsApproval(protocol) and not exp.approved then return false, "требуется согласование" end
    local ok, why = requirementsMet(protocol, ctx)
    if not ok then return false, why end
    local okEq, missing = equipmentStatus(protocol, ctx)
    if not okEq then return false, "нет оборудования: " .. table.concat(missing, ", ") end
    local _, _, blocked = environmentStatus(protocol, ctx)
    if blocked then return false, "не выполнено условие: " .. blocked end
    local okSubject, subjectWhy = subjectAvailable(exp, protocol)
    if not okSubject then return false, subjectWhy end
    if not inZone(exp, exp.lead) then return false, "руководитель должен находиться в зоне эксперимента" end
    return true, nil, ctx
end

Net.handle("research.start", function(ply)
    local exp = Research.byPlayer[ply]
    if not exp or exp.lead ~= ply then return false, "Вы не руководите экспериментом." end
    if exp.status ~= "draft" then return false, "Эксперимент нельзя начать в текущем состоянии." end
    local ok, why, ctx = readyToStart(exp)
    if not ok then return false, "Нельзя начать: " .. why .. "." end
    -- Consumed equipment is taken at the start; a later failure keeps it spent.
    local _, _, _, _, holderOf = equipmentStatus(exp.protocol, ctx)
    for itemId, n in pairs(exp.protocol.equipment.consumed or {}) do
        if itemId == "sample" then
            local _, holder, item = subjectAvailable(exp, exp.protocol)
            if holder and item then Inv.removeUid(holder, item.uid, 1) end
        else
            local holder = holderOf(itemId, n)
            if holder then Inv.take(holder, itemId, n) end
        end
    end
    exp.status = "running"
    exp.step = 1
    exp.startedAt = os.time()
    exp.seed = SV.RNG.seedFor("experiment", exp.id)
    exp.lastCtx = ctx
    DB.query("UPDATE sv_experiments SET status = 'running', started_at = ?, seed = ? WHERE id = ?", exp.startedAt, exp.seed, exp.id)
    SV.Audit.log("research", "start", ply, nil, {id = exp.id, seed = exp.seed})
    SV.Bus.emit("experiment.started", {ply = ply, id = exp.id, protocol = exp.protocol.id})
    pushState(exp)
    return true, "Эксперимент начат. Выполняйте шаги протокола."
end)

--[[---------------------------------------------------------------------------
Steps, completion, emergency
---------------------------------------------------------------------------]]
local function applyRewards(exp, outcome, ctx)
    local reward = outcome.reward or {}
    local shift = SV.Shift.id
    local budgetGiven = false
    for _, p in ipairs(exp.members) do
        if IsValid(p) and p.SVChar then
            local fresh = DB.queryValue("SELECT 1 FROM sv_experiment_rewards WHERE char_id = ? AND protocol = ? AND shift = ?", p.SVChar.id, exp.protocol.id, shift) == nil
            if fresh then
                DB.query("INSERT OR IGNORE INTO sv_experiment_rewards (char_id, protocol, shift) VALUES (?, ?, ?)", p.SVChar.id, exp.protocol.id, shift)
                local xp = math.floor((reward.xp or 0) * (p == exp.lead and 1 or 0.7))
                if xp > 0 then SV.Chars.addXP(p, xp, "research") end
                if not budgetGiven and reward.budget and SV.Supply then
                    budgetGiven = true
                    SV.Supply.adjustBudget("science", reward.budget, "Эксперимент №" .. exp.id, exp.lead)
                end
            end
            SV.Bus.emit("experiment.participated", {ply = p, id = exp.id, protocol = exp.protocol.id, outcome = outcome.id})
        end
    end
    local dossierId = dossierOf(exp.protocol.subject)
    if outcome.fact and C.Dossiers[dossierId] then
        local _, new = SV.Knowledge.confirmFact(dossierId, outcome.fact, "experiment:" .. exp.id, exp.lead)
        for _, p in ipairs(ctx.participants) do SV.Knowledge.learn(p, dossierId, outcome.fact, "experiment:" .. exp.id) end
        exp.factNew = new
    end
    if outcome.unlock then
        local scpId = SV.SCP.defs[dossierId] and dossierId or "global"
        SV.SCP.unlock(scpId, outcome.unlock)
    end
end

function Research.finish(exp)
    local ctx = buildContext(exp)
    local weights, quality, risk = Research.weights(exp, ctx)
    local rng = SV.RNG.new(exp.seed)
    local pick = rng:weighted(weights)
    local outcome
    for _, o in ipairs(exp.protocol.outcomes) do if o.id == pick then outcome = o end end
    outcome = outcome or exp.protocol.outcomes[1]
    exp.weights, exp.quality, exp.risk = weights, quality, risk
    exp.status = "completed"
    Research.lastRun[exp.protocol.id] = CurTime()
    if outcome.effect then SV.Log.guard("experiment effect", outcome.effect, ctx) end
    applyRewards(exp, outcome, ctx)
    record(exp, {outcome = outcome.id, outcomeName = outcome.name, notes = outcome.text})
    SV.Audit.log("research", "finish", exp.lead, nil, {id = exp.id, outcome = outcome.id, seed = exp.seed, weights = weights})
    SV.Bus.emit("experiment.finished", {id = exp.id, protocol = exp.protocol.id, outcome = outcome.id, kind = outcome.kind, ply = exp.lead})
    local text = "Эксперимент №" .. exp.id .. ": " .. outcome.name .. ". " .. (outcome.text or "") ..
        (outcome.fact and exp.factNew == false and " (сведения подтверждены повторно)" or "")
    for _, p in ipairs(exp.members) do
        if IsValid(p) then
            DarkRP.notify(p, outcome.kind == "incident" and 1 or 0, 10, text)
            Net.send(p, "research.result", {id = exp.id, name = outcome.name, kind = outcome.kind, text = outcome.text})
        end
    end
    close(exp)
    return outcome
end

--- Emergency termination: rolled from incident and "none" outcomes only.
function Research.emergency(exp, reason)
    if exp.status ~= "running" then return end
    local ctx = buildContext(exp)
    local weights = {}
    for _, o in ipairs(exp.protocol.outcomes) do
        if o.kind == "incident" then weights[o.id] = o.weight * 1.5
        elseif o.kind == "none" then weights[o.id] = o.weight end
    end
    local rng = SV.RNG.new((exp.seed or 1) + 7919)
    local pick = rng:weighted(weights)
    local outcome
    for _, o in ipairs(exp.protocol.outcomes) do if o.id == pick then outcome = o end end
    exp.status = "emergency"
    Research.lastRun[exp.protocol.id] = CurTime()
    if outcome and outcome.kind == "incident" and outcome.effect then SV.Log.guard("experiment emergency", outcome.effect, ctx) end
    record(exp, {outcome = outcome and outcome.id or "aborted", outcomeName = "Аварийное прекращение", notes = reason .. (outcome and (". " .. outcome.name) or "")})
    SV.Audit.log("research", "emergency", exp.lead, nil, {id = exp.id, reason = reason, outcome = outcome and outcome.id})
    SV.Bus.emit("experiment.emergency", {id = exp.id, protocol = exp.protocol.id, reason = reason, outcome = outcome and outcome.id})
    for _, p in ipairs(exp.members) do
        if IsValid(p) then DarkRP.notify(p, 1, 10, "АВАРИЙНОЕ ПРЕКРАЩЕНИЕ эксперимента №" .. exp.id .. ": " .. reason .. (outcome and outcome.kind == "incident" and (". " .. outcome.name) or "") .. ".") end
    end
    if exp.sector and outcome and outcome.kind == "incident" then SV.Facility.setAlert(exp.sector, nil, true, "Инцидент при эксперименте №" .. exp.id) end
    close(exp)
end

--- Clean abort (no critical step running) or emergency.
function Research.abort(exp, reason, actor)
    if exp.status ~= "running" then
        exp.status = "aborted"
        record(exp, {notes = reason})
        close(exp)
        return
    end
    local step = exp.protocol.steps[exp.step]
    if step and step.critical and exp.stepActive then
        Research.emergency(exp, reason)
    else
        exp.status = "aborted"
        Research.lastRun[exp.protocol.id] = CurTime()
        record(exp, {outcome = "aborted", outcomeName = "Прекращён", notes = reason})
        SV.Audit.log("research", "abort", actor, nil, {id = exp.id, reason = reason})
        for _, p in ipairs(exp.members) do
            if IsValid(p) then DarkRP.notify(p, 1, 8, "Эксперимент №" .. exp.id .. " прекращён: " .. reason) end
        end
        close(exp)
    end
end

function Research.participantLost(exp, ply, reason)
    removeMember(exp, ply)
    if exp.status ~= "running" then
        if exp.lead == ply then
            exp.status = "cancelled"
            record(exp, {notes = "Руководитель выбыл"})
            close(exp)
        else
            pushState(exp)
        end
        return
    end
    local step = exp.protocol.steps[exp.step]
    if step and step.critical then
        Research.emergency(exp, reason)
        return
    end
    local ctx = buildContext(exp)
    if exp.lead == ply or not requirementsMet(exp.protocol, ctx) then
        Research.abort(exp, reason)
    else
        pushState(exp)
    end
end

local function canDoStep(exp, ply, step)
    if step.by == "lead" then return ply == exp.lead end
    if step.by == "classd" then return categoryOf(ply).classd == true end
    return true
end

Net.handle("research.step", function(ply, id)
    local exp = Research.active[id]
    if not exp or Research.byPlayer[ply] ~= exp then return false, "Вы не участвуете в этом эксперименте." end
    if exp.status ~= "running" then return false, "Эксперимент не идёт." end
    if exp.stepActive then return false, "Шаг уже выполняется." end
    local step = exp.protocol.steps[exp.step]
    if not step then return false end
    if not canDoStep(exp, ply, step) then
        return false, step.by == "lead" and "Этот шаг выполняет руководитель." or "Этот шаг выполняет испытуемый класса D."
    end
    if not inZone(exp, ply) then return false, "Вы вне зоны эксперимента." end
    local ok, why = requirementsMet(exp.protocol, buildContext(exp))
    if not ok then return false, "Нельзя продолжить: " .. why .. "." end
    exp.stepActive = true
    local okStart, reason = SV.Actions.start(ply, {
        id = "experiment", label = step.name, duration = step.time, allowMove = true, maxDist = 99999, cancelOnDamage = step.critical,
        canContinue = function(p)
            if exp.status ~= "running" then return false, "эксперимент завершён" end
            if not inZone(exp, p) then return false, "вы покинули зону эксперимента" end
            if step.critical then
                local okReq, whyReq = requirementsMet(exp.protocol, buildContext(exp))
                if not okReq then return false, whyReq end
            end
            return true
        end,
        onComplete = function()
            exp.stepActive = nil
            exp.step = exp.step + 1
            if exp.step > #exp.protocol.steps then
                Research.finish(exp)
            else
                pushState(exp)
            end
        end,
        onCancel = function(_, why2)
            exp.stepActive = nil
            if exp.status ~= "running" then return end
            if step.critical then
                Research.emergency(exp, "критический шаг прерван: " .. tostring(why2))
            else
                pushState(exp)
            end
        end,
    })
    if not okStart then exp.stepActive = nil end
    pushState(exp)
    return okStart, reason
end)

Net.handle("research.abort", function(ply, id, reason)
    local exp = Research.active[id]
    if not exp then return false, "Эксперимент не найден." end
    local member = Research.byPlayer[ply] == exp
    local allowed = exp.lead == ply or (member and Roles.hasFlag(ply, "canDetain")) or Roles.hasFlag(ply, "approveExperiments") or SV.Admin.isOnDuty(ply)
    if not allowed then return false, "Прекратить эксперимент могут руководитель, охрана участников и согласующие." end
    reason = U.cleanText(reason, 200)
    if reason == "" then reason = "решение " .. SV.Chars.displayName(ply) end
    -- An action in progress is cancelled first; its onCancel handles the emergency.
    for p, a in pairs(SV.Actions.active) do
        if a.id == "experiment" and Research.byPlayer[p] == exp then SV.Actions.cancel(p, "аварийное прекращение") end
    end
    if Research.active[id] then Research.abort(exp, reason, ply) end
    return true
end)

Net.handle("research.state", function(ply)
    local exp = Research.byPlayer[ply]
    if not exp then return false, "Вы не участвуете в эксперименте." end
    Net.send(ply, "research.state", Research.view(exp))
end)

Net.handle("research.history", function(ply, ent)
    if not SV.Terminals.canUse(ply, ent, "research") then return false end
    local clearance = SV.Access.clearance(ply)
    local rows = DB.query("SELECT id, protocol, status, lead_name, outcome_name, notes, approved_by, finished_at FROM sv_experiments WHERE finished_at IS NOT NULL ORDER BY id DESC LIMIT 30") or {}
    local list = {}
    for _, r in ipairs(rows) do
        local p = Research.protocols[r.protocol]
        if p and p.clearance <= clearance then
            list[#list + 1] = {id = tonumber(r.id), name = p.name, status = r.status, lead = r.lead_name, outcome = r.outcome_name, notes = r.notes,
                approvedBy = r.approved_by, when = U.clockString(tonumber(r.finished_at))}
        end
    end
    Net.send(ply, "research.history", {list = list})
end)

-- Lost participants: death, disconnect, character switch.
local function lost(ply, reason)
    local exp = Research.byPlayer[ply]
    if exp then Research.participantLost(exp, ply, reason) end
end
hook.Add("PlayerDeath", "SiteVeil.Research", function(ply) lost(ply, "участник погиб") end)
hook.Add("PlayerDisconnected", "SiteVeil.Research", function(ply) lost(ply, "участник отключился") end)
hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.Research", function(ply) lost(ply, "участник сменил персонажа") end)
hook.Add("SiteVeil.RoleAssigned", "SiteVeil.Research", function(ply) lost(ply, "участник сменил должность") end)

-- Breach of the subject stops experiments with it.
SV.Bus.on("scp.breached", "research", function(data)
    for _, exp in pairs(Research.active) do
        if exp.protocol.subject == data.scp then Research.abort(exp, "объект покинул камеру") end
    end
end)

-- Stale drafts are dropped after 15 minutes.
timer.Create("SiteVeil.Research.Cleanup", 30, 0, function()
    for _, exp in pairs(Research.active) do
        if exp.status ~= "running" and CurTime() - exp.createdAt > 900 then
            exp.status = "cancelled"
            record(exp, {notes = "Истёк срок подготовки"})
            close(exp)
        end
    end
end)

SV.Facility.registerTerminal("research", {
    name = "Исследовательский терминал", req = {clearance = 1, tags = {"science", "labs", "administration"}}, power = 0.5,
    open = function(ply, ent) Net.handlers["research.protocols"](ply, ent) end,
})

--- Replays the roll of a finished experiment from its stored seed/weights.
concommand.Add("sv_research_replay", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local id = tonumber(args[1])
    local row = id and DB.queryRow("SELECT seed, weights, outcome FROM sv_experiments WHERE id = ?", id)
    if not row or not row.seed then print("эксперимент не найден или не имеет записи броска") return end
    local weights = DB.decode(row.weights)
    local pick = SV.RNG.new(tonumber(row.seed)):weighted(weights)
    local msg = string.format("эксперимент %d: сохранённый исход %s, повтор броска %s", id, tostring(row.outcome), tostring(pick))
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)

SV.Perf.registry("research.active", function() return U.count(Research.active) end)

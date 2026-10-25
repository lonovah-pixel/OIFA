--[[---------------------------------------------------------------------------
"След инцидента" (server): traces, collection, analysis, cases.

Traces live in memory, are capped (C.Evidence.maxTraces, maxPerSector) and
expire (per kind TTL). Hidden facts about a trace (who, which weapon) never
leave the server until analysis, and analysis gives limited precision:
  field scan    kind and rounded age
  level 1       division of the people involved, weapon category, time ±10 min
  level 2       identities where physically traceable (victim, issued weapon),
                time ±3 min; needs a sensor kit
The exact record of every event is the admin audit log, not this module.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Evidence = SV.Evidence
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local E = C.Evidence
local Roles = SV.Roles
local Inv = SV.Inv

Evidence.traces = Evidence.traces or {} -- id -> trace
Evidence.nextId = Evidence.nextId or 1

DB.registerMigrations("evidence", {
    {1, "evidence and cases", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_evidence (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, sector TEXT,
            x REAL, y REAL, z REAL, created_at INTEGER NOT NULL, hidden TEXT, collected_by INTEGER, collected_name TEXT,
            collected_at INTEGER, case_id INTEGER, level INTEGER NOT NULL DEFAULT 0, report TEXT)]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_cases (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, status TEXT NOT NULL,
            lead_char INTEGER, lead_name TEXT, created_at INTEGER NOT NULL, closed_at INTEGER, verdict TEXT)]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_case_notes (id INTEGER PRIMARY KEY AUTOINCREMENT, case_id INTEGER NOT NULL,
            author_char INTEGER, author_name TEXT, text TEXT NOT NULL, time INTEGER NOT NULL)]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_evidence_case ON sv_evidence (case_id)")
    end},
})

local function isInvestigator(ply)
    return Roles.hasFlag(ply, "investigator") or SV.Admin.isOnDuty(ply)
end
Evidence.isInvestigator = isInvestigator

local function charInfo(p)
    if not IsValid(p) or not p:IsPlayer() then return nil end
    local char = p.SVChar
    local scp = SV.SCP.of(p)
    return {char = char and char.id, name = char and char.name, division = char and char.division, scp = scp}
end

--[[---------------------------------------------------------------------------
Traces
---------------------------------------------------------------------------]]
local function enforceCaps(sector)
    local total, inSector = 0, {}
    local oldest, oldestSector
    for id, t in pairs(Evidence.traces) do
        total = total + 1
        if t.sector == sector then inSector[#inSector + 1] = t end
        if not oldest or t.created < Evidence.traces[oldest].created then oldest = id end
    end
    if total > E.maxTraces and oldest then Evidence.traces[oldest] = nil end
    if #inSector > E.maxPerSector then
        table.sort(inSector, function(a, b) return a.created < b.created end)
        oldestSector = inSector[1]
        Evidence.traces[oldestSector.id] = nil
    end
end

--- Adds a trace at pos. hidden = server-only facts. Returns the trace.
function Evidence.addTrace(kind, pos, hidden)
    local def = C.TraceKinds[kind]
    if not def or not pos then return nil end
    local now = CurTime()
    for _, t in pairs(Evidence.traces) do
        if t.kind == kind and now - t.updated < E.mergeTime and t.pos:DistToSqr(pos) < E.mergeRadius * E.mergeRadius then
            t.count = t.count + 1
            t.updated = now
            t.expires = now + def.ttl
            -- The first contributor stays the analysed one; others are noted.
            t.hidden.extra = math.min((t.hidden.extra or 0) + 1, 20)
            return t
        end
    end
    local id = Evidence.nextId
    Evidence.nextId = id + 1
    local sector = SV.Facility.sectorAt(pos)
    local t = {id = id, kind = kind, pos = Vector(pos), sector = sector, created = now, updated = now, expires = now + def.ttl,
        realTime = os.time(), count = 1, hidden = hidden or {}}
    Evidence.traces[id] = t
    enforceCaps(sector)
    return t
end

timer.Create("SiteVeil.Evidence.Expire", 10, 0, function()
    local now = CurTime()
    for id, t in pairs(Evidence.traces) do
        if now >= t.expires then Evidence.traces[id] = nil end
    end
end)

-- Sources --------------------------------------------------------------------
SV.Bus.on("medical.down", "evidence", function(data)
    if not IsValid(data.ply) then return end
    Evidence.addTrace("blood", data.ply:GetPos(), {victim = charInfo(data.ply), attacker = charInfo(data.attacker), cause = data.cause})
end)

hook.Add("PlayerDeath", "SiteVeil.Evidence", function(ply, inflictor, attacker)
    if not ply.SVChar or Roles.isSCP(ply) then return end
    local wep = IsValid(inflictor) and inflictor:IsWeapon() and inflictor:GetClass() or nil
    Evidence.addTrace("blood", ply:GetPos(), {victim = charInfo(ply), attacker = charInfo(attacker), weapon = wep})
end)

SV.Bus.on("scp.attack", "evidence", function(data)
    if not IsValid(data.target) then return end
    local kind = data.scp == "scp106" and "slime" or (data.scp == "scp173" and "scratch" or "blood")
    Evidence.addTrace(kind, data.target:GetPos(), {victim = charInfo(data.target), attacker = {scp = data.scp}})
end)

SV.Bus.on("scp106.pocket", "evidence", function(data)
    if IsValid(data.target) then Evidence.addTrace("slime", data.target:GetPos(), {victim = charInfo(data.target), attacker = {scp = "scp106"}}) end
end)

SV.Bus.on("scp.doorBroken", "evidence", function(data)
    if not IsValid(data.door) then return end
    local kind = data.scp == "scp106" and "slime" or (data.scp == "scp173" and "scratch" or "damage")
    Evidence.addTrace(kind, data.door:GetPos(), {attacker = {scp = data.scp}, door = true})
end)

SV.Bus.on("node.sabotaged", "evidence", function(data)
    if data.node then Evidence.addTrace("damage", data.node.pos, {attacker = charInfo(data.ply), node = data.node.name}) end
end)

SV.Bus.on("knowledge.leak", "evidence", function(data)
    if IsValid(data.ply) then Evidence.addTrace("document", data.ply:GetPos(), {attacker = charInfo(data.ply), dossier = data.dossier}) end
end)

hook.Add("EntityFireBullets", "SiteVeil.Evidence", function(ent)
    if not IsValid(ent) or not ent:IsPlayer() or not ent.SVChar or Roles.isSCP(ent) then return end
    local now = CurTime()
    if (ent.SVLastCasing or -1e9) + E.casingInterval > now then return end
    ent.SVLastCasing = now
    local wep = ent:GetActiveWeapon()
    local uid = IsValid(wep) and wep.SVItemUid or nil
    local issued
    if uid then
        local row = DB.queryRow("SELECT issued_to FROM sv_items WHERE uid = ?", uid)
        issued = row and tonumber(row.issued_to)
    end
    Evidence.addTrace("casing", ent:GetPos(), {attacker = charInfo(ent), weapon = IsValid(wep) and wep:GetClass() or nil, itemUid = uid, issuedTo = issued})
end)

--[[---------------------------------------------------------------------------
Field scan and collection
---------------------------------------------------------------------------]]
local function hasKit(ply)
    return ply:HasWeapon("sv_evidence_kit") or SV.Admin.isOnDuty(ply)
end

local function roundedAge(seconds)
    local step = E.ageStep
    local n = math.max(math.floor(seconds / step + 0.5), 0) * step / 60
    if n < 5 then return "недавно" end
    return "около " .. n .. " мин назад"
end

function Evidence.scan(ply)
    local now = CurTime()
    local list = {}
    local r2 = E.scanRadius * E.scanRadius
    for id, t in pairs(Evidence.traces) do
        if t.pos:DistToSqr(ply:GetPos()) <= r2 then
            list[#list + 1] = {id = id, kind = t.kind, name = C.TraceKinds[t.kind].name, count = t.count, age = roundedAge(now - t.created),
                pos = {math.Round(t.pos.x), math.Round(t.pos.y), math.Round(t.pos.z)}}
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

Net.handle("evidence.scan", function(ply)
    if not hasKit(ply) then return false, "Нужен набор криминалиста." end
    if (ply.SVLastScan or -1e9) + E.scanCooldown > CurTime() then return false end
    ply.SVLastScan = CurTime()
    local list = Evidence.scan(ply)
    Net.send(ply, "evidence.scan", {list = list})
    return true, #list > 0 and ("Обнаружено следов: " .. #list .. ".") or "Следов поблизости не обнаружено."
end)

function Evidence.collect(ply, id)
    local t = Evidence.traces[id]
    if not t then return false, "След исчез." end
    if not hasKit(ply) then return false, "Нужен набор криминалиста." end
    if ply:GetPos():DistToSqr(t.pos) > E.collectDistance * E.collectDistance then return false, "Подойдите к следу." end
    if not Inv.fits(ply, "evidence_bag", 1) then return false, "Нет места в инвентаре." end
    return SV.Actions.start(ply, {
        id = "evidence", label = "Сбор улики: " .. C.TraceKinds[t.kind].name, duration = E.collectTime, maxDist = 99999,
        canContinue = function(p)
            if not Evidence.traces[id] then return false, "след исчез" end
            return p:GetPos():DistToSqr(t.pos) <= E.collectDistance * E.collectDistance, "вы отошли"
        end,
        onComplete = function(p)
            if not Evidence.traces[id] then return end
            Evidence.traces[id] = nil
            DB.query([[INSERT INTO sv_evidence (kind, sector, x, y, z, created_at, hidden, collected_by, collected_name, collected_at, level)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)]], t.kind, t.sector, t.pos.x, t.pos.y, t.pos.z, t.realTime, DB.encode(t.hidden),
                p.SVChar.id, p.SVChar.name, os.time())
            local eid = DB.lastInsertId()
            Inv.add(p, "evidence_bag", 1, {force = true, data = {evidence = eid, title = "Улика №" .. eid .. ": " .. C.TraceKinds[t.kind].name}})
            SV.Audit.log("evidence", "collect", p, nil, {evidence = eid, kind = t.kind, hidden = t.hidden})
            SV.Bus.emit("evidence.collected", {ply = p, evidence = eid, kind = t.kind})
            DarkRP.notify(p, 0, 5, "Улика №" .. eid .. " упакована. Анализ — на терминале службы безопасности.")
        end,
    })
end

Net.handle("evidence.collect", function(ply, id) return Evidence.collect(ply, id) end)

--[[---------------------------------------------------------------------------
Analysis (limited precision)
---------------------------------------------------------------------------]]
local weaponCategories = {
    weapon_pistol = "пистолетный патрон", weapon_357 = "револьверный патрон .357", weapon_smg1 = "патрон пистолета-пулемёта",
    weapon_ar2 = "импульсный заряд", weapon_shotgun = "дробь", weapon_crossbow = "арбалетный болт",
}

local function divisionName(id)
    local d = id and Roles.getDivision(id)
    return d and d.name or "не установлено"
end

local function scpName(id)
    local def = id and SV.SCP.defs[id]
    if def then return def.name end
    if id == "scp0492" then return "SCP-049-2" end
    return nil
end

local function timeWindow(realTime, window)
    local lo, hi = realTime - window, realTime + window
    return "между " .. os.date("%H:%M", lo) .. " и " .. os.date("%H:%M", hi)
end

--- Builds the report text for a level of analysis.
function Evidence.report(row, level)
    local h = DB.decode(row.hidden) or {}
    local lines = {}
    local window = E.analysis[level].window
    lines[#lines + 1] = "Время образования: " .. timeWindow(tonumber(row.created_at), window) .. "."
    local victim, attacker = h.victim, h.attacker
    if row.kind == "blood" then
        if victim then
            lines[#lines + 1] = level >= 2 and victim.name and ("Кровь принадлежит: " .. victim.name .. ".") or
                ("Кровь сотрудника подразделения: " .. divisionName(victim.division) .. ".")
        end
        if attacker and scpName(attacker.scp) then
            lines[#lines + 1] = level >= 2 and ("Характер повреждений соответствует " .. scpName(attacker.scp) .. ".") or "Характер повреждений нетипичен для оружия."
        elseif attacker and attacker.division then
            lines[#lines + 1] = level >= 2 and ("Следы борьбы: нападавший из подразделения «" .. divisionName(attacker.division) .. "».") or "Есть следы борьбы."
        end
        if h.weapon and level >= 2 then lines[#lines + 1] = "Использовано: " .. (weaponCategories[h.weapon] or "холодное оружие или инструмент") .. "." end
    elseif row.kind == "casing" then
        lines[#lines + 1] = "Боеприпас: " .. (weaponCategories[h.weapon] or "неустановленный") .. "."
        if level >= 2 then
            if h.issuedTo then
                local who = DB.queryValue("SELECT name FROM sv_characters WHERE id = ?", h.issuedTo)
                lines[#lines + 1] = "По журналу оружейной оружие выдано: " .. (who or "неизвестно") .. "."
            else
                lines[#lines + 1] = "Оружие не числится в журнале оружейной."
            end
        elseif attacker then
            lines[#lines + 1] = "Стрелок из подразделения: " .. divisionName(attacker.division) .. "."
        end
    elseif row.kind == "slime" or row.kind == "scratch" then
        lines[#lines + 1] = "Аномальный след: " .. (level >= 2 and (scpName(attacker and attacker.scp) or "объект не установлен") or "требуется лабораторное сравнение") .. "."
    elseif row.kind == "damage" then
        lines[#lines + 1] = h.node and ("Повреждённое оборудование: " .. h.node .. ".") or "Следы взлома."
        if attacker and attacker.scp then
            lines[#lines + 1] = "Повреждения нанесены аномальным объектом."
        elseif attacker and level >= 2 then
            lines[#lines + 1] = "Отпечатки и инструмент указывают на подразделение: " .. divisionName(attacker.division) .. "."
        else
            lines[#lines + 1] = "Использован инструмент."
        end
    elseif row.kind == "document" then
        lines[#lines + 1] = "Секретный документ читал сотрудник без допуска."
        if level >= 2 and attacker then lines[#lines + 1] = "Подразделение читавшего: " .. divisionName(attacker.division) .. "." end
    elseif row.kind == "stash" then
        lines[#lines + 1] = "Тайник использовался."
        if level >= 2 and attacker then lines[#lines + 1] = "Подразделение пользователя тайника: " .. divisionName(attacker.division) .. "." end
    end
    if (h.extra or 0) > 0 then lines[#lines + 1] = "Рядом следы ещё " .. h.extra .. " эпизодов того же рода." end
    return table.concat(lines, " ")
end

local function securityTerminal(ply, ent, silent)
    return SV.Terminals.canUse(ply, ent, "security", silent)
end

local function evidenceItem(ply, uid)
    local item = Inv.getItem(ply, uid)
    if not item or item.id ~= "evidence_bag" or not item.data.evidence then return nil end
    return item
end

Net.handle("evidence.analyze", function(ply, uid, ent)
    if not isInvestigator(ply) then return false, "Анализ проводят следователи." end
    if not securityTerminal(ply, ent) then return false end
    local item = evidenceItem(ply, uid)
    if not item then return false, "Нужен пакет с уликой." end
    local row = DB.queryRow("SELECT * FROM sv_evidence WHERE id = ?", item.data.evidence)
    if not row then return false, "Улика не найдена в архиве." end
    local level = tonumber(row.level) + 1
    local step = E.analysis[level]
    if not step then return false, "Улика исследована полностью." end
    if step.needs and not Inv.has(ply, step.needs) then return false, "Для этого анализа нужен: " .. C.Items[step.needs].name .. "." end
    return SV.Actions.start(ply, {
        id = "analysis", label = step.label .. " улики №" .. row.id, duration = step.time, target = ent, maxDist = 160,
        canContinue = function(p) return evidenceItem(p, uid) ~= nil, "улика у вас изъята" end,
        onComplete = function(p)
            local text = Evidence.report(row, level)
            DB.query("UPDATE sv_evidence SET level = ?, report = ? WHERE id = ?", level, text, row.id)
            SV.Audit.log("evidence", "analyze", p, nil, {evidence = row.id, level = level})
            SV.Bus.emit("evidence.analyzed", {ply = p, evidence = tonumber(row.id), level = level})
            Net.send(p, "evidence.report", {id = tonumber(row.id), kind = row.kind, name = C.TraceKinds[row.kind].name, level = level, text = text})
        end,
    })
end)

--[[---------------------------------------------------------------------------
Cases
---------------------------------------------------------------------------]]
local function caseView(id)
    local c = DB.queryRow("SELECT * FROM sv_cases WHERE id = ?", id)
    if not c then return nil end
    local evidence = {}
    for _, r in ipairs(DB.query("SELECT id, kind, sector, level, report, collected_name, created_at FROM sv_evidence WHERE case_id = ? ORDER BY id", id) or {}) do
        evidence[#evidence + 1] = {id = tonumber(r.id), name = C.TraceKinds[r.kind] and C.TraceKinds[r.kind].name or r.kind, sector = r.sector,
            level = tonumber(r.level), report = r.report, collector = r.collected_name, when = U.clockString(tonumber(r.created_at))}
    end
    local notes = {}
    for _, n in ipairs(DB.query("SELECT author_name, text, time FROM sv_case_notes WHERE case_id = ? ORDER BY id", id) or {}) do
        notes[#notes + 1] = {author = n.author_name, text = n.text, when = U.clockString(tonumber(n.time))}
    end
    return {id = tonumber(c.id), title = c.title, status = c.status, lead = c.lead_name, created = U.clockString(tonumber(c.created_at)),
        verdict = c.verdict, evidence = evidence, notes = notes}
end
Evidence.caseView = caseView

Net.handle("case.list", function(ply)
    if not isInvestigator(ply) then return false, "Доступно следователям." end
    local list = {}
    for _, c in ipairs(DB.query("SELECT id, title, status, lead_name, created_at FROM sv_cases ORDER BY status = 'open' DESC, id DESC LIMIT 40") or {}) do
        list[#list + 1] = {id = tonumber(c.id), title = c.title, status = c.status, lead = c.lead_name, created = U.clockString(tonumber(c.created_at))}
    end
    local bags = {}
    for _, item in ipairs(Inv.find(ply, function(it) return it.id == "evidence_bag" end)) do
        bags[#bags + 1] = {uid = item.uid, title = item.data.title}
    end
    Net.send(ply, "case.list", {list = list, bags = bags})
end)

Net.handle("case.view", function(ply, id)
    if not isInvestigator(ply) then return false, "Доступно следователям." end
    local v = caseView(id)
    if not v then return false, "Дело не найдено." end
    Net.send(ply, "case.view", v)
end)

Net.handle("case.create", function(ply, title)
    if not isInvestigator(ply) then return false, "Доступно следователям." end
    title = U.cleanText(title, 80)
    if U.utf8len(title) < 4 then return false, "Название дела слишком короткое." end
    local open = tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_cases WHERE status = 'open'")) or 0
    if open >= 30 then return false, "Слишком много открытых дел: закройте завершённые." end
    DB.query("INSERT INTO sv_cases (title, status, lead_char, lead_name, created_at) VALUES (?, 'open', ?, ?, ?)",
        title, ply.SVChar and ply.SVChar.id, ply.SVChar and ply.SVChar.name or ply:SteamName(), os.time())
    local id = DB.lastInsertId()
    SV.Audit.log("evidence", "case.create", ply, nil, {case = id, title = title})
    Net.send(ply, "case.view", caseView(id))
    return true, "Заведено дело №" .. id .. "."
end)

Net.handle("case.attach", function(ply, caseId, uid)
    if not isInvestigator(ply) then return false, "Доступно следователям." end
    local c = DB.queryRow("SELECT status FROM sv_cases WHERE id = ?", caseId)
    if not c or c.status ~= "open" then return false, "Дело закрыто или не найдено." end
    local item = evidenceItem(ply, uid)
    if not item then return false, "Нужен пакет с уликой." end
    local eid = item.data.evidence
    -- The bag goes into the case archive.
    Inv.removeUid(ply, uid)
    DB.query("UPDATE sv_evidence SET case_id = ? WHERE id = ?", caseId, eid)
    SV.Audit.log("evidence", "case.attach", ply, nil, {case = caseId, evidence = eid})
    Net.send(ply, "case.view", caseView(caseId))
    return true, "Улика №" .. eid .. " приобщена к делу."
end)

Net.handle("case.note", function(ply, caseId, text)
    if not isInvestigator(ply) then return false, "Доступно следователям." end
    local c = DB.queryRow("SELECT status FROM sv_cases WHERE id = ?", caseId)
    if not c or c.status ~= "open" then return false, "Дело закрыто или не найдено." end
    text = U.cleanText(text, 500)
    if U.utf8len(text) < 3 then return false, "Пустая запись." end
    DB.query("INSERT INTO sv_case_notes (case_id, author_char, author_name, text, time) VALUES (?, ?, ?, ?, ?)",
        caseId, ply.SVChar and ply.SVChar.id, ply.SVChar and ply.SVChar.name or ply:SteamName(), text, os.time())
    Net.send(ply, "case.view", caseView(caseId))
    return true
end)

Net.handle("case.close", function(ply, caseId, verdict)
    if not isInvestigator(ply) then return false, "Доступно следователям." end
    local c = DB.queryRow("SELECT status, lead_char FROM sv_cases WHERE id = ?", caseId)
    if not c or c.status ~= "open" then return false, "Дело закрыто или не найдено." end
    verdict = U.cleanText(verdict, 500)
    if U.utf8len(verdict) < 10 then return false, "Опишите заключение по делу." end
    DB.query("UPDATE sv_cases SET status = 'closed', closed_at = ?, verdict = ? WHERE id = ?", os.time(), verdict, caseId)
    SV.Audit.log("evidence", "case.close", ply, nil, {case = caseId})
    SV.Bus.emit("evidence.caseClosed", {ply = ply, case = caseId, evidence = tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_evidence WHERE case_id = ?", caseId)) or 0})
    Net.send(ply, "case.view", caseView(caseId))
    return true, "Дело №" .. caseId .. " закрыто."
end)

--[[---------------------------------------------------------------------------
Security terminal
---------------------------------------------------------------------------]]
Net.handle("evidence.terminal", function(ply, ent)
    if not securityTerminal(ply, ent) then return false end
    local bags = {}
    for _, item in ipairs(Inv.find(ply, function(it) return it.id == "evidence_bag" end)) do
        local row = DB.queryRow("SELECT level, report, kind FROM sv_evidence WHERE id = ?", item.data.evidence)
        bags[#bags + 1] = {uid = item.uid, title = item.data.title, level = row and tonumber(row.level) or 0, report = row and row.report,
            next = row and E.analysis[tonumber(row.level) + 1] and E.analysis[tonumber(row.level) + 1].label or nil}
    end
    local detentions = {}
    for target, d in pairs(SV.Security.detained) do
        if IsValid(target) then
            detentions[#detentions + 1] = {name = SV.Chars.displayName(target), left = math.max(math.ceil(d.untilTime - CurTime()), 0), reason = d.reason}
        end
    end
    local confiscations = DB.query("SELECT item_id, from_name, by_name, reason, time FROM sv_confiscations ORDER BY id DESC LIMIT 15") or {}
    for _, c in ipairs(confiscations) do
        c.item = C.Items[c.item_id] and C.Items[c.item_id].name or c.item_id
        c.when = U.clockString(tonumber(c.time))
        c.item_id, c.time = nil, nil
    end
    Net.send(ply, "evidence.terminal", {ent = ent:EntIndex(), bags = bags, investigator = isInvestigator(ply), detentions = detentions,
        confiscations = confiscations, hasSensor = Inv.has(ply, "sensor_kit")})
end)

SV.Facility.registerTerminal("security", {
    name = "Терминал службы безопасности", req = {clearance = 1, tags = {"security"}}, power = 0.5,
    open = function(ply, ent) Net.handlers["evidence.terminal"](ply, ent) end,
})

SV.Perf.registry("evidence.traces", function() return U.count(Evidence.traces) end)

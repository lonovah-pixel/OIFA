--[[---------------------------------------------------------------------------
"Знание имеет допуск" (server).

Three separate things:
  1. What the server knows      config/sv_dossiers.lua + sv_dossier_entries
  2. What a character knows      sv_char_knowledge (facts learned in play)
  3. What a tool shows           terminals filter by the card's clearance

Rules:
  * A section above the viewer's clearance is sent as a locked stub (title and
    level only), never with its text.
  * The service menu (F4) shows only open sections, facts the character has
    learned and the character's own reports. Clearance-gated reading needs a
    records or research terminal.
  * A printed document can be read by anyone holding it. Reading a document
    above one's clearance is a leak: it is recorded and security is alerted
    (if the sector's security subsystem works).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Knowledge = SV.Knowledge
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local Roles = SV.Roles
local Inv = SV.Inv

DB.registerMigrations("knowledge", {
    {1, "dossier entries, history, character knowledge, prints, leaks", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_dossier_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT, dossier TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
            clearance INTEGER NOT NULL, title TEXT, text TEXT NOT NULL, fact TEXT, source TEXT,
            author_char INTEGER, author_name TEXT, created_at INTEGER NOT NULL,
            reviewed_char INTEGER, reviewed_name TEXT, reviewed_at INTEGER, note TEXT)]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_entries_dossier ON sv_dossier_entries (dossier, status)")
        DB.query([[CREATE TABLE IF NOT EXISTS sv_dossier_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT, entry_id INTEGER NOT NULL, action TEXT NOT NULL,
            actor_char INTEGER, actor_name TEXT, note TEXT, time INTEGER NOT NULL)]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_char_knowledge (
            char_id INTEGER NOT NULL, dossier TEXT NOT NULL, fact TEXT NOT NULL, source TEXT, time INTEGER NOT NULL,
            PRIMARY KEY (char_id, dossier, fact))]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_document_prints (
            serial TEXT PRIMARY KEY, dossier TEXT NOT NULL, section TEXT NOT NULL, clearance INTEGER NOT NULL,
            char_id INTEGER, char_name TEXT, card_serial TEXT, terminal TEXT, sector TEXT, time INTEGER NOT NULL)]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_leaks (
            id INTEGER PRIMARY KEY AUTOINCREMENT, doc_serial TEXT, dossier TEXT, section TEXT, clearance INTEGER,
            reader_char INTEGER, reader_name TEXT, reader_clearance INTEGER, sector TEXT, time INTEGER NOT NULL, case_id INTEGER)]])
    end},
})

local function dossier(id)
    return C.Dossiers[id]
end

local function charName(ply)
    return ply.SVChar and ply.SVChar.name or ply:SteamName()
end

local function clearanceOf(ply)
    return SV.Access.clearance(ply)
end

local function history(entryId, action, actor, note)
    DB.query("INSERT INTO sv_dossier_history (entry_id, action, actor_char, actor_name, note, time) VALUES (?, ?, ?, ?, ?, ?)",
        entryId, action, IsValid(actor) and actor.SVChar and actor.SVChar.id or nil, IsValid(actor) and charName(actor) or "Система", note, os.time())
end

--[[---------------------------------------------------------------------------
Character knowledge
---------------------------------------------------------------------------]]
function Knowledge.knows(char, dossierId, fact)
    return DB.queryValue("SELECT 1 FROM sv_char_knowledge WHERE char_id = ? AND dossier = ? AND fact = ?", char.id, dossierId, fact) ~= nil
end

function Knowledge.learn(ply, dossierId, fact, source)
    local char = ply.SVChar
    if not char or char.isSCP then return false end
    if Knowledge.knows(char, dossierId, fact) then return false end
    DB.query("INSERT OR IGNORE INTO sv_char_knowledge (char_id, dossier, fact, source, time) VALUES (?, ?, ?, ?, ?)",
        char.id, dossierId, fact, source, os.time())
    SV.Bus.emit("knowledge.learned", {ply = ply, dossier = dossierId, fact = fact, source = source})
    return true
end

--- Records a discovered fact as a confirmed observation (once per fact).
--- Returns the entry id and whether it was new.
function Knowledge.confirmFact(dossierId, fact, source, author)
    local d = dossier(dossierId)
    local f = d and d.facts[fact]
    if not f then return nil end
    local existing = DB.queryValue("SELECT id FROM sv_dossier_entries WHERE dossier = ? AND fact = ? AND status = 'confirmed'", dossierId, fact)
    if existing then return tonumber(existing), false end
    DB.query([[INSERT INTO sv_dossier_entries (dossier, kind, status, clearance, title, text, fact, source, author_char, author_name, created_at)
        VALUES (?, 'observation', 'confirmed', ?, ?, ?, ?, ?, ?, ?, ?)]], dossierId, f.clearance, f.title, f.text, fact, source,
        IsValid(author) and author.SVChar and author.SVChar.id or nil, IsValid(author) and charName(author) or "Протокол", os.time())
    local id = DB.lastInsertId()
    history(id, "confirmed", author, source)
    SV.Bus.emit("knowledge.factConfirmed", {dossier = dossierId, fact = fact, entry = id, ply = author})
    return id, true
end

--[[---------------------------------------------------------------------------
Views
---------------------------------------------------------------------------]]
--- Builds the view of a dossier for ply. mode = "personal" (F4) or "terminal".
function Knowledge.view(ply, dossierId, mode)
    local d = dossier(dossierId)
    if not d then return nil end
    local char = ply.SVChar
    local clearance = mode == "terminal" and clearanceOf(ply) or 0
    local view = {id = dossierId, title = d.title, class = d.class, mode = mode, clearance = clearance, sections = {}, entries = {}, known = {}}

    for _, s in ipairs(d.sections) do
        if s.clearance <= clearance then
            view.sections[#view.sections + 1] = {id = s.id, title = s.title, kind = s.kind, clearance = s.clearance, text = s.text}
        else
            view.sections[#view.sections + 1] = {id = s.id, title = s.title, kind = s.kind, clearance = s.clearance, locked = true}
        end
    end

    local rows = DB.query("SELECT * FROM sv_dossier_entries WHERE dossier = ? ORDER BY id", dossierId) or {}
    for _, r in ipairs(rows) do
        local own = char and tonumber(r.author_char) == char.id
        local lvl = tonumber(r.clearance)
        local visible = own or (mode == "terminal" and lvl <= clearance and (r.status ~= "proposed" or Roles.hasFlag(ply, "research") or Roles.hasFlag(ply, "investigator")))
        if visible then
            view.entries[#view.entries + 1] = {id = tonumber(r.id), kind = r.kind, status = r.status, clearance = lvl, title = r.title, text = r.text,
                author = r.author_name, created = U.clockString(tonumber(r.created_at)), reviewed = r.reviewed_name, note = r.note, own = own}
        elseif mode == "terminal" and lvl > clearance and r.status == "confirmed" then
            view.entries[#view.entries + 1] = {id = tonumber(r.id), kind = r.kind, status = r.status, clearance = lvl, locked = true}
        end
    end

    if char then
        for _, k in ipairs(DB.query("SELECT fact, source, time FROM sv_char_knowledge WHERE char_id = ? AND dossier = ?", char.id, dossierId) or {}) do
            local f = d.facts[k.fact]
            local section
            if not f and string.sub(k.fact, 1, 4) == "sec:" then
                for _, s in ipairs(d.sections) do if "sec:" .. s.id == k.fact then section = s end end
            end
            if f or section then
                view.known[#view.known + 1] = {title = (f or section).title, text = (f or section).text, source = k.source}
            end
        end
    end
    view.canReview = mode == "terminal" and Roles.hasFlag(ply, "reviewDossier")
    view.canSubmit = Roles.hasFlag(ply, "research") or Roles.hasFlag(ply, "investigator")
    return view
end

function Knowledge.list(ply)
    local out = {}
    for id, d in pairs(C.Dossiers) do
        out[#out + 1] = {id = id, title = d.title, class = d.class}
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function terminalOk(ply, ent)
    if not IsValid(ent) then return false end
    local kind = ent.GetTerminalKind and ent:GetTerminalKind()
    if kind ~= "records" and kind ~= "research" then return false end
    return SV.Terminals.canUse(ply, ent, kind, true)
end

Net.handle("know.list", function(ply)
    Net.send(ply, "know.list", {list = Knowledge.list(ply)})
end)

Net.handle("know.open", function(ply, dossierId, ent)
    local mode = terminalOk(ply, ent) and "terminal" or "personal"
    local view = Knowledge.view(ply, dossierId, mode)
    if not view then return false, "Досье не найдено." end
    view.terminal = mode == "terminal" and ent:EntIndex() or nil
    Net.send(ply, "know.view", view)
    if mode == "terminal" then
        SV.Bus.emit("knowledge.viewed", {ply = ply, dossier = dossierId, terminal = ent})
    end
end)

--[[---------------------------------------------------------------------------
Reports and review
---------------------------------------------------------------------------]]
function Knowledge.submit(ply, dossierId, kind, clearance, text, ent)
    if not dossier(dossierId) then return false, "Досье не найдено." end
    if not (Roles.hasFlag(ply, "research") or Roles.hasFlag(ply, "investigator")) then return false, "Отчёты составляют научные сотрудники и следователи." end
    if kind ~= "observation" and kind ~= "hypothesis" then return false, "Тип отчёта: наблюдение или гипотеза." end
    local atTerminal = terminalOk(ply, ent)
    if not atTerminal and not Inv.has(ply, "notebook") then return false, "Нужен терминал или рабочий журнал." end
    text = U.cleanText(text, 600)
    if U.utf8len(text) < 20 then return false, "Отчёт слишком короткий (минимум 20 символов)." end
    clearance = math.Clamp(clearance, 0, clearanceOf(ply))
    local recent = tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_dossier_entries WHERE author_char = ? AND created_at > ?", ply.SVChar.id, os.time() - 600)) or 0
    if recent >= 3 then return false, "Не более трёх отчётов за 10 минут." end
    DB.query([[INSERT INTO sv_dossier_entries (dossier, kind, status, clearance, title, text, source, author_char, author_name, created_at)
        VALUES (?, ?, ?, ?, ?, ?, 'report', ?, ?, ?)]], dossierId, kind, kind == "hypothesis" and "hypothesis" or "proposed", clearance,
        kind == "hypothesis" and "Гипотеза" or "Наблюдение", text, ply.SVChar.id, charName(ply), os.time())
    local id = DB.lastInsertId()
    history(id, "submitted", ply)
    SV.Audit.log("knowledge", "submit", ply, nil, {entry = id, dossier = dossierId, kind = kind})
    SV.Bus.emit("dossier.submitted", {ply = ply, dossier = dossierId, entry = id, kind = kind})
    return true, "Отчёт №" .. id .. " внесён в досье."
end

function Knowledge.review(ply, entryId, decision, note, ent)
    if not Roles.hasFlag(ply, "reviewDossier") then return false, "Рецензирование доступно старшим научным сотрудникам." end
    if not terminalOk(ply, ent) then return false, "Рецензирование проводится с терминала." end
    local r = DB.queryRow("SELECT * FROM sv_dossier_entries WHERE id = ?", entryId)
    if not r then return false, "Запись не найдена." end
    if tonumber(r.author_char) == ply.SVChar.id then return false, "Нельзя рецензировать собственный отчёт." end
    if tonumber(r.clearance) > clearanceOf(ply) then return false, "Недостаточный допуск." end
    local status = ({confirm = "confirmed", refute = "refuted", hypothesis = "hypothesis"})[decision]
    if not status then return false, "Неизвестное решение." end
    if r.status == status then return false, "Статус уже установлен." end
    note = U.cleanText(note, 200)
    DB.query("UPDATE sv_dossier_entries SET status = ?, kind = ?, reviewed_char = ?, reviewed_name = ?, reviewed_at = ?, note = ? WHERE id = ?",
        status, status == "confirmed" and "observation" or (status == "refuted" and "refuted" or "hypothesis"), ply.SVChar.id, charName(ply), os.time(), note, entryId)
    history(entryId, decision, ply, note)
    SV.Audit.log("knowledge", "review", ply, nil, {entry = entryId, decision = decision})
    SV.Bus.emit("dossier.reviewed", {ply = ply, entry = entryId, decision = decision})
    if status == "confirmed" and r.author_char then
        local author = SV.Chars.active[tonumber(r.author_char)]
        if IsValid(author) then
            SV.Chars.addXP(author, 25, "research")
            DarkRP.notify(author, 0, 6, "Ваш отчёт №" .. entryId .. " подтверждён.")
        end
    end
    return true, "Решение по записи №" .. entryId .. " внесено."
end

Net.handle("know.submit", function(ply, dossierId, kind, clearance, text, ent)
    return Knowledge.submit(ply, dossierId, kind, clearance, text, ent)
end)

Net.handle("know.review", function(ply, entryId, decision, note, ent)
    return Knowledge.review(ply, entryId, decision, note, ent)
end)

--[[---------------------------------------------------------------------------
Documents and leaks
---------------------------------------------------------------------------]]
function Knowledge.printDocument(ply, dossierId, sectionId, ent)
    if not terminalOk(ply, ent) then return false, "Печать доступна с архивного или исследовательского терминала." end
    local d = dossier(dossierId)
    if not d then return false, "Досье не найдено." end
    local section
    for _, s in ipairs(d.sections) do if s.id == sectionId then section = s end end
    if not section then return false, "Раздел не найден." end
    if section.clearance > clearanceOf(ply) then return false, "Недостаточный допуск." end
    local serial = string.format("DOC-%04X%02X", math.random(0, 65535), math.random(0, 255))
    local ok, why = Inv.add(ply, "document", 1, {data = {title = d.title .. " — " .. section.title, dossier = dossierId, section = sectionId,
        clearance = section.clearance, serial = serial, label = "Гриф: допуск " .. section.clearance}})
    if not ok then return false, why end
    local cr = SV.Access.credentials(ply)
    DB.query([[INSERT INTO sv_document_prints (serial, dossier, section, clearance, char_id, char_name, card_serial, terminal, sector, time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], serial, dossierId, sectionId, section.clearance, ply.SVChar.id, charName(ply),
        cr.serials[1], SV.Terminals.key(ent), SV.Facility.sectorAt(ent:GetPos()), os.time())
    SV.Audit.log("knowledge", "print", ply, nil, {serial = serial, dossier = dossierId, section = sectionId})
    SV.Bus.emit("knowledge.printed", {ply = ply, serial = serial, dossier = dossierId, section = sectionId, terminal = ent, clearance = section.clearance})
    return true, "Документ " .. serial .. " распечатан."
end

Net.handle("know.print", function(ply, dossierId, sectionId, ent)
    return Knowledge.printDocument(ply, dossierId, sectionId, ent)
end)

local function readDocument(ply, item)
    local data = item.data
    local d = data.dossier and dossier(data.dossier)
    local section
    if d then
        for _, s in ipairs(d.sections) do if s.id == data.section then section = s end end
    end
    if not section then
        Net.send(ply, "know.document", {title = data.title or "Документ", text = data.text or "Текст неразборчив.", serial = data.serial})
        return true
    end
    Net.send(ply, "know.document", {title = data.title, text = section.text, serial = data.serial, clearance = section.clearance})
    Knowledge.learn(ply, data.dossier, "sec:" .. section.id, "document")

    local readerClear = clearanceOf(ply)
    if section.clearance > readerClear then
        ply.SVLeaksRead = ply.SVLeaksRead or {}
        if not ply.SVLeaksRead[data.serial] then
            ply.SVLeaksRead[data.serial] = true
            local sector = SV.Facility.sectorOf(ply)
            DB.query([[INSERT INTO sv_leaks (doc_serial, dossier, section, clearance, reader_char, reader_name, reader_clearance, sector, time)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], data.serial, data.dossier, data.section, section.clearance, ply.SVChar.id, charName(ply),
                readerClear, sector, os.time())
            local leakId = DB.lastInsertId()
            SV.Audit.log("knowledge", "leak", ply, nil, {serial = data.serial, dossier = data.dossier, section = data.section})
            SV.Bus.emit("knowledge.leak", {ply = ply, serial = data.serial, dossier = data.dossier, section = data.section,
                clearance = section.clearance, sector = sector, leak = leakId})
            if not sector or SV.Facility.subsystemOk(sector, "security") then
                local sectorName = sector and SV.Facility.sectors[sector] and SV.Facility.sectors[sector].name or "неизвестный сектор"
                timer.Simple(math.random(20, 60), function()
                    for _, p in ipairs(player.GetAll()) do
                        if Roles.hasFlag(p, "investigator") or Roles.hasFlag(p, "revokeCards") then
                            DarkRP.notify(p, 3, 8, "Система учёта: несанкционированное ознакомление с документом (гриф " .. section.clearance .. "), " .. sectorName .. ".")
                        end
                    end
                end)
            end
        end
    end
    return true
end
Knowledge.readDocument = readDocument

Inv.registerUse("read", function(ply, item)
    readDocument(ply, item)
    return true
end)

Net.handle("know.read", function(ply, uid)
    local item = Inv.getItem(ply, uid)
    if not item or C.Items[item.id].use ~= "read" then return false, "Документ не найден." end
    return readDocument(ply, item)
end)

--[[---------------------------------------------------------------------------
Records terminal
---------------------------------------------------------------------------]]
SV.Facility.registerTerminal("records", {
    name = "Архивный терминал", req = {clearance = 1}, power = 0.5,
    open = function(ply, ent)
        Net.send(ply, "know.terminal", {ent = ent:EntIndex(), list = Knowledge.list(ply), clearance = clearanceOf(ply)})
    end,
})

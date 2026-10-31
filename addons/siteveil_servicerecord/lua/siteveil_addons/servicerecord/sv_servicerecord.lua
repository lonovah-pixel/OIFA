--[[---------------------------------------------------------------------------
Service record (server).

Who may issue: a superior of the same division (rank higher than the
target's) with the promote or divisionHead flag; internal affairs (flag
audit) may issue reprimands in any division; admins on duty. A reason is
required; one officer issues at most perShift records per shift and one
record of each kind per person per shift. A commendation gives a little
experience (capped by the gamemode); active reprimands (last 7 days, not
revoked) above the limit block promotion. The issuer, the head of the
target's division and admins can revoke a record with a reason.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SR = SV.ServiceRecord
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local K = SV.Config.ServiceRecord
local Roles = SV.Roles

DB.registerMigrations("servicerecord", {
    {1, "service records", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_service_records (id INTEGER PRIMARY KEY AUTOINCREMENT, char_id INTEGER NOT NULL,
            kind TEXT NOT NULL, reason TEXT NOT NULL, by_char INTEGER, by_name TEXT, shift INTEGER, created_at INTEGER NOT NULL,
            revoked_at INTEGER, revoked_by TEXT, revoke_reason TEXT)]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_service_records_char ON sv_service_records (char_id, created_at)")
    end},
})

--- Why actor cannot issue a record of kind to target (nil = can).
function SR.blockedReason(actor, target, kind)
    if not K.kinds[kind] then return "неизвестный вид записи" end
    local a, t = actor.SVChar, IsValid(target) and target.SVChar
    if not a or not t or t.isSCP then return "нет сотрудника" end
    if actor == target then return "нельзя себе" end
    if not SV.Admin.isOnDuty(actor) then
        local ia = kind == "reprimand" and Roles.hasFlag(actor, "audit")
        local superior = a.division == t.division and a.rank > t.rank and (Roles.hasFlag(actor, "promote") or Roles.hasFlag(actor, "divisionHead"))
        if not ia and not superior then return "нужен старший по званию в том же подразделении (или внутренняя безопасность для взысканий)" end
        local issued = tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_service_records WHERE by_char = ? AND shift = ?", a.id, SV.Shift.id)) or 0
        if issued >= K.perShift then return "лимит записей за смену исчерпан" end
        if DB.queryValue("SELECT 1 FROM sv_service_records WHERE by_char = ? AND char_id = ? AND kind = ? AND shift = ?", a.id, t.id, kind, SV.Shift.id) then
            return "вы уже делали такую запись этому сотруднику в эту смену"
        end
    end
    return nil
end

function SR.activeReprimands(charId)
    return tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_service_records WHERE char_id = ? AND kind = 'reprimand' AND revoked_at IS NULL AND created_at > ?",
        charId, os.time() - K.reprimandWindow)) or 0
end

function SR.issue(actor, target, kind, reason)
    reason = U.cleanText(reason, K.reasonMax)
    if U.utf8len(reason) < K.reasonMin then return false, "Укажите основание (не менее " .. K.reasonMin .. " символов)." end
    local why = SR.blockedReason(actor, target, kind)
    if why then return false, "Запись невозможна: " .. why .. "." end
    if not U.within(actor, target, K.range) then return false, "Сотрудник слишком далеко." end
    DB.query("INSERT INTO sv_service_records (char_id, kind, reason, by_char, by_name, shift, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        target.SVChar.id, kind, reason, actor.SVChar and actor.SVChar.id, SV.Chars.displayName(actor), SV.Shift.id, os.time())
    if kind == "commendation" then SV.Chars.addXP(target, K.commendationXP, "task") end
    DarkRP.notify(target, kind == "commendation" and 0 or 1, 10, K.kinds[kind] .. " от " .. SV.Chars.displayName(actor) .. ": " .. reason)
    SV.Audit.log("servicerecord", kind, actor, target, {reason = reason})
    SV.Bus.emit("servicerecord.issued", {ply = actor, target = target, kind = kind})
    return true, K.kinds[kind] .. " внесена в личное дело."
end

local function canView(viewer, target)
    if viewer == target or SV.Admin.isOnDuty(viewer) or Roles.hasFlag(viewer, "audit") then return true end
    local a, t = viewer.SVChar, target.SVChar
    return a and t and a.division == t.division and a.rank > t.rank and (Roles.hasFlag(viewer, "promote") or Roles.hasFlag(viewer, "divisionHead"))
end

local function canRevoke(ply, row, targetDivision)
    if SV.Admin.isOnDuty(ply) then return true end
    local c = ply.SVChar
    if not c then return false end
    return tonumber(row.by_char) == c.id or (Roles.hasFlag(ply, "divisionHead") and c.division == targetDivision)
end

function SR.view(viewer, target)
    local t = target.SVChar
    local rows = DB.query("SELECT * FROM sv_service_records WHERE char_id = ? ORDER BY id DESC LIMIT 30", t.id) or {}
    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = {id = tonumber(r.id), kind = r.kind, kindName = K.kinds[r.kind], reason = r.reason, by = r.by_name,
            when = U.clockString(tonumber(r.created_at)), revoked = r.revoked_at and (r.revoked_by .. ": " .. (r.revoke_reason or "")) or nil,
            canRevoke = r.revoked_at == nil and canRevoke(viewer, r, t.division)}
    end
    return {name = t.name, number = t.number, records = list, active = SR.activeReprimands(t.id), limit = K.reprimandsBlockingPromotion,
        canIssue = {commendation = SR.blockedReason(viewer, target, "commendation") == nil, reprimand = SR.blockedReason(viewer, target, "reprimand") == nil},
        target = target:EntIndex()}
end

Net.handle("srec.issue", function(ply, target, kind, reason) return SR.issue(ply, target, kind, reason) end)

Net.handle("srec.view", function(ply, target)
    if not IsValid(target) or not target:IsPlayer() or not target.SVChar then return false, "Нет сотрудника." end
    if not canView(ply, target) then return false, "Личное дело доступно самому сотруднику, его начальству и внутренней безопасности." end
    Net.send(ply, "srec.view", SR.view(ply, target))
end)

Net.handle("srec.revoke", function(ply, id, reason)
    local row = DB.queryRow("SELECT * FROM sv_service_records WHERE id = ?", id)
    if not row or row.revoked_at then return false, "Запись не найдена." end
    local division = DB.queryValue("SELECT division FROM sv_characters WHERE id = ?", row.char_id)
    if not canRevoke(ply, row, division) then return false, "Нет полномочий." end
    reason = U.cleanText(reason, K.reasonMax)
    if U.utf8len(reason) < K.reasonMin then return false, "Укажите основание отмены." end
    DB.query("UPDATE sv_service_records SET revoked_at = ?, revoked_by = ?, revoke_reason = ? WHERE id = ?", os.time(), SV.Chars.displayName(ply), reason, id)
    SV.Audit.log("servicerecord", "revoke", ply, nil, {id = id, reason = reason})
    return true, "Запись отменена."
end)

hook.Add("SiteVeil.PromotionConditions", "SiteVeil.ServiceRecord", function(char, conditions)
    local n = SR.activeReprimands(char.id)
    local allowed = K.reprimandsBlockingPromotion - 1
    table.insert(conditions, {text = string.format("Действующих взысканий: %d (допускается не более %d)", n, allowed), met = n <= allowed})
end)

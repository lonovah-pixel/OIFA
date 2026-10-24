--[[---------------------------------------------------------------------------
Exact administrative audit log (server).

This is the precise record for administrators: who (SteamID64 + character),
what, where and when, with exact timestamps. It is NEVER exposed through game
interfaces; in-game investigation uses modules/evidence which only stores
deliberately imprecise copies.

Entries are buffered in memory and written in one transaction every few
seconds.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Audit = SV.Audit or {}
local Audit = SV.Audit
local DB = SV.DB

Audit.buffer = Audit.buffer or {}
Audit.recent = Audit.recent or {}
local MAX_RECENT = 500

DB.registerMigrations("audit", {
    {1, "create audit table", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            time INTEGER NOT NULL,
            category TEXT NOT NULL,
            action TEXT NOT NULL,
            actor_sid TEXT,
            actor_char INTEGER,
            actor_name TEXT,
            target_sid TEXT,
            target_char INTEGER,
            map TEXT,
            pos TEXT,
            details TEXT
        )]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_audit_time ON sv_audit (time)")
        DB.query("CREATE INDEX IF NOT EXISTS sv_audit_cat ON sv_audit (category, time)")
        DB.query("CREATE INDEX IF NOT EXISTS sv_audit_actor ON sv_audit (actor_sid, time)")
    end},
})

local function describe(ent)
    if not IsValid(ent) or not ent:IsPlayer() then return nil, nil, nil end
    local char = ent.SVChar
    return ent:SteamID64(), char and char.id or nil, char and char.name or ent:Nick()
end

--- Records an audit entry.
--  category: "access", "inventory", "security", "admin", "net", "character", ...
--  actor/target: players or nil; details: table (JSON encoded)
function Audit.log(category, action, actor, target, details)
    local actorSid, actorChar, actorName = describe(actor)
    local targetSid, targetChar = describe(target)
    local pos
    if IsValid(actor) then
        local p = actor:GetPos()
        pos = string.format("%d %d %d", p.x, p.y, p.z)
    end

    local entry = {
        time = os.time(),
        category = category,
        action = action,
        actor_sid = actorSid,
        actor_char = actorChar,
        actor_name = actorName,
        target_sid = targetSid,
        target_char = targetChar,
        map = game.GetMap(),
        pos = pos,
        details = details and util.TableToJSON(details) or nil,
    }
    table.insert(Audit.buffer, entry)
    table.insert(Audit.recent, entry)
    if #Audit.recent > MAX_RECENT then table.remove(Audit.recent, 1) end
    hook.Run("SiteVeil.AuditEntry", entry)
end

function Audit.flush()
    if #Audit.buffer == 0 or not DB.ready then return end
    local batch = Audit.buffer
    Audit.buffer = {}
    local ok = DB.transaction(function()
        for _, e in ipairs(batch) do
            DB.query([[INSERT INTO sv_audit (time, category, action, actor_sid, actor_char, actor_name,
                target_sid, target_char, map, pos, details) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
                e.time, e.category, e.action, e.actor_sid, e.actor_char, e.actor_name,
                e.target_sid, e.target_char, e.map, e.pos, e.details)
        end
    end)
    if not ok then
        -- Keep the entries for the next attempt instead of losing them.
        for i = #batch, 1, -1 do table.insert(Audit.buffer, 1, batch[i]) end
    end
end

--- Searches the audit log (admin panel). All filters optional.
function Audit.search(filter)
    filter = filter or {}
    local where, params = {"1 = 1"}, {}
    if filter.category then table.insert(where, "category = ?") table.insert(params, filter.category) end
    if filter.actor then table.insert(where, "(actor_sid = ? OR target_sid = ?)") table.insert(params, filter.actor) table.insert(params, filter.actor) end
    if filter.since then table.insert(where, "time >= ?") table.insert(params, filter.since) end
    if filter.text then
        table.insert(where, "(action LIKE ? OR details LIKE ? OR actor_name LIKE ?)")
        local like = "%" .. string.gsub(filter.text, "[%%_]", "") .. "%"
        table.insert(params, like) table.insert(params, like) table.insert(params, like)
    end
    local limit = math.Clamp(tonumber(filter.limit) or 100, 1, 500)
    table.insert(params, limit)
    return DB.query("SELECT * FROM sv_audit WHERE " .. table.concat(where, " AND ") .. " ORDER BY id DESC LIMIT ?", unpack(params)) or {}
end

timer.Create("SiteVeil.Audit.Flush", 5, 0, Audit.flush)
hook.Add("ShutDown", "SiteVeil.Audit.Flush", Audit.flush)

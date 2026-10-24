--[[---------------------------------------------------------------------------
Database layer (server).

SQLite through Garry's Mod's built-in `sql` library (garrysmod/sv.db), the
same database file DarkRP uses for its own tables. All SITE-VEIL tables are
prefixed with "sv_".

Rules:
  * Queries are built with `?` placeholders only. Values are escaped by
    DB.escape(); identifiers are never taken from players.
  * Every schema change is a numbered migration of a module. Migrations run
    once, in manifest order, each inside its own transaction.
  * Transactions roll back on any error (DB.transaction).
  * Nothing writes to the database every frame: modules batch through
    DB.defer() which flushes on a timer, on disconnect and on shutdown.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.DB = SV.DB or {}
local DB = SV.DB
local Log = SV.Log

DB.migrations = DB.migrations or {}   -- module -> list of {version, name, up}
DB.migrationOrder = DB.migrationOrder or {}
DB.ready = DB.ready or false
DB.failed = DB.failed or false
DB.stats = DB.stats or {queries = 0, errors = 0, slowest = 0, slowestQuery = ""}

local txDepth = 0

--[[---------------------------------------------------------------------------
Escaping and formatting
---------------------------------------------------------------------------]]
function DB.escape(v)
    local t = type(v)
    if v == nil then return "NULL" end
    if t == "boolean" then return v and "1" or "0" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            error("DB.escape: non-finite number", 3)
        end
        if v == math.floor(v) and math.abs(v) < 2^53 then
            return string.format("%d", v)
        end
        return string.format("%.17g", v)
    end
    if t == "string" then
        -- sql.SQLStr quotes and doubles single quotes; NUL bytes are removed
        -- because SQLite's C API would truncate the statement at them.
        local clean = string.gsub(v, "%z", "")
        return sql.SQLStr(clean)
    end
    error("DB.escape: unsupported type " .. t, 3)
end

--- Replaces each `?` with the escaped value of the next argument.
function DB.format(query, ...)
    local args = {...}
    local n = select("#", ...)
    local i = 0
    local out = string.gsub(query, "%?", function()
        i = i + 1
        if i > n then error("DB.format: not enough parameters for query: " .. query, 4) end
        return DB.escape(args[i])
    end)
    if i ~= n then
        error(string.format("DB.format: %d placeholders, %d parameters: %s", i, n, query), 3)
    end
    return out
end

--[[---------------------------------------------------------------------------
Execution
---------------------------------------------------------------------------]]
local function run(text)
    sql.m_strError = nil -- reset so LastError reflects this statement only
    local started = SysTime()
    local result = sql.Query(text)
    local elapsed = SysTime() - started

    DB.stats.queries = DB.stats.queries + 1
    if elapsed > DB.stats.slowest then
        DB.stats.slowest = elapsed
        DB.stats.slowestQuery = string.sub(text, 1, 120)
    end
    if SV.Perf then SV.Perf.record("db.query", elapsed) end

    local err = sql.LastError()
    if result == false or (result == nil and err and err ~= "") then
        DB.stats.errors = DB.stats.errors + 1
        return nil, err or "unknown sqlite error"
    end
    -- Garry's Mod returns every value as a string and SQL NULL as the string
    -- "NULL". Normalise NULL to nil here so callers never see the sentinel.
    if result then
        for _, row in ipairs(result) do
            for k, v in pairs(row) do
                if v == "NULL" then row[k] = nil end
            end
        end
    end
    return result or {}
end

--- Runs a query. Returns rows (possibly empty table) or nil, error.
function DB.query(query, ...)
    local text = DB.format(query, ...)
    local rows, err = run(text)
    if not rows then
        Log.error("SQL error: %s | %s", tostring(err), string.sub(text, 1, 300))
        if txDepth > 0 then error("sql: " .. tostring(err), 0) end
        return nil, err
    end
    return rows
end

function DB.queryRow(query, ...)
    local rows, err = DB.query(query, ...)
    if not rows then return nil, err end
    return rows[1]
end

function DB.queryValue(query, ...)
    local row, err = DB.queryRow(query, ...)
    if not row then return nil, err end
    local _, v = next(row)
    return v
end

function DB.exec(query, ...)
    return DB.query(query, ...) ~= nil
end

function DB.lastInsertId()
    local rows = run("SELECT last_insert_rowid() AS id")
    return rows and rows[1] and tonumber(rows[1].id) or nil
end

function DB.changes()
    local rows = run("SELECT changes() AS n")
    return rows and rows[1] and tonumber(rows[1].n) or 0
end

--- Runs fn inside a transaction. Nested calls use savepoints. Any error
--- (Lua or SQL) rolls back and is returned as `false, err`.
function DB.transaction(fn, ...)
    local savepoint = "sv_sp" .. (txDepth + 1)
    if txDepth == 0 then
        local _, err = run("BEGIN IMMEDIATE")
        if err then return false, err end
    else
        run("SAVEPOINT " .. savepoint)
    end

    txDepth = txDepth + 1
    local results = {pcall(fn, ...)}
    txDepth = txDepth - 1

    if results[1] then
        if txDepth == 0 then
            local _, err = run("COMMIT")
            if err then
                run("ROLLBACK")
                return false, err
            end
        else
            run("RELEASE " .. savepoint)
        end
        return true, unpack(results, 2)
    end

    if txDepth == 0 then
        run("ROLLBACK")
    else
        run("ROLLBACK TO " .. savepoint)
        run("RELEASE " .. savepoint)
    end
    Log.error("transaction rolled back: %s", tostring(results[2]))
    return false, results[2]
end

function DB.inTransaction()
    return txDepth > 0
end

--[[---------------------------------------------------------------------------
Migrations
---------------------------------------------------------------------------]]

--- Registers migrations of a module. `list` entries: {version, name, up}
--- where up is either a SQL string or function() (runs inside the transaction).
function DB.registerMigrations(module, list)
    if not DB.migrations[module] then
        table.insert(DB.migrationOrder, module)
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    DB.migrations[module] = list
end

local function appliedVersions()
    local applied = {}
    local rows = DB.query("SELECT module, version FROM sv_migrations") or {}
    for _, row in ipairs(rows) do
        applied[row.module .. "#" .. row.version] = true
    end
    return applied
end

-- Runs inside a transaction. A string migration may contain several
-- statements separated by ";" at line ends.
local function applyMigration(module, m)
    local version, name, up = m[1], m[2], m[3]
    if isstring(up) then
        for statement in string.gmatch(up .. ";\n", "(.-);%s*\n") do
            if string.find(statement, "%S") then
                local _, qerr = run(statement)
                if qerr then error(qerr, 0) end
            end
        end
    else
        up()
    end
    DB.query("INSERT INTO sv_migrations (module, version, name, applied_at) VALUES (?, ?, ?, ?)",
        module, version, name, os.time())
end

function DB.migrate()
    local ok = DB.exec([[CREATE TABLE IF NOT EXISTS sv_migrations (
        module TEXT NOT NULL,
        version INTEGER NOT NULL,
        name TEXT NOT NULL,
        applied_at INTEGER NOT NULL,
        PRIMARY KEY (module, version)
    )]])
    if not ok then
        DB.failed = true
        return false, "cannot create sv_migrations"
    end

    local applied = appliedVersions()
    local count = 0

    for _, module in ipairs(DB.migrationOrder) do
        for _, m in ipairs(DB.migrations[module]) do
            if not applied[module .. "#" .. m[1]] then
                local success, err = DB.transaction(applyMigration, module, m)
                if not success then
                    DB.failed = true
                    Log.error("migration %s#%d (%s) failed: %s", module, m[1], m[2], tostring(err))
                    return false, err
                end
                count = count + 1
                Log.info("migration applied: %s#%d %s", module, m[1], m[2])
            end
        end
    end

    DB.ready = true
    return true, count
end

--[[---------------------------------------------------------------------------
Deferred writes

DB.defer(key, fn) remembers the latest writer for a key; fn runs on the next
flush. Use it for data that changes often (inventory, progress). Flushes
happen every `interval` seconds, on PlayerDisconnected and on ShutDown.
---------------------------------------------------------------------------]]
DB.pending = DB.pending or {}
DB.pendingOrder = DB.pendingOrder or {}

function DB.defer(key, fn)
    if not DB.pending[key] then
        table.insert(DB.pendingOrder, key)
    end
    DB.pending[key] = fn
end

function DB.flushKey(key)
    local fn = DB.pending[key]
    if not fn then return true end
    DB.pending[key] = nil
    for i, k in ipairs(DB.pendingOrder) do
        if k == key then table.remove(DB.pendingOrder, i) break end
    end
    local ok, err = DB.transaction(fn)
    if not ok then Log.error("deferred write %s failed: %s", key, tostring(err)) end
    return ok
end

function DB.flush()
    if #DB.pendingOrder == 0 then return 0 end
    local order = DB.pendingOrder
    local pending = DB.pending
    DB.pendingOrder = {}
    DB.pending = {}

    local ok, err = DB.transaction(function()
        for _, key in ipairs(order) do
            local fn = pending[key]
            if fn then fn() end
        end
    end)
    if not ok then
        Log.error("deferred flush failed, retrying keys individually: %s", tostring(err))
        for _, key in ipairs(order) do
            if pending[key] then
                local okKey, errKey = DB.transaction(pending[key])
                if not okKey then Log.error("deferred write %s lost: %s", key, tostring(errKey)) end
            end
        end
    end
    return #order
end

timer.Create("SiteVeil.DB.Flush", 10, 0, function() DB.flush() end)
hook.Add("ShutDown", "SiteVeil.DB.Flush", function() DB.flush() end)

--[[---------------------------------------------------------------------------
Helpers for JSON columns
---------------------------------------------------------------------------]]
function DB.encode(tbl)
    return util.TableToJSON(tbl or {}) or "{}"
end

function DB.decode(text)
    if not isstring(text) or text == "" then return {} end
    return util.JSONToTable(text) or {}
end

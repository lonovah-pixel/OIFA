--[[---------------------------------------------------------------------------
Persistent key/value settings (server): director switch, shift counter,
admin toggles. Values are JSON encoded.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local DB = SV.DB

DB.registerMigrations("settings", {
    {1, "settings table", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )]])
    end},
})

SV.Settings = SV.Settings or {}
local Settings = SV.Settings

function Settings.get(key, default)
    if not DB.ready then return default end
    local v = DB.queryValue("SELECT value FROM sv_settings WHERE key = ?", key)
    if v == nil then return default end
    local decoded = util.JSONToTable("[" .. v .. "]")
    if decoded then return decoded[1] end
    return default
end

function Settings.set(key, value)
    local encoded = util.TableToJSON({value})
    encoded = string.sub(encoded, 2, -2)
    return DB.exec("INSERT OR REPLACE INTO sv_settings (key, value, updated_at) VALUES (?, ?, ?)", key, encoded, os.time())
end


--[[---------------------------------------------------------------------------
SITE-VEIL addon loader.

An addon is a normal Garry's Mod addon (garrysmod/addons/<folder>/) whose
Lua lives in lua/siteveil_addons/<id>/. Its description file
lua/siteveil_addons/<id>/addon.lua returns:

    return {
        id = "intercom",                    -- must equal the folder name
        name = "Интерком", version = "1.0.0", author = "...", description = "...",
        requires = {"comms", "facility"},   -- SITE-VEIL modules (sh_manifest.lua)
        depends = {"cctv"},                 -- other addons that must be present
        after = {"tesla"},                  -- load after these addons if present
        config = {"sh_config.lua"},         -- boot stage, right after the gamemode
                                            -- config: may extend SiteVeil.Config
                                            -- (roles, items, ...) before indexing
        files = {"sh_x.lua", "sv_x.lua", "cl_x.lua"},  -- main stage, after all modules
    }

File realms follow the same prefixes as the gamemode (sh_, sv_, cl_).
An addon that fails to load (missing dependency, Lua error) is reported in
the console and the admin panel and does not stop the gamemode. Addons are
switched off with the convar siteveil_addons_disabled "id1,id2" (restart).
See ADDONS.md.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Loader = SV.Loader

SV.Addons = SV.Addons or {}
local Addons = SV.Addons

Addons.list = Addons.list or {}   -- ordered list of addon records
Addons.byId = Addons.byId or {}

local ROOT = "siteveil_addons/"

local disabledConvar = CreateConVar("siteveil_addons_disabled", "", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "SITE-VEIL: comma separated ids of addons that are not loaded (restart required)")

local function disabledSet()
    local out = {}
    for id in string.gmatch(disabledConvar:GetString() or "", "[^,%s]+") do out[id] = true end
    return out
end

local function fail(rec, msg)
    rec.status = "error"
    rec.error = msg
    Loader.addError("addon '" .. rec.id .. "': " .. msg)
end

--- Runs one Lua file of an addon; errors are contained.
local function runFile(path)
    if CompileFile then
        local fn = CompileFile(path)
        if not fn then return false, "cannot compile " .. path end
        local ok, err = pcall(fn)
        if not ok then return false, tostring(err) end
        return true
    end
    local ok, err = pcall(include, path)
    if not ok then return false, tostring(err) end
    return true
end

local function loadAddonFile(rec, file)
    local full = ROOT .. rec.id .. "/" .. file
    local prefix = string.sub(string.match(file, "([^/]+)$") or file, 1, 3)
    if prefix == "sh_" then
        if SERVER then AddCSLuaFile(full) end
        return runFile(full)
    elseif prefix == "sv_" then
        if SERVER then return runFile(full) end
        return true
    elseif prefix == "cl_" then
        if SERVER then
            AddCSLuaFile(full)
            return true
        end
        return runFile(full)
    end
    return false, "file without realm prefix: " .. file
end

--- Orders addons so that `depends` and `after` come first (stable by id).
local function order(records)
    local byId, out, state = {}, {}, {}
    for _, r in ipairs(records) do byId[r.id] = r end
    local function visit(r)
        if state[r.id] == "done" then return end
        if state[r.id] == "visiting" then
            fail(r, "cyclic addon dependency")
            return
        end
        state[r.id] = "visiting"
        local before = {}
        for _, d in ipairs(r.def.depends or {}) do before[#before + 1] = d end
        for _, d in ipairs(r.def.after or {}) do before[#before + 1] = d end
        for _, d in ipairs(before) do
            if byId[d] then visit(byId[d]) end
        end
        state[r.id] = "done"
        out[#out + 1] = r
    end
    for _, r in ipairs(records) do visit(r) end
    return out
end

--- Finds addons, reads their descriptions. Called once at boot.
function Addons.discover()
    Addons.list, Addons.byId = {}, {}
    local _, dirs = file.Find(ROOT .. "*", "LUA")
    table.sort(dirs)
    local disabled = disabledSet()
    local records = {}
    for _, id in ipairs(dirs) do
        local rec = {id = id, status = "pending"}
        Addons.byId[id] = rec
        records[#records + 1] = rec
        local descPath = ROOT .. id .. "/addon.lua"
        if disabled[id] then
            rec.status = "disabled"
        elseif not file.Exists(descPath, "LUA") then
            fail(rec, "addon.lua not found")
        else
            if SERVER then AddCSLuaFile(descPath) end
            local fn = CompileFile and CompileFile(descPath) or function() return include(descPath) end
            local ok, def = pcall(fn)
            if not ok or not istable(def) then
                fail(rec, "addon.lua must return a table" .. (ok and "" or (": " .. tostring(def))))
            elseif def.id ~= id then
                fail(rec, "addon.lua id '" .. tostring(def.id) .. "' does not match the folder")
            else
                rec.def = def
                rec.name = def.name or id
                rec.version = def.version or "?"
            end
        end
    end
    for _, rec in ipairs(records) do
        if rec.status == "pending" then
            for _, d in ipairs(rec.def.depends or {}) do
                local other = Addons.byId[d]
                if not other or other.status == "disabled" then
                    fail(rec, "requires addon '" .. d .. "'" .. (other and " which is disabled" or " which is not installed"))
                    break
                end
            end
        end
    end
    local usable = {}
    for _, rec in ipairs(records) do
        if rec.status == "pending" then usable[#usable + 1] = rec end
    end
    Addons.list = order(usable)
    for _, rec in ipairs(records) do
        if rec.status ~= "pending" then Addons.list[#Addons.list + 1] = rec end
    end
end

--- Loads the files of one addon stage ("config" or "files") of every usable addon.
function Addons.loadStage(stage)
    for _, rec in ipairs(Addons.list) do
        if rec.status == "pending" or rec.status == "config" then
            local blocked
            for _, d in ipairs(rec.def.depends or {}) do
                local other = Addons.byId[d]
                if not other or other.status == "error" then blocked = d end
            end
            if stage == "files" then
                for _, m in ipairs(rec.def.requires or {}) do
                    if not SV.Loaded[m] then blocked = "module " .. m end
                end
            end
            if blocked then
                fail(rec, "dependency " .. blocked .. " is not available")
            else
                for _, f in ipairs(rec.def[stage] or {}) do
                    local ok, err = loadAddonFile(rec, f)
                    if not ok then
                        fail(rec, err)
                        break
                    end
                end
                if rec.status ~= "error" then rec.status = stage == "config" and "config" or "loaded" end
            end
        end
    end
end

function Addons.isLoaded(id)
    local rec = Addons.byId[id]
    return rec ~= nil and rec.status == "loaded"
end

--- Summary for the admin panel.
function Addons.describe()
    local out = {}
    for _, rec in ipairs(Addons.list) do
        out[#out + 1] = {id = rec.id, name = rec.name or rec.id, version = rec.version, status = rec.status, error = rec.error,
            description = rec.def and rec.def.description or nil}
    end
    return out
end

-- Hook into the module loader: addon config right after the gamemode
-- config, addon files after the last main-stage module.
Loader.afterModule = function(name)
    if name == "config" then Addons.loadStage("config") end
end
Loader.afterStage = function(stage)
    if stage == "main" then Addons.loadStage("files") end
end

Addons.discover()

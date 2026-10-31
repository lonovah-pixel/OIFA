--[[---------------------------------------------------------------------------
Manifest driven loader.

Every SITE-VEIL file is listed explicitly in sh_manifest.lua together with the
module it belongs to and the modules it depends on. The realm of a file is
derived from its prefix (sh_, sv_, cl_). The loader refuses to load a module
whose dependencies have not been loaded before it, which makes the load order
explicit and rules out dependency cycles.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Loader = SV.Loader or {}
local Loader = SV.Loader

Loader.modules = Loader.modules or {}      -- ordered list of module definitions
Loader.byName = Loader.byName or {}
Loader.errors = Loader.errors or {}

local function fileName(path)
    return string.match(path, "([^/]+)$") or path
end

local function realmPrefix(path)
    return string.sub(fileName(path), 1, 3)
end

function Loader.addError(msg)
    table.insert(Loader.errors, msg)
    ErrorNoHalt("[SITE-VEIL] " .. msg .. "\n")
end

--- Declares a module. Called from sh_manifest.lua only.
function Loader.module(def)
    assert(isstring(def.name), "module needs a name")
    assert(istable(def.files), "module " .. def.name .. " needs files")
    def.stage = def.stage or "main"
    def.deps = def.deps or {}

    if Loader.byName[def.name] then
        -- Manifest reloaded (lua refresh): replace the definition in place.
        for i, m in ipairs(Loader.modules) do
            if m.name == def.name then Loader.modules[i] = def end
        end
    else
        table.insert(Loader.modules, def)
    end
    Loader.byName[def.name] = def
end

function Loader.loadFile(path)
    local full = SV.Root .. path
    local prefix = realmPrefix(path)

    if prefix == "sh_" then
        if SERVER then AddCSLuaFile(full) end
        include(full)
    elseif prefix == "sv_" then
        if SERVER then include(full) end
    elseif prefix == "cl_" then
        if SERVER then AddCSLuaFile(full) else include(full) end
    else
        Loader.addError("file without realm prefix in manifest: " .. path)
    end
end

--- Loads all modules of one stage in manifest order.
function Loader.loadStage(stage)
    for _, def in ipairs(Loader.modules) do
        if def.stage == stage then
            local missing
            for _, dep in ipairs(def.deps) do
                if not SV.Loaded[dep] then
                    missing = dep
                    break
                end
            end

            if missing then
                Loader.addError(string.format("module '%s' requires '%s' which is not loaded before it", def.name, missing))
            else
                for _, path in ipairs(def.files) do
                    Loader.loadFile(path)
                end
                SV.Loaded[def.name] = true
                if Loader.afterModule then Loader.afterModule(def.name) end
            end
        end
    end
    if Loader.afterStage then Loader.afterStage(stage) end
end

--- Returns the manifest as a list of {name, deps} for diagnostics and tests.
function Loader.describe()
    local out = {}
    for _, def in ipairs(Loader.modules) do
        table.insert(out, {name = def.name, stage = def.stage, deps = def.deps, loaded = SV.Loaded[def.name] == true})
    end
    return out
end

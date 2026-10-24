--[[---------------------------------------------------------------------------
Facility (shared): subsystems, status buckets, terminal registry, network
schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Facility = SV.Facility or {}
local Facility = SV.Facility
local C = SV.Config
local Net = SV.Net

Facility.subsystems = C.Facility.subsystems

SV.Sync.define("sectors", {scope = "global"})
SV.Sync.define("facility", {scope = "global"})

--- Status bucket of a 0..1 value.
function Facility.bucket(v)
    if v == nil then return "unknown" end
    local h = v * 100
    if h >= C.Facility.healthOk then return "ok" end
    if h >= C.Facility.healthDegraded then return "degraded" end
    if h >= C.Facility.healthDamaged then return "damaged" end
    return "offline"
end

Facility.bucketNames = {
    ok = "норма", degraded = "нестабильно", damaged = "авария", offline = "отказ", unknown = "нет данных",
}

--[[---------------------------------------------------------------------------
Terminals: each kind is registered by the module that owns its screen.
    Facility.registerTerminal("infrastructure", {
        name = "...", req = {clearance = 1, tags = {...}},
        power = 0.5,                      -- minimal sector power
        open = function(ply, ent) end,    -- server
    })
---------------------------------------------------------------------------]]
Facility.terminals = Facility.terminals or {}

function Facility.registerTerminal(kind, def)
    Facility.terminals[kind] = def
end

Net.define("infra.node", {args = {"ent"}, rate = {burst = 4, refill = 1}})
Net.define("infra.action", {args = {"ent", "str:16"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("infra.overview", {args = {"ent"}, rate = {burst = 3, refill = 0.5}})
Net.define("infra.priority", {args = {"ent", "str:32", "u8"}, alive = true, rate = {burst = 6, refill = 1}})
Net.define("facility.declare", {args = {"str:16", "str:32", "str:200"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("facility.status", {args = {}, rate = {burst = 3, refill = 0.5}})

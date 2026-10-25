--[[---------------------------------------------------------------------------
SCP framework (shared): registry of definitions, stage helpers, network
schema. Behaviour lives in sv_scp.lua and sv_scp<id>.lua.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.SCP = SV.SCP or {}
local SCP = SV.SCP
local C = SV.Config

SCP.defs = SCP.defs or {}

SV.Sync.define("scp", {scope = "global"})

function SCP.stageOf(integrity)
    for _, s in ipairs(C.SCP.stages) do
        if integrity >= s.min then return s end
    end
    return C.SCP.stages[#C.SCP.stages]
end

function SCP.stageName(id)
    for _, s in ipairs(C.SCP.stages) do
        if s.id == id then return s.name end
    end
    return id
end

--- SCP id played by ply, or nil.
function SCP.of(ply)
    local role = SV.Roles.ofPlayer(ply)
    return role and role.scp or nil
end

SV.Net.define("scp.panel", {args = {"ent"}, rate = {burst = 4, refill = 1}})
SV.Net.define("scp.procedure", {args = {"ent", "str:24"}, alive = true, rate = {burst = 2, refill = 0.3}})
SV.Net.define("scp.recapture", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.3}})
SV.Net.define("scp.ability", {args = {"str:16", "ent"}, alive = true, ignoreStates = true, rate = {burst = 6, refill = 3}, rateMessage = false})

--[[---------------------------------------------------------------------------
Duty tasks (shared): network schema and lookup.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Tasks = SV.Tasks or {}
local Tasks = SV.Tasks

Tasks.defs = {}
for _, def in ipairs(SV.Config.TaskList) do
    assert(not Tasks.defs[def.id], "duplicate task id " .. def.id)
    Tasks.defs[def.id] = def
end

SV.Net.define("tasks.list", {args = {}, rate = {burst = 3, refill = 0.5}})
SV.Net.define("tasks.accept", {args = {"str:32"}, rate = {burst = 3, refill = 0.3}})
SV.Net.define("tasks.abandon", {args = {"str:32"}, rate = {burst = 3, refill = 0.3}})

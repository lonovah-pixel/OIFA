--[[---------------------------------------------------------------------------
Director (shared): network schema and the public channel of running events.
Event definitions are server only (config/sv_director.lua).
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Director = SV.Director or {}
local Net = SV.Net

-- Running events as seen by players: name, task text, solver divisions,
-- rounded position of callouts, end time. Nothing about future events.
SV.Sync.define("director", {scope = "global"})

Net.define("director.status", {args = {}, allowNoChar = true, ignoreStates = true, admin = true, rate = {burst = 3, refill = 0.5}})
Net.define("director.toggle", {args = {"bool"}, allowNoChar = true, ignoreStates = true, admin = true, rate = {burst = 2, refill = 0.2}})
Net.define("director.event", {args = {"str:32", "bool"}, allowNoChar = true, ignoreStates = true, admin = true, rate = {burst = 6, refill = 1}})
Net.define("director.force", {args = {"str:32"}, allowNoChar = true, ignoreStates = true, admin = true, rate = {burst = 2, refill = 0.2}})
Net.define("director.cancel", {args = {"u32"}, allowNoChar = true, ignoreStates = true, admin = true, rate = {burst = 3, refill = 0.5}})

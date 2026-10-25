--[[---------------------------------------------------------------------------
Reinforcement waves (shared): network schema and the public wave channel.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Reinforcements = SV.Reinforcements or {}
local Net = SV.Net

SV.Sync.define("reinforcements", {scope = "global"})

Net.define("reinf.queue", {args = {"str:8", "u32"}, allowNoChar = true, ignoreStates = true, rate = {burst = 3, refill = 0.3}})
Net.define("reinf.leave", {args = {}, allowNoChar = true, ignoreStates = true, rate = {burst = 3, refill = 0.3}})
Net.define("reinf.call", {args = {"str:8"}, alive = true, rate = {burst = 2, refill = 0.1}})

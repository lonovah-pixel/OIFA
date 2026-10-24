--[[---------------------------------------------------------------------------
Supply (shared): network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Supply = SV.Supply or {}
local Net = SV.Net

SV.Sync.define("budgets", {scope = "global"})

Net.define("supply.overview", {args = {}, rate = {burst = 3, refill = 0.5}})
Net.define("supply.request", {args = {"json:1024", "str:200"}, rate = {burst = 2, refill = 0.05}})
Net.define("supply.decide", {args = {"u32", "bool", "str:200"}, rate = {burst = 4, refill = 0.5}})
Net.define("supply.cancel", {args = {"u32"}, rate = {burst = 3, refill = 0.3}})
Net.define("supply.lockerTake", {args = {"ent", "str:32"}, alive = true, rate = {burst = 4, refill = 1}})
Net.define("supply.lockerReturn", {args = {"ent", "u32"}, alive = true, rate = {burst = 4, refill = 1}})

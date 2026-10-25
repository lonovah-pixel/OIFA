--[[---------------------------------------------------------------------------
Hidden tasks (shared): network schema. Task definitions are server only.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Hidden = SV.Hidden or {}
local Net = SV.Net

Net.define("hidden.optin", {args = {"bool"}, rate = {burst = 2, refill = 0.2}})
Net.define("hidden.answer", {args = {"bool"}, rate = {burst = 2, refill = 0.3}})
Net.define("hidden.abandon", {args = {}, rate = {burst = 2, refill = 0.3}})
Net.define("hidden.state", {args = {}, rate = {burst = 3, refill = 0.5}})
Net.define("hidden.toggle", {args = {"bool"}, allowNoChar = true, ignoreStates = true, admin = true, rate = {burst = 2, refill = 0.2}})

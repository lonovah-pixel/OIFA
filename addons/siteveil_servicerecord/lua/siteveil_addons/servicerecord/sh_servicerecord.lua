--[[---------------------------------------------------------------------------
Service record (shared): configuration and network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.ServiceRecord = SV.ServiceRecord or {}
local Net = SV.Net

SV.Config.ServiceRecord = {
    reasonMin = 10,
    reasonMax = 200,
    perShift = 4,              -- records one officer may issue per shift
    commendationXP = 15,
    reprimandWindow = 7 * 86400,
    reprimandsBlockingPromotion = 2,
    range = 300,
    kinds = {commendation = "Благодарность", reprimand = "Взыскание"},
}

Net.define("srec.issue", {args = {"ent", "str:16", "str:200"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("srec.view", {args = {"ent"}, rate = {burst = 4, refill = 1}})
Net.define("srec.revoke", {args = {"u32", "str:200"}, rate = {burst = 3, refill = 0.3}})

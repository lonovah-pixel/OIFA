--[[---------------------------------------------------------------------------
Administration panel (shared): players, whitelist, tickets, audit search.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Net = SV.Net

local function def(name, args, rate)
    Net.define(name, {args = args, allowNoChar = true, ignoreStates = true, admin = true, rate = rate or {burst = 4, refill = 1}})
end

def("admin.players", {})
def("admin.whitelist", {"str:20", "str:16", "str:32", "bool", "str:120"}, {burst = 6, refill = 1})
def("admin.whitelistOf", {"str:20"})
def("admin.tickets", {})
def("admin.ticket", {"u32", "str:8", "str:300"}, {burst = 6, refill = 1})
def("admin.audit", {"json:512"}, {burst = 3, refill = 0.3})

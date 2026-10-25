--[[---------------------------------------------------------------------------
Evidence and investigations (shared): network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Evidence = SV.Evidence or {}
local Net = SV.Net

Net.define("evidence.scan", {args = {}, alive = true, rate = {burst = 2, refill = 0.4}})
Net.define("evidence.collect", {args = {"u32"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("evidence.analyze", {args = {"u32", "ent"}, alive = true, rate = {burst = 2, refill = 0.2}})
Net.define("evidence.terminal", {args = {"ent"}, rate = {burst = 3, refill = 0.5}})
Net.define("case.list", {args = {}, rate = {burst = 3, refill = 0.5}})
Net.define("case.view", {args = {"u32"}, rate = {burst = 4, refill = 1}})
Net.define("case.create", {args = {"str:80"}, rate = {burst = 2, refill = 0.1}})
Net.define("case.attach", {args = {"u32", "u32"}, alive = true, rate = {burst = 4, refill = 0.5}})
Net.define("case.note", {args = {"u32", "str:500"}, rate = {burst = 3, refill = 0.2}})
Net.define("case.close", {args = {"u32", "str:500"}, rate = {burst = 2, refill = 0.1}})

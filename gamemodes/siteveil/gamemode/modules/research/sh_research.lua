--[[---------------------------------------------------------------------------
Research (shared): network schema. Protocol definitions are server only
(config/sv_protocols.lua).
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Research = SV.Research or {}
local Net = SV.Net

Net.define("research.protocols", {args = {"ent"}, rate = {burst = 3, refill = 0.5}})
Net.define("research.create", {args = {"ent", "str:32"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("research.invite", {args = {"ent"}, alive = true, rate = {burst = 6, refill = 1}})
Net.define("research.join", {args = {"u32", "bool"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("research.leave", {args = {}, alive = true, rate = {burst = 2, refill = 0.3}})
Net.define("research.requestApproval", {args = {}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("research.approve", {args = {"u32", "bool", "str:200"}, rate = {burst = 3, refill = 0.3}})
Net.define("research.start", {args = {}, alive = true, rate = {burst = 2, refill = 0.2}})
Net.define("research.step", {args = {"u32"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("research.abort", {args = {"u32", "str:200"}, rate = {burst = 2, refill = 0.3}})
Net.define("research.state", {args = {}, rate = {burst = 4, refill = 1}})
Net.define("research.history", {args = {"ent"}, rate = {burst = 2, refill = 0.3}})
Net.define("research.cancel", {args = {}, rate = {burst = 2, refill = 0.3}})

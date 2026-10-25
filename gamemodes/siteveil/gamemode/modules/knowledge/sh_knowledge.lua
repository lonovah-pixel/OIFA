--[[---------------------------------------------------------------------------
"Знание имеет допуск" (shared): network schema. Dossier content is server
only (config/sv_dossiers.lua).
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Knowledge = SV.Knowledge or {}
local Net = SV.Net

SV.Knowledge.kindNames = {
    open = "Открытые сведения", clearance = "Сведения по допуску", observation = "Подтверждённое наблюдение",
    hypothesis = "Гипотеза", refuted = "Опровергнуто", proposed = "На рассмотрении",
}

Net.define("know.list", {args = {}, rate = {burst = 3, refill = 0.5}})
Net.define("know.open", {args = {"str:24", "ent"}, rate = {burst = 4, refill = 1}})
Net.define("know.submit", {args = {"str:24", "str:16", "u8", "str:600", "ent"}, rate = {burst = 2, refill = 0.05}})
Net.define("know.review", {args = {"u32", "str:16", "str:200", "ent"}, rate = {burst = 4, refill = 0.5}})
Net.define("know.print", {args = {"str:24", "str:32", "ent"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("know.read", {args = {"u32"}, rate = {burst = 3, refill = 1}})

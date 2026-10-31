--[[---------------------------------------------------------------------------
Crafting (shared): benches, recipes, map kind, network schema.
Recipes reference items of other addons only when those are installed.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Crafting = SV.Crafting or {}
local Items = SV.Config.Items

SV.Config.Crafting = {
    benches = {general = "Слесарный верстак", engineering = "Инженерный верстак", medical = "Медицинский стол"},
    scrapChance = 0.3,          -- chance of scrap after a finished labor job
    recipes = {
        {id = "shiv", bench = "general", divisions = {"classd"}, inputs = {scrap = 2}, output = {"shiv", 1}, time = 8},
        {id = "lockpick", bench = "general", divisions = {"classd", "engineering"}, inputs = {scrap = 1, spare_parts = 1}, output = {"lockpick", 1}, time = 10},
        {id = "sensor_kit", bench = "engineering", divisions = {"engineering"}, inputs = {spare_parts = 3}, output = {"sensor_kit", 1}, time = 15},
        {id = "coating", bench = "engineering", divisions = {"engineering"}, inputs = {spare_parts = 1, fuel = 1}, output = {"coating", 1}, time = 12},
        {id = "filter", bench = "engineering", divisions = {"engineering"}, inputs = {spare_parts = 1, scrap = 1}, output = {"filter", 1}, time = 8},
        {id = "medkit", bench = "medical", divisions = {"medical"}, inputs = {bandage = 2, painkillers = 1}, output = {"medkit", 1}, time = 10},
        {id = "tourniquet", bench = "medical", divisions = {"medical"}, inputs = {bandage = 2}, output = {"tourniquet", 1}, time = 6},
    },
    lockpick = {time = 12, maxClearance = 1, success = 0.6, breakOnSuccess = 0.3, openFor = 5, range = 90},
}

if Items.jammer then
    table.insert(SV.Config.Crafting.recipes, {id = "jammer", bench = "general", divisions = {"classd", "engineering"},
        inputs = {scrap = 3, radio = 1}, output = {"jammer", 1}, time = 20})
end

SV.MapCfg.pointKinds.workbench = {name = "Верстак", entity = "sv_workbench", needsProp = "bench"}

SV.Net.define("craft.open", {args = {"ent"}, alive = true, rate = {burst = 3, refill = 0.5}})
SV.Net.define("craft.make", {args = {"ent", "str:24"}, alive = true, rate = {burst = 2, refill = 0.3}})

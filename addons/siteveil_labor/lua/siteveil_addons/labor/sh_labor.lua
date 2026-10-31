--[[---------------------------------------------------------------------------
Class-D labor (shared): job types, map kind, network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Labor = SV.Labor or {}
local Net = SV.Net

SV.Config.Labor = {
    timeLimit = 30,
    minStepTime = 0.3,        -- faster than this per step is not a human
    cooldown = 10,
    failCooldown = 20,
    perShift = 15,            -- completed jobs per character per shift
    jobs = {
        sorting = {name = "Сортировка грузов", divisions = {"classd"}, steps = 6, symbols = {"▲", "■", "●", "◆"},
            hint = "Разложите ящики по контейнерам с тем же знаком — по порядку слева направо.",
            reward = {xp = 6, budget = {division = "administration", amount = 4}}},
        assembly = {name = "Сборка узлов", divisions = {"classd", "engineering"}, steps = 5,
            hint = "Соберите детали в порядке возрастания номеров.",
            reward = {xp = 8, stock = {division = "engineering", item = "spare_parts", count = 1}}},
        cleaning = {name = "Уборка помещения", divisions = {"classd"}, steps = 4, grid = 9,
            hint = "Отметьте все загрязнённые участки.",
            reward = {xp = 5}},
    },
}

SV.MapCfg.pointKinds.workstation = {name = "Рабочее место", entity = "sv_workstation", needsProp = "job"}

Net.define("labor.start", {args = {"ent"}, alive = true, rate = {burst = 3, refill = 0.3}})
Net.define("labor.answer", {args = {"u32", "json:256"}, alive = true, rate = {burst = 3, refill = 0.3}})

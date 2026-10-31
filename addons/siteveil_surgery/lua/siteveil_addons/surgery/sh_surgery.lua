--[[---------------------------------------------------------------------------
Surgery (shared): operations, tools, map kind, network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Surgery = SV.Surgery or {}
local Net = SV.Net

SV.Config.Surgery = {
    tools = {"Скальпель", "Зажим", "Тампон", "Иглодержатель"},
    stepMin = 0.5,             -- seconds: faster is not a surgeon
    stepMax = 8,               -- seconds per step before it counts as a mistake
    complications = 2,         -- mistakes allowed (one more with an assisting medic)
    patientRadius = 90,
    doctorRadius = 140,
    assistRadius = 200,
    xp = 25,
    operations = {
        trauma = {name = "Ушивание ран", steps = 4, items = {tourniquet = 1, bandage = 2},
            needs = "тяжёлое кровотечение или недееспособность без стабилизации"},
        fracture = {name = "Остеосинтез", steps = 5, items = {splint = 1, painkillers = 1}, needs = "перелом"},
        infection = {name = "Удаление очага поветрия", steps = 6, items = {antiviral = 1, bandage = 2},
            needs = "вторая стадия заражения SCP-049"},
    },
}

SV.MapCfg.pointKinds.medbed = {name = "Операционный стол", entity = "sv_medbed"}

Net.define("surgery.open", {args = {"ent"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("surgery.start", {args = {"ent", "ent", "str:16"}, alive = true, rate = {burst = 2, refill = 0.2}})
Net.define("surgery.step", {args = {"u32", "u8"}, alive = true, rate = {burst = 6, refill = 2}})
Net.define("surgery.consent", {args = {"bool"}, alive = true, rate = {burst = 3, refill = 0.5}})

--[[---------------------------------------------------------------------------
"Директор напряжения" (SERVER ONLY): event catalogue. See BALANCE.md.

The director starts an event only when
  - it is enabled (admin panel / sv_director 0|1) and the event is enabled,
  - enough players are online (minOnline) and the facility is calm enough
    (tension below C.Director.tensionMax, event condition true),
  - somebody who can solve it is on shift (`solvers`: divisions or role
    flags with a minimum count) - an event never starts without a solution,
  - its own cooldown and the global cooldown passed, fewer than maxActive
    events run, no other event runs in the same sector.
If every solver leaves during the event it is withdrawn without
consequences.

Event kinds (implemented in modules/director/sv_director.lua):
  fault        damages an infrastructure node; solved by its repair
  containment  lowers SCP containment; solved by an inspection/procedure
  callout      a place to attend: a solver must stay near it for `hold` s
  supply       unscheduled delivery confirmed at a logistics point (callout)

Fields: id, name, kind, weight, minOnline, cooldown, duration, warn (seconds
of warning before the effect), warnText, text (task shown to solvers),
solvers = {{division = id | flag = flag, min = n}}, condition(ctx),
reward = {xp, budget, division}, fail = {...} (consequence), params.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Director = {
    enabled = true,
    tick = 1,
    decisionInterval = 60,     -- how often the director considers a new event
    firstDelay = 300,          -- quiet start of a shift / server
    globalCooldown = 240,      -- between two event starts
    maxActive = 2,
    minOnline = 4,
    tensionMax = 60,           -- no new events above this tension
    tensionDecay = 1,          -- per 10 s
    tension = {                -- bus event -> tension added
        ["scp.breached"] = 35, ["scp.incident"] = 15, ["medical.down"] = 4, ["facility.alertChanged"] = 8,
        ["experiment.emergency"] = 12, ["node.failed"] = 6, ["security.escape"] = 8, ["knowledge.leak"] = 5,
    },
    calloutRadius = 160,
    xpSource = "task",
}

C.DirectorEvents = {
    {
        id = "power_fault", name = "Перегрев силового узла", kind = "fault", weight = 10, minOnline = 4, cooldown = 1200,
        duration = 480, warn = 40, warnText = "Диагностика: растёт температура силового оборудования.",
        text = "Устраните неисправность силового узла до отключения сектора.",
        solvers = {{flag = "engineer", min = 1}},
        params = {subsystems = {"generator", "power"}, damage = 35, fault = "overheat"},
        reward = {xp = 30, budget = 30, division = "engineering"},
        fail = {damage = 30, fault = "short"},
    },
    {
        id = "vent_fault", name = "Засорение вентиляции", kind = "fault", weight = 8, minOnline = 4, cooldown = 1200,
        duration = 420, warn = 30, warnText = "Датчики вентиляции фиксируют падение тяги.",
        text = "Замените фильтр и отремонтируйте вентиляционный узел.",
        solvers = {{flag = "engineer", min = 1}},
        params = {subsystems = {"ventilation"}, damage = 40, fault = "contamination"},
        reward = {xp = 30, budget = 25, division = "engineering"},
        fail = {damage = 25},
    },
    {
        id = "comms_fault", name = "Помехи в линиях связи", kind = "fault", weight = 7, minOnline = 6, cooldown = 1500,
        duration = 420, warn = 20, warnText = "Узел связи сообщает о скачках напряжения.",
        text = "Восстановите узел связи: радиосвязь в секторе искажается.",
        solvers = {{flag = "engineer", min = 1}},
        params = {subsystems = {"comms"}, damage = 45, fault = "short"},
        reward = {xp = 25, budget = 20, division = "engineering"},
        fail = {damage = 20},
    },
    {
        id = "camera_fault", name = "Отказ видеонаблюдения", kind = "fault", weight = 6, minOnline = 6, cooldown = 1500,
        duration = 420, warn = 20, warnText = "Пропадает сигнал части камер наблюдения.",
        text = "Восстановите узел видеонаблюдения: камеры у камер содержания не работают.",
        solvers = {{flag = "engineer", min = 1}},
        params = {subsystems = {"surveillance"}, damage = 50, fault = "wear"},
        reward = {xp = 25, budget = 20, division = "engineering"},
        fail = {damage = 20},
    },
    {
        id = "containment_drift", name = "Отклонение условий содержания", kind = "containment", weight = 9, minOnline = 4, cooldown = 900,
        duration = 420, warn = 0,
        text = "Проведите осмотр или процедуру у панели содержания объекта.",
        solvers = {{flag = "research", min = 1}, {flag = "recontain", min = 1}, {flag = "canDetain", min = 1}},
        condition = function(ctx) return not ctx.anyBreached end,
        params = {integrity = -12, recover = 6, failIntegrity = -10},
        reward = {xp = 25, budget = 20, division = "science"},
    },
    {
        id = "injured_worker", name = "Пострадавший сотрудник", kind = "callout", weight = 8, minOnline = 4, cooldown = 900,
        duration = 300, warn = 0,
        text = "Сообщение о травме на объекте: окажите помощь на месте.",
        solvers = {{flag = "medic", min = 1}},
        params = {points = {"checkpoint"}, hold = 15},
        reward = {xp = 25, budget = 20, division = "medical"},
        fail = {budget = -15, budgetDivision = "medical", text = "Пострадавший доставлен с опозданием: жалоба в администрацию."},
    },
    {
        id = "suspicious_package", name = "Подозрительный предмет", kind = "callout", weight = 7, minOnline = 6, cooldown = 1200,
        duration = 300, warn = 0,
        text = "Обнаружен бесхозный предмет: осмотрите и оцепите место.",
        solvers = {{flag = "canDetain", min = 1}},
        params = {points = {"checkpoint", "logistics"}, hold = 20},
        reward = {xp = 25, budget = 20, division = "security"},
        fail = {alert = 120, text = "Предмет не осмотрен вовремя: в секторе объявлена тревога."},
    },
    {
        id = "anomalous_reading", name = "Аномальные показания датчиков", kind = "callout", weight = 6, minOnline = 4, cooldown = 1200,
        duration = 360, warn = 0,
        text = "Датчики зафиксировали всплеск: снимите показания на месте.",
        solvers = {{flag = "research", min = 1}},
        params = {points = {"checkpoint", "terminal"}, hold = 20},
        reward = {xp = 30, budget = 25, division = "science"},
    },
    {
        id = "supply_drop", name = "Внеплановая поставка", kind = "supply", weight = 5, minOnline = 4, cooldown = 1800,
        duration = 300, warn = 0,
        text = "Прибыла внеплановая поставка: примите её у точки поставок.",
        solvers = {{flag = "logistics", min = 1}, {flag = "approveSupply", min = 1}},
        params = {points = {"logistics"}, hold = 10, stock = {{"medical", "bandage", 4}, {"engineering", "spare_parts", 3}, {"science", "sample_kit", 2}}},
        reward = {xp = 15},
    },
    {
        id = "dblock_unrest", name = "Волнения в блоке D", kind = "callout", weight = 6, minOnline = 8, cooldown = 1500,
        duration = 300, warn = 30, warnText = "В блоке D нарастает напряжение.",
        text = "Восстановите порядок: патруль на посту блока D.",
        solvers = {{flag = "canDetain", min = 1}},
        condition = function(ctx) return (ctx.divisions.classd or 0) >= 2 end,
        params = {points = {"checkpoint"}, preferDivision = "classd", hold = 25},
        reward = {xp = 30, budget = 20, division = "security"},
        fail = {alert = 180, text = "Беспорядки в блоке D: объявлена локальная тревога."},
    },
    {
        id = "o5_inspection", name = "Проверка представителя Совета", kind = "callout", weight = 4, minOnline = 10, cooldown = 2400,
        duration = 360, warn = 60, warnText = "Ожидается проверка представителя Совета О5.",
        text = "Встретьте проверяющего и представьте отчётность на месте.",
        solvers = {{division = "administration", min = 1}},
        params = {points = {"terminal", "checkpoint"}, hold = 30},
        reward = {xp = 30, budget = 50, division = "administration"},
        fail = {budget = -25, budgetDivision = "administration", text = "Проверка завершилась замечаниями."},
    },
    {
        id = "medical_shortage", name = "Дефицит медикаментов", kind = "supply", weight = 4, minOnline = 8, cooldown = 2400,
        duration = 360, warn = 0,
        text = "Медблоку срочно нужны перевязочные материалы: примите партию у точки поставок.",
        solvers = {{flag = "medic", min = 1}},
        condition = function() return SV.Supply.stock("medical", "bandage") < 4 end,
        params = {points = {"logistics"}, hold = 10, stock = {{"medical", "bandage", 6}, {"medical", "tourniquet", 2}}},
        reward = {xp = 20},
    },
}

--[[---------------------------------------------------------------------------
"Живой комплекс": infrastructure and facility states (shared configuration).
See BALANCE.md for the reasoning behind the numbers.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Facility = {
    tick = 2,                       -- infrastructure simulation step, seconds
    sectorCheckInterval = 1,        -- how often player sectors are recomputed

    subsystems = {
        power = {name = "Питание", node = "Распределительный щит"},
        comms = {name = "Связь", node = "Ретранслятор связи"},
        ventilation = {name = "Вентиляция", node = "Вентиляционный узел"},
        surveillance = {name = "Наблюдение", node = "Узел видеонаблюдения"},
        security = {name = "Безопасность", node = "Контроллер дверей"},
        generator = {name = "Главный генератор", node = "Главный генератор", global = true},
    },

    -- Health thresholds (0..100) used for states and symptoms.
    healthOk = 70,
    healthDegraded = 40,
    healthDamaged = 15,

    wearPerMinute = 0.6,            -- natural wear of every node
    faultChancePerMinute = 0.02,    -- base chance of a spontaneous fault when health < 50 (scaled by damage)

    generatorCapacity = 100,        -- power units at full generator health
    defaultSectorDemand = 20,
    backupFuelMax = 600,            -- seconds of backup operation per sector
    backupStartFuel = 300,
    backupLevel = 0.6,              -- power level provided by the backup generator

    faults = {
        wear = {name = "Износ", rate = 0, severity = 1, hint = "Плановая замена деталей"},
        overheat = {name = "Перегрев", rate = 1.5, severity = 2, hint = "Охлаждение и замена предохранителей"},
        short = {name = "Короткое замыкание", rate = 3, severity = 2, hint = "Изоляция и замена проводки"},
        tamper = {name = "Следы вмешательства", rate = 2, severity = 3, hint = "Восстановление схемы после вскрытия"},
        contamination = {name = "Загрязнение", rate = 1, severity = 2, hint = "Замена фильтрующего картриджа", item = "filter"},
        corrosion = {name = "Коррозия", rate = 1.2, severity = 2, hint = "Зачистка и антикоррозийная обработка", item = "coating"},
    },

    repairBase = 6,                 -- seconds
    repairPerSeverity = 4,
    partsPerSeverity = 1,           -- spare parts needed per severity level
    diagnoseTime = 3,
    bypassTime = 5,
    bypassHealth = 60,
    bypassDuration = 600,           -- after this a bypassed node fails hard
    refuelTime = 5,
    refuelAmount = 300,

    sabotage = {
        time = 10,
        damage = 55,
        cooldown = 300,             -- per player
        windowLimit = 2,            -- per player within window
        window = 900,
        generatorPrep = true,       -- the main generator needs a preparation step first
        prepWindow = {120, 600},    -- the second step must follow within this window (seconds)
        generatorFloor = 30,        -- one player cannot take the generator below this in a window
    },

    states = {
        normal = {name = "ШТАТНЫЙ РЕЖИМ"},
        breach = {name = "НАРУШЕНИЕ СОДЕРЖАНИЯ", sound = "alarmBreach"},
        evacuation = {name = "ЭВАКУАЦИЯ", sound = "alarmEvac"},
        recovery = {name = "ВОССТАНОВЛЕНИЕ"},
    },
    alertDuration = 300,
    lockdownMax = 600,
    lockdownExtendMax = 1,
    stateCooldown = 60,             -- minimal time between declared global transitions
    recoveryMinTime = 180,
    recoveryMaxTime = 600,
    recoveryInfraTarget = 60,       -- average node health needed to finish recovery early
    breachPenalty = {security = 60, science = 30},
    recoveryBonus = {engineering = 50, security = 40, medical = 30},
    evacuationXP = 30,
    contaminationDamage = 2,        -- every 4 s without a mask in a contaminated sector
}

--[[---------------------------------------------------------------------------
Research protocols (SERVER ONLY: outcome tables and the facts they reveal
must not reach clients before an experiment ends).

Each protocol:
  subject        SCP id ("scp173") or inventory item id ("ao_echo", "sample:scp173")
  zone           "cell" (the subject SCP's cell) or "lab" (near the terminal)
  danger         1..4; approval required from 3
  clearance      minimal card clearance of the lead researcher
  participants   {category, min, label}; categories: classd, security, science,
                 medical, engineering, staff (anyone non-D), any
  equipment      required = {item = n}; consumed = {item = n}; optional = {item = qualityBonus}
  environment    {id, text, check(ctx) -> ok, riskIfNot}
  safety         {id, name, check(ctx) -> ok, risk (reduction when met)}
  steps          {id, name, by ("lead" | "any" | "classd"), time, critical}
  outcomes       {id, name, kind ("data" | "partial" | "none" | "incident" | "discovery"),
                  weight, fact, unlock, reward = {xp, budget}, text, effect(ctx)}
  cooldown       seconds between runs (per protocol, facility-wide)
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

local function facility() return SV.Facility end
local function scpState(id) return SV.SCP.get(id) end

local function cellPowered(id)
    return facility().devicePowered(SV.SCP.cellSector(id), "containment")
end

local function normalState()
    local st = facility().stateId()
    return st == "normal" or st == "recovery"
end

local function injureFirst(list, cause)
    local p = list and list[1]
    if IsValid(p) and p:Alive() then SV.Medical.incapacitate(p, cause) return p end
end

local function hurt(list, amount)
    for _, p in ipairs(list or {}) do
        if IsValid(p) and p:Alive() then
            local d = DamageInfo()
            d:SetDamage(amount)
            d:SetDamageType(DMG_GENERIC)
            d:SetAttacker(game.GetWorld())
            p:TakeDamageInfo(d)
        end
    end
end

local commonSafety = {
    guard = {id = "guard", name = "Охрана в зоне эксперимента", risk = 0.15, check = function(ctx) return #ctx.byCategory.security > 0 end},
    medic = {id = "medic", name = "Медик на месте", risk = 0.1, check = function(ctx) return #ctx.byCategory.medical > 0 end},
    plan = {id = "plan", name = "Аварийный план согласован", risk = 0.1, check = function(ctx) return ctx.approved == true end},
    hazmat = {id = "hazmat", name = "Защитные костюмы у участников", risk = 0.15, check = function(ctx)
        for _, p in ipairs(ctx.participants) do
            if not SV.Inv.isWearing(p, "hazmat") then return false end
        end
        return #ctx.participants > 0
    end},
}

C.Protocols = {
    {
        id = "p173_blink", name = "Наблюдение за SCP-173 при чередовании моргания", subject = "scp173", zone = "cell",
        danger = 3, clearance = 2, cooldown = 900,
        desc = "Испытуемый класса D находится в камере, двое наблюдателей чередуют моргание по команде. Фиксируется реакция объекта на окна без наблюдения.",
        participants = {{category = "classd", min = 1, label = "Испытуемый класса D"}, {category = "staff", min = 2, label = "Наблюдатели"}},
        equipment = {required = {hs_camera = 1}, optional = {sensor_kit = 0.15}},
        environment = {
            {id = "power", text = "Питание замков камеры", riskIfNot = 0.35, check = function() return cellPowered("scp173") end},
            {id = "state", text = "Комплекс в штатном режиме", riskIfNot = 0.3, check = normalState},
            {id = "stable", text = "Объект стабилен", riskIfNot = 0.25, check = function() local st = scpState("scp173") return st and (st.stage == "stable" or st.stage == "signs") end},
        },
        safety = {commonSafety.guard, commonSafety.medic, commonSafety.plan},
        steps = {
            {id = "prep", name = "Подготовка камеры и записи", by = "lead", time = 8},
            {id = "enter", name = "Ввод испытуемого", by = "lead", time = 5},
            {id = "expose", name = "Чередование моргания (воздействие)", by = "lead", time = 20, critical = true},
            {id = "record", name = "Фиксация результатов", by = "lead", time = 6},
        },
        outcomes = {
            {id = "data", name = "Получены новые данные", kind = "data", weight = 40, fact = "blink", reward = {xp = 45, budget = 35},
                text = "Объект начинает движение сразу после того, как последний наблюдатель моргнул."},
            {id = "partial", name = "Частичный результат", kind = "partial", weight = 25, fact = "sound", reward = {xp = 25, budget = 15},
                text = "Перемещение подтверждено по звуку, точный момент не зафиксирован."},
            {id = "none", name = "Результат не получен", kind = "none", weight = 15, reward = {xp = 10},
                text = "Объект не проявил активности."},
            {id = "injury", name = "Инцидент: испытуемый травмирован", kind = "incident", weight = 12, reward = {xp = 10},
                text = "Окно без наблюдения оказалось длиннее допустимого.",
                effect = function(ctx) injureFirst(ctx.byCategory.classd, "SCP-173") end},
            {id = "containment", name = "Инцидент: нарушение условий", kind = "incident", weight = 4, reward = {xp = 5},
                text = "Объект повредил элементы камеры.",
                effect = function() SV.SCP.adjustIntegrity("scp173", -30, "experiment") end},
            {id = "discovery", name = "Неожиданное открытие", kind = "discovery", weight = 4, fact = "cameras", unlock = "watch_protocol", reward = {xp = 60, budget = 60},
                text = "Разработан усиленный протокол видеонаблюдения: отказ камер меньше влияет на содержание."},
        },
    },
    {
        id = "p173_secretion", name = "Анализ выделений SCP-173", subject = "sample:scp173", zone = "lab",
        danger = 1, clearance = 2, cooldown = 600,
        desc = "Лабораторный анализ образца, полученного при уборке камеры SCP-173.",
        participants = {{category = "science", min = 1, label = "Лаборант (можно руководителя)"}},
        equipment = {required = {}, consumed = {sample = 1}, optional = {sensor_kit = 0.25}},
        environment = {
            {id = "power", text = "Питание лаборатории", riskIfNot = 0.2, check = function(ctx) return facility().power(ctx.sector) >= 0.6 end},
            {id = "vent", text = "Вентиляция лаборатории", riskIfNot = 0.2, check = function(ctx) return facility().subsystemOk(ctx.sector, "ventilation") end},
        },
        safety = {commonSafety.hazmat},
        steps = {
            {id = "prep", name = "Подготовка проб", by = "lead", time = 8},
            {id = "analyse", name = "Спектральный анализ", by = "any", time = 12},
            {id = "record", name = "Отчёт", by = "lead", time = 5},
        },
        outcomes = {
            {id = "data", name = "Состав определён", kind = "data", weight = 50, fact = "secretion", reward = {xp = 30, budget = 25},
                text = "Образец содержит органические вещества неустановленного происхождения."},
            {id = "partial", name = "Частичный анализ", kind = "partial", weight = 30, reward = {xp = 15},
                text = "Определены отдельные компоненты."},
            {id = "none", name = "Образец испорчен", kind = "none", weight = 15, reward = {xp = 5}, text = "Проба деградировала."},
            {id = "fumes", name = "Инцидент: выделение паров", kind = "incident", weight = 5, reward = {xp = 5},
                text = "Пары вызвали раздражение дыхательных путей.",
                effect = function(ctx) hurt(ctx.participants, 15) end},
        },
    },
    {
        id = "p173_dark", name = "Поведение SCP-173 при сниженном освещении", subject = "scp173", zone = "cell",
        danger = 4, clearance = 3, cooldown = 1800,
        desc = "Инженер снижает мощность сектора камеры. Наблюдатели с фонарями фиксируют, как темнота влияет на объект.",
        participants = {{category = "classd", min = 1, label = "Испытуемый класса D"}, {category = "staff", min = 2, label = "Наблюдатели с фонарями"},
            {category = "engineering", min = 1, label = "Инженер (управление питанием)"}},
        equipment = {required = {hs_camera = 1}, optional = {sensor_kit = 0.1, em_shield = 0.1}},
        environment = {
            {id = "lowpower", text = "Питание сектора камеры снижено (ниже 60%)", riskIfNot = 0, check = function()
                return facility().power(SV.SCP.cellSector("scp173")) < 0.6 end, required = true},
            {id = "state", text = "Комплекс в штатном режиме", riskIfNot = 0.3, check = normalState},
        },
        safety = {commonSafety.guard, commonSafety.medic, commonSafety.plan},
        steps = {
            {id = "prep", name = "Подготовка фонарей и записи", by = "lead", time = 8},
            {id = "dim", name = "Снижение освещения", by = "any", time = 6},
            {id = "expose", name = "Наблюдение в темноте", by = "lead", time = 20, critical = true},
            {id = "record", name = "Восстановление питания и отчёт", by = "lead", time = 6},
        },
        outcomes = {
            {id = "data", name = "Подтверждена зависимость от освещения", kind = "data", weight = 35, fact = "darkness", reward = {xp = 60, budget = 50},
                text = "Без освещения наблюдение эффективно только вблизи или с фонарём."},
            {id = "partial", name = "Частичный результат", kind = "partial", weight = 20, reward = {xp = 30}, text = "Данные неполные."},
            {id = "none", name = "Результат не получен", kind = "none", weight = 10, reward = {xp = 10}, text = "Объект не двигался."},
            {id = "injury", name = "Инцидент: испытуемый погиб", kind = "incident", weight = 22, reward = {xp = 10},
                text = "Объект воспользовался темнотой.",
                effect = function(ctx)
                    local p = ctx.byCategory.classd[1]
                    if IsValid(p) and p:Alive() then SV.Medical.markLethal(p) p:TakeDamage(500, game.GetWorld()) end
                end},
            {id = "containment", name = "Инцидент: нарушение условий", kind = "incident", weight = 13, reward = {xp = 5},
                text = "Замки камеры дали сбой в темноте.",
                effect = function() SV.SCP.adjustIntegrity("scp173", -45, "experiment") end},
        },
    },
    {
        id = "p049_interview", name = "Собеседование с SCP-049", subject = "scp049", zone = "cell",
        danger = 2, clearance = 2, cooldown = 900,
        desc = "Научный сотрудник беседует с объектом о медицине под охраной. Снижает беспокойство объекта.",
        participants = {{category = "science", min = 1, label = "Интервьюер"}, {category = "security", min = 1, label = "Охрана"}},
        equipment = {required = {notebook = 1}, optional = {sensor_kit = 0.1}},
        environment = {
            {id = "power", text = "Питание замка камеры", riskIfNot = 0.3, check = function() return cellPowered("scp049") end},
            {id = "state", text = "Комплекс в штатном режиме", riskIfNot = 0.2, check = normalState},
        },
        safety = {commonSafety.hazmat, commonSafety.guard},
        steps = {
            {id = "enter", name = "Вход в камеру", by = "lead", time = 5},
            {id = "talk", name = "Беседа", by = "lead", time = 30, critical = true},
            {id = "record", name = "Протокол беседы", by = "lead", time = 5},
        },
        outcomes = {
            {id = "data", name = "Объект успокоен, получены сведения", kind = "data", weight = 45, fact = "interview", reward = {xp = 40, budget = 25},
                text = "Объект охотно обсуждал «поветрие». Беспокойство снижено.",
                effect = function() local st = scpState("scp049") if st then st.data.lastInterview = CurTime() SV.SCP.adjustIntegrity("scp049", 15, "interview") end end},
            {id = "partial", name = "Беседа без новых сведений", kind = "partial", weight = 30, fact = "hazmat", reward = {xp = 20},
                text = "Объект отвечал уклончиво.",
                effect = function() local st = scpState("scp049") if st then st.data.lastInterview = CurTime() SV.SCP.adjustIntegrity("scp049", 8, "interview") end end},
            {id = "none", name = "Объект отказался говорить", kind = "none", weight = 15, reward = {xp = 5}, text = "Объект молчал."},
            {id = "infection", name = "Инцидент: контакт с объектом", kind = "incident", weight = 10, reward = {xp = 5},
                text = "Объект коснулся интервьюера.",
                effect = function(ctx)
                    local p = ctx.lead
                    if IsValid(p) and not SV.Inv.isWearing(p, "hazmat") then SV.Medical.infect(p, "scp049") end
                end},
        },
    },
    {
        id = "p049_tissue", name = "Анализ тканей экземпляра SCP-049-2", subject = "sample:scp0492", zone = "lab",
        danger = 3, clearance = 3, cooldown = 1200,
        desc = "Исследование образца тканей «излечённого» экземпляра. Возможна разработка антивирусной схемы.",
        participants = {{category = "science", min = 1, label = "Исследователь"}, {category = "medical", min = 1, label = "Врач"}},
        equipment = {required = {sensor_kit = 1}, consumed = {sample = 1}, optional = {em_shield = 0.1}},
        environment = {
            {id = "vent", text = "Вентиляция лаборатории", riskIfNot = 0.3, check = function(ctx) return facility().subsystemOk(ctx.sector, "ventilation") end},
        },
        safety = {commonSafety.hazmat, commonSafety.plan},
        steps = {
            {id = "prep", name = "Подготовка изолятора", by = "lead", time = 8},
            {id = "analyse", name = "Анализ тканей", by = "any", time = 20, critical = true},
            {id = "record", name = "Отчёт", by = "lead", time = 5},
        },
        outcomes = {
            {id = "data", name = "Описана стадия заражения", kind = "data", weight = 40, fact = "cure_window", reward = {xp = 50, budget = 40},
                text = "На ранней стадии симптомы поддаются антивирусу."},
            {id = "partial", name = "Частичный результат", kind = "partial", weight = 25, fact = "instances", reward = {xp = 25}, text = "Экземпляры нестабильны."},
            {id = "none", name = "Образец непригоден", kind = "none", weight = 15, reward = {xp = 5}, text = "Ткани разложились."},
            {id = "exposure", name = "Инцидент: заражение участника", kind = "incident", weight = 12, reward = {xp = 5},
                text = "Нарушена герметичность изолятора.",
                effect = function(ctx)
                    for _, p in ipairs(ctx.participants) do
                        if not SV.Inv.isWearing(p, "hazmat") then SV.Medical.infect(p, "tissue") break end
                    end
                end},
            {id = "discovery", name = "Разработана антивирусная схема", kind = "discovery", weight = 8, unlock = "antiviral_formula", reward = {xp = 70, budget = 60},
                text = "Медицинская служба получает дополнительную партию антивируса.",
                effect = function() if SV.Supply then SV.Supply.addStock("medical", "antiviral", 4) end end},
        },
    },
    {
        id = "p096_acoustic", name = "Акустический мониторинг SCP-096", subject = "scp096", zone = "cell",
        danger = 3, clearance = 3, cooldown = 1200,
        desc = "Запись звуков объекта без визуального контакта. Камеры должны быть замаскированы, вентиляция исправна.",
        participants = {{category = "science", min = 1, label = "Акустик"}, {category = "security", min = 1, label = "Охрана"}},
        equipment = {required = {sensor_kit = 1}, optional = {hs_camera = 0.05}},
        environment = {
            {id = "vent", text = "Шумоизоляция (вентиляция сектора)", riskIfNot = 0.35, check = function()
                return facility().subsystemOk(SV.SCP.cellSector("scp096"), "ventilation") end},
            {id = "masked", text = "Камеры в камере замаскированы", riskIfNot = 0.3, check = function()
                local st = scpState("scp096") return st and st.data.maskedUntil and CurTime() < st.data.maskedUntil end},
            {id = "calm", text = "Объект спокоен", riskIfNot = 0.5, check = function() local st = scpState("scp096") return st and (st.data.mode or "calm") == "calm" end},
        },
        safety = {commonSafety.guard, commonSafety.plan},
        steps = {
            {id = "prep", name = "Установка микрофонов (не смотреть на объект)", by = "lead", time = 10},
            {id = "record", name = "Запись", by = "lead", time = 25, critical = true},
            {id = "report", name = "Расшифровка", by = "lead", time = 5},
        },
        outcomes = {
            {id = "data", name = "Записан цикл активности", kind = "data", weight = 40, fact = "noise", reward = {xp = 50, budget = 35},
                text = "Шум вентиляции заметно усиливает беспокойство объекта."},
            {id = "partial", name = "Частичная запись", kind = "partial", weight = 25, fact = "exhaustion", reward = {xp = 25}, text = "Зафиксирован период покоя после возбуждения."},
            {id = "none", name = "Помехи на записи", kind = "none", weight = 20, reward = {xp = 5}, text = "Запись непригодна."},
            {id = "trigger", name = "Инцидент: визуальный контакт", kind = "incident", weight = 15, reward = {xp = 5},
                text = "Участник увидел лицо объекта.",
                effect = function(ctx)
                    local p = ctx.participants[1]
                    if SV.SCP.S096 and IsValid(p) then SV.SCP.S096.addTarget(p, "experiment") end
                end},
        },
    },
    {
        id = "p106_materials", name = "Коррозионная стойкость материалов", subject = "scp106", zone = "cell",
        danger = 4, clearance = 3, cooldown = 1800,
        desc = "Образцы покрытий размещаются в камере SCP-106. Инженер и исследователь фиксируют скорость разрушения.",
        participants = {{category = "science", min = 1, label = "Исследователь"}, {category = "engineering", min = 1, label = "Инженер"},
            {category = "security", min = 1, label = "Охрана"}},
        equipment = {required = {coating = 1}, consumed = {coating = 1}, optional = {sensor_kit = 0.15, em_shield = 0.15}},
        environment = {
            {id = "power", text = "Электромагнитная стабилизация камеры", riskIfNot = 0.5, check = function() return cellPowered("scp106") end},
            {id = "state", text = "Комплекс в штатном режиме", riskIfNot = 0.3, check = normalState},
        },
        safety = {commonSafety.guard, commonSafety.medic, commonSafety.plan},
        steps = {
            {id = "prep", name = "Подготовка образцов", by = "lead", time = 8},
            {id = "place", name = "Размещение образцов в камере", by = "any", time = 10, critical = true},
            {id = "observe", name = "Наблюдение", by = "lead", time = 20, critical = true},
            {id = "record", name = "Отчёт", by = "lead", time = 5},
        },
        outcomes = {
            {id = "data", name = "Определены стойкие материалы", kind = "data", weight = 35, fact = "materials", reward = {xp = 60, budget = 50},
                text = "Свинцовые и керамические покрытия держатся дольше всего."},
            {id = "partial", name = "Частичный результат", kind = "partial", weight = 25, fact = "corrosion", reward = {xp = 30}, text = "Коррозия зафиксирована."},
            {id = "none", name = "Образцы уничтожены", kind = "none", weight = 10, reward = {xp = 10}, text = "Образцы растворились."},
            {id = "abduction", name = "Инцидент: участник уведён объектом", kind = "incident", weight = 15, reward = {xp = 5},
                text = "Объект появился из стены камеры.",
                effect = function(ctx)
                    local p = ctx.participants[#ctx.participants]
                    if SV.SCP.S106 and IsValid(p) then SV.SCP.S106.sendToPocket(p, nil) end
                end},
            {id = "containment", name = "Инцидент: повреждение камеры", kind = "incident", weight = 7, reward = {xp = 5},
                text = "Покрытие камеры разрушено.",
                effect = function() SV.SCP.adjustIntegrity("scp106", -35, "experiment") end},
            {id = "discovery", name = "Новое покрытие камеры", kind = "discovery", weight = 8, unlock = "coating_v2", reward = {xp = 80, budget = 70},
                text = "Обработка покрытием теперь восстанавливает содержание SCP-106 вдвое эффективнее."},
        },
    },
    {
        id = "pao_echo", name = "Калибровка AO-3127 «Эхо»", subject = "ao_echo", zone = "lab",
        danger = 1, clearance = 1, cooldown = 480,
        desc = "Измерение задержки предсказанных звуков аномального терменвокса. Подходит для небольших смен.",
        participants = {{category = "any", min = 1, label = "Участник"}},
        equipment = {required = {}, optional = {sensor_kit = 0.3, hs_camera = 0.1}},
        environment = {
            {id = "power", text = "Питание лаборатории", riskIfNot = 0.1, check = function(ctx) return facility().power(ctx.sector) >= 0.5 end},
        },
        safety = {},
        steps = {
            {id = "setup", name = "Установка объекта", by = "lead", time = 6},
            {id = "measure", name = "Серия звуковых проб", by = "any", time = 15},
            {id = "record", name = "Запись результатов", by = "lead", time = 5},
        },
        outcomes = {
            {id = "data", name = "Задержка измерена", kind = "data", weight = 50, fact = "delay", reward = {xp = 25, budget = 15},
                text = "Задержка зависит от расстояния до источника."},
            {id = "partial", name = "Объект предсказал тишину", kind = "partial", weight = 25, fact = "silence", reward = {xp = 20},
                text = "Объект замолк перед полной тишиной в лаборатории."},
            {id = "none", name = "Объект не отвечает", kind = "none", weight = 20, reward = {xp = 5}, text = "Звуков не было."},
            {id = "shock", name = "Инцидент: акустический удар", kind = "incident", weight = 5, reward = {xp = 5},
                text = "Объект воспроизвёл громкий звук.",
                effect = function(ctx) hurt(ctx.participants, 10) end},
        },
    },
    {
        id = "pao_liquid", name = "Реакция AO-5510 с органическими тканями", subject = "ao_liquid", zone = "lab",
        danger = 2, clearance = 2, cooldown = 720,
        desc = "Контролируемый контакт жидкости с кожей испытуемого класса D в защитной камере.",
        participants = {{category = "classd", min = 1, label = "Испытуемый класса D"}, {category = "science", min = 1, label = "Исследователь"}},
        equipment = {required = {}, optional = {sensor_kit = 0.2}},
        environment = {
            {id = "vent", text = "Вентиляция лаборатории", riskIfNot = 0.2, check = function(ctx) return facility().subsystemOk(ctx.sector, "ventilation") end},
        },
        safety = {commonSafety.medic, commonSafety.plan},
        steps = {
            {id = "prep", name = "Подготовка", by = "lead", time = 6},
            {id = "contact", name = "Контакт", by = "classd", time = 10, critical = true},
            {id = "record", name = "Наблюдение и запись", by = "lead", time = 10},
        },
        outcomes = {
            {id = "data", name = "Описана реакция", kind = "data", weight = 45, fact = "organic", reward = {xp = 35, budget = 25},
                text = "Плёнка на коже вызывает временное онемение."},
            {id = "partial", name = "Частичный результат", kind = "partial", weight = 25, fact = "heat", reward = {xp = 20},
                text = "Нагрев образца прекратил реакцию."},
            {id = "none", name = "Реакции нет", kind = "none", weight = 20, reward = {xp = 5}, text = "Жидкость не проявила свойств."},
            {id = "numb", name = "Инцидент: онемение конечности", kind = "incident", weight = 10, reward = {xp = 5},
                text = "Испытуемый потерял подвижность.",
                effect = function(ctx)
                    local p = ctx.byCategory.classd[1]
                    if IsValid(p) and p:Alive() then
                        local s = SV.Medical.get(p)
                        s.fracture = true
                        SV.Move.set(p, "fracture", {speed = C.Medical.fractureSpeed})
                        SV.Medical.publish(p)
                    end
                end},
        },
    },
}

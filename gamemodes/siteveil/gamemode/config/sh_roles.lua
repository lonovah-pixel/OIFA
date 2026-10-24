--[[---------------------------------------------------------------------------
Divisions, ranks and roles (shared).

This file is the single source of truth for roles. Every role below becomes
exactly one DarkRP job (modules/darkrp_bridge/sh_jobs.lua); DarkRP's default
jobs are disabled. Never create DarkRP jobs anywhere else.

Role fields:
  division       division id
  name           display name (Russian)
  description    one paragraph
  duties         list of routine duties (штатный режим)
  alarm          list of actions during alerts and breaches
  clearance      access clearance 0..5 granted by the role
  tags           access tags granted by the role
  minRank        minimal rank in the division
  whitelist      true: needs a role whitelist entry (division whitelist also counts)
  quota          {base, per, max, minOnline}: slots = min(max, base + floor(online / per))
  hidden         not selectable in the role menu (assigned by game systems)
  reinforcement  "mtf" / "chaos": only deployable through reinforcement waves
  scp            id of the SCP definition for playable SCP roles
  weapons        role tools (SWEPs) given on every spawn, never droppable
  kit            inventory items issued once per life (no duplicates)
  flags          authority flags, see ARCHITECTURE.md "Полномочия"
  models         player models; the first valid one is used as fallback
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Divisions = {
    {
        id = "classd", name = "Класс D", short = "D", color = Color(214, 120, 40),
        ranks = {"Новоприбывший", "Работник", "Опытный работник", "Бригадир", "Доверенный"},
        rankXP = {0, 120, 350, 700, 1200}, rankHours = {0, 1, 3, 6, 10},
        approvalFromRank = 5, defaultRole = "classd_worker",
        selectable = true, whitelist = false, spawn = "classd",
    },
    {
        id = "science", name = "Научный отдел", short = "НО", color = Color(90, 170, 230),
        ranks = {"Лаборант", "Младший исследователь", "Исследователь", "Старший исследователь", "Ведущий исследователь", "Руководитель группы"},
        rankXP = {0, 150, 400, 800, 1400, 2200}, rankHours = {0, 1, 3, 6, 10, 15},
        approvalFromRank = 4, defaultRole = "sci_junior",
        selectable = true, whitelist = false, spawn = "science",
    },
    {
        id = "security", name = "Служба безопасности", short = "СБ", color = Color(70, 110, 200),
        ranks = {"Рядовой", "Ефрейтор", "Сержант", "Старший сержант", "Лейтенант", "Капитан"},
        rankXP = {0, 150, 400, 800, 1400, 2200}, rankHours = {0, 1, 3, 6, 10, 15},
        approvalFromRank = 4, defaultRole = "sec_guard",
        selectable = true, whitelist = false, spawn = "security",
    },
    {
        id = "engineering", name = "Инженерная служба", short = "ИС", color = Color(230, 190, 60),
        ranks = {"Стажёр", "Техник", "Старший техник", "Инженер", "Ведущий инженер"},
        rankXP = {0, 150, 400, 800, 1400}, rankHours = {0, 1, 3, 6, 10},
        approvalFromRank = 4, defaultRole = "eng_tech",
        selectable = true, whitelist = false, spawn = "engineering",
    },
    {
        id = "medical", name = "Медицинская служба", short = "МС", color = Color(220, 80, 90),
        ranks = {"Санитар", "Фельдшер", "Врач", "Старший врач", "Заведующий отделением"},
        rankXP = {0, 150, 400, 800, 1400}, rankHours = {0, 1, 3, 6, 10},
        approvalFromRank = 4, defaultRole = "med_orderly",
        selectable = true, whitelist = false, spawn = "medical",
    },
    {
        id = "administration", name = "Администрация комплекса", short = "АК", color = Color(180, 180, 190),
        ranks = {"Делопроизводитель", "Специалист", "Старший специалист", "Заместитель директора", "Директор"},
        rankXP = {0, 200, 500, 1000, 1800}, rankHours = {0, 2, 5, 10, 20},
        approvalFromRank = 3, defaultRole = "adm_clerk",
        selectable = false, whitelist = true, spawn = "administration",
    },
    {
        id = "mtf", name = "Мобильная оперативная группа", short = "МОГ", color = Color(60, 140, 90),
        ranks = {"Оперативник", "Старший оперативник", "Сержант группы", "Командир отделения", "Командир группы"},
        rankXP = {0, 200, 500, 1000, 1800}, rankHours = {0, 2, 5, 10, 20},
        approvalFromRank = 3, defaultRole = "mtf_garrison",
        selectable = false, whitelist = true, spawn = "mtf",
    },
    {
        id = "chaos", name = "Повстанцы Хаоса", short = "ПХ", color = Color(110, 120, 60),
        ranks = {"Боец", "Ветеран", "Командир звена", "Командир ячейки"},
        rankXP = {0, 200, 500, 1000}, rankHours = {0, 2, 5, 10},
        approvalFromRank = 3, defaultRole = "chaos_operative",
        selectable = false, whitelist = true, spawn = "chaos",
    },
    {
        id = "scp", name = "Аномальные объекты", short = "SCP", color = Color(160, 30, 30),
        ranks = {"Объект"}, rankXP = {0}, rankHours = {0},
        approvalFromRank = 99, defaultRole = nil,
        selectable = false, whitelist = true, spawn = "scp",
    },
}

local citizenMale = {
    "models/player/group01/male_01.mdl", "models/player/group01/male_02.mdl", "models/player/group01/male_03.mdl",
    "models/player/group01/male_04.mdl", "models/player/group01/male_07.mdl", "models/player/group01/female_01.mdl",
    "models/player/group01/female_02.mdl",
}
local scientists = {"models/player/kleiner.mdl", "models/player/magnusson.mdl", "models/player/mossman.mdl", "models/player/eli.mdl"}
local guards = {"models/player/police.mdl", "models/player/police_fem.mdl"}
local medics = {"models/player/group03m/male_02.mdl", "models/player/group03m/male_05.mdl", "models/player/group03m/female_01.mdl", "models/player/group03m/female_03.mdl"}
local engineers = {"models/player/group03/male_04.mdl", "models/player/group03/male_06.mdl", "models/player/group03/female_02.mdl"}
local admins = {"models/player/breen.mdl", "models/player/mossman_arctic.mdl", "models/player/magnusson.mdl"}
local mtf = {"models/player/combine_soldier.mdl", "models/player/combine_soldier_prisonguard.mdl"}
local chaos = {"models/player/group03/male_01.mdl", "models/player/group03/male_03.mdl", "models/player/group03/male_08.mdl"}

C.FallbackModel = "models/player/kleiner.mdl"
C.LobbyRole = "lobby"

C.Roles = {
    {
        id = "lobby", division = nil, name = "Без назначения", hidden = true,
        description = "Игрок ещё не выбрал персонажа.",
        duties = {}, alarm = {}, clearance = 0, tags = {}, models = {C.FallbackModel},
        weapons = {}, kit = {}, flags = {},
    },

    -- Класс D ---------------------------------------------------------------
    {
        id = "classd_worker", division = "classd", name = "Сотрудник класса D",
        description = "Персонал для работ в опасных условиях. Живёт в блоке D, работает по нарядам охраны и научного отдела.",
        duties = {"Выполнять наряды по уборке и обслуживанию секторов", "Участвовать в экспериментах по вызову", "Работать на складе и разгрузке поставок", "Следовать указаниям охраны"},
        alarm = {"Вернуться в блок D или ближайшее укрытие", "Не приближаться к нарушенным камерам", "При эвакуации идти за сотрудником охраны"},
        clearance = 0, tags = {"dblock"}, minRank = 1,
        quota = nil, models = citizenMale,
        weapons = {"sv_hands"}, kit = {{"id_card", 1}},
        flags = {}, health = 100, walkSpeed = 160, runSpeed = 235,
    },
    {
        id = "classd_trustee", division = "classd", name = "Доверенный класса D",
        description = "Сотрудник класса D с хорошей характеристикой. Помогает охране поддерживать порядок в блоке D и получает доступ к складу.",
        duties = {"Организовывать работу бригад класса D", "Сопровождать новичков на наряды", "Помогать на складе"},
        alarm = {"Собрать бригаду и увести её в укрытие", "Сообщать охране о пропавших"},
        clearance = 0, tags = {"dblock", "storage"}, minRank = 4,
        quota = {base = 1, per = 12, max = 3}, models = citizenMale,
        weapons = {"sv_hands"}, kit = {{"id_card", 1}, {"radio", 1}},
        flags = {}, health = 100,
    },

    -- Научный отдел -----------------------------------------------------------
    {
        id = "sci_junior", division = "science", name = "Младший научный сотрудник",
        description = "Помогает в экспериментах, собирает наблюдения и готовит оборудование.",
        duties = {"Готовить оборудование для экспериментов", "Записывать наблюдения в досье", "Проверять датчики в лабораториях"},
        alarm = {"Прекратить эксперимент по аварийному протоколу", "Укрыться в научном секторе", "Сохранить материалы исследований"},
        clearance = 1, tags = {"science"}, minRank = 1,
        models = scientists, weapons = {"sv_hands"},
        kit = {{"id_card", 1}, {"radio", 1}, {"notebook", 1}},
        flags = {research = true},
    },
    {
        id = "sci_researcher", division = "science", name = "Научный сотрудник",
        description = "Руководит стандартными экспериментами и составляет отчёты.",
        duties = {"Проводить эксперименты по утверждённым протоколам", "Составлять отчёты и гипотезы", "Запрашивать оборудование через снабжение"},
        alarm = {"Аварийно прекратить эксперименты", "Координировать укрытие научного персонала"},
        clearance = 2, tags = {"science", "labs"}, minRank = 3,
        quota = {base = 2, per = 6, max = 8}, models = scientists, weapons = {"sv_hands"},
        kit = {{"id_card", 1}, {"radio", 1}, {"notebook", 1}},
        flags = {research = true, leadExperiments = true},
    },
    {
        id = "sci_senior", division = "science", name = "Старший научный сотрудник",
        description = "Согласует опасные эксперименты и проверяет отчёты коллег.",
        duties = {"Согласовывать опасные эксперименты", "Подтверждать или опровергать наблюдения в досье", "Распределять задачи научного отдела"},
        alarm = {"Принимать решение о прекращении всех экспериментов", "Консультировать службу безопасности по объектам"},
        clearance = 3, tags = {"science", "labs", "containment"}, minRank = 4,
        quota = {base = 1, per = 12, max = 3}, models = scientists, weapons = {"sv_hands"},
        kit = {{"id_card", 1}, {"radio", 1}, {"notebook", 1}},
        flags = {research = true, leadExperiments = true, approveExperiments = true, reviewDossier = true, approveSupply = true},
    },
    {
        id = "sci_head", division = "science", name = "Руководитель научного отдела",
        description = "Отвечает за научную программу комплекса и бюджет отдела.",
        duties = {"Утверждать исследовательскую программу", "Распоряжаться бюджетом научного отдела", "Согласовывать переводы и повышения"},
        alarm = {"Объявлять локальную тревогу в научном секторе", "Входить в штаб восстановления"},
        clearance = 4, tags = {"science", "labs", "containment"}, minRank = 5, whitelist = true,
        quota = {base = 1, per = 99, max = 1}, models = scientists, weapons = {"sv_hands"},
        kit = {{"id_card", 1}, {"radio", 1}, {"notebook", 1}},
        flags = {research = true, leadExperiments = true, approveExperiments = true, reviewDossier = true, approveSupply = true, divisionHead = true, declareAlert = true, promote = true},
    },

    -- Служба безопасности -----------------------------------------------------
    {
        id = "sec_guard", division = "security", name = "Охранник",
        description = "Поддерживает порядок, сопровождает класс D и проверяет пропуска.",
        duties = {"Патрулировать закреплённые секторы", "Сопровождать класс D на наряды и эксперименты", "Проверять пропуска на КПП"},
        alarm = {"Перекрыть проходы к нарушенному сектору", "Сопровождать эвакуацию", "Задерживать нарушителей"},
        clearance = 1, tags = {"security", "dblock"}, minRank = 1,
        models = guards, weapons = {"sv_hands", "sv_restraints", "sv_baton"},
        kit = {{"id_card", 1}, {"radio", 1}, {"pistol", 1}, {"ammo_pistol", 2}, {"vest", 1}},
        flags = {canDetain = true, search = true},
        armor = 25,
    },
    {
        id = "sec_officer", division = "security", name = "Офицер охраны",
        description = "Командует нарядом охраны, имеет право аварийного открытия дверей и оформления задержаний.",
        duties = {"Распределять посты и патрули", "Оформлять задержания", "Выдавать временные пропуска"},
        alarm = {"Объявлять локальную тревогу", "Блокировать секторы", "Руководить сдерживанием до прибытия МОГ"},
        clearance = 2, tags = {"security", "dblock", "armory"}, minRank = 3,
        quota = {base = 1, per = 6, max = 6}, models = guards, weapons = {"sv_hands", "sv_restraints", "sv_baton"},
        kit = {{"id_card", 1}, {"radio", 1}, {"pistol", 1}, {"ammo_pistol", 3}, {"vest", 1}},
        flags = {canDetain = true, search = true, emergencyOverride = true, issuePasses = true, declareAlert = true, lockdown = true},
        armor = 35,
    },
    {
        id = "sec_investigator", division = "security", name = "Следователь СБ",
        description = "Собирает улики, ведёт дела о происшествиях и утечках.",
        duties = {"Осматривать места происшествий", "Собирать и анализировать улики", "Вести дела и составлять отчёты"},
        alarm = {"Фиксировать следы инцидента до восстановления", "Опрашивать свидетелей"},
        clearance = 3, tags = {"security", "investigation", "dblock"}, minRank = 4,
        quota = {base = 1, per = 15, max = 2}, models = guards, weapons = {"sv_hands", "sv_restraints", "sv_evidence_kit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"pistol", 1}, {"ammo_pistol", 1}},
        flags = {canDetain = true, search = true, investigator = true, revokeCards = true},
    },
    {
        id = "sec_chief", division = "security", name = "Начальник службы безопасности",
        description = "Отвечает за безопасность комплекса и объявляет режимы тревоги.",
        duties = {"Утверждать график постов", "Распоряжаться бюджетом службы", "Контролировать журналы доступа"},
        alarm = {"Объявлять нарушение содержания и блокировки", "Вызывать МОГ", "Объявлять эвакуацию при отсутствии директора"},
        clearance = 4, tags = {"security", "dblock", "armory", "investigation", "containment"}, minRank = 5, whitelist = true,
        quota = {base = 1, per = 99, max = 1}, models = guards, weapons = {"sv_hands", "sv_restraints", "sv_baton"},
        kit = {{"id_card", 1}, {"radio", 1}, {"pistol", 1}, {"ammo_pistol", 3}, {"vest", 1}},
        flags = {canDetain = true, search = true, emergencyOverride = true, issuePasses = true, revokeCards = true, investigator = true,
            declareAlert = true, declareBreach = true, declareEvac = true, declareRecovery = true, lockdown = true,
            callReinforcements = true, approveSupply = true, divisionHead = true, promote = true},
        armor = 50,
    },

    -- Инженерная служба -------------------------------------------------------
    {
        id = "eng_tech", division = "engineering", name = "Техник",
        description = "Обслуживает инфраструктуру: питание, связь, вентиляцию и наблюдение.",
        duties = {"Проводить профилактику узлов", "Устранять мелкие неисправности", "Доставлять запчасти"},
        alarm = {"Восстанавливать питание критических систем", "Подключать резервное питание"},
        clearance = 1, tags = {"engineering", "maintenance"}, minRank = 1,
        models = engineers, weapons = {"sv_hands", "sv_toolkit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"spare_parts", 2}},
        flags = {engineer = true},
    },
    {
        id = "eng_engineer", division = "engineering", name = "Инженер",
        description = "Диагностирует сложные неисправности и распределяет мощность между секторами.",
        duties = {"Диагностировать неисправности", "Распределять мощность", "Проектировать обходные решения"},
        alarm = {"Перераспределять мощность в пользу камер содержания", "Руководить аварийным ремонтом"},
        clearance = 2, tags = {"engineering", "maintenance", "power"}, minRank = 3,
        quota = {base = 1, per = 8, max = 5}, models = engineers, weapons = {"sv_hands", "sv_toolkit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"spare_parts", 3}},
        flags = {engineer = true, powerControl = true},
    },
    {
        id = "eng_chief", division = "engineering", name = "Главный инженер",
        description = "Отвечает за работоспособность комплекса и бюджет инженерной службы.",
        duties = {"Планировать ремонт и закупки", "Утверждать заявки инженерной службы"},
        alarm = {"Объявлять локальную тревогу при аварии инфраструктуры", "Входить в штаб восстановления"},
        clearance = 3, tags = {"engineering", "maintenance", "power", "containment"}, minRank = 4, whitelist = true,
        quota = {base = 1, per = 99, max = 1}, models = engineers, weapons = {"sv_hands", "sv_toolkit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"spare_parts", 3}},
        flags = {engineer = true, powerControl = true, approveSupply = true, divisionHead = true, declareAlert = true, promote = true},
    },

    -- Медицинская служба ------------------------------------------------------
    {
        id = "med_orderly", division = "medical", name = "Санитар",
        description = "Оказывает первую помощь и доставляет пострадавших в медблок.",
        duties = {"Проводить плановые медосмотры", "Пополнять аптечки", "Сопровождать эксперименты"},
        alarm = {"Стабилизировать раненых", "Эвакуировать пострадавших"},
        clearance = 1, tags = {"medical"}, minRank = 1,
        models = medics, weapons = {"sv_hands", "sv_medkit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"bandage", 4}, {"tourniquet", 1}},
        flags = {medic = true},
    },
    {
        id = "med_doctor", division = "medical", name = "Врач",
        description = "Лечит тяжёлые ранения, выводит из недееспособности, анализирует биологические улики.",
        duties = {"Лечить персонал", "Проводить анализы", "Контролировать расход медикаментов"},
        alarm = {"Организовать сортировку раненых", "Выводить пострадавших из недееспособности"},
        clearance = 2, tags = {"medical", "labs"}, minRank = 3,
        quota = {base = 1, per = 8, max = 5}, models = medics, weapons = {"sv_hands", "sv_medkit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"bandage", 4}, {"tourniquet", 2}, {"splint", 1}, {"stimulant", 1}},
        flags = {medic = true, doctor = true},
    },
    {
        id = "med_chief", division = "medical", name = "Главный врач",
        description = "Руководит медицинской службой и её запасами.",
        duties = {"Утверждать заявки медицинской службы", "Проводить расследования медицинских происшествий"},
        alarm = {"Развернуть пункт помощи", "Входить в штаб восстановления"},
        clearance = 3, tags = {"medical", "labs", "containment"}, minRank = 4, whitelist = true,
        quota = {base = 1, per = 99, max = 1}, models = medics, weapons = {"sv_hands", "sv_medkit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"bandage", 4}, {"tourniquet", 2}, {"splint", 2}, {"stimulant", 2}},
        flags = {medic = true, doctor = true, approveSupply = true, divisionHead = true, promote = true},
    },

    -- Администрация -----------------------------------------------------------
    {
        id = "adm_clerk", division = "administration", name = "Специалист администрации",
        description = "Ведёт логистику, документооборот и бюджеты подразделений.",
        duties = {"Рассматривать заявки на снабжение", "Принимать поставки", "Проводить внутренние проверки"},
        alarm = {"Вести журнал инцидента", "Координировать эвакуацию гражданского персонала"},
        clearance = 2, tags = {"administration", "storage", "logistics"}, minRank = 1, whitelist = true,
        quota = {base = 1, per = 10, max = 4}, models = admins, weapons = {"sv_hands"},
        kit = {{"id_card", 1}, {"radio", 1}, {"notebook", 1}},
        flags = {approveSupply = true, logistics = true, issuePasses = true},
    },
    {
        id = "adm_ia", division = "administration", name = "Агент внутренних расследований",
        description = "Проверяет соблюдение протоколов и расследует злоупотребления персонала.",
        duties = {"Проводить аудит расходов", "Проверять соблюдение протоколов", "Расследовать утечки"},
        alarm = {"Сохранять доказательства", "Фиксировать решения руководства"},
        clearance = 3, tags = {"administration", "investigation"}, minRank = 2, whitelist = true,
        quota = {base = 1, per = 20, max = 2}, models = admins, weapons = {"sv_hands", "sv_evidence_kit"},
        kit = {{"id_card", 1}, {"radio", 1}, {"notebook", 1}},
        flags = {investigator = true, audit = true, revokeCards = true},
    },
    {
        id = "adm_director", division = "administration", name = "Директор комплекса",
        description = "Высшее руководство комплекса. Объявляет режимы, утверждает бюджеты и переводы.",
        duties = {"Утверждать бюджеты и переводы", "Согласовывать опасные исследования", "Проводить совещания"},
        alarm = {"Объявлять нарушение содержания, эвакуацию и восстановление", "Вызывать МОГ"},
        clearance = 5, tags = {"administration", "storage", "logistics", "security", "science", "labs", "containment", "armory", "power", "medical", "engineering"},
        minRank = 4, whitelist = true,
        quota = {base = 1, per = 99, max = 1}, models = admins, weapons = {"sv_hands"},
        kit = {{"id_card", 1}, {"radio", 1}, {"notebook", 1}},
        flags = {approveSupply = true, approveExperiments = true, approveTransfers = true, declareAlert = true, declareBreach = true,
            declareEvac = true, declareRecovery = true, lockdown = true, callReinforcements = true, issuePasses = true,
            revokeCards = true, promote = true, divisionHead = true, emergencyOverride = true},
    },

    -- МОГ ------------------------------------------------------------------------
    {
        id = "mtf_garrison", division = "mtf", name = "Оперативник МОГ (гарнизон)",
        description = "Небольшой постоянный гарнизон МОГ. Инспектирует камеры содержания и сопровождает опасные эксперименты.",
        duties = {"Инспектировать камеры содержания", "Сопровождать эксперименты классов 3-4", "Проводить учения с охраной"},
        alarm = {"Возглавить сдерживание до прибытия группы", "Обеспечить повторный захват"},
        clearance = 3, tags = {"security", "containment", "armory", "mtf"}, minRank = 1, whitelist = true,
        quota = {base = 0, per = 16, max = 2, minOnline = 16}, models = mtf, weapons = {"sv_hands", "sv_restraints"},
        kit = {{"id_card", 1}, {"radio", 1}, {"smg", 1}, {"ammo_smg", 2}, {"vest_heavy", 1}},
        flags = {canDetain = true, search = true, emergencyOverride = true, recontain = true},
        armor = 60,
    },
    {
        id = "mtf_operative", division = "mtf", name = "Оперативник МОГ Эпсилон-11",
        description = "Оперативник группы реагирования. Прибывает только по вызову при нарушении содержания.",
        duties = {"Ожидать развертывания"},
        alarm = {"Выполнять задачи развертывания", "Повторно захватывать объекты", "Эвакуировать персонал"},
        clearance = 3, tags = {"security", "containment", "armory", "mtf"}, minRank = 1, whitelist = true,
        reinforcement = "mtf", models = mtf, weapons = {"sv_hands", "sv_restraints"},
        kit = {{"id_card", 1}, {"radio", 1}, {"rifle", 1}, {"ammo_rifle", 3}, {"vest_heavy", 1}, {"bandage", 2}},
        flags = {canDetain = true, search = true, emergencyOverride = true, recontain = true},
        armor = 80,
    },
    {
        id = "mtf_commander", division = "mtf", name = "Командир группы МОГ",
        description = "Командует развернутой группой МОГ.",
        duties = {"Ожидать развертывания"},
        alarm = {"Распределять задачи группы", "Докладывать администрации о ходе операции"},
        clearance = 4, tags = {"security", "containment", "armory", "mtf"}, minRank = 4, whitelist = true,
        reinforcement = "mtf", models = mtf, weapons = {"sv_hands", "sv_restraints"},
        kit = {{"id_card", 1}, {"radio", 1}, {"rifle", 1}, {"ammo_rifle", 3}, {"vest_heavy", 1}, {"bandage", 2}},
        flags = {canDetain = true, search = true, emergencyOverride = true, recontain = true, declareRecovery = true},
        armor = 80,
    },

    -- Повстанцы Хаоса -------------------------------------------------------------
    {
        id = "chaos_operative", division = "chaos", name = "Боец Повстанцев Хаоса",
        description = "Участник рейда Повстанцев Хаоса. Появляется только во время рейда.",
        duties = {"Ожидать рейда"},
        alarm = {"Выполнять цели рейда", "Похищать документы и оборудование"},
        clearance = 0, tags = {"chaos"}, minRank = 1, whitelist = true,
        reinforcement = "chaos", models = chaos, weapons = {"sv_hands", "sv_restraints"},
        kit = {{"radio_chaos", 1}, {"smg", 1}, {"ammo_smg", 3}, {"vest", 1}, {"bandage", 2}},
        flags = {canDetain = true, search = true, sabotage = true},
        armor = 40,
    },
    {
        id = "chaos_leader", division = "chaos", name = "Командир ячейки Хаоса",
        description = "Командует рейдом Повстанцев Хаоса.",
        duties = {"Ожидать рейда"},
        alarm = {"Выбирать цели рейда", "Решать, когда отступать"},
        clearance = 0, tags = {"chaos"}, minRank = 3, whitelist = true,
        reinforcement = "chaos", models = chaos, weapons = {"sv_hands", "sv_restraints"},
        kit = {{"radio_chaos", 1}, {"shotgun", 1}, {"ammo_shotgun", 3}, {"vest", 1}, {"bandage", 2}},
        flags = {canDetain = true, search = true, sabotage = true},
        armor = 50,
    },

    -- SCP --------------------------------------------------------------------------
    {
        id = "scp173", division = "scp", name = "SCP-173", scp = "scp173", whitelist = true,
        description = "Скульптура, способная двигаться только вне прямого визуального контакта.",
        duties = {"Находиться в камере содержания", "Реагировать на условия содержания"},
        alarm = {"Использовать нарушение содержания"},
        clearance = 0, tags = {}, quota = {base = 1, per = 99, max = 1, minOnline = 6},
        models = {"models/player/charple.mdl"}, weapons = {"sv_scp173"}, kit = {}, flags = {scp = true},
        health = 3000,
    },
    {
        id = "scp106", division = "scp", name = "SCP-106", scp = "scp106", whitelist = true,
        description = "Гуманоид, проходящий сквозь твёрдые материалы и уводящий жертв в карманное измерение.",
        duties = {"Находиться в камере содержания"},
        alarm = {"Использовать нарушение содержания"},
        clearance = 0, tags = {}, quota = {base = 1, per = 99, max = 1, minOnline = 12},
        models = {"models/player/corpse1.mdl"}, weapons = {"sv_scp106"}, kit = {}, flags = {scp = true},
        health = 2000,
    },
    {
        id = "scp049", division = "scp", name = "SCP-049", scp = "scp049", whitelist = true,
        description = "Гуманоид, называющий себя доктором. Стремится «излечить» людей от «поветрия».",
        duties = {"Находиться в камере содержания", "Проходить собеседования"},
        alarm = {"Использовать нарушение содержания"},
        clearance = 0, tags = {}, quota = {base = 1, per = 99, max = 1, minOnline = 10},
        models = {"models/player/gman_high.mdl"}, weapons = {"sv_scp049"}, kit = {}, flags = {scp = true},
        health = 1800,
    },
    {
        id = "scp096", division = "scp", name = "SCP-096", scp = "scp096", whitelist = true,
        description = "Гуманоид, впадающий в ярость, если кто-то увидит его лицо.",
        duties = {"Находиться в камере содержания"},
        alarm = {"Использовать нарушение содержания"},
        clearance = 0, tags = {}, quota = {base = 1, per = 99, max = 1, minOnline = 16},
        models = {"models/player/skeleton.mdl"}, weapons = {"sv_scp096"}, kit = {}, flags = {scp = true},
        health = 2500,
    },
    {
        id = "scp0492", division = "scp", name = "SCP-049-2", scp = "scp0492", hidden = true,
        description = "Субъект, «излечённый» SCP-049. Временная роль, после гибели игрок возвращается к своему персонажу.",
        duties = {"Следовать за SCP-049"}, alarm = {},
        clearance = 0, tags = {}, models = {"models/player/zombie_classic.mdl"}, weapons = {"sv_scp0492"}, kit = {},
        flags = {scp = true, temporary = true}, health = 220,
    },
}

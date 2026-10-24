--[[---------------------------------------------------------------------------
Item catalogue (shared). Single source of truth for inventory items, locker
contents, supply prices and role kits.

Fields:
  name, desc       display texts
  category         equipment | weapon | ammo | consumable | tool | keycard |
                   document | evidence | quest | anomaly | contraband
  weight           kg
  stack            maximum stack size (1 = unique instances)
  weapon           SWEP class given when equipped
  ammoType, ammo   ammo items: engine ammo type and rounds per item
  armor            armour items: armour points on use
  use              server use handler id (modules/inventory/sv_use.lua)
  noDrop           cannot be dropped or handed over by the holder
  noConfiscate     cannot be confiscated during a search
  contraband       forbidden for Class D; found during searches
  hidden           not shown to others during a search (tiny items)
  price            supply price in budget units (nil = not orderable)
  division         divisions that may order it (nil = any)
  model            world model for dropped items
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Inventory = {
    baseSlots = 12,
    baseWeight = 22,          -- kg
    roleSlots = {sec_guard = 14, sec_officer = 14, mtf_garrison = 16, mtf_operative = 16, mtf_commander = 16,
        chaos_operative = 16, chaos_leader = 16, eng_tech = 16, eng_engineer = 16, eng_chief = 16},
    pickupDistance = 110,
    giveDistance = 140,
    offerTimeout = 20,
    worldItemLifetime = 600,  -- dropped items despawn after 10 minutes
    deathBagLifetime = 300,
    maxWorldItems = 120,      -- global cap, oldest dropped items are removed first
    kitRefillsPerShift = 4,   -- consumable kit top-ups on respawn per shift
}

local M = {
    card = "models/props_lab/clipboard.mdl",
    radio = "models/props_lab/citizenradio.mdl",
    box = "models/props_junk/cardboard_box004a.mdl",
    ammo = "models/items/boxsrounds.mdl",
    med = "models/items/healthkit.mdl",
    vial = "models/healthvial.mdl",
    vest = "models/items/item_item_crate.mdl",
    parts = "models/props_c17/tools_wrench01a.mdl",
    paper = "models/props_c17/paper01.mdl",
    bag = "models/props_junk/garbage_bag001a.mdl",
    can = "models/props_junk/gascan001a.mdl",
    device = "models/props_lab/reciever01b.mdl",
}

C.Items = {
    -- credentials -------------------------------------------------------------
    id_card = {name = "Служебное удостоверение", category = "keycard", weight = 0.05, stack = 1, noDrop = true, hidden = false,
        desc = "Удостоверение с чипом допуска. Считыватели проверяют серийный номер в реестре.", model = M.card},
    temp_pass = {name = "Временный пропуск", category = "keycard", weight = 0.02, stack = 1,
        desc = "Пропуск с ограниченным сроком действия. Выдаётся охраной.", model = M.card},

    -- equipment -----------------------------------------------------------------
    radio = {name = "Рация", category = "equipment", weight = 0.4, stack = 1, desc = "Служебная рация. Каналы зависят от подразделения.", model = M.radio, price = 15},
    radio_chaos = {name = "Защищённая рация", category = "equipment", weight = 0.4, stack = 1, desc = "Рация на нештатных частотах.", model = M.radio},
    notebook = {name = "Рабочий журнал", category = "tool", weight = 0.3, stack = 1, desc = "Записи о наблюдениях. Позволяет составлять отчёты в поле.", model = M.paper},
    vest = {name = "Бронежилет", category = "equipment", weight = 6, stack = 1, armor = 50, use = "armor", desc = "Защита 50.", model = M.vest, price = 40, division = {"security", "administration"}},
    vest_heavy = {name = "Тяжёлый бронежилет", category = "equipment", weight = 9, stack = 1, armor = 100, use = "armor", desc = "Защита 100.", model = M.vest},
    gas_mask = {name = "Противогаз", category = "equipment", weight = 1, stack = 1, use = "wear", slot = "face", desc = "Защищает от загрязнённого воздуха.", model = M.device, price = 20},
    hazmat = {name = "Защитный костюм", category = "equipment", weight = 4, stack = 1, use = "wear", slot = "body", desc = "Снижает риск заражения SCP-049 и загрязнения.", model = M.box, price = 45, division = {"science", "medical", "engineering"}},
    flashlight = {name = "Фонарь", category = "equipment", weight = 0.5, stack = 1, desc = "Позволяет включать фонарик (F).", model = M.device, price = 5},

    -- weapons (Half-Life 2 weapons shipped with Garry's Mod) ---------------------------
    pistol = {name = "Пистолет USP", category = "weapon", weight = 1, stack = 1, weapon = "weapon_pistol", ammoType = "Pistol", desc = "Табельное оружие охраны.", model = "models/weapons/w_pistol.mdl", price = 60, division = {"security"}},
    revolver = {name = "Револьвер .357", category = "weapon", weight = 1.4, stack = 1, weapon = "weapon_357", ammoType = "357", desc = "Оружие командного состава.", model = "models/weapons/w_357.mdl", price = 90, division = {"security"}},
    smg = {name = "Пистолет-пулемёт", category = "weapon", weight = 3, stack = 1, weapon = "weapon_smg1", ammoType = "SMG1", desc = "Автоматическое оружие.", model = "models/weapons/w_smg1.mdl", price = 120, division = {"security"}},
    rifle = {name = "Импульсная винтовка", category = "weapon", weight = 4, stack = 1, weapon = "weapon_ar2", ammoType = "AR2", desc = "Штурмовое оружие МОГ.", model = "models/weapons/w_irifle.mdl"},
    shotgun = {name = "Дробовик", category = "weapon", weight = 3.5, stack = 1, weapon = "weapon_shotgun", ammoType = "Buckshot", desc = "Ближний бой.", model = "models/weapons/w_shotgun.mdl", price = 110, division = {"security"}},
    crowbar = {name = "Монтировка", category = "weapon", weight = 1.5, stack = 1, weapon = "weapon_crowbar", desc = "Инструмент, который можно использовать как оружие.", model = "models/weapons/w_crowbar.mdl", price = 10, division = {"engineering"}},

    ammo_pistol = {name = "Магазин 9 мм", category = "ammo", weight = 0.25, stack = 10, ammoType = "Pistol", ammo = 18, use = "ammo", desc = "18 патронов.", model = M.ammo, price = 6, division = {"security"}},
    ammo_357 = {name = "Патроны .357", category = "ammo", weight = 0.2, stack = 10, ammoType = "357", ammo = 6, use = "ammo", desc = "6 патронов.", model = M.ammo, price = 8, division = {"security"}},
    ammo_smg = {name = "Магазин ПП", category = "ammo", weight = 0.4, stack = 10, ammoType = "SMG1", ammo = 45, use = "ammo", desc = "45 патронов.", model = "models/items/boxmrounds.mdl", price = 10, division = {"security"}},
    ammo_rifle = {name = "Энергоячейка", category = "ammo", weight = 0.4, stack = 10, ammoType = "AR2", ammo = 30, use = "ammo", desc = "30 выстрелов.", model = "models/items/combine_rifle_cartridge01.mdl"},
    ammo_shotgun = {name = "Патроны 12 калибра", category = "ammo", weight = 0.4, stack = 10, ammoType = "Buckshot", ammo = 12, use = "ammo", desc = "12 патронов.", model = "models/items/boxbuckshot.mdl", price = 9, division = {"security"}},

    -- medical --------------------------------------------------------------------------
    bandage = {name = "Бинт", category = "consumable", weight = 0.1, stack = 10, use = "medical", desc = "Останавливает лёгкое кровотечение.", model = M.vial, price = 3, division = {"medical", "security", "administration"}},
    tourniquet = {name = "Жгут", category = "consumable", weight = 0.15, stack = 5, use = "medical", desc = "Останавливает сильное кровотечение.", model = M.vial, price = 6, division = {"medical", "security"}},
    splint = {name = "Шина", category = "consumable", weight = 0.4, stack = 5, use = "medical", desc = "Фиксирует перелом.", model = M.vial, price = 8, division = {"medical"}},
    stimulant = {name = "Адреналин", category = "consumable", weight = 0.1, stack = 5, use = "medical", desc = "Выводит из недееспособности (только медик).", model = M.vial, price = 18, division = {"medical"}},
    medkit = {name = "Аптечка", category = "consumable", weight = 1.2, stack = 3, use = "medical", desc = "Постепенно восстанавливает здоровье.", model = M.med, price = 15, division = {"medical", "security", "administration"}},
    painkillers = {name = "Обезболивающее", category = "consumable", weight = 0.1, stack = 10, use = "medical", desc = "Снимает боль и замедление от ранений.", model = M.vial, price = 4, division = {"medical"}},
    antiviral = {name = "Экспериментальный антивирус", category = "consumable", weight = 0.1, stack = 5, use = "medical", desc = "Снимает симптомы «поветрия» SCP-049 на ранней стадии.", model = M.vial, price = 30, division = {"medical", "science"}},

    -- engineering ----------------------------------------------------------------------
    spare_parts = {name = "Запчасти", category = "consumable", weight = 1, stack = 10, desc = "Нужны для ремонта узлов.", model = M.parts, price = 8, division = {"engineering", "administration"}},
    fuel = {name = "Канистра топлива", category = "consumable", weight = 5, stack = 2, desc = "Заправка резервного генератора сектора.", model = M.can, price = 12, division = {"engineering"}},
    filter = {name = "Фильтрующий картридж", category = "consumable", weight = 1, stack = 5, desc = "Очистка вентиляционного узла.", model = M.device, price = 10, division = {"engineering"}},
    coating = {name = "Антикоррозийное покрытие", category = "consumable", weight = 2, stack = 5, desc = "Обработка камеры SCP-106.", model = M.can, price = 14, division = {"engineering", "science"}},

    -- science ------------------------------------------------------------------------------
    sensor_kit = {name = "Набор датчиков", category = "tool", weight = 2, stack = 3, desc = "Оборудование для экспериментов: повышает точность данных.", model = M.device, price = 25, division = {"science"}},
    hs_camera = {name = "Высокоскоростная камера", category = "tool", weight = 3, stack = 2, desc = "Фиксирует быстрые события. Нужна для части протоколов.", model = M.device, price = 35, division = {"science"}},
    em_shield = {name = "ЭМ-экран", category = "tool", weight = 4, stack = 2, desc = "Снижает риск при экспериментах с аномальной энергией.", model = M.device, price = 40, division = {"science", "engineering"}},
    sample_kit = {name = "Набор для образцов", category = "consumable", weight = 0.5, stack = 5, desc = "Контейнеры для забора образцов.", model = M.vial, price = 8, division = {"science", "medical"}},
    sample = {name = "Образец", category = "quest", weight = 0.2, stack = 1, desc = "Образец для анализа. Содержимое указано на этикетке.", model = M.vial},
    head_bag = {name = "Мешок для головы", category = "tool", weight = 0.3, stack = 2, desc = "Используется по протоколу содержания SCP-096.", model = M.bag, price = 20, division = {"security", "mtf", "science"}},
    lure_record = {name = "Звуковая запись-приманка", category = "tool", weight = 0.2, stack = 1, desc = "Носитель для протокола повторного содержания SCP-106.", model = M.device, price = 30, division = {"science", "security"}},

    -- documents and evidence -----------------------------------------------------------------
    document = {name = "Документ", category = "document", weight = 0.02, stack = 1, use = "read", desc = "Распечатка из архива. Гриф указан на первой странице.", model = M.paper},
    evidence_bag = {name = "Пакет с уликой", category = "evidence", weight = 0.1, stack = 1, desc = "Опечатанная улика. Номер дела на бирке.", model = M.bag},
    audit_report = {name = "Акт проверки", category = "document", weight = 0.02, stack = 1, use = "read", desc = "Документ внутренней проверки.", model = M.paper},

    -- anomalous objects (safe class, research subjects) ----------------------------------------
    ao_echo = {name = "Аномальный объект AO-3127 «Эхо»", category = "anomaly", weight = 2, stack = 1, noDrop = false, desc = "Терменвокс, воспроизводящий звуки за 30 секунд до их появления. Безопасный класс.", model = "models/props_lab/harddrive02.mdl"},
    ao_liquid = {name = "Аномальный объект AO-5510 «Ртутный мёд»", category = "anomaly", weight = 1, stack = 1, desc = "Вязкая жидкость, реагирующая на органику.", model = M.vial},

    -- contraband -------------------------------------------------------------------------------------
    contraband = {name = "Контрабанда", category = "contraband", weight = 0.3, stack = 5, contraband = true, desc = "Запрещённые предметы: сигареты, самодельные инструменты.", model = M.box},
    shiv = {name = "Заточка", category = "weapon", weight = 0.3, stack = 1, weapon = "weapon_crowbar", contraband = true, desc = "Самодельное оружие.", model = "models/weapons/w_crowbar.mdl"},
}

for id, item in pairs(C.Items) do
    item.id = id
    item.stack = item.stack or 1
    item.weight = item.weight or 0
end

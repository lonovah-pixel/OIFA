--[[---------------------------------------------------------------------------
Supply and budgets (shared configuration). Prices are in C.Items[*].price;
the server never trusts a price sent by a client.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Supply = {
    -- Budget given to each division at the start of every shift.
    allocation = {
        classd = 0, science = 220, security = 260, engineering = 220, medical = 200,
        administration = 150, mtf = 120, chaos = 0, scp = 0,
    },
    maxBudget = 2000,
    startBudget = 300,
    -- Starting stock per division (applied once, on the first start).
    startStock = {
        security = {pistol = 4, ammo_pistol = 20, vest = 4, smg = 2, ammo_smg = 8, bandage = 10, tourniquet = 4, head_bag = 1, revolver = 1, ammo_357 = 4},
        medical = {bandage = 30, tourniquet = 10, splint = 8, stimulant = 6, medkit = 6, painkillers = 12, antiviral = 2, sample_kit = 4},
        engineering = {spare_parts = 20, fuel = 4, filter = 6, coating = 3, gas_mask = 4, flashlight = 4, crowbar = 2},
        science = {sensor_kit = 4, hs_camera = 2, em_shield = 1, sample_kit = 8, hazmat = 3, gas_mask = 3, lure_record = 1, head_bag = 1},
        administration = {radio = 6, bandage = 6, medkit = 2, spare_parts = 4, flashlight = 2},
        mtf = {head_bag = 2, gas_mask = 4},
    },
    requestMaxLines = 8,
    requestMaxItems = 30,
    deliveryDelay = 90,        -- seconds after approval
    crateLifetime = 900,       -- unopened crates are booked automatically after this
    requesterMinRank = 2,
    -- Who can open crates of any division (unpacking duty).
    unpackDivisions = {"classd", "administration", "engineering"},
}

-- Lockers: what each locker kind hands out, from which division stock,
-- to whom and how much per character and shift.
C.Lockers = {
    armory = {name = "Оружейная", stock = "security", divisions = {"security", "mtf", "administration"}, tags = {"armory", "security"},
        items = {pistol = 1, ammo_pistol = 4, smg = 1, ammo_smg = 3, revolver = 1, ammo_357 = 2, vest = 1, head_bag = 1, tourniquet = 2, bandage = 3}},
    medical = {name = "Медицинский шкаф", stock = "medical", divisions = {"medical", "security", "mtf", "science", "administration", "engineering"}, tags = {"medical"},
        items = {bandage = 4, tourniquet = 2, splint = 2, stimulant = 2, medkit = 2, painkillers = 4, antiviral = 1, sample_kit = 2}},
    engineering = {name = "Инженерный склад", stock = "engineering", divisions = {"engineering", "administration"}, tags = {"engineering"},
        items = {spare_parts = 5, fuel = 2, filter = 2, coating = 2, gas_mask = 1, flashlight = 1, crowbar = 1}},
    science = {name = "Научный склад", stock = "science", divisions = {"science", "administration"}, tags = {"science"},
        items = {sensor_kit = 2, hs_camera = 1, em_shield = 1, sample_kit = 4, hazmat = 1, gas_mask = 1, lure_record = 1, head_bag = 1}},
    general = {name = "Хозяйственный склад", stock = "administration", divisions = nil, tags = nil,
        items = {flashlight = 1, bandage = 2}},
}

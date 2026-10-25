--[[---------------------------------------------------------------------------
Medicine (shared configuration). See BALANCE.md.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Medical = {
    tick = 5,                    -- bleeding tick, seconds
    bleedLight = 1,              -- hp per tick added by a wound >= 15 damage
    bleedHeavy = 3,              -- hp per tick added by a wound >= 35 damage
    bleedMax = 8,
    bleedoutTime = 90,           -- seconds incapacitated before death (not stabilised)
    bleedoutTimeHeavy = 60,      -- when bleeding heavily
    stabilisedMax = 300,         -- a stabilised patient wakes up on their own after this
    wakeHealth = 15,
    reviveHealth = 30,
    giveUpAfter = 20,            -- an incapacitated player may choose death after this
    crawlSpeed = 40,
    fractureSpeed = 0.55,        -- walk/run multiplier with a leg fracture
    fractureFallDamage = 25,
    headshotLethal = 45,         -- head bullet damage that kills outright
    explosionLethal = 160,
    painPerDamage = 1.2,
    painBlur = 60,
    examineCooldown = 300,       -- per medic and patient: counts for tasks once
    treatCooldown = 120,
    medkitHeal = 40,
    medkitDuration = 20,
    medicBonus = 1.5,            -- medics treat more effectively
    stunHits = 3,                -- baton hits within stunWindow that knock out
    stunWindow = 10,
    stunTime = 12,
    lowPopInjury = true,         -- on small servers SCP attacks incapacitate instead of killing
}

-- Treatment actions per medical item.
C.Treatments = {
    bandage = {time = 3, medicOnly = false, effect = "bleed", amount = 2, label = "Перевязка"},
    tourniquet = {time = 4, medicOnly = false, effect = "bleed", amount = 5, label = "Жгут"},
    splint = {time = 6, medicOnly = false, effect = "fracture", label = "Наложение шины"},
    painkillers = {time = 1, medicOnly = false, effect = "pain", amount = 50, label = "Обезболивание"},
    medkit = {time = 4, medicOnly = false, effect = "heal", label = "Обработка ран"},
    stimulant = {time = 4, medicOnly = true, doctor = true, effect = "revive", label = "Реанимация"},
    antiviral = {time = 3, medicOnly = true, effect = "cure", label = "Введение антивируса"},
}

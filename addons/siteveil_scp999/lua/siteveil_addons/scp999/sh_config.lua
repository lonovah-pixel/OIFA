--[[---------------------------------------------------------------------------
SCP-999 (shared configuration, boot stage): role, item, numbers.
Runs after the gamemode configuration and before roles are indexed and
turned into DarkRP jobs.
---------------------------------------------------------------------------]]

local C = SiteVeil.Config

table.insert(C.Roles, {
    id = "scp999", division = "scp", name = "SCP-999", scp = "scp999", whitelist = true,
    description = "Студенистое оранжевое существо, дружелюбное ко всем. Успокаивает и подбадривает людей.",
    duties = {"Находиться в камере содержания", "Участвовать в исследованиях"},
    alarm = {"Покинуть камеру и искать людей, которым нужна помощь"},
    clearance = 0, tags = {}, quota = {base = 1, per = 99, max = 1, minOnline = 4},
    -- No blob model ships with Garry's Mod: a shrunken, tinted HL2 model is a placeholder.
    models = {"models/player/zombie_fast.mdl"}, weapons = {"sv_scp999"}, kit = {}, flags = {scp = true},
    health = 800,
})

C.Items.sweets = {
    name = "Конфеты", category = "consumable", weight = 0.1, stack = 10, model = "models/props_junk/PopCan01a.mdl",
    desc = "Сладости. SCP-999 их очень любит.", price = 3, division = {"science", "medical", "administration"},
}
C.Supply.startStock.science = C.Supply.startStock.science or {}
C.Supply.startStock.science.sweets = 10

C.SCP.scp999 = {
    hugRange = 80,
    hugCooldown = 8,
    heal = 25,
    painRelief = 40,
    calmRange = 250,
    calmCooldown = 600,
    calmCooldownBoost = 300,  -- after the research discovery "calm_boost"
    calmTension = 10,         -- tension removed from the director when nothing needs calming
    recaptureTime = 5,
    visitOk = 900,            -- seconds since somebody was in the cell
    fedOk = 1200,
    scale = 0.55,
    damageFactor = 0.5,
}

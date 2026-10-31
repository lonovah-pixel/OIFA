--[[---------------------------------------------------------------------------
SCP-939 (shared configuration, boot stage): role and numbers.
---------------------------------------------------------------------------]]

local C = SiteVeil.Config

table.insert(C.Roles, {
    id = "scp939", division = "scp", name = "SCP-939", scp = "scp939", whitelist = true,
    description = "Слепой хищник, ориентирующийся по звуку и подражающий голосам своих жертв.",
    duties = {"Находиться в камере содержания"},
    alarm = {"Охотиться на тех, кто шумит"},
    clearance = 0, tags = {}, quota = {base = 1, per = 99, max = 1, minOnline = 12},
    -- No SCP-939 model ships with Garry's Mod: a tinted HL2 model is a placeholder.
    models = {"models/player/zombie_soldier.mdl"}, weapons = {"sv_scp939"}, kit = {}, flags = {scp = true},
    health = 1600,
})

C.SCP.scp939 = {
    hearRange = 1800,          -- noise further away is not heard
    noiseLife = 4,             -- seconds a noise stays on 939's "picture"
    runSpeed = 210,            -- moving faster than this is audible
    talkNoise = 1,             -- noise weights
    yellNoise = 2,
    shotNoise = 3,
    runNoise = 1,
    attackRange = 90,
    attackCooldown = 2,
    lureRange = 700,
    lureCooldown = 20,
    lureSounds = {"vo/npc/male01/help01.wav", "vo/npc/male01/hi01.wav", "vo/npc/male01/overhere01.wav",
        "vo/npc/female01/help01.wav", "vo/npc/female01/hi02.wav", "vo/npc/male01/excuseme01.wav"},
    suppressHealth = 0.35,
    suppressTime = 25,
    recaptureTime = 8,
    quietOk = 600,             -- seconds without noise near the cell keep it calm
    pushInterval = 0.5,
}

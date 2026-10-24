--[[---------------------------------------------------------------------------
General SITE-VEIL configuration (shared).

Balance values specific to one system live in that system's config file
(sh_roles.lua, sh_items.lua, sh_facility.lua, ...). See BALANCE.md for the
reasoning behind the numbers.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Config = SV.Config or {}
local C = SV.Config

C.ServerName = "SITE-VEIL"
C.Language = "ru"

-- Population thresholds used by quotas, the director and SCP adaptation.
C.Population = {
    low = 10,       -- below: "малый онлайн"
    medium = 25,    -- below: "средний онлайн"
    target = 48,    -- design target (40-64 players), not a measured capacity
}

C.Characters = {
    slots = 3,                  -- character slots per player (admins can add extra slots)
    maxSlots = 6,
    nameMinLength = 4,
    nameMaxLength = 32,
    switchCooldown = 120,       -- seconds between character switches
    combatLock = 30,            -- no switching within N seconds after taking/dealing damage
    deleteConfirmWord = true,   -- deletion requires typing the character name
    startDivisions = {"classd", "science", "security", "engineering", "medical"},
}

C.Shift = {
    length = 3600,              -- one shift cycle in seconds
    warnBefore = 300,           -- announce the end of the shift N seconds before
}

C.Respawn = {
    base = 15,                  -- seconds
    perPlayers = 0.25,          -- extra seconds per online player (bigger servers wait longer)
    max = 45,
    reinforcementDelay = 5,     -- MTF/Chaos members return to the queue after death
}

C.Chat = {
    talkDistance = 300,
    whisperDistance = 90,
    yellDistance = 650,
    meDistance = 350,
    maxLength = 300,
    icRate = {burst = 4, refill = 0.8},   -- tokens per second
    oocRate = {burst = 2, refill = 0.15},
    radioRate = {burst = 3, refill = 0.5},
    oocEnabled = true,
}

C.Voice = {
    distance = 600,
    updateInterval = 0.5,
    roomCheck = true,           -- walls block local voice
}

C.Net = {
    maxRpcBytes = 4096,
    globalRate = {burst = 40, refill = 20},
    violationKick = 60,         -- violations within violationWindow before a kick
    violationWindow = 60,
}

C.Sync = {
    flushInterval = 0.15,
}

C.Debug = false

-- Sounds from Half-Life 2 / Garry's Mod base content. Replace freely.
C.Sounds = {
    alarmLocal = "ambient/alarms/alarm1.wav",
    alarmBreach = "ambient/alarms/klaxon1.wav",
    alarmEvac = "ambient/alarms/apc_alarm_loop1.wav",
    announce = "buttons/blip1.wav",
    denied = "buttons/button10.wav",
    granted = "buttons/button14.wav",
    radioOn = "npc/combine_soldier/vo/on1.wav",
    radioOff = "npc/combine_soldier/vo/off1.wav",
    radioStatic = "ambient/levels/prison/radio_random1.wav",
    sparks = "ambient/energy/spark1.wav",
    powerDown = "ambient/machines/thumper_shutdown1.wav",
    powerUp = "ambient/machines/thumper_startup1.wav",
    repair = "ambient/machines/pneumatic_drill_1.wav",
    taskDone = "buttons/bell1.wav",
    notify = "buttons/lightswitch2.wav",
}

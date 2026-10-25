--[[---------------------------------------------------------------------------
Security (shared configuration). See BALANCE.md.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Security = {
    restrainTime = 3,             -- seconds to cuff a resisting target
    restrainDistance = 80,
    restrainMax = 480,            -- automatic release after 8 minutes
    reRestrainGrace = 90,         -- after an automatic release the same target is protected unless they fight
    restrainedSpeed = 0.55,
    escortDistance = 70,
    escortBreak = 450,
    selfReleaseAlone = 60,        -- restrained and nobody who can detain within selfReleaseRadius for this long
    selfReleaseRadius = 500,
    selfReleaseTime = 12,
    searchTime = 4,
    searchDistance = 90,
    detainDistance = 220,         -- without configured cells: detention near the officer
    detainDefault = 5,            -- minutes
    detainMax = 10,               -- minutes for officers
    detainMaxChief = 20,          -- minutes with the chief / director flag
    idCheckCooldown = 600,
    batonCooldown = 0.9,
    batonDamage = 5,
}

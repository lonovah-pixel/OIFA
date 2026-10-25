--[[---------------------------------------------------------------------------
Playable SCPs (shared configuration). Numbers are gameplay values, not
secrets; restricted lore lives in config/sv_dossiers.lua.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.SCP = {
    tick = 10,                       -- containment simulation step, seconds
    breachCheck = 1,                 -- breach detection interval
    virtualCellRadius = 350,         -- fallback cell around the SCP spawn when no cell zone exists
    stages = {                       -- integrity thresholds (lower bound)
        {id = "stable", min = 75, name = "Стабильно"},
        {id = "signs", min = 50, name = "Признаки нестабильности"},
        {id = "degrading", min = 25, name = "Ухудшение"},
        {id = "danger", min = 10, name = "Опасное состояние"},
        {id = "escape", min = 0, name = "Возможен побег"},
    },
    recontainIntegrity = 60,
    unplayedIncidentDelay = 60,      -- unplayed SCP at "escape": containment incident (no real breach)
    recaptureXP = 40,
    popFloor = 0.3,                  -- minimal population factor for degradation

    scp173 = {
        observeRange = 3000,
        observeDot = 0.55,           -- cos of half the effective field of view
        darkRange = 350,             -- without light, observation works only this close (unless flashlight)
        blinkMin = 5, blinkMax = 7, blinkTime = 0.35,
        blinkMinLowPop = 7, blinkMaxLowPop = 9,
        attackRange = 80,
        attackCooldown = 2.5,
        moveDelay = 0.25,            -- reaction window after becoming unobserved
        runSpeed = 520,
        blackoutRadius = 600,
        blackoutCooldown = 45,
        blackoutBlink = 1.2,
        doorBreakTime = 6,
        doorBreakTimeLowPop = 10,
        dirtPerMinute = 0.5,
        recaptureTime = 12,
        recaptureObservers = 2,
    },

    scp106 = {
        attackRange = 75,
        attackCooldown = 6,
        corrosionDamage = 15,        -- on the touch that sends a victim to the pocket
        pocketTick = 5,
        pocketDamage = 4,            -- per tick inside the pocket; never below pocketFloorHealth
        pocketFloorHealth = 10,
        pocketMax = 90,              -- seconds: the victim is always expelled after this
        pocketNoExit = 30,           -- pocket without exit points: expelled after this
        pocketFallback = 8,          -- no pocket zone on the map: blind + corrosion, then expelled
        pocketExitRadius = 80,
        phaseRange = 100,
        phaseDepth = 90,             -- how far behind the door 106 appears
        phaseCooldown = 8,
        travelCooldown = 90,
        bulletFactor = 0.3,          -- share of bullet damage that reaches 106
        retreatHealth = 0.2,         -- below this share of health 106 retreats into its cell
        coatingDecay = 1,            -- coating points per minute
        coatingProcedure = 60,
        lureTime = 30,
    },

    scp049 = {
        touchRange = 70,
        touchCooldown = 20,
        cureTime = 8,                -- operation on an incapacitated or stage-2 infected victim
        cureRange = 80,
        stageTime = 240,             -- seconds from infection stage 1 to stage 2
        maxInstances = 2,            -- simultaneous SCP-049-2
        maxInstancesLowPop = 1,
        instanceTime = 420,          -- an instance collapses after this
        recureCooldown = 1800,       -- the same character cannot be converted again for this long
        interviewOk = 1200,          -- seconds since the last interview: no anxiety
        interviewWarn = 2400,
        suppressHealth = 0.4,        -- below this share of health 049 is suppressed
        suppressTime = 25,
        recaptureTime = 10,
        zombieDamage = 22,
        zombieRange = 70,
        zombieCooldown = 1.2,
    },

    scp096 = {
        viewRange = 2500,
        viewRangeDark = 600,
        faceDot = 0.92,              -- observer looks at the face
        facingDot = 0.2,             -- 096 is turned towards the observer
        triggerTime = 6,             -- crying before the rage
        rageSpeed = 560,
        calmSpeed = 140,
        rageMax = 150,               -- rage always ends after this
        calmingTime = 6,
        exhaustedTime = 40,
        maxTargets = 6,
        attackRange = 85,
        attackCooldown = 1,
        doorBreakTime = 2,
        bagTime = 6,
        maskTime = 1800,
    },
}

--[[---------------------------------------------------------------------------
"След инцидента" (shared configuration). See BALANCE.md.

Traces are temporary world marks created by game events. Players see only
what their tools reveal: a field scan gives the kind and an approximate age;
laboratory analysis at a security terminal adds limited, rounded facts.
Exact data (names, times) stays in the admin audit log.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Evidence = {
    maxTraces = 250,          -- whole map; the oldest go first
    maxPerSector = 50,
    mergeRadius = 60,         -- same kind close together and recent: merged
    mergeTime = 30,
    scanRadius = 400,
    scanCooldown = 3,
    collectDistance = 90,
    collectTime = 4,
    casingInterval = 4,       -- at most one casing trace per shooter per N s
    analysis = {
        {time = 15, window = 600, label = "Первичный анализ"},
        {time = 30, window = 180, label = "Лабораторный анализ", needs = "sensor_kit"},
    },
    ageStep = 300,            -- field scans round the age to this many seconds
}

C.TraceKinds = {
    blood = {name = "Следы крови", ttl = 900},
    casing = {name = "Гильзы", ttl = 600},
    slime = {name = "Чёрная едкая слизь", ttl = 1200},
    scratch = {name = "Следы трения бетона", ttl = 900},
    damage = {name = "Следы вмешательства в оборудование", ttl = 1200},
    document = {name = "Следы работы с секретным документом", ttl = 900},
    stash = {name = "Признаки тайника", ttl = 1800},
}

--[[---------------------------------------------------------------------------
Post-load verification of the DarkRP integration. Every finding is a load
error shown in the console and in the admin panel ("Состояние сервера").
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Bridge = SV.DarkRP

function Bridge.verify()
    local problems = {}
    local function problem(fmt, ...) problems[#problems + 1] = string.format(fmt, ...) end

    if not Bridge.preloadRan then problem("хук DarkRPPreLoadModules не сработал: модули DarkRP не отключены") end
    if not Bridge.jobsCreated then problem("роли SITE-VEIL не созданы как профессии DarkRP") end

    for name in pairs(Bridge.disabledModules) do
        if not DarkRP.disabledDefaults.modules[name] then problem("модуль DarkRP %s не отключён", name) end
    end

    for i, job in pairs(RPExtraTeams) do
        if not job.siteVeilRole then problem("посторонняя профессия DarkRP #%d: %s", i, tostring(job.name)) end
    end
    for _, role in ipairs(SV.Roles.list) do
        if not role.team or not RPExtraTeams[role.team] then problem("у роли %s нет профессии DarkRP", role.id) end
    end

    if #DarkRPEntities > 0 then problem("остались покупаемые сущности DarkRP: %d", #DarkRPEntities) end
    if #CustomShipments > 0 then problem("остались поставки DarkRP: %d", #CustomShipments) end
    if GAMEMODE and GAMEMODE.AmmoTypes and #GAMEMODE.AmmoTypes > 0 then problem("остались патроны DarkRP: %d", #GAMEMODE.AmmoTypes) end

    local cfg = (GAMEMODE or GM).Config
    for k, v in pairs(Bridge.configOverrides) do
        if not istable(v) and cfg[k] ~= v then problem("GM.Config.%s = %s, ожидается %s", k, tostring(cfg[k]), tostring(v)) end
    end

    for _, p in ipairs(problems) do SV.Loader.addError("DarkRP: " .. p) end
    Bridge.verified = #problems == 0
    if Bridge.verified then SV.Log.info("интеграция с DarkRP проверена: отключено модулей %d", SV.Util.count(Bridge.disabledModules)) end
    return problems
end

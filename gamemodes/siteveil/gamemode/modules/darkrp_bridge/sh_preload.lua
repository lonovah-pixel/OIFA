--[[---------------------------------------------------------------------------
DarkRP pre-load configuration (shared, boot stage).

DarkRP calls hook "DarkRPPreLoadModules" after its config/config.lua and before
it loads its modules. At that moment we:

  1. disable DarkRP modules whose mechanics SITE-VEIL removes or replaces;
  2. disable DarkRP's default jobs, shipments, entities, ammo, agendas, group
     chats, door groups and demote groups;
  3. override GM.Config values that DarkRP modules read while loading.

The replaced modules keep their interface stubs (DarkRP loads every
*_interface.lua regardless of disabledDefaults). SITE-VEIL implements those
stubs in modules/darkrp_bridge/*_shims.lua so callers in the remaining DarkRP
code keep working. See DARKRP_CHANGES.md.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.DarkRP = SV.DarkRP or {}
local Bridge = SV.DarkRP

-- DarkRP modules removed from SITE-VEIL and the replacing system.
Bridge.disabledModules = {
    afk = "не используется",
    chatsounds = "не используется",
    events = "заменён директором напряжения (modules/director)",
    f1menu = "заменён справкой служебной системы (F1)",
    f4menu = "заменён служебной системой (F4)",
    hitmenu = "городская механика удалена",
    hobo = "городская механика удалена",
    hud = "заменён HUD SITE-VEIL (modules/ui)",
    hungermod = "городская механика удалена",
    money = "заменён бюджетами подразделений (modules/supply)",
    police = "заменён системой безопасности (modules/security)",
    sleep = "заменён недееспособностью (modules/medical)",
    tipjar = "городская механика удалена",
}

local defaultJobs = {"citizen", "cp", "gangster", "mobboss", "gundealer", "medic", "chief", "mayor", "hobo", "cook"}
local defaultShipments = {"Desert eagle", "Fiveseven", "Glock", "P228", "AK47", "MP5", "M4", "Mac 10", "Pump shotgun", "Sniper rifle"}
local defaultEntities = {"Drug lab", "Money printer", "Tip Jar", "Gun lab"}
local defaultAmmo = {"Pistol ammo", "Shotgun ammo", "Rifle ammo"}
local defaultAgendas = {"Gangster's agenda", "Police agenda"}
local defaultDoorGroups = {"Cops and Mayor only", "Gundealer only"}
local defaultDemoteGroups = {"Cops", "Gangsters"}

-- GM.Config values applied before DarkRP modules load.
Bridge.configOverrides = {
    -- security
    disallowClientsideScripts = true,
    adminBypassJobRestrictions = false,
    AdminsCopWeapons = false,
    adminsents = 2,
    adminweapons = 1,
    adminvehicles = 3,
    adminnpcs = 2,
    -- roles are assigned by modules/characters only
    allowjobswitch = false,
    customjobs = false,
    allowrpnames = false,
    restrictallteams = false,
    norespawn = true,
    instantjob = false,
    removeclassitems = false,
    -- money and city mechanics
    startingmoney = 0,
    normalsalary = 0,
    paydelay = 3600,
    npckillpay = 0,
    proppaying = false,
    propertytax = false,
    cit_propertytax = false,
    wallettax = false,
    lottery = false,
    letters = false,
    license = false,
    enablebuypistol = false,
    dropmoneyondeath = false,
    allowvehicleowning = false,
    doorwarrants = false,
    lockdown = false,
    npcarrest = false,
    earthquakes = false,
    printeroverheat = false,
    -- props and items: inventory owns all items
    propspawning = false,
    dropweapondeath = false,
    droppocketdeath = false,
    droppocketarrest = false,
    dropspawnedweapons = false,
    -- chat and voice are handled by modules/comms
    ooc = false,
    alltalk = false,
    voiceradius = false,
    voice3D = true,
    dynamicvoice = false,
    deadvoice = false,
    deadtalk = false,
    chatsounds = false,
    -- misc
    allowsprays = false,
    allowActs = false,
    customspawns = false,
    deathblack = false,
    deathpov = false,
    showdeaths = false,
    babygod = true,
    babygodtime = 4,
    respawntime = 10,
    strictsuicide = false,
    unlockdoorsonstart = false,
    canforcedooropen = false,
    realisticfalldamage = true,
    runspeed = 235,
    walkspeed = 160,
    hideNonBuyable = true,
    hideTeamUnbuyable = true,
    DefaultWeapons = {},
    AdminWeapons = {},
    currency = "",
}

local function setAll(target, list)
    for _, key in ipairs(list) do target[key] = true end
end

hook.Add("DarkRPPreLoadModules", "SiteVeil.PreLoad", function()
    local dd = DarkRP.disabledDefaults

    for name in pairs(Bridge.disabledModules) do
        dd.modules[name] = true
    end

    setAll(dd.jobs, defaultJobs)
    setAll(dd.shipments, defaultShipments)
    setAll(dd.entities, defaultEntities)
    setAll(dd.ammo, defaultAmmo)
    setAll(dd.agendas, defaultAgendas)
    setAll(dd.doorgroups, defaultDoorGroups)
    setAll(dd.demotegroups, defaultDemoteGroups)
    for i = 1, 3 do dd.groupchat[i] = true end

    -- During DarkRP's own load the global GM is DarkRP's gamemode table. The
    -- derived gamemode inherits the same Config table by reference.
    local gm = GM or GAMEMODE
    for k, v in pairs(Bridge.configOverrides) do
        gm.Config[k] = v
    end

    Bridge.preloadRan = true
end)

hook.Add("DarkRPFinishedLoading", "SiteVeil.CreateJobs", function()
    Bridge.createJobs()
end)

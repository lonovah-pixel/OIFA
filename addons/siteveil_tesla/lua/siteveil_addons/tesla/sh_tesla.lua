--[[---------------------------------------------------------------------------
Tesla gates (shared): configuration, map point kind, network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Tesla = SV.Tesla or {}

SV.Config.Tesla = {
    radius = 90,               -- horizontal radius of the field (map prop "radius" overrides)
    height = 110,
    tick = 0.2,
    charge = 0.8,              -- audible warning before the discharge
    cooldown = 2,
    damage = 80,               -- DMG_SHOCK: incapacitates a human, wears down SCPs
    bypass = {clearance = 3, tags = {"security"}},  -- passing people with such a card do not trigger it
    disableMax = 120,          -- seconds a gate group can be switched off at once
    disableCooldown = 60,
    disableFlags = {"lockdown", "recontain"},
}

SV.MapCfg.pointKinds.tesla = {name = "Тесла-ворота", entity = "sv_tesla_gate"}

SV.Sync.define("tesla", {scope = "global"})
SV.Net.define("tesla.disable", {args = {"str:32", "u8"}, alive = true, rate = {burst = 3, refill = 0.3}})

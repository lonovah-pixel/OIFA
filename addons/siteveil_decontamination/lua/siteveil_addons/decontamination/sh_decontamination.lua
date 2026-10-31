--[[---------------------------------------------------------------------------
Sector decontamination (shared): configuration and network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Decon = SV.Decon or {}

SV.Config.Decontamination = {
    warnTime = 120,               -- countdown before the gas: time to leave
    announceAt = {60, 30, 10},
    duration = 90,                -- gas phase; the sector stays locked meanwhile
    tick = 2,
    damage = 8,                   -- per tick for unprotected people (incapacitates, rarely kills)
    protection = {"gas_mask", "hazmat"},
    cooldown = 1800,              -- per sector
    flags = {"declareBreach", "declareEvac"},
    affectsRoles = {scp0492 = true},  -- SCP roles that the gas affects
}

SV.Sync.define("decon", {scope = "global"})
SV.Net.define("decon.start", {args = {"str:32"}, alive = true, rate = {burst = 2, refill = 0.1}})
SV.Net.define("decon.cancel", {args = {"str:32"}, rate = {burst = 2, refill = 0.2}})

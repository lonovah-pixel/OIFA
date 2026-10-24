--[[---------------------------------------------------------------------------
Implementations of the shared interface stubs of DarkRP modules that
SITE-VEIL disables (police, money, hitmenu, hungermod).

DarkRP loads every module's *_interface.lua even when the module is disabled.
An unimplemented stub returns nil and queues the call forever, so every stub
of a disabled module is implemented here and maps onto the SITE-VEIL system
that replaced it. These functions are the only bridge between remaining
DarkRP code (base, doors, FAdmin) and SITE-VEIL state.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local plyMeta = FindMetaTable("Player")
local entMeta = FindMetaTable("Entity")

-- police ------------------------------------------------------------------
-- "Arrested" in DarkRP terms = held in detention by modules/security.
function plyMeta:isArrested()
    local sec = SV.Security
    return sec ~= nil and sec.isDetained ~= nil and sec.isDetained(self) or false
end

-- SITE-VEIL has no wanted list; security alerts are part of investigations.
function plyMeta:isWanted()
    return false
end

function plyMeta:getWantedReason()
    return nil
end

-- "Civil protection" = any role that may detain (security, MTF).
function plyMeta:isCP()
    return SV.Roles.hasFlag(self, "canDetain")
end

-- There is no mayor or police chief; facility authority is expressed with
-- role flags (declareBreach, lockdown, ...).
function plyMeta:isMayor()
    return false
end

function plyMeta:isChief()
    return false
end

-- money ---------------------------------------------------------------------
-- Personal wallets are removed; budgets belong to divisions (modules/supply).
function plyMeta:canAfford(amount)
    return (tonumber(amount) or 0) <= 0
end

function entMeta:isMoneyBag()
    return false
end

-- hitmenu ---------------------------------------------------------------------
function plyMeta:isHitman() return false end
function plyMeta:hasHit() return false end
function plyMeta:getHitTarget() return nil end
function plyMeta:getHitPrice() return 0 end
function DarkRP.addHitmanTeam() end
function DarkRP.getHitmanTeams() return {} end

-- hungermod -------------------------------------------------------------------
function DarkRP.createFood() end
function DarkRP.removeFoodItem() end
function plyMeta:isCook() return false end
function DarkRP.getFoodItems() return {} end

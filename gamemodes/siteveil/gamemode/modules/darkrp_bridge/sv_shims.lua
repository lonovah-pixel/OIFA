--[[---------------------------------------------------------------------------
Server-side implementations of interface stubs of disabled DarkRP modules
(money, police, hitmenu, hungermod, sleep). See sh_shims.lua.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local plyMeta = FindMetaTable("Player")

-- money -------------------------------------------------------------------
-- No personal money exists. Calls from remaining DarkRP code (doors, base)
-- become no-ops; they are unreachable because buying is disabled, but must not
-- leak into DarkRP's delayed stub queue.
function plyMeta:addMoney()
    return false
end

function plyMeta:payDay()
end

function DarkRP.payPlayer()
end

function DarkRP.createMoneyBag()
    return NULL
end

-- police --------------------------------------------------------------------
-- DarkRP's lockdown is replaced by facility states (modules/facility).
function DarkRP.lockdown(ply)
    if IsValid(ply) then
        DarkRP.notify(ply, 1, 5, "Комендантский час DarkRP отключён. Используйте режимы комплекса (F4 → Комплекс).")
    end
    return false
end

function DarkRP.unLockdown()
    return false
end

function plyMeta:requestWarrant() return false end
function plyMeta:warrant() return false end
function plyMeta:unWarrant() return false end
function plyMeta:wanted() return false end
function plyMeta:unWanted() return false end

-- arrest/unArrest are kept working for third-party addons by mapping them onto
-- SITE-VEIL detention.
function plyMeta:arrest(time, arrester)
    local sec = SV.Security
    if not sec or not sec.adminDetain then return false end
    return sec.adminDetain(self, arrester, time, "Задержание (совместимость DarkRP)")
end

function plyMeta:unArrest(actor)
    local sec = SV.Security
    if not sec or not sec.release then return false end
    return sec.release(self, actor, "Освобождение (совместимость DarkRP)")
end

function DarkRP.iterateArrestedPlayers()
    local list = DarkRP.arrestedPlayers()
    local i = 0
    return function()
        i = i + 1
        return list[i]
    end
end

function DarkRP.arrestedPlayers()
    local out = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply:isArrested() then out[#out + 1] = ply end
    end
    return out
end

function DarkRP.arrestedPlayerCount()
    return #DarkRP.arrestedPlayers()
end

-- hitmenu ---------------------------------------------------------------------
function plyMeta:requestHit() return false end
function plyMeta:placeHit() end
function plyMeta:setHitTarget() end
function plyMeta:setHitPrice() end
function plyMeta:setHitCustomer() end
function plyMeta:getHitCustomer() return nil end
function plyMeta:abortHit() end
function plyMeta:finishHit() end
function DarkRP.getHits() return {} end

-- hungermod -------------------------------------------------------------------
function plyMeta:newHungerData() end
function plyMeta:hungerUpdate() end

-- sleep -------------------------------------------------------------------------
-- Ragdoll sleeping is replaced by medical incapacitation.
function DarkRP.toggleSleep()
    return false
end

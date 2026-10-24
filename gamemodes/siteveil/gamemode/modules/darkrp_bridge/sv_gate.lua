--[[---------------------------------------------------------------------------
Server-side gate in front of the remaining DarkRP systems.

Closes every entry point of removed mechanics, independent of the UI:
  * chat/console commands that are not on the allow list
  * job changes that were not issued by modules/characters
  * money changes, salaries, door purchases, pocket, demotes, votes
  * spawning of city entities (printers, labs, shipments) even for admins
  * DarkRP's per-job console commands rp_<job>
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Bridge = SV.DarkRP
local BaseClass = SV.BaseClass

-- Entity classes of removed mechanics. Nobody may spawn them.
Bridge.blockedClasses = {
    money_printer = true, drug_lab = true, drug = true, gunlab = true, microwave = true,
    food = true, spawned_food = true, spawned_money = true, spawned_shipment = true,
    spawned_weapon = true, spawned_ammo = true, darkrp_cheque = true, darkrp_tip_jar = true,
    darkrp_billboard = true, darkrp_laws = true, letter = true, lab_base = true, meteor = true,
    -- DarkRP tools of removed mechanics
    keys = true, pocket = true, lockpick = true, door_ram = true, arrest_stick = true,
    unarrest_stick = true, stunstick = true, weaponchecker = true, weapon_keypadchecker = true,
    med_kit = true,
}

--[[---------------------------------------------------------------------------
Commands
---------------------------------------------------------------------------]]
function GM:canChatCommand(ply, cmd, ...)
    if not Bridge.isAllowedCommand(cmd) then
        if IsValid(ply) then
            DarkRP.notify(ply, 1, 4, "Команда /" .. tostring(cmd) .. " отключена в SITE-VEIL.")
        end
        return false
    end
    return BaseClass.canChatCommand(self, ply, cmd, ...)
end

hook.Add("InitPostEntity", "SiteVeil.RemoveJobConCommands", function()
    timer.Simple(1, function()
        for _, role in ipairs(SV.Roles.list) do
            concommand.Remove("rp_" .. Bridge.jobCommand(role))
        end
    end)
end)

--[[---------------------------------------------------------------------------
Roles: only modules/characters may change the DarkRP team.
---------------------------------------------------------------------------]]

--- Changes the player's DarkRP team on behalf of SITE-VEIL. Returns success.
function Bridge.setTeam(ply, teamId)
    if ply:Team() == teamId then return true end
    ply.SVTeamToken = teamId
    local ok = ply:changeTeam(teamId, true, true, true)
    ply.SVTeamToken = nil
    return ok == true
end

hook.Add("playerCanChangeTeam", "SiteVeil.Gate", function(ply, teamId)
    if ply.SVTeamToken == teamId then return true end
    return false, "Должность меняется через служебную систему (F4 → Подразделение)."
end)

function GM:canDemote()
    return false, "Разжалование выполняется через систему званий."
end

function GM:canVote()
    return false
end

function GM:CanChangeRPName()
    return false, "Имя задаётся при создании персонажа."
end

--[[---------------------------------------------------------------------------
Money: wallets stay at 0, salaries are suppressed.
---------------------------------------------------------------------------]]
function GM:playerWalletChanged(ply, amount, wallet)
    return wallet or 0
end

function GM:playerGetSalary()
    return true, nil, 0
end

--[[---------------------------------------------------------------------------
Doors: no ownership. Access is handled by modules/access.
---------------------------------------------------------------------------]]
function GM:playerBuyDoor()
    return false, "Двери не продаются: доступ определяется допуском."
end

function GM:playerBuyVehicle()
    return false, "Транспорт не продаётся."
end

function GM:getDoorCost() return 0 end
function GM:getVehicleCost() return 0 end
function GM:canKeysLock() return false end
function GM:canKeysUnlock() return false end
function GM:canPocket() return false, "Карман отключён: используйте инвентарь." end
function GM:canDropWeapon() return false end
function GM:canTax() return false end

--[[---------------------------------------------------------------------------
Spawning
---------------------------------------------------------------------------]]
function GM:PlayerSpawnSENT(ply, class)
    if Bridge.blockedClasses[class] then
        DarkRP.notify(ply, 1, 4, "Эта сущность отключена в SITE-VEIL.")
        return false
    end
    return BaseClass.PlayerSpawnSENT(self, ply, class)
end

function GM:PlayerSpawnSWEP(ply, class, info)
    if Bridge.blockedClasses[class] then return false end
    return BaseClass.PlayerSpawnSWEP(self, ply, class, info)
end

function GM:PlayerGiveSWEP(ply, class, info)
    if Bridge.blockedClasses[class] then return false end
    return BaseClass.PlayerGiveSWEP(self, ply, class, info)
end

-- Props are reserved for administrators on duty (map dressing).
function GM:PlayerSpawnProp(ply, model)
    if not ply:IsSuperAdmin() then
        DarkRP.notify(ply, 1, 4, "Создание пропов доступно только администраторам.")
        return false
    end
    return self.Sandbox.PlayerSpawnProp(self, ply, model)
end

hook.Add("OnEntityCreated", "SiteVeil.BlockCityEntities", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) and Bridge.blockedClasses[ent:GetClass()] and not ent:IsWeapon() then
            SV.Log.warn("удалена отключённая сущность %s", ent:GetClass())
            ent:Remove()
        end
    end)
end)

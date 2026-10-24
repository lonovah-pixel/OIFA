--[[---------------------------------------------------------------------------
Items in the world (server): dropping, picking up, death bags, map weapons.

World items are temporary: they live at most C.Inventory.worldItemLifetime
seconds, there are at most C.Inventory.maxWorldItems of them (oldest go
first) and they do not survive a restart.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Inv = SV.Inv
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config

Inv.world = Inv.world or {}   -- ent -> {expires, items = {item, ...}, bag = bool}

local function worldCount()
    local n = 0
    for ent in pairs(Inv.world) do
        if IsValid(ent) then n = n + 1 else Inv.world[ent] = nil end
    end
    return n
end

local function destroyWorldEntry(ent, reason)
    local entry = Inv.world[ent]
    Inv.world[ent] = nil
    if entry then
        for _, item in ipairs(entry.items) do Inv.deleteItem(item) end
        if reason then SV.Log.debug("world item removed: %s", reason) end
    end
    if IsValid(ent) then
        ent.SVRemoving = true
        ent:Remove()
    end
end
Inv.destroyWorldEntry = destroyWorldEntry

local function enforceCap()
    while worldCount() >= C.Inventory.maxWorldItems do
        local oldest, oldestAt
        for ent, entry in pairs(Inv.world) do
            if not oldestAt or entry.expires < oldestAt then oldest, oldestAt = ent, entry.expires end
        end
        if not oldest then break end
        destroyWorldEntry(oldest, "cap")
    end
end

--- Places items into the world as one entity. Items must already be detached
--- from any inventory; their rows are moved to location "world".
function Inv.spawnWorld(items, pos, ang, opts)
    opts = opts or {}
    enforceCap()
    local bag = opts.bag or #items > 1
    local ent = ents.Create(bag and "sv_item_bag" or "sv_item")
    if not IsValid(ent) then return nil end
    ent:SetPos(pos)
    ent:SetAngles(ang or Angle(0, math.random(0, 359), 0))
    if not bag then
        ent:SetItemId(items[1].id)
        ent:SetItemCount(items[1].count)
    else
        ent:SetOwnerName(opts.ownerName or "")
    end
    ent:Spawn()
    ent:Activate()
    local lifetime = opts.lifetime or (bag and C.Inventory.deathBagLifetime or C.Inventory.worldItemLifetime)
    Inv.world[ent] = {expires = CurTime() + lifetime, items = items, bag = bag}
    for _, item in ipairs(items) do Inv.setLocation(item, "world", nil, nil) end
    return ent
end

function Inv.drop(ply, uid, count)
    local item = Inv.getItem(ply, uid)
    if not item then return false, "Предмет не найден." end
    local def = C.Items[item.id]
    if def.noDrop then return false, "Этот предмет нельзя выбросить." end
    if item.lock then return false, "Предмет занят." end
    local veto, reason = hook.Run("SiteVeil.CanDropItem", ply, item)
    if veto == false then return false, reason end
    count = math.Clamp(math.floor(count or item.count), 1, item.count)

    local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 60, filter = ply})
    local pos = tr.HitPos + tr.HitNormal * 8

    local moved
    local ok, err = DB.transaction(function()
        if count == item.count then
            Inv.detach(ply, item)
            moved = item
        else
            item.count = item.count - count
            Inv.saveItem(item)
            moved = Inv.createItem(item.id, count, U.copy(item.data), "world", nil, item.issuedTo, item.kit)
        end
    end)
    if not ok then
        Inv.reload(ply)
        return false, "Ошибка базы данных: " .. tostring(err)
    end
    Inv.changed(ply)
    Inv.spawnWorld({moved}, pos)
    SV.Audit.log("inventory", "drop", ply, nil, {item = moved.id, uid = moved.uid, count = count})
    return true
end

--- Picks up a single world item entity.
function Inv.pickup(ply, ent)
    local entry = Inv.world[ent]
    if not entry or entry.bag or ent.SVTaken then return false end
    if not ply.SVChar or not ply:Alive() then return false end
    if not U.within(ply, ent, C.Inventory.pickupDistance) then return false end
    local veto, reason = hook.Run("SiteVeil.CanPickupItem", ply, entry.items[1])
    if veto == false then
        DarkRP.notify(ply, 1, 4, reason or "Нельзя подобрать.")
        return false
    end
    local item = entry.items[1]
    local ok, why = Inv.fits(ply, item.id, item.count, false)
    if not ok then
        DarkRP.notify(ply, 1, 4, "Не помещается: " .. why)
        return false
    end
    ent.SVTaken = true -- second Use in the same tick sees this flag
    Inv.world[ent] = nil
    Inv.attach(ply, item)
    Inv.changed(ply)
    ent.SVRemoving = true
    ent:Remove()
    SV.Audit.log("inventory", "pickup", ply, nil, {item = item.id, uid = item.uid, count = item.count})
    hook.Run("SiteVeil.ItemPickedUp", ply, item)
    return true
end

--- Sends the contents of a bag to a player.
function Inv.openBag(ply, ent)
    local entry = Inv.world[ent]
    if not entry or not entry.bag then return end
    if not U.within(ply, ent, C.Inventory.pickupDistance) then return end
    local list = {}
    for _, item in ipairs(entry.items) do
        list[#list + 1] = {uid = item.uid, id = item.id, count = item.count, title = item.data.title}
    end
    Net.send(ply, "inv.bag", {ent = ent:EntIndex(), owner = ent:GetOwnerName(), items = list})
end

Net.handle("inv.bagTake", function(ply, ent, uid)
    local entry = IsValid(ent) and Inv.world[ent]
    if not entry or not entry.bag then return false, "Контейнер недоступен." end
    if not U.within(ply, ent, C.Inventory.pickupDistance) then return false, "Подойдите ближе." end
    local idx
    for i, item in ipairs(entry.items) do
        if item.uid == uid then idx = i break end
    end
    if not idx then return false, "Предмет уже забрали." end
    local item = entry.items[idx]
    local veto, reason = hook.Run("SiteVeil.CanPickupItem", ply, item)
    if veto == false then return false, reason end
    local ok, why = Inv.fits(ply, item.id, item.count, false)
    if not ok then return false, "Не помещается: " .. why end
    table.remove(entry.items, idx)
    Inv.attach(ply, item)
    Inv.changed(ply)
    SV.Audit.log("inventory", "bag.take", ply, nil, {item = item.id, uid = item.uid, owner = ent:GetOwnerName()})
    if #entry.items == 0 then
        Inv.world[ent] = nil
        ent.SVRemoving = true
        ent:Remove()
    else
        Inv.openBag(ply, ent)
    end
    return true
end)

-- Death: everything that is not a kit item of this character drops into a
-- bag. Kit items stay with the character ("сданы на склад"). Reserve ammo in
-- the weapons is lost.
hook.Add("PlayerDeath", "SiteVeil.Inv.DeathDrop", function(ply)
    local char = ply.SVChar
    local cont = Inv.get(ply)
    if not char or not cont then return end
    local drop = {}
    for _, item in pairs(cont.items) do
        local def = C.Items[item.id]
        if item.issuedTo ~= char.id and not def.noDrop then drop[#drop + 1] = item end
    end
    for id, offer in pairs(Inv.offers) do
        if offer.from == ply or offer.to == ply then Inv.cancelOffer(id, "участник погиб") end
    end
    ply:RemoveAllAmmo()
    if #drop == 0 then
        Inv.changed(ply)
        return
    end
    table.sort(drop, function(a, b) return a.uid < b.uid end)
    for _, item in ipairs(drop) do
        item.lock = nil
        Inv.detach(ply, item)
    end
    Inv.changed(ply)
    Inv.spawnWorld(drop, ply:GetPos() + Vector(0, 0, 10), nil, {bag = true, ownerName = SV.Chars.displayName(ply)})
    SV.Audit.log("inventory", "death.drop", ply, nil, {count = #drop})
end)

-- Expiry of world items.
timer.Create("SiteVeil.Inv.World", 5, 0, function()
    local now = CurTime()
    for ent, entry in pairs(Inv.world) do
        if not IsValid(ent) then
            Inv.world[ent] = nil
            for _, item in ipairs(entry.items) do Inv.deleteItem(item) end
        elseif now > entry.expires then
            destroyWorldEntry(ent, "expired")
        end
    end
end)

-- Entities removed by other means (cleanup, admin remover) destroy their items.
hook.Add("EntityRemoved", "SiteVeil.Inv.World", function(ent)
    if Inv.world[ent] and not ent.SVRemoving then
        local entry = Inv.world[ent]
        Inv.world[ent] = nil
        for _, item in ipairs(entry.items) do Inv.deleteItem(item) end
    end
end)

-- Map-placed weapons become catalogue items (or disappear), so no weapon
-- exists outside the inventory system.
local function convertMapWeapons()
    local byClass = {}
    for id, def in pairs(C.Items) do
        if def.weapon and not def.contraband and not byClass[def.weapon] then byClass[def.weapon] = id end
    end
    local converted, removed = 0, 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:IsWeapon() and not IsValid(ent:GetOwner()) then
            local itemId = byClass[ent:GetClass()]
            local pos, ang = ent:GetPos(), ent:GetAngles()
            ent:Remove()
            if itemId then
                local item = Inv.createItem(itemId, 1, {}, "world", nil, nil, nil)
                Inv.spawnWorld({item}, pos, ang, {lifetime = 86400})
                converted = converted + 1
            else
                removed = removed + 1
            end
        end
    end
    if converted + removed > 0 then SV.Log.info("оружие карты: преобразовано %d, удалено %d", converted, removed) end
end
hook.Add("InitPostEntity", "SiteVeil.Inv.MapWeapons", function() timer.Simple(1, convertMapWeapons) end)
hook.Add("PostCleanupMap", "SiteVeil.Inv.MapWeapons", function()
    Inv.world = {}
    DB.query("DELETE FROM sv_items WHERE location = 'world'")
    timer.Simple(1, convertMapWeapons)
end)

SV.Perf.registry("inventory.world", worldCount)

--[[---------------------------------------------------------------------------
Inventory (server). The only owner of items in SITE-VEIL.

Every item instance has a persistent uid (sv_items.uid) and exactly one
location at any time:
    char      in a character's inventory   (char_id set)
    world     dropped item entity / death bag (removed at startup)
    storage   confiscation storage          (storage = id)

Every move is a single UPDATE of that row, executed immediately, so memory
and database never disagree and an item cannot exist in two places. Lua runs
single-threaded; concurrent requests are processed one after another and
each one re-validates the current location of the item. Items involved in a
pending handover are locked (item.lock) and refuse every other operation.

Weapons: an inventory weapon item is "equipped" while its SWEP exists on the
player. SWEPs that do not come from the inventory or the role's tool list are
refused (PlayerCanPickupWeapon / PlayerGiveSWEP).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Inv = SV.Inv
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local Roles = SV.Roles

Inv.containers = Inv.containers or {}  -- ply -> container
Inv.offers = Inv.offers or {}          -- id -> offer
Inv.nextOffer = Inv.nextOffer or 1

DB.registerMigrations("inventory", {
    {1, "items", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_items (
            uid INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id TEXT NOT NULL,
            count INTEGER NOT NULL,
            data TEXT NOT NULL DEFAULT '{}',
            location TEXT NOT NULL,
            char_id INTEGER,
            storage TEXT,
            issued_to INTEGER,
            kit TEXT,
            created_at INTEGER NOT NULL
        )]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_items_char ON sv_items (char_id)")
        DB.query("CREATE INDEX IF NOT EXISTS sv_items_issued ON sv_items (issued_to)")
        DB.query("CREATE INDEX IF NOT EXISTS sv_items_storage ON sv_items (storage)")
    end},
})

--[[---------------------------------------------------------------------------
Rows
---------------------------------------------------------------------------]]
local function rowToItem(row)
    return {
        uid = tonumber(row.uid),
        id = row.item_id,
        count = tonumber(row.count),
        data = DB.decode(row.data),
        issuedTo = tonumber(row.issued_to),
        kit = row.kit,
    }
end

--- Creates a new item row and returns the instance.
local function createItem(itemId, count, data, location, charId, issuedTo, kit, storage)
    DB.query([[INSERT INTO sv_items (item_id, count, data, location, char_id, storage, issued_to, kit, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], itemId, count, DB.encode(data or {}), location, charId, storage, issuedTo, kit, os.time())
    local uid = DB.lastInsertId()
    return {uid = uid, id = itemId, count = count, data = data or {}, issuedTo = issuedTo, kit = kit}
end
Inv.createItem = createItem

local function saveItem(item)
    DB.query("UPDATE sv_items SET count = ?, data = ? WHERE uid = ?", item.count, DB.encode(item.data), item.uid)
end
Inv.saveItem = saveItem

local function setLocation(item, location, charId, storage)
    DB.query("UPDATE sv_items SET location = ?, char_id = ?, storage = ? WHERE uid = ?", location, charId, storage, item.uid)
end
Inv.setLocation = setLocation

local function deleteItem(item)
    DB.query("DELETE FROM sv_items WHERE uid = ?", item.uid)
end
Inv.deleteItem = deleteItem

--[[---------------------------------------------------------------------------
Containers
---------------------------------------------------------------------------]]
function Inv.get(ply)
    return Inv.containers[ply]
end

function Inv.capacity(ply)
    local role = Roles.ofPlayer(ply)
    local slots = (role and C.Inventory.roleSlots[role.id]) or C.Inventory.baseSlots
    return slots, C.Inventory.baseWeight
end

function Inv.usage(ply)
    local cont = Inv.containers[ply]
    if not cont then return 0, 0 end
    local slots, weight = 0, 0
    for _, item in pairs(cont.items) do
        slots = slots + 1
        local def = C.Items[item.id]
        weight = weight + (def and def.weight or 0) * item.count
    end
    return slots, weight
end

--- Whether `count` of itemId fits into ply's inventory.
function Inv.fits(ply, itemId, count, mergeable)
    local def = C.Items[itemId]
    if not def then return false, "неизвестный предмет" end
    local cont = Inv.containers[ply]
    if not cont then return false, "инвентарь недоступен" end
    local maxSlots, maxWeight = Inv.capacity(ply)
    local slots, weight = Inv.usage(ply)
    if weight + def.weight * count > maxWeight + 1e-6 then
        return false, string.format("слишком тяжело (%.1f / %d кг)", weight + def.weight * count, maxWeight)
    end
    local needSlots = 0
    if def.stack > 1 and mergeable ~= false then
        local free = 0
        for _, item in pairs(cont.items) do
            if item.id == itemId and next(item.data) == nil and not item.issuedTo then free = free + (def.stack - item.count) end
        end
        local rest = math.max(count - free, 0)
        needSlots = math.ceil(rest / def.stack)
    else
        needSlots = def.stack > 1 and math.ceil(count / def.stack) or count
    end
    if slots + needSlots > maxSlots then return false, "нет свободных ячеек (" .. slots .. " / " .. maxSlots .. ")" end
    return true
end

function Inv.publish(ply)
    local cont = Inv.containers[ply]
    if not cont then
        SV.Sync.setFor(ply, "self", "inv", nil)
        return
    end
    local list = {}
    for _, item in pairs(cont.items) do
        list[#list + 1] = {uid = item.uid, id = item.id, count = item.count, equipped = item.equipped, worn = item.data.worn,
            title = item.data.title, kit = item.issuedTo == (ply.SVChar and ply.SVChar.id) or nil, locked = item.lock ~= nil,
            serial = item.data.serial, expires = item.data.expires}
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    local maxSlots, maxWeight = Inv.capacity(ply)
    local slots, weight = Inv.usage(ply)
    SV.Sync.setFor(ply, "self", "inv", {items = list, slots = slots, maxSlots = maxSlots, weight = math.Round(weight, 1), maxWeight = maxWeight})
end

local function changed(ply)
    Inv.publish(ply)
    hook.Run("SiteVeil.InventoryChanged", ply)
end
Inv.changed = changed

--- Adds items. Stackable items without data merge into existing stacks.
--  opts: {force = ignore capacity, issuedTo, kit, data}
--  Returns ok, reason, items(list of touched instances)
function Inv.add(ply, itemId, count, opts)
    opts = opts or {}
    count = math.floor(count or 1)
    local def = C.Items[itemId]
    local cont = Inv.containers[ply]
    if not def or count < 1 then return false, "неверный предмет" end
    if not cont then return false, "инвентарь недоступен" end

    local data = opts.data
    local mergeable = def.stack > 1 and (data == nil or next(data) == nil) and not opts.issuedTo
    if not opts.force then
        local ok, reason = Inv.fits(ply, itemId, count, mergeable)
        if not ok then return false, reason end
    end

    local touched = {}
    local left = count
    if mergeable then
        for _, item in pairs(cont.items) do
            if left <= 0 then break end
            if item.id == itemId and next(item.data) == nil and not item.issuedTo and item.count < def.stack and not item.lock then
                local n = math.min(def.stack - item.count, left)
                item.count = item.count + n
                left = left - n
                saveItem(item)
                touched[#touched + 1] = item
            end
        end
    end
    while left > 0 do
        local n = def.stack > 1 and math.min(def.stack, left) or 1
        local item = createItem(itemId, n, data and U.copy(data) or {}, "char", ply.SVChar.id, opts.issuedTo, opts.kit)
        cont.items[item.uid] = item
        left = left - n
        touched[#touched + 1] = item
        hook.Run("SiteVeil.ItemCreated", ply, item)
    end
    changed(ply)
    return true, nil, touched
end

--- Removes `count` from a specific instance (destroys it when empty).
function Inv.removeUid(ply, uid, count)
    local cont = Inv.containers[ply]
    local item = cont and cont.items[uid]
    if not item then return false, "предмет не найден" end
    count = math.min(count or item.count, item.count)
    if item.equipped then Inv.holster(ply, item) end
    item.count = item.count - count
    if item.count <= 0 then
        cont.items[uid] = nil
        deleteItem(item)
        hook.Run("SiteVeil.ItemDestroyed", ply, item)
    else
        saveItem(item)
    end
    changed(ply)
    return true
end

function Inv.count(ply, itemId)
    local cont = Inv.containers[ply]
    if not cont then return 0 end
    local n = 0
    for _, item in pairs(cont.items) do
        if item.id == itemId then n = n + item.count end
    end
    return n
end

function Inv.has(ply, itemId, count)
    return Inv.count(ply, itemId) >= (count or 1)
end

--- Consumes `count` items of a kind (unlocked stacks only).
function Inv.take(ply, itemId, count)
    count = count or 1
    if Inv.countFree(ply, itemId) < count then return false end
    local cont = Inv.containers[ply]
    local uids = {}
    for uid, item in pairs(cont.items) do
        if item.id == itemId and not item.lock then uids[#uids + 1] = uid end
    end
    table.sort(uids)
    for _, uid in ipairs(uids) do
        if count <= 0 then break end
        local item = cont.items[uid]
        local n = math.min(item.count, count)
        Inv.removeUid(ply, uid, n)
        count = count - n
    end
    return true
end

function Inv.countFree(ply, itemId)
    local cont = Inv.containers[ply]
    if not cont then return 0 end
    local n = 0
    for _, item in pairs(cont.items) do
        if item.id == itemId and not item.lock then n = n + item.count end
    end
    return n
end

function Inv.find(ply, fn)
    local out = {}
    local cont = Inv.containers[ply]
    if not cont then return out end
    for _, item in pairs(cont.items) do
        if fn(item, C.Items[item.id]) then out[#out + 1] = item end
    end
    table.sort(out, function(a, b) return a.uid < b.uid end)
    return out
end

function Inv.getItem(ply, uid)
    local cont = Inv.containers[ply]
    return cont and cont.items[uid]
end

--- Detaches an instance from a player (for moving elsewhere). Holsters it.
local function detach(ply, item)
    local cont = Inv.containers[ply]
    if item.equipped then Inv.holster(ply, item) end
    if item.data.worn then
        item.data.worn = nil
        saveItem(item)
    end
    cont.items[item.uid] = nil
end
Inv.detach = detach

--- Inserts an existing instance into ply's inventory (location update).
local function attach(ply, item)
    local cont = Inv.containers[ply]
    cont.items[item.uid] = item
    setLocation(item, "char", ply.SVChar.id, nil)
end
Inv.attach = attach

--- Moves an instance (or part of a stack) between two players. Atomic:
--- validated first, then a single DB transaction.
function Inv.transfer(from, to, uid, count, opts)
    opts = opts or {}
    local item = Inv.getItem(from, uid)
    if not item then return false, "предмет не найден" end
    if item.lock and item.lock ~= opts.lock then return false, "предмет занят" end
    if not Inv.containers[to] then return false, "у получателя нет инвентаря" end
    count = math.Clamp(math.floor(count or item.count), 1, item.count)
    local ok, reason = Inv.fits(to, item.id, count, false)
    if not ok and not opts.force then return false, "у получателя " .. reason end

    local success, err = DB.transaction(function()
        if count == item.count then
            detach(from, item)
            item.lock = nil
            attach(to, item)
        else
            item.count = item.count - count
            saveItem(item)
            local part = createItem(item.id, count, U.copy(item.data), "char", to.SVChar.id, nil, nil)
            Inv.containers[to].items[part.uid] = part
        end
    end)
    if not success then
        -- Reload both inventories from the database: the DB is authoritative.
        Inv.reload(from)
        Inv.reload(to)
        return false, "ошибка базы данных: " .. tostring(err)
    end
    changed(from)
    changed(to)
    SV.Audit.log("inventory", "transfer", from, to, {item = item.id, uid = uid, count = count, reason = opts.reason})
    return true
end

--[[---------------------------------------------------------------------------
Loading and unloading
---------------------------------------------------------------------------]]
function Inv.load(ply)
    local char = ply.SVChar
    local cont = {items = {}}
    for _, row in ipairs(DB.query("SELECT * FROM sv_items WHERE location = 'char' AND char_id = ?", char.id) or {}) do
        local item = rowToItem(row)
        if C.Items[item.id] then
            item.equipped = nil
            cont.items[item.uid] = item
        else
            SV.Log.warn("удалён неизвестный предмет %s (uid %d) персонажа %d", item.id, item.uid, char.id)
            deleteItem(item)
        end
    end
    Inv.containers[ply] = cont
    changed(ply)
end

function Inv.reload(ply)
    if IsValid(ply) and ply.SVChar then
        local cont = Inv.containers[ply]
        if cont then
            for _, item in pairs(cont.items) do
                if item.equipped then ply:StripWeapon(C.Items[item.id].weapon) end
            end
        end
        Inv.load(ply)
    end
end

--- Converts the player's reserve ammo back into ammo items. Partial
--- magazines are kept as a remainder in char.data.ammoRemainder.
function Inv.packAmmo(ply)
    local char = ply.SVChar
    local cont = Inv.containers[ply]
    if not char or not cont then return end
    char.data.ammoRemainder = char.data.ammoRemainder or {}
    for itemId, def in pairs(C.Items) do
        if def.category == "ammo" and def.ammoType then
            local rounds = ply:GetAmmoCount(def.ammoType) + (char.data.ammoRemainder[def.ammoType] or 0)
            if rounds > 0 then
                local mags = math.floor(rounds / def.ammo)
                char.data.ammoRemainder[def.ammoType] = rounds - mags * def.ammo
                ply:SetAmmo(0, def.ammoType)
                if mags > 0 then Inv.add(ply, itemId, mags, {force = true}) end
            end
        end
    end
end

local function unload(ply)
    local cont = Inv.containers[ply]
    if not cont then return end
    for _, item in pairs(cont.items) do
        if item.equipped then Inv.holster(ply, item) end
    end
    if ply:Alive() then Inv.packAmmo(ply) end
    for id, offer in pairs(Inv.offers) do
        if offer.from == ply or offer.to == ply then Inv.cancelOffer(id, "участник недоступен") end
    end
    Inv.containers[ply] = nil
end
Inv.unload = unload

hook.Add("SiteVeil.CharacterLoaded", "SiteVeil.Inv", function(ply)
    Inv.load(ply)
end)

hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.Inv", function(ply, _, reason)
    unload(ply)
    if reason ~= "disconnect" and IsValid(ply) then SV.Sync.setFor(ply, "self", "inv", nil) end
end)

hook.Add("SiteVeil.CharacterDeleted", "SiteVeil.Inv", function(charId)
    DB.query("DELETE FROM sv_items WHERE location = 'char' AND char_id = ?", charId)
end)

-- World items and death bags do not survive a restart.
hook.Add("SiteVeil.DatabaseReady", "SiteVeil.Inv.Cleanup", function()
    DB.query("DELETE FROM sv_items WHERE location = 'world'")
end)

--[[---------------------------------------------------------------------------
Weapons
---------------------------------------------------------------------------]]
function Inv.equip(ply, item)
    local def = C.Items[item.id]
    if not def.weapon then return false, "это не оружие" end
    if item.lock then return false, "предмет занят" end
    if item.equipped then return Inv.holster(ply, item) end
    if ply:HasWeapon(def.weapon) then return false, "такое оружие уже в руках" end
    local veto, reason = hook.Run("SiteVeil.CanEquip", ply, item)
    if veto == false then return false, reason end

    ply.SVGivingWeapon = def.weapon
    local wep = ply:Give(def.weapon, true)
    ply.SVGivingWeapon = nil
    if not IsValid(wep) then return false, "оружие недоступно на сервере" end
    wep.SVItemUid = item.uid
    if wep.SetClip1 then wep:SetClip1(item.data.clip or 0) end
    item.equipped = true
    ply:SelectWeapon(def.weapon)
    changed(ply)
    return true
end

function Inv.holster(ply, item)
    local def = C.Items[item.id]
    if not item.equipped then return true end
    local wep = ply:GetWeapon(def.weapon)
    if IsValid(wep) then
        item.data.clip = wep.Clip1 and math.max(wep:Clip1(), 0) or 0
        ply:StripWeapon(def.weapon)
    end
    item.equipped = nil
    saveItem(item)
    changed(ply)
    return true
end

local function roleTool(ply, class)
    local role = Roles.ofPlayer(ply)
    return role and U.contains(role.weapons, class)
end

function GM:PlayerCanPickupWeapon(ply, wep)
    if ply.SVGivingWeapon == wep:GetClass() or wep.SVItemUid then return true end
    if roleTool(ply, wep:GetClass()) then return true end
    if SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply) then return true end
    return false
end

-- Engine-side weapon losses (death, StripWeapons by other code) unequip items.
hook.Add("PlayerDeath", "SiteVeil.Inv.Unequip", function(ply)
    local cont = Inv.containers[ply]
    if not cont then return end
    for _, item in pairs(cont.items) do
        item.equipped = nil
    end
end)

--[[---------------------------------------------------------------------------
Role kits

Durable kit items (weapons, radio, credentials, tools) exist at most once per
character: an instance issued to the character anywhere in the database
(their own inventory, someone else's after a confiscation, storage) blocks a
new issue. Consumables are topped up to the kit amount on respawn, at most
C.Inventory.kitRefillsPerShift times per shift.
---------------------------------------------------------------------------]]
local function liveIssued(charId, itemId)
    return tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_items WHERE issued_to = ? AND item_id = ?", charId, itemId)) or 0
end

function Inv.ensureKit(ply, role)
    local char = ply.SVChar
    if not char or not Inv.containers[ply] then return end
    local refills = char.data.kitRefills
    if not refills or refills.shift ~= SV.Shift.id then
        refills = {shift = SV.Shift.id, count = 0}
        char.data.kitRefills = refills
    end
    local refillAllowed = refills.count < C.Inventory.kitRefillsPerShift
    local refilled = false

    for _, entry in ipairs(role.kit) do
        local itemId, amount = entry[1], entry[2]
        local def = C.Items[itemId]
        if def then
            if Inv.isConsumable(def) then
                local have = 0
                for _, item in pairs(Inv.containers[ply].items) do
                    if item.id == itemId and item.issuedTo == char.id then have = have + item.count end
                end
                if have < amount and (refillAllowed or not char.data.kitIssuedOnce) then
                    Inv.add(ply, itemId, amount - have, {force = true, issuedTo = char.id, kit = role.id})
                    refilled = true
                end
            elseif liveIssued(char.id, itemId) < amount then
                local suppressed = char.data.confiscated and char.data.confiscated[itemId]
                if not suppressed then
                    for _ = 1, amount - liveIssued(char.id, itemId) do
                        Inv.add(ply, itemId, 1, {force = true, issuedTo = char.id, kit = role.id})
                    end
                end
            end
        end
    end
    if refilled and char.data.kitIssuedOnce then refills.count = refills.count + 1 end
    char.data.kitIssuedOnce = true
    SV.Chars.save(char)
end

--- Removes kit items of the previous role from the character's own
--- inventory (they are returned to the division's equipment).
function Inv.returnKit(ply, oldRole, newRole)
    local char = ply.SVChar
    if not char or not oldRole then return end
    local keep = {}
    for _, entry in ipairs(newRole and newRole.kit or {}) do keep[entry[1]] = true end
    for _, item in ipairs(Inv.find(ply, function(it) return it.issuedTo == char.id and it.kit == oldRole.id end)) do
        if keep[item.id] then
            item.kit = newRole.id
            DB.query("UPDATE sv_items SET kit = ? WHERE uid = ?", newRole.id, item.uid)
        else
            Inv.removeUid(ply, item.uid)
        end
    end
    char.data.kitIssuedOnce = nil
end

hook.Add("SiteVeil.BeforeRoleChange", "SiteVeil.Inv", function(ply)
    local cont = Inv.containers[ply]
    if not cont then return end
    for _, item in pairs(cont.items) do
        if item.equipped then Inv.holster(ply, item) end
    end
    if ply:Alive() then Inv.packAmmo(ply) end
end)

hook.Add("SiteVeil.RoleAssigned", "SiteVeil.Inv", function(ply, role, oldRole)
    if oldRole and oldRole ~= role and oldRole.id ~= C.LobbyRole then Inv.returnKit(ply, oldRole, role) end
end)

hook.Add("SiteVeil.RoleSpawn", "SiteVeil.Inv", function(ply, role)
    Inv.ensureKit(ply, role)
    -- Partial magazines saved earlier go back into the reserve.
    local rem = ply.SVChar and ply.SVChar.data.ammoRemainder
    if rem then
        for ammoType, rounds in pairs(rem) do
            if rounds > 0 then ply:GiveAmmo(rounds, ammoType, true) end
        end
        ply.SVChar.data.ammoRemainder = {}
    end
end)

--[[---------------------------------------------------------------------------
Handover offers (give to another player; the receiver must accept)
---------------------------------------------------------------------------]]
function Inv.cancelOffer(id, reason)
    local offer = Inv.offers[id]
    if not offer then return end
    Inv.offers[id] = nil
    local item = IsValid(offer.from) and Inv.getItem(offer.from, offer.uid)
    if item and item.lock == id then
        item.lock = nil
        changed(offer.from)
    end
    if reason and IsValid(offer.from) then DarkRP.notify(offer.from, 1, 4, "Передача отменена: " .. reason) end
    if IsValid(offer.to) then Net.send(offer.to, "inv.offerClosed", {id = id}) end
end

function Inv.offer(from, to, uid, count)
    local item = Inv.getItem(from, uid)
    if not item then return false, "предмет не найден" end
    local def = C.Items[item.id]
    if def.noDrop then return false, "этот предмет нельзя передать" end
    if item.lock then return false, "предмет уже предлагается" end
    if not IsValid(to) or not to:IsPlayer() or to == from or not to.SVChar or not to:Alive() then return false, "некому передать" end
    if not U.within(from, to, C.Inventory.giveDistance) then return false, "подойдите ближе" end
    local veto, reason = hook.Run("SiteVeil.CanHandItems", from, to)
    if veto == false then return false, reason end

    count = math.Clamp(count, 1, item.count)
    local id = Inv.nextOffer
    Inv.nextOffer = id + 1
    Inv.offers[id] = {id = id, from = from, to = to, uid = uid, count = count, expires = CurTime() + C.Inventory.offerTimeout}
    item.lock = id
    changed(from)
    Net.send(to, "inv.offer", {id = id, from = from:EntIndex(), fromName = SV.Chars.displayName(from), item = item.id, title = item.data.title, count = count})
    return true, "Предложение отправлено: " .. SV.Chars.displayName(to)
end

function Inv.answer(ply, id, accept)
    local offer = Inv.offers[id]
    if not offer or offer.to ~= ply then return false, "предложение не найдено" end
    if not accept then
        Inv.cancelOffer(id, "получатель отказался")
        return true
    end
    if not IsValid(offer.from) or not offer.from:Alive() then
        Inv.cancelOffer(id)
        return false, "передающий недоступен"
    end
    if not U.within(offer.from, ply, C.Inventory.giveDistance + 30) then
        Inv.cancelOffer(id, "участники разошлись")
        return false, "передающий слишком далеко"
    end
    local ok, reason = Inv.transfer(offer.from, ply, offer.uid, offer.count, {lock = id, reason = "handover"})
    Inv.offers[id] = nil
    if not ok then
        local item = Inv.getItem(offer.from, offer.uid)
        if item and item.lock == id then item.lock = nil changed(offer.from) end
        return false, reason
    end
    DarkRP.notify(offer.from, 0, 4, "Предмет передан.")
    return true, "Предмет получен."
end

timer.Create("SiteVeil.Inv.Offers", 1, 0, function()
    local now = CurTime()
    for id, offer in pairs(Inv.offers) do
        if now > offer.expires then Inv.cancelOffer(id, "время ожидания истекло") end
    end
end)

--[[---------------------------------------------------------------------------
Network handlers
---------------------------------------------------------------------------]]
Net.handle("inv.use", function(ply, uid)
    local item = Inv.getItem(ply, uid)
    if not item then return false, "Предмет не найден." end
    return Inv.use(ply, item, nil)
end)

Net.handle("inv.useOn", function(ply, uid, target)
    local item = Inv.getItem(ply, uid)
    if not item then return false, "Предмет не найден." end
    if not IsValid(target) or not target:IsPlayer() then return false, "Нет цели." end
    return Inv.use(ply, item, target)
end)

Net.handle("inv.equip", function(ply, uid)
    local item = Inv.getItem(ply, uid)
    if not item then return false, "Предмет не найден." end
    return Inv.equip(ply, item)
end)

Net.handle("inv.drop", function(ply, uid, count)
    return Inv.drop(ply, uid, count)
end)

Net.handle("inv.offer", function(ply, uid, count, target)
    return Inv.offer(ply, target, uid, count)
end)

Net.handle("inv.answer", function(ply, id, accept)
    return Inv.answer(ply, id, accept)
end)

Net.handle("inv.inspect", function(ply, uid)
    local item = Inv.getItem(ply, uid)
    if not item then return false, "Предмет не найден." end
    local def = C.Items[item.id]
    Net.send(ply, "inv.inspect", {uid = uid, id = item.id, name = Inv.displayName(item), desc = def.desc, data = {
        serial = item.data.serial, expires = item.data.expires, label = item.data.label, case = item.data.case,
    }})
end)

SV.Perf.registry("inventory.containers", function() return U.count(Inv.containers) end)
SV.Perf.registry("inventory.offers", function() return U.count(Inv.offers) end)

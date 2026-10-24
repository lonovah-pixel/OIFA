--[[---------------------------------------------------------------------------
Item use handlers (server). Handlers for medical items and documents live
in their modules and register themselves with Inv.registerUse().
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Inv = SV.Inv
local C = SV.Config

Inv.useHandlers = Inv.useHandlers or {}

--- handler(ply, item, def, target) -> ok, message
function Inv.registerUse(kind, handler)
    Inv.useHandlers[kind] = handler
end

function Inv.use(ply, item, target)
    local def = C.Items[item.id]
    if item.lock then return false, "Предмет занят." end
    if def.weapon and not def.use then return Inv.equip(ply, item) end
    local handler = def.use and Inv.useHandlers[def.use]
    if not handler then return false, "Этот предмет нельзя использовать." end
    local veto, reason = hook.Run("SiteVeil.CanUseItem", ply, item, target)
    if veto == false then return false, reason end
    return handler(ply, item, def, target)
end

Inv.registerUse("armor", function(ply, item, def)
    local current = ply:Armor()
    if current >= def.armor then return false, "Текущая защита не ниже, чем у этого бронежилета." end
    ply:SetArmor(def.armor)
    Inv.removeUid(ply, item.uid, 1)
    ply:EmitSound("items/ammopickup.wav", 60)
    return true, "Бронежилет надет (защита " .. def.armor .. ")."
end)

Inv.registerUse("ammo", function(ply, item, def)
    ply:GiveAmmo(def.ammo, def.ammoType, true)
    Inv.removeUid(ply, item.uid, 1)
    ply:EmitSound("items/ammo_pickup.wav", 60)
    return true, def.name .. ": +" .. def.ammo .. " в запас."
end)

Inv.registerUse("wear", function(ply, item, def)
    if item.data.worn then
        item.data.worn = nil
        Inv.saveItem(item)
        Inv.changed(ply)
        return true, def.name .. ": снято."
    end
    for _, other in pairs(Inv.get(ply).items) do
        local odef = C.Items[other.id]
        if other ~= item and other.data.worn and odef.slot == def.slot then
            return false, "Сначала снимите: " .. odef.name .. "."
        end
    end
    item.data.worn = true
    Inv.saveItem(item)
    Inv.changed(ply)
    return true, def.name .. ": надето."
end)

--- Whether the player wears an item of this id.
function Inv.isWearing(ply, itemId)
    local cont = Inv.get(ply)
    if not cont then return false end
    for _, item in pairs(cont.items) do
        if item.id == itemId and item.data.worn then return true end
    end
    return false
end

--[[---------------------------------------------------------------------------
Inventory (shared): network schema and item helpers.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Inv = SV.Inv or {}
local Inv = SV.Inv
local Net = SV.Net
local C = SV.Config

function Inv.def(id)
    return C.Items[id]
end

function Inv.isConsumable(def)
    return def.category == "consumable" or def.category == "ammo" or def.use == "armor"
end

--- Display name of an item instance (documents show their title).
function Inv.displayName(item)
    local def = C.Items[item.id]
    if not def then return item.id end
    if item.data and item.data.title then return def.name .. ": " .. item.data.title end
    return def.name
end

Net.define("inv.use", {args = {"u32"}, alive = true, rate = {burst = 4, refill = 2}})
Net.define("inv.useOn", {args = {"u32", "ent"}, alive = true, rate = {burst = 3, refill = 1}})
Net.define("inv.equip", {args = {"u32"}, alive = true, rate = {burst = 4, refill = 2}})
Net.define("inv.drop", {args = {"u32", "u8"}, alive = true, rate = {burst = 3, refill = 1}})
Net.define("inv.offer", {args = {"u32", "u8", "ent"}, alive = true, rate = {burst = 2, refill = 0.5}})
Net.define("inv.answer", {args = {"u32", "bool"}, alive = true, rate = {burst = 3, refill = 1}})
Net.define("inv.bagTake", {args = {"ent", "u32"}, alive = true, rate = {burst = 5, refill = 3}})
Net.define("inv.inspect", {args = {"u32"}, rate = {burst = 4, refill = 2}})

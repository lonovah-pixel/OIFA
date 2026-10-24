--[[---------------------------------------------------------------------------
sv_item: one inventory item lying in the world. The item instance itself is
held server-side by modules/inventory/sv_world.lua; the entity only shows
its id and count.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Предмет"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ItemId")
    self:NetworkVar("Int", 0, "ItemCount")
end

function ENT:ItemDef()
    return SiteVeil.Config.Items[self:GetItemId()]
end

if SERVER then
    function ENT:Initialize()
        local def = self:ItemDef()
        self:SetModel(def and def.model or "models/props_junk/cardboard_box004a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        SiteVeil.Inv.pickup(activator, self)
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Item", function(ent, x, y)
        if ent:GetClass() ~= "sv_item" then return end
        local def = ent:ItemDef()
        if not def then return end
        local text = def.name .. (ent:GetItemCount() > 1 and (" ×" .. ent:GetItemCount()) or "")
        draw.SimpleText(text, "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] подобрать", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
        return true
    end)
end

--[[---------------------------------------------------------------------------
sv_item_bag: personal effects left after death (several items). Contents are
held server-side; using the bag shows them to the player.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Личные вещи"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "OwnerName")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_junk/garbage_bag001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() or not activator.SVChar then return end
        SiteVeil.Inv.openBag(activator, self)
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.ItemBag", function(ent, x, y)
        if ent:GetClass() ~= "sv_item_bag" then return end
        draw.SimpleText("Личные вещи: " .. ent:GetOwnerName(), "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] осмотреть", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
        return true
    end)
end

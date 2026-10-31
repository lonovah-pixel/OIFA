--[[---------------------------------------------------------------------------
sv_medbed: operating table (addon siteveil_surgery), map point kind "medbed".
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Операционный стол"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/furniturebed001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if IsValid(activator) and activator:IsPlayer() then SiteVeil.Net.handlers["surgery.open"](activator, self) end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Medbed", function(ent, x, y)
        if ent:GetClass() ~= "sv_medbed" then return end
        draw.SimpleText("Операционный стол", "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] врачу — операция", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
    end)
end

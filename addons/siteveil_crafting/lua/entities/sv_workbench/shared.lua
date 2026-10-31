--[[---------------------------------------------------------------------------
sv_workbench: crafting bench (addon siteveil_crafting), map point kind
"workbench" with prop bench = general | engineering | medical.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Верстак"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/FurnitureTable001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if IsValid(activator) and activator:IsPlayer() then SiteVeil.Net.handlers["craft.open"](activator, self) end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Workbench", function(ent, x, y)
        if ent:GetClass() ~= "sv_workbench" then return end
        draw.SimpleText("Верстак", "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] мастерская", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
    end)
end

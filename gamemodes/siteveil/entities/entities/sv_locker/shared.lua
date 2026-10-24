--[[---------------------------------------------------------------------------
sv_locker: equipment locker. Contents, quotas and access come from
C.Lockers[kind] (config/sh_supply.lua); stock from the owning division.
Placed by the map configuration (point kind "locker", prop "locker").
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Шкаф снаряжения"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "LockerKind")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/lockers001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        if self.SVPoint and self.SVPoint.props.locker then
            self:SetLockerKind(self.SVPoint.props.locker)
        end
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() or not activator.SVChar then return end
        if (activator.SVNextLockerUse or 0) > CurTime() then return end
        activator.SVNextLockerUse = CurTime() + 0.5
        SiteVeil.Supply.lockerView(activator, self)
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Locker", function(ent, x, y)
        if ent:GetClass() ~= "sv_locker" then return end
        local L = SiteVeil.Config.Lockers[ent:GetLockerKind()]
        draw.SimpleText(L and L.name or "Шкаф", "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] открыть", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
        return true
    end)
end

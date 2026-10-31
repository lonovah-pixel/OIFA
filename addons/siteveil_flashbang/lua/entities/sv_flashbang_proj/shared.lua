--[[---------------------------------------------------------------------------
sv_flashbang_proj: thrown flashbang (addon siteveil_flashbang).
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Светошумовая граната"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/weapons/w_grenade.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end
end

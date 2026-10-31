--[[---------------------------------------------------------------------------
sv_cctv_camera: surveillance camera (addon siteveil_cctv). Placed by the map
configuration (point kind "camera"); looks along the point's angles.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Камера наблюдения"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_combine/combinecamera001.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if SiteVeil.Cctv and SiteVeil.Cctv.register then SiteVeil.Cctv.register(self) end
    end

    function ENT:OnRemove()
        if SiteVeil.Cctv and SiteVeil.Cctv.unregister then SiteVeil.Cctv.unregister(self) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end
end

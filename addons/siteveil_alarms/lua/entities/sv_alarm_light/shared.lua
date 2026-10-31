--[[---------------------------------------------------------------------------
sv_alarm_light: alarm lamp (addon siteveil_alarms). The server sets Mode;
the client draws a flashing dynamic light and plays the siren.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Аварийная лампа"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Mode")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/light_cagelight01_on.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetMode("")
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if SiteVeil.Alarms and SiteVeil.Alarms.register then SiteVeil.Alarms.register(self) end
    end

    function ENT:OnRemove()
        if SiteVeil.Alarms and SiteVeil.Alarms.unregister then SiteVeil.Alarms.unregister(self) end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end

    function ENT:Think()
        local K = SiteVeil.Config.Alarms
        local m = K.modes[self:GetMode()]
        if m and math.floor(CurTime() / m.period) % 2 == 0 then
            local d = DynamicLight(self:EntIndex())
            if d then
                d.pos = self:GetPos()
                d.r, d.g, d.b = m.color.r, m.color.g, m.color.b
                d.brightness = 3
                d.size = K.lightSize
                d.decay = 1000
                d.dietime = CurTime() + 0.2
            end
        end
        local siren = m and m.siren
        if siren ~= self.SVSirenPath then
            if self.SVSiren then self.SVSiren:Stop() end
            self.SVSiren = siren and CreateSound(self, siren) or nil
            self.SVSirenPath = siren
            if self.SVSiren then self.SVSiren:PlayEx(GetConVar("sv_alarm_volume"):GetFloat(), 100) end
        end
        self:SetNextClientThink(CurTime() + 0.1)
        return true
    end

    function ENT:OnRemove()
        if self.SVSiren then self.SVSiren:Stop() end
    end
end

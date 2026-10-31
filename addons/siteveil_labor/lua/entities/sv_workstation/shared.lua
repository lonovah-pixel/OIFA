--[[---------------------------------------------------------------------------
sv_workstation: labor station (addon siteveil_labor), map point kind
"workstation" with prop job = sorting | assembly | cleaning.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Рабочее место"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Job")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_junk/wood_crate001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetJob(self.SVPoint and self.SVPoint.props.job or "")
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        local ok, msg = SiteVeil.Labor.start(activator, self)
        if not ok and msg then DarkRP.notify(activator, 1, 4, msg) end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Workstation", function(ent, x, y)
        if ent:GetClass() ~= "sv_workstation" then return end
        local job = SiteVeil.Config.Labor.jobs[ent:GetJob()]
        draw.SimpleText(job and job.name or "Рабочее место", "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] приступить к работе", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
    end)
end

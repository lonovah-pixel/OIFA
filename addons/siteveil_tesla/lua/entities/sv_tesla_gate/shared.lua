--[[---------------------------------------------------------------------------
sv_tesla_gate: tesla gate emitter (addon siteveil_tesla). Placed by the map
configuration (point kind "tesla"); all logic is in sv_tesla.lua.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Тесла-ворота"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Charging")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_combine/combine_emitter01.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if SiteVeil.Tesla and SiteVeil.Tesla.register then SiteVeil.Tesla.register(self) end
    end

    function ENT:OnRemove()
        if SiteVeil.Tesla and SiteVeil.Tesla.unregister then SiteVeil.Tesla.unregister(self) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.TeslaGate", function(ent, x, y)
        if ent:GetClass() ~= "sv_tesla_gate" then return end
        draw.SimpleText("Тесла-ворота", "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("Не входите без допуска", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(217, 83, 79), TEXT_ALIGN_CENTER)
    end)
end

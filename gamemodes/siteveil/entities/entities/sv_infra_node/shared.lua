--[[---------------------------------------------------------------------------
sv_infra_node: infrastructure node (power panel, comms relay, ventilation,
surveillance, door controller, generator). State lives in
modules/facility/sv_infra.lua; the entity shows an indicator colour.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Инфраструктурный узел"
ENT.Spawnable = false

local models = {
    power = "models/props_lab/powerbox01a.mdl",
    comms = "models/props_lab/reciever_cart.mdl",
    ventilation = "models/props_c17/furnitureboiler001a.mdl",
    surveillance = "models/props_lab/monitor02.mdl",
    security = "models/props_lab/powerbox02d.mdl",
    generator = "models/props_vehicles/generatortrailer01.mdl",
}

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Subsystem")
    self:NetworkVar("String", 1, "NodeName")
    self:NetworkVar("Int", 0, "Indicator") -- 0 ok, 1 degraded, 2 damaged, 3 offline
end

if SERVER then
    function ENT:Initialize()
        local p = self.SVPoint
        local sub = p and p.props.subsystem or "power"
        self:SetSubsystem(sub)
        self:SetNodeName(p and p.props.name or "Узел")
        self:SetModel(models[sub] or models.power)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Think()
        local n = SiteVeil.Facility.nodeForEntity(self)
        if n then
            local F = SiteVeil.Config.Facility
            local ind = n.health >= F.healthOk and 0 or (n.health >= F.healthDegraded and 1 or (n.health >= F.healthDamaged and 2 or 3))
            if self:GetIndicator() ~= ind then self:SetIndicator(ind) end
        end
        self:NextThink(CurTime() + 2)
        return true
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() or not activator.SVChar then return end
        if (activator.SVNextNodeUse or 0) > CurTime() then return end
        activator.SVNextNodeUse = CurTime() + 0.5
        SiteVeil.Net.handlers["infra.node"](activator, self)
    end
end

if CLIENT then
    local colors = {[0] = Color(76, 175, 122), [1] = Color(224, 176, 64), [2] = Color(217, 83, 79), [3] = Color(40, 40, 40)}
    local glow = Material("sprites/light_glow02_add")

    function ENT:Draw()
        self:DrawModel()
        local ind = self:GetIndicator()
        if ind == 3 then return end
        if ind == 2 and math.floor(CurTime() * 4) % 2 == 0 then return end
        render.SetMaterial(glow)
        render.DrawSprite(self:WorldSpaceCenter() + self:GetForward() * 12 + Vector(0, 0, 10), 14, 14, colors[ind])
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Node", function(ent, x, y)
        if ent:GetClass() ~= "sv_infra_node" then return end
        draw.SimpleText(ent:GetNodeName(), "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] осмотреть узел", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
        return true
    end)
end

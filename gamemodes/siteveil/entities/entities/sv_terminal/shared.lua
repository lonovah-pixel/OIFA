--[[---------------------------------------------------------------------------
sv_terminal: facility terminal. The kind (research, infrastructure,
security, logistics, records, medical) selects the screen registered with
SiteVeil.Facility.registerTerminal. Requires sector power and access.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Терминал"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "TerminalKind")
    self:NetworkVar("Bool", 0, "Powered")
end

if SERVER then
    function ENT:Initialize()
        local p = self.SVPoint
        self:SetTerminalKind(p and p.props.terminal or self:GetTerminalKind() or "records")
        self:SetModel("models/props_lab/monitor01b.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetPowered(true)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Think()
        local Facility = SiteVeil.Facility
        local def = Facility.terminals[self:GetTerminalKind()]
        local powered = Facility.power(Facility.sectorAt(self:GetPos())) >= (def and def.power or 0.5)
        if powered ~= self:GetPowered() then self:SetPowered(powered) end
        self:NextThink(CurTime() + 2)
        return true
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        if (activator.SVNextTerminalUse or 0) > CurTime() then return end
        activator.SVNextTerminalUse = CurTime() + 1
        SiteVeil.Terminals.use(activator, self)
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Terminal", function(ent, x, y)
        if ent:GetClass() ~= "sv_terminal" then return end
        local name = SiteVeil.MapCfg.terminalKinds[ent:GetTerminalKind()] or "Терминал"
        draw.SimpleText(name, "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        local sub = ent:GetPowered() and "[E] войти в систему" or "Нет питания"
        draw.SimpleText(sub, "SV.HUDSmall", x, y + SiteVeil.UI.S(22), ent:GetPowered() and Color(150, 160, 175) or Color(217, 83, 79), TEXT_ALIGN_CENTER)
        return true
    end)
end

--[[---------------------------------------------------------------------------
sv_containment_panel: containment control panel of one SCP (point kind
"panel", prop "scp"). Shows containment conditions and starts procedures.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Панель содержания"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ScpId")
end

if SERVER then
    function ENT:Initialize()
        if self.SVPoint and self.SVPoint.props.scp then self:SetScpId(self.SVPoint.props.scp) end
        self:SetModel("models/props_lab/workspace002.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() or not activator.SVChar then return end
        if (activator.SVNextPanelUse or 0) > CurTime() then return end
        activator.SVNextPanelUse = CurTime() + 1
        local ok, msg = SiteVeil.Net.handlers["scp.panel"](activator, self)
        if ok == false and msg then DarkRP.notify(activator, 1, 4, msg) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.ContainmentPanel", function(ent, x, y)
        if ent:GetClass() ~= "sv_containment_panel" then return end
        local st = SiteVeil.Sync.get("scp", ent:GetScpId())
        draw.SimpleText("Панель содержания " .. (st and st.name or ent:GetScpId()), "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        if st then
            draw.SimpleText(SiteVeil.SCP.stageName(st.stage) .. (st.breached and " · ОБЪЕКТ ВНЕ КАМЕРЫ" or ""), "SV.HUDSmall", x, y + SiteVeil.UI.S(22),
                st.breached and Color(217, 83, 79) or Color(150, 160, 175), TEXT_ALIGN_CENTER)
        end
        return true
    end)
end

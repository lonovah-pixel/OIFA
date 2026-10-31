--[[---------------------------------------------------------------------------
sv_notice_board: notice board (addon siteveil_notes), map point kind
"board" with optional props name and division.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Доска объявлений"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/paper01.mdl")
        self:SetModelScale(4, 0)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        if SiteVeil.Notes and SiteVeil.Notes.registerBoard then SiteVeil.Notes.registerBoard(self) end
    end

    function ENT:OnRemove()
        if SiteVeil.Notes and SiteVeil.Notes.unregisterBoard then SiteVeil.Notes.unregisterBoard(self) end
    end

    function ENT:Use(activator)
        if IsValid(activator) and activator:IsPlayer() then SiteVeil.Net.handlers["board.view"](activator, self) end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.NoticeBoard", function(ent, x, y)
        if ent:GetClass() ~= "sv_notice_board" then return end
        draw.SimpleText("Доска объявлений", "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] читать", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
    end)
end

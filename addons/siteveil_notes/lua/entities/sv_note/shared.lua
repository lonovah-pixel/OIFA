--[[---------------------------------------------------------------------------
sv_note: a paper note left by a player (addon siteveil_notes). The text is
sent only on reading (E); the entity networks just its title.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Записка"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "NoteTitle")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/paper01.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    end

    function ENT:Use(activator)
        if IsValid(activator) and activator:IsPlayer() then SiteVeil.Net.handlers["notes.read"](activator, self) end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Note", function(ent, x, y)
        if ent:GetClass() ~= "sv_note" then return end
        draw.SimpleText(ent:GetNoteTitle(), "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] прочитать", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
    end)
end

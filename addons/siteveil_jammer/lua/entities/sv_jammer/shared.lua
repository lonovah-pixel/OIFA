--[[---------------------------------------------------------------------------
sv_jammer: active radio jammer (addon siteveil_jammer).
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Глушилка"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_lab/reciever01b.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:EmitSound("ambient/levels/labs/electric_explosion1.wav", 60)
    end

    function ENT:Use(activator)
        if IsValid(activator) and activator:IsPlayer() then
            local ok, msg = SiteVeil.Net.handlers["jammer.disarm"](activator, self)
            if not ok and msg then DarkRP.notify(activator, 1, 3, msg) end
        end
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Jammer", function(ent, x, y)
        if ent:GetClass() ~= "sv_jammer" then return end
        draw.SimpleText("Подозрительное устройство", "SV.HUD", x, y, Color(217, 83, 79), TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] отключить", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
    end)
end

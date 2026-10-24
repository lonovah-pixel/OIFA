--[[---------------------------------------------------------------------------
sv_supply_crate: delivered supply request waiting to be unpacked at the
logistics point. Unpacking books the contents into the division's stock.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Поставка"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Division")
    self:NetworkVar("Int", 0, "RequestId")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/items/item_item_crate.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        local ok, msg = SiteVeil.Supply.unpackCrate(activator, self)
        if not ok and msg then DarkRP.notify(activator, 1, 4, msg) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end

    hook.Add("SiteVeil.HUDLookAt", "SiteVeil.Crate", function(ent, x, y)
        if ent:GetClass() ~= "sv_supply_crate" then return end
        local div = SiteVeil.Roles.getDivision(ent:GetDivision())
        draw.SimpleText("Поставка #" .. ent:GetRequestId() .. (div and (" · " .. div.name) or ""), "SV.HUD", x, y, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] разобрать", "SV.HUDSmall", x, y + SiteVeil.UI.S(22), Color(150, 160, 175), TEXT_ALIGN_CENTER)
        return true
    end)
end

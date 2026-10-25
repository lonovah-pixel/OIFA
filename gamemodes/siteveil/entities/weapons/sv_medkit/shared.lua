--[[---------------------------------------------------------------------------
sv_medkit: medical bag of the medical service.
  ЛКМ — помощь пациенту (по взгляду), ПКМ — осмотр, R — помощь себе.
Treatment items are taken from the inventory (modules/medical).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Медицинская сумка"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — помощь, ПКМ — осмотр, R — помощь себе"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 1
SWEP.DrawAmmo = false
SWEP.ViewModel = "models/weapons/c_medkit.mdl"
SWEP.WorldModel = "models/weapons/w_medkit.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

local function lookTarget(self)
    local owner = self:GetOwner()
    local tr = owner:GetEyeTrace()
    if IsValid(tr.Entity) and tr.Entity:IsPlayer() and tr.StartPos:DistToSqr(tr.HitPos) < 100 * 100 then return tr.Entity end
    return nil
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.6)
    if not CLIENT or not IsFirstTimePredicted() then return end
    local t = lookTarget(self)
    if t then SiteVeil.UI.openTreatment(t) else SiteVeil.UI.notify("Наведитесь на пациента или нажмите R для помощи себе.", 3) end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.6)
    if not CLIENT or not IsFirstTimePredicted() then return end
    SiteVeil.Net.call("med.examine", lookTarget(self) or self:GetOwner())
end

function SWEP:Reload()
    if not CLIENT or not IsFirstTimePredicted() or (self.NextReload or 0) > CurTime() then return end
    self.NextReload = CurTime() + 0.8
    SiteVeil.UI.openTreatment(self:GetOwner())
end

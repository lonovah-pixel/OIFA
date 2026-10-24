--[[---------------------------------------------------------------------------
sv_mapper: map configuration tool for superadmins on duty.
  ЛКМ   — угол 1 объёма (по взгляду)
  ПКМ   — угол 2 объёма
  R     — открыть редактор карты
While held, configured zones, points and doors are drawn in the world.
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Настройка карты"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ/ПКМ — углы объёма, R — редактор"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 5
SWEP.DrawAmmo = false
SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    if CLIENT and IsFirstTimePredicted() then SiteVeil.Net.call("mapcfg.corner", 1) end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if CLIENT and IsFirstTimePredicted() then SiteVeil.Net.call("mapcfg.corner", 2) end
end

function SWEP:Reload()
    if CLIENT and IsFirstTimePredicted() and (self.NextOpen or 0) < CurTime() then
        self.NextOpen = CurTime() + 1
        SiteVeil.UI.openMapEditor()
    end
end

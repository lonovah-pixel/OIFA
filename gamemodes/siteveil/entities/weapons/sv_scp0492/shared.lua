--[[---------------------------------------------------------------------------
sv_scp0492: abilities of the SCP-049-2 player.
  ЛКМ — удар
Validation happens on the server (modules/scp/sv_scp049.lua).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "SCP-049-2"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — удар"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = ""
SWEP.WorldModel = ""
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.4)
    if not SERVER then return end
    local owner = self:GetOwner()
    if IsValid(owner) then SiteVeil.SCP.S049.zombieAttack(owner) end
end

function SWEP:SecondaryAttack() end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

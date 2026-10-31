--[[---------------------------------------------------------------------------
sv_flashbang: thrown from the inventory item (addon siteveil_flashbang).
  ЛКМ — бросить. Validation: sv_flashbang.lua.
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Светошумовая граната"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — бросить"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.DrawAmmo = false
SWEP.ViewModel = "models/weapons/c_grenade.mdl"
SWEP.WorldModel = "models/weapons/w_grenade.mdl"
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
    self:SetNextPrimaryFire(CurTime() + 1)
    if not SERVER then return end
    local owner = self:GetOwner()
    if IsValid(owner) and SiteVeil.Flash then SiteVeil.Flash.throw(owner) end
end

function SWEP:SecondaryAttack() end

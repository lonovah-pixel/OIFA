--[[---------------------------------------------------------------------------
sv_scp999: abilities of the SCP-999 player (addon siteveil_scp999).
  ЛКМ — обнять, ПКМ — успокоение. Validation: sv_scp999.lua.
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "SCP-999"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — обнять, ПКМ — успокоение"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = ""
SWEP.WorldModel = ""
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local function ability(self, name)
    if not SERVER then return end
    local SCP = SiteVeil.SCP
    local owner = self:GetOwner()
    if not IsValid(owner) or SCP.of(owner) ~= "scp999" then return end
    SCP.defs.scp999.abilities[name](owner, SCP.state.scp999)
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    ability(self, "hug")
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    ability(self, "calm")
end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

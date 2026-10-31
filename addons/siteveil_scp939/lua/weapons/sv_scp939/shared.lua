--[[---------------------------------------------------------------------------
sv_scp939: abilities of the SCP-939 player (addon siteveil_scp939).
  ЛКМ — атака, ПКМ — голос-приманка. Validation: sv_scp939.lua.
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "SCP-939"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — атака, ПКМ — голос-приманка"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.DrawAmmo = false
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

local function ability(self, name)
    if not SERVER then return end
    local SCP = SiteVeil.SCP
    local owner = self:GetOwner()
    if not IsValid(owner) or SCP.of(owner) ~= "scp939" then return end
    SCP.defs.scp939.abilities[name](owner, SCP.state.scp939)
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.4)
    ability(self, "attack")
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    ability(self, "lure")
end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

--[[---------------------------------------------------------------------------
sv_scp096: abilities of the SCP-096 player.
  ЛКМ — атака цели (в ярости), ПКМ — взлом двери (в ярости),
  R   — сорвать мешок (при нарушении содержания)
Validation happens on the server (modules/scp/sv_scp096.lua).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "SCP-096"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — атака, ПКМ — дверь, R — сорвать мешок"
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

local function ability(self, name)
    if not SERVER then return end
    local SCP = SiteVeil.SCP
    local owner = self:GetOwner()
    if not IsValid(owner) or SCP.of(owner) ~= "scp096" then return end
    local fn = SCP.defs.scp096.abilities[name]
    if fn then fn(owner, SCP.state.scp096) end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    ability(self, "attack")
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    ability(self, "breakDoor")
end

function SWEP:Reload()
    if (self.NextReload or 0) > CurTime() then return end
    self.NextReload = CurTime() + 1
    ability(self, "tearBag")
end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

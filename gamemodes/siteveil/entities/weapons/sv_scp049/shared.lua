--[[---------------------------------------------------------------------------
sv_scp049: abilities of the SCP-049 player.
  ЛКМ — прикосновение / «лечение» недееспособного или тяжело заражённого
Validation happens on the server (modules/scp/sv_scp049.lua).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "SCP-049"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — прикосновение / «лечение»"
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
    if not IsValid(owner) or SCP.of(owner) ~= "scp049" then return end
    local fn = SCP.defs.scp049.abilities[name]
    if fn then fn(owner, SCP.state.scp049) end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.6)
    ability(self, "touch")
end

function SWEP:SecondaryAttack() end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

--[[---------------------------------------------------------------------------
sv_scp106: abilities of the SCP-106 player.
  ЛКМ — касание (карманное измерение), ПКМ — пройти сквозь дверь,
  R   — перемещение к точке выхода (вне камеры)
Validation happens on the server (modules/scp/sv_scp106.lua).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "SCP-106"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — касание, ПКМ — сквозь дверь, R — перемещение"
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
    if not IsValid(owner) or SCP.of(owner) ~= "scp106" then return end
    local fn = SCP.defs.scp106.abilities[name]
    if fn then fn(owner, SCP.state.scp106) end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    ability(self, "attack")
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    ability(self, "phase")
end

function SWEP:Reload()
    if (self.NextReload or 0) > CurTime() then return end
    self.NextReload = CurTime() + 1
    ability(self, "travel")
end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

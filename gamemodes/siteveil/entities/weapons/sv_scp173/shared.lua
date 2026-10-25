--[[---------------------------------------------------------------------------
sv_scp173: abilities of the SCP-173 player.
  ЛКМ — атака (только вне наблюдения), ПКМ — взлом двери / проверка камеры,
  R   — «Затемнение»
Validation happens on the server (modules/scp/sv_scp173.lua).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "SCP-173"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — атака, ПКМ — дверь/камера, R — затемнение"
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
    local def = SCP.defs.scp173
    local owner = self:GetOwner()
    if not IsValid(owner) or SCP.of(owner) ~= "scp173" then return end
    def.abilities[name](owner, SCP.state.scp173)
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.2)
    ability(self, "attack")
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    if not SERVER then return end
    local owner = self:GetOwner()
    local tr = owner:GetEyeTrace()
    local c = IsValid(tr.Entity) and tr.Entity:GetClass() or ""
    if (c == "prop_door_rotating" or c == "func_door" or c == "func_door_rotating") and tr.StartPos:DistToSqr(tr.HitPos) < 110 * 110 then
        ability(self, "breakDoor")
    else
        ability(self, "probe")
    end
end

function SWEP:Reload()
    if (self.NextReload or 0) > CurTime() then return end
    self.NextReload = CurTime() + 1
    ability(self, "blackout")
end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

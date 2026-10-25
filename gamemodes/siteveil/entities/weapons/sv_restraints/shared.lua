--[[---------------------------------------------------------------------------
sv_restraints: handcuffs.
  ЛКМ — надеть наручники (3 с; мгновенно, если цель сдалась или без сознания)
  ПКМ — снять наручники, R — вести / отпустить
All checks are server-side (modules/security).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Наручники"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — надеть, ПКМ — снять, R — вести"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 1
SWEP.DrawAmmo = false
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.HoldType = "normal"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local function target(self)
    local tr = self:GetOwner():GetEyeTrace()
    if IsValid(tr.Entity) and tr.Entity:IsPlayer() and tr.StartPos:DistToSqr(tr.HitPos) < 100 * 100 then return tr.Entity end
end

function SWEP:Initialize() self:SetHoldType(self.HoldType) end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1)
    if CLIENT and IsFirstTimePredicted() then
        local t = target(self)
        if t then SiteVeil.Net.call("sec.restrain", t) end
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    if CLIENT and IsFirstTimePredicted() then
        local t = target(self)
        if t then SiteVeil.Net.call("sec.release", t) end
    end
end

function SWEP:Reload()
    if CLIENT and IsFirstTimePredicted() and (self.NextR or 0) < CurTime() then
        self.NextR = CurTime() + 0.8
        local t = target(self)
        if t then SiteVeil.Net.call("sec.escort", t) end
    end
end

function SWEP:DrawWorldModel() end
function SWEP:PreDrawViewModel() return true end

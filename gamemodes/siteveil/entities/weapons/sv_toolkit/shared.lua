--[[---------------------------------------------------------------------------
sv_toolkit: engineering tool kit.
  ЛКМ по узлу      — панель узла (диагностика, ремонт, обход, заправка)
  ПКМ по двери     — ручной привод обесточенной двери
All actions are validated on the server (modules/facility, modules/access).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Инструмент техника"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ по узлу — работа с узлом, ПКМ по двери — ручной привод"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 1
SWEP.DrawAmmo = false
SWEP.ViewModel = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/props_c17/tools_wrench01a.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

local function target(self)
    local owner = self:GetOwner()
    if not IsValid(owner) then return nil end
    local tr = owner:GetEyeTrace()
    if not IsValid(tr.Entity) or tr.StartPos:DistToSqr(tr.HitPos) > 120 * 120 then return nil end
    return tr.Entity
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    if not CLIENT or not IsFirstTimePredicted() then return end
    local ent = target(self)
    if IsValid(ent) and ent:GetClass() == "sv_infra_node" then
        SiteVeil.Net.call("infra.node", ent)
    elseif SiteVeil.UI then
        SiteVeil.UI.notify("Наведитесь на инфраструктурный узел.", 3)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.5)
    if not CLIENT or not IsFirstTimePredicted() then return end
    local ent = target(self)
    if IsValid(ent) then SiteVeil.Net.call("access.crank", ent) end
end

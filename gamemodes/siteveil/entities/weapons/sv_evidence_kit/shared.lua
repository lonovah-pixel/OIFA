--[[---------------------------------------------------------------------------
sv_evidence_kit: набор криминалиста.
  ЛКМ — осмотр места (следы в радиусе, приблизительный возраст)
  ПКМ — собрать след, на который вы смотрите
Server validation: modules/evidence/sv_evidence.lua.
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Набор криминалиста"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — осмотр места, ПКМ — собрать след"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = ""
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
    if CLIENT and IsFirstTimePredicted() then SiteVeil.Net.call("evidence.scan") end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    if not CLIENT or not IsFirstTimePredicted() then return end
    local t = SiteVeil.Evidence.traceInSight()
    if t then
        SiteVeil.Net.call("evidence.collect", t.id)
    else
        SiteVeil.UI.notify("Сначала осмотрите место (ЛКМ) и наведитесь на след.", 1)
    end
end

function SWEP:DrawWorldModel() end

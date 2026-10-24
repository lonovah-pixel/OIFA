--[[---------------------------------------------------------------------------
sv_hands: empty hands. Every role carries it so that "no weapon" is an
explicit, safe state (holstered). Interactions use the E key on entities;
right click on a player opens the interaction menu (modules/ui).
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Руки"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ПКМ по игроку — меню взаимодействия"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
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

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.5)
    if CLIENT and IsFirstTimePredicted() then
        local ent = self:GetOwner():GetEyeTrace().Entity
        if IsValid(ent) and ent:IsPlayer() and SiteVeil.UI and SiteVeil.UI.openInteraction then
            SiteVeil.UI.openInteraction(ent)
        end
    end
end

function SWEP:Reload()
end

function SWEP:DrawWorldModel()
end

function SWEP:PreDrawViewModel()
    return true
end

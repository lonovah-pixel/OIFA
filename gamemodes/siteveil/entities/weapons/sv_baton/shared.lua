--[[---------------------------------------------------------------------------
sv_baton: non-lethal baton. A few hits in a short time knock the target out
for a limited time (modules/medical Medical.stunHit). No effect on SCPs.
---------------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Дубинка"
SWEP.Author = "SITE-VEIL"
SWEP.Instructions = "ЛКМ — удар (оглушение после нескольких ударов)"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 1
SWEP.DrawAmmo = false
SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.UseHands = true
SWEP.HoldType = "melee"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize() self:SetHoldType(self.HoldType) end

function SWEP:PrimaryAttack()
    local cfg = SiteVeil.Config.Security
    self:SetNextPrimaryFire(CurTime() + cfg.batonCooldown)
    local owner = self:GetOwner()
    owner:SetAnimation(PLAYER_ATTACK1)
    self:SendWeaponAnim(ACT_VM_HITCENTER)
    self:EmitSound("Weapon_StunStick.Swing")
    if not SERVER then return end
    owner:LagCompensation(true)
    local tr = util.TraceHull({start = owner:GetShootPos(), endpos = owner:GetShootPos() + owner:GetAimVector() * 70,
        filter = owner, mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), mask = MASK_SHOT_HULL})
    owner:LagCompensation(false)
    local ent = tr.Entity
    if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end
    if SiteVeil.Roles.isSCP(ent) then return end
    self:EmitSound("Weapon_StunStick.Melee_Hit")
    local d = DamageInfo()
    d:SetDamage(cfg.batonDamage)
    d:SetDamageType(DMG_CLUB)
    d:SetAttacker(owner)
    d:SetInflictor(self)
    ent:TakeDamageInfo(d)
    SiteVeil.Medical.stunHit(ent, owner)
end

function SWEP:SecondaryAttack() return false end

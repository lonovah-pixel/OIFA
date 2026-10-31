--[[---------------------------------------------------------------------------
Flashbang (server). Throwing takes one grenade from the inventory; the
detonation blinds people in line of sight (SCP.blind) for blindMin..blindMax
seconds by distance and facing, deafens them and leaves a trace. Blinded
people neither hold SCP-173 nor see SCP-096's face - a tactical choice with
consequences for both sides. SCP-173 itself is not affected.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Flash = SV.Flash or {}
local Flash = SV.Flash
local Inv = SV.Inv
local K = SV.Config.Flashbang

function Flash.detonate(pos, by)
    local hit = {}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and SV.SCP.of(p) ~= "scp173" then
            local eye = p:EyePos()
            local dist = eye:Distance(pos)
            if dist <= K.radius and not util.TraceLine({start = pos, endpos = eye, filter = p, mask = MASK_OPAQUE}).Hit then
                local dir = pos - eye
                dir:Normalize()
                local factor = 1 - dist / K.radius
                if p:GetAimVector():Dot(dir) < K.facingDot then factor = factor * 0.5 end
                local seconds = K.blindMin + (K.blindMax - K.blindMin) * factor
                SV.SCP.blind(p, seconds)
                p:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 255), 0.6, seconds)
                p:SetDSP(35, false)
                SV.Net.send(p, "flash.effect", {duration = seconds})
                hit[#hit + 1] = p
            end
        end
    end
    sound.Play("weapons/flashbang/flashbang_explode2.wav", pos, 100)
    if SV.Evidence then
        SV.Evidence.addTrace("flash", pos, {attacker = IsValid(by) and by.SVChar and {char = by.SVChar.id, name = by.SVChar.name, division = by.SVChar.division} or nil})
    end
    SV.Audit.log("flashbang", "detonate", IsValid(by) and by or nil, nil, {hit = #hit})
    SV.Bus.emit("flash.detonated", {ply = by, pos = pos, hit = hit})
    return hit
end

--- Throws the grenade held by ply (the equipped inventory item).
function Flash.throw(ply)
    if (ply.SVFlashNext or -1e9) > CurTime() then return false end
    local wep = ply:GetActiveWeapon()
    local item = IsValid(wep) and wep.SVItemUid and Inv.getItem(ply, wep.SVItemUid)
    if not item or item.id ~= "flashbang" then return false end
    ply.SVFlashNext = CurTime() + K.cooldown
    Inv.removeUid(ply, item.uid, 1)
    local rest = Inv.getItem(ply, item.uid)
    if rest then Inv.equip(ply, rest) end
    local ent = ents.Create("sv_flashbang_proj")
    if not IsValid(ent) then return false end
    ent:SetPos(ply:EyePos() + ply:GetAimVector() * 24)
    ent:Spawn()
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:SetVelocity(ply:GetAimVector() * K.throwSpeed) end
    ent.SVThrower = ply
    timer.Simple(K.fuse, function()
        if not IsValid(ent) then return end
        Flash.detonate(ent:GetPos(), ent.SVThrower)
        ent:Remove()
    end)
    SV.Audit.log("flashbang", "throw", ply)
    return true
end

--[[---------------------------------------------------------------------------
Security (shared): network schema and state helpers.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Security = SV.Security or {}
local Security = SV.Security
local Net = SV.Net

function Security.isRestrained(ply)
    return ply:GetNW2Bool("sv_cuffed", false)
end

function Security.escortOf(ply)
    return ply:GetNW2Entity("sv_escort")
end

-- Escort movement runs in the shared SetupMove so that client prediction
-- agrees: the escorted player is pulled towards the escort.
hook.Add("SetupMove", "SiteVeil.Security.Escort", function(ply, mv)
    local escort = ply:GetNW2Entity("sv_escort")
    if not IsValid(escort) then return end
    local target = escort:GetPos() - escort:GetForward() * 40
    local delta = target - ply:GetPos()
    delta.z = 0
    local dist = delta:Length()
    if dist < 30 then
        mv:SetVelocity(Vector(0, 0, mv:GetVelocity().z))
        return
    end
    local speed = math.min(dist * 3, 260)
    local vel = delta:GetNormalized() * speed
    vel.z = mv:GetVelocity().z
    mv:SetVelocity(vel)
end)

Net.define("sec.restrain", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.5}})
Net.define("sec.release", {args = {"ent"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("sec.escort", {args = {"ent"}, alive = true, rate = {burst = 4, refill = 1}})
Net.define("sec.search", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.3}})
Net.define("sec.confiscate", {args = {"ent", "u32", "str:120"}, alive = true, rate = {burst = 6, refill = 2}})
Net.define("sec.detain", {args = {"ent", "u8", "str:200"}, alive = true, rate = {burst = 2, refill = 0.2}})
Net.define("sec.unDetain", {args = {"ent", "str:200"}, alive = true, rate = {burst = 2, refill = 0.2}})
Net.define("sec.checkId", {args = {"ent"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("sec.struggle", {args = {}, alive = true, ignoreStates = true, rate = {burst = 1, refill = 0.1}})
Net.define("sec.surrender", {args = {}, alive = true, rate = {burst = 2, refill = 0.5}})
Net.define("sec.detentions", {args = {}, rate = {burst = 2, refill = 0.3}})

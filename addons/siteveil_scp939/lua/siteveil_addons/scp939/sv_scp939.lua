--[[---------------------------------------------------------------------------
SCP-939 (server).

The object is blind: its client darkens the screen and draws only noises the
server sends to it (positions rounded, last noiseLife seconds, within
hearRange): speech and yelling (comms.said), gunfire, running. It attacks
what it reaches, and "lures" by playing a recorded human voice at a point it
looks at. Counterplay: silence and walking; sustained fire suppresses it,
then a recapture action returns it to the cell.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SCP = SV.SCP
local U = SV.Util
local K = SV.Config.SCP.scp939
local Roles = SV.Roles
local Facility = SV.Facility
local Move = SV.Move

local ID = "scp939"
local S939 = {noises = {}}
SCP.S939 = S939

--- Records a noise made by ply (weight = loudness).
function S939.noise(ply, weight)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or Roles.isSCP(ply) then return end
    local n = S939.noises[ply]
    if not n then
        n = {}
        S939.noises[ply] = n
    end
    n.at = CurTime()
    n.pos = ply:GetPos()
    n.weight = math.max(n.weight or 0, weight)
    local st = SCP.get(ID)
    if st and SCP.inCell(ID, ply:GetPos()) then st.data.noiseAt = CurTime() end
end

SV.Bus.on("comms.said", "scp939", function(data)
    local dist = data.dist or 0
    S939.noise(data.ply, dist >= SV.Config.Chat.yellDistance and K.yellNoise or K.talkNoise)
end)
hook.Add("EntityFireBullets", "SiteVeil.SCP939", function(ent)
    if IsValid(ent) and ent:IsPlayer() then S939.noise(ent, K.shotNoise) end
end)

local function suppressed(st)
    return st.data.suppressedUntil ~= nil and CurTime() < st.data.suppressedUntil
end

--- What 939 hears now: list of {pos, weight}.
function S939.heard(scp)
    local now, out = CurTime(), {}
    local r2 = K.hearRange * K.hearRange
    for ply, n in pairs(S939.noises) do
        if not IsValid(ply) or now - n.at > K.noiseLife then
            S939.noises[ply] = nil
        elseif n.pos:DistToSqr(scp:GetPos()) <= r2 then
            out[#out + 1] = {pos = {math.Round(n.pos.x, -1), math.Round(n.pos.y, -1), math.Round(n.pos.z, -1)}, weight = n.weight,
                age = math.Round(now - n.at, 1)}
        end
    end
    return out
end

local nextPush = 0
timer.Create("SiteVeil.SCP939", 0.25, 0, function()
    -- Running is audible.
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p.SVChar and not Roles.isSCP(p) and p:GetVelocity():Length2D() > K.runSpeed then S939.noise(p, K.runNoise) end
    end
    local scp = SCP.playerOf(ID)
    if scp and CurTime() >= nextPush then
        nextPush = CurTime() + K.pushInterval
        SV.Net.send(scp, "scp939.heard", {list = S939.heard(scp)})
    end
end)

local abilities = {}

abilities.attack = function(ply, st)
    local now = CurTime()
    if suppressed(st) or (st.nextAttack or 0) > now then return false end
    local target = SCP.frontTarget(ply, K.attackRange)
    if not SCP.validVictim(target) then return false end
    if not st.breached and not SCP.inCell(ID, target:GetPos()) then return false end
    st.nextAttack = now + K.attackCooldown
    target:EmitSound("npc/antlion_guard/shove1.wav", 80)
    SCP.harm(ply, target, ID)
    return true
end

abilities.lure = function(ply, st)
    local now = CurTime()
    if (st.nextLure or 0) > now then
        DarkRP.notify(ply, 1, 3, "Голос будет доступен через " .. math.ceil(st.nextLure - now) .. " с.")
        return false
    end
    local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * K.lureRange, filter = ply, mask = MASK_SOLID_BRUSHONLY})
    st.nextLure = now + K.lureCooldown
    local snd = K.lureSounds[math.random(#K.lureSounds)]
    sound.Play(snd, tr.HitPos, 75, 100)
    SV.Audit.log("scp", "939.lure", ply)
    SV.Bus.emit("scp939.lure", {ply = ply, pos = tr.HitPos})
    return true
end

local function recapture(ply, target, st)
    if not (Roles.hasFlag(ply, "recontain") or Roles.hasFlag(ply, "canDetain") or SV.Admin.isOnDuty(ply)) then return false, "Повторное содержание проводят МОГ и охрана." end
    if not suppressed(st) then return false, "Объект не подавлен: сначала ослабьте его огнём." end
    if not U.within(ply, target, 150) then return false, "Подойдите к объекту." end
    return SV.Actions.start(ply, {
        id = "recapture939", label = "Конвоирование SCP-939", duration = K.recaptureTime, target = target, maxDist = 170,
        canContinue = function()
            st.data.suppressedUntil = math.max(st.data.suppressedUntil or 0, CurTime() + 2)
            return st.breached, "объект уже в камере"
        end,
        onComplete = function(p) SCP.recontain(ID, p, "escort") end,
    })
end

SCP.register(ID, {
    name = "SCP-939", role = "scp939", regen = 1,
    setup = function(st) st.data.noiseAt = st.data.noiseAt or -1e9 end,
    conditions = {
        {id = "quiet", name = "Акустическая изоляция", eval = function(st)
            if CurTime() - (st.data.noiseAt or -1e9) > K.quietOk then return "ok", 0, "тихо" end
            return "warn", -3, "у камеры шумели"
        end},
        {id = "power", name = "Питание замков", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "containment") then return "ok", 0, "норма" end
            return "bad", -8, "замки обесточены"
        end},
    },
    procedures = {
        {id = "inspection", name = "Тихий осмотр камеры", desc = "Проверка замков без разговоров у камеры.", duration = 10, cooldown = 120, xp = 5,
            effect = function() SCP.adjustIntegrity(ID, 3, "inspection") end},
    },
    abilities = abilities,
    recapture = recapture,
    onSpawn = function(st, ply)
        ply:SetRunSpeed(260)
        ply:SetWalkSpeed(140)
        ply:SetColor(Color(150, 40, 40))
        st.data.suppressedUntil = nil
    end,
    onLeave = function(_, ply) if IsValid(ply) then ply:SetColor(Color(255, 255, 255)) Move.clear(ply, "939supp") end end,
    onDamage = function(st, ply, dmg)
        if ply:Health() - dmg:GetDamage() <= ply:GetMaxHealth() * K.suppressHealth and not suppressed(st) then
            st.data.suppressedUntil = CurTime() + K.suppressTime
            Move.set(ply, "939supp", {speed = 0.4, noattack = true})
            DarkRP.notify(ply, 1, K.suppressTime, "Вы подавлены огнём.")
            timer.Create("SiteVeil.SCP939.Supp", K.suppressTime, 1, function()
                if IsValid(ply) and not suppressed(st) then Move.clear(ply, "939supp") end
            end)
        end
    end,
    onRecontain = function(st, ply)
        st.data.suppressedUntil = nil
        if IsValid(ply) then
            Move.clear(ply, "939supp")
            ply:SetHealth(ply:GetMaxHealth())
        end
    end,
    publicData = function(st) return {suppressed = suppressed(st)} end,
})

hook.Add("PlayerDisconnected", "SiteVeil.SCP939", function(ply) S939.noises[ply] = nil end)

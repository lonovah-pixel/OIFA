--[[---------------------------------------------------------------------------
SCP-106 (server).

Touch: corrosion damage and transfer into the pocket dimension. The pocket is
a map zone of kind "pocket"; victims leave it through "pocket_exit" points or
are expelled automatically after C.SCP.scp106.pocketMax seconds, so nobody
can be stuck there. Without a pocket zone on the map the transfer is
simulated (blindness and corrosion, then expulsion). Every destination is
validated (inside the world, free hull); a rejected destination falls back
to the victim's role spawn.

Phasing: 106 passes through a door in front of it; the position behind the
door is validated, otherwise the ability is refused.

Recontainment: the "lure" procedure (sound recording, optional lure cell),
sustained fire (106 retreats into its cell below 20% health).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SCP = SV.SCP
local U = SV.Util
local C = SV.Config
local K = C.SCP.scp106
local Roles = SV.Roles
local Facility = SV.Facility
local Move = SV.Move
local MapCfg = SV.MapCfg

local ID = "scp106"
local S106 = {}
SCP.S106 = S106

S106.pocket = S106.pocket or {} -- victim -> {since, untilTime, fallback, nextDamage}

--[[---------------------------------------------------------------------------
Pocket dimension
---------------------------------------------------------------------------]]
local function pocketZone()
    return MapCfg.zones("pocket")[1]
end

local function zoneCenter(z)
    local b = z.boxes[1]
    return Vector((b.min[1] + b.max[1]) / 2, (b.min[2] + b.max[2]) / 2, b.min[3] + 8)
end

function S106.inPocket(ply)
    return S106.pocket[ply] ~= nil
end

local function exitDestination()
    local points = MapCfg.points("emergence")
    if #points > 0 then return MapCfg.toVec(points[math.random(#points)].pos) end
    return nil
end

--- Removes the victim from the pocket and places them in the facility.
function S106.expel(ply, reason)
    local p = S106.pocket[ply]
    if not p then return end
    S106.pocket[ply] = nil
    if not IsValid(ply) then return end
    Move.clear(ply, "pocket")
    SV.Sync.setFor(ply, "self", "pocket", nil)
    if ply:Alive() then
        SCP.teleport(ply, exitDestination())
        ply:ScreenFade(SCREENFADE.IN, Color(20, 10, 0, 240), 1.5, 0)
        DarkRP.notify(ply, 0, 6, reason == "exit" and "Вы нашли выход из карманного измерения." or "Карманное измерение выбросило вас обратно.")
    end
    SV.Audit.log("scp", "pocket.leave", ply, nil, {reason = reason})
    SV.Bus.emit("scp106.pocketLeft", {ply = ply, reason = reason})
end

--- Sends a human into the pocket dimension. by may be nil (experiments).
function S106.sendToPocket(victim, by)
    if not IsValid(victim) or not victim:IsPlayer() or not victim:Alive() or not victim.SVChar or Roles.isSCP(victim) then return false end
    if S106.pocket[victim] then return false end
    local d = DamageInfo()
    d:SetDamage(K.corrosionDamage)
    d:SetDamageType(DMG_ACID)
    d:SetAttacker(IsValid(by) and by or game.GetWorld())
    d:SetInflictor(IsValid(by) and by or game.GetWorld())
    victim:TakeDamageInfo(d)
    -- A victim who collapsed from the touch stays where they fell.
    if not victim:Alive() or SV.Medical.isIncapacitated(victim) then return false end

    local zone = pocketZone()
    local now = CurTime()
    local entry = {since = now, nextDamage = now + K.pocketTick, by = by}
    if zone then
        local hasExits = #MapCfg.points("pocket_exit") > 0
        entry.untilTime = now + (hasExits and K.pocketMax or K.pocketNoExit)
        if not SCP.teleport(victim, zoneCenter(zone)) then
            -- The pocket position itself is unusable: simulate instead.
            entry.fallback = true
            entry.untilTime = now + K.pocketFallback
        end
        entry.zone = zone.id
    else
        entry.fallback = true
        entry.untilTime = now + K.pocketFallback
    end
    if entry.fallback then
        Move.set(victim, "pocket", {frozen = true, noattack = true, nouse = true})
        victim:ScreenFade(SCREENFADE.OUT, Color(20, 10, 0, 250), 0.4, K.pocketFallback)
    end
    S106.pocket[victim] = entry
    SV.Sync.setFor(victim, "self", "pocket", {untilTime = entry.untilTime, fallback = entry.fallback or false})
    victim:EmitSound("npc/zombie/zombie_pain" .. math.random(1, 6) .. ".wav", 75, 70)
    DarkRP.notify(victim, 1, 8, entry.fallback and "Вас затянуло во тьму. Сопротивляйтесь." or "Вы в карманном измерении. Ищите выход.")
    SV.Audit.log("scp", "pocket.enter", by, victim, {fallback = entry.fallback})
    SV.Bus.emit("scp106.pocket", {ply = by, target = victim})
    return true
end

local function pocketTick()
    local now = CurTime()
    local exits = MapCfg.points("pocket_exit")
    for ply, p in pairs(S106.pocket) do
        if not IsValid(ply) or not ply:Alive() then
            S106.pocket[ply] = nil
        elseif now >= p.untilTime then
            S106.expel(ply, "time")
        else
            local zone = p.zone and MapCfg.zone(p.zone)
            local nearExit = false
            for _, e in ipairs(exits) do
                if ply:GetPos():DistToSqr(MapCfg.toVec(e.pos)) <= K.pocketExitRadius * K.pocketExitRadius then nearExit = true end
            end
            if not p.fallback and nearExit then
                S106.expel(ply, "exit")
            elseif not p.fallback and zone and not MapCfg.zoneContains(zone, ply:GetPos()) then
                -- Left the pocket volume some other way: treat as an exit.
                S106.expel(ply, "outside")
            elseif now >= p.nextDamage then
                p.nextDamage = now + K.pocketTick
                ply:SetHealth(math.max(ply:Health() - K.pocketDamage, math.min(ply:Health(), K.pocketFloorHealth)))
            end
        end
    end
end
timer.Create("SiteVeil.SCP106.Pocket", 0.5, 0, function() SV.Perf.time("scp106.pocket", pocketTick) end)

local function leavePocket(ply)
    if S106.pocket[ply] then
        S106.pocket[ply] = nil
        if IsValid(ply) then
            Move.clear(ply, "pocket")
            SV.Sync.setFor(ply, "self", "pocket", nil)
        end
    end
end
hook.Add("PlayerDeath", "SiteVeil.SCP106", leavePocket)
hook.Add("PlayerDisconnected", "SiteVeil.SCP106", leavePocket)
hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.SCP106", leavePocket)
hook.Add("SiteVeil.CanSwitchCharacter", "SiteVeil.SCP106", function(ply)
    if S106.pocket[ply] then return false, "Нельзя сменить персонажа в карманном измерении." end
end)

--[[---------------------------------------------------------------------------
Abilities
---------------------------------------------------------------------------]]
local function isDoor(ent)
    local c = IsValid(ent) and ent:GetClass() or ""
    return c == "prop_door_rotating" or c == "func_door" or c == "func_door_rotating"
end

local abilities = {}

abilities.attack = function(ply, st)
    local now = CurTime()
    if (st.nextAttack or 0) > now then return false end
    local target = SCP.frontTarget(ply, K.attackRange)
    if not SCP.validVictim(target) then return false end
    if not st.breached and not SCP.inCell(ID, target:GetPos()) then return false end
    st.nextAttack = now + K.attackCooldown
    return S106.sendToPocket(target, ply)
end

abilities.phase = function(ply, st)
    local now = CurTime()
    if (st.nextPhase or 0) > now then
        DarkRP.notify(ply, 1, 3, "Проход сквозь стену будет доступен через " .. math.ceil(st.nextPhase - now) .. " с.")
        return false
    end
    if not st.breached and st.stage ~= "escape" then
        DarkRP.notify(ply, 1, 4, "Камера держит: условия содержания ещё не нарушены.")
        return false
    end
    local door = SCP.frontTarget(ply, K.phaseRange)
    if not isDoor(door) then
        DarkRP.notify(ply, 1, 3, "Перед вами нет двери.")
        return false
    end
    local dir = ply:GetAimVector()
    dir.z = 0
    dir:Normalize()
    local dist = ply:GetPos():Distance(door:GetPos())
    local dest = ply:GetPos() + dir * (dist + K.phaseDepth)
    if not SCP.validDestination(dest) then
        DarkRP.notify(ply, 1, 3, "За дверью нет свободного места.")
        return false
    end
    st.nextPhase = now + K.phaseCooldown
    ply:SetPos(dest)
    ply:EmitSound("ambient/levels/citadel/strange_talk" .. math.random(3, 5) .. ".wav", 70)
    SV.Audit.log("scp", "phase", ply, nil, {door = door:MapCreationID()})
    SV.Bus.emit("scp.doorBroken", {scp = ID, ply = ply, door = door, phase = true})
    return true
end

abilities.travel = function(ply, st)
    local now = CurTime()
    if not st.breached then
        DarkRP.notify(ply, 1, 4, "Перемещение доступно только вне камеры.")
        return false
    end
    if (st.nextTravel or 0) > now then
        DarkRP.notify(ply, 1, 3, "Перемещение будет доступно через " .. math.ceil(st.nextTravel - now) .. " с.")
        return false
    end
    local points = MapCfg.points("emergence")
    if #points == 0 then
        DarkRP.notify(ply, 1, 4, "На этой карте не настроены точки выхода SCP-106.")
        return false
    end
    local dest = DarkRP.findEmptyPos(MapCfg.toVec(points[math.random(#points)].pos), {ply}, 200, 30, Vector(16, 16, 64))
    if not SCP.validDestination(dest) then
        DarkRP.notify(ply, 1, 3, "Точка выхода занята.")
        return false
    end
    st.nextTravel = now + K.travelCooldown
    ply:SetPos(dest)
    SV.Bus.emit("scp.ability", {scp = ID, ply = ply, ability = "travel"})
    return true
end

--[[---------------------------------------------------------------------------
Definition
---------------------------------------------------------------------------]]
local function lureVictim()
    local zone = MapCfg.zones("lure")[1]
    if not zone then return nil, false end
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p.SVChar and not Roles.isSCP(p) and MapCfg.zoneContains(zone, p:GetPos()) then return p, true end
    end
    return nil, true
end

SCP.register(ID, {
    name = "SCP-106", role = "scp106",
    regen = 1,
    setup = function(st)
        st.data.coating = st.data.coating or 100
    end,
    tick = function(st, dt)
        st.data.coating = math.max((st.data.coating or 0) - K.coatingDecay * dt / 60 * SCP.popFactor(), 0)
    end,
    conditions = {
        {id = "em", name = "Электромагнитная стабилизация", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "containment") then return "ok", 0, "норма" end
            return "bad", -7, "камера обесточена"
        end},
        {id = "coating", name = "Покрытие камеры", eval = function(st)
            local c = st.data.coating or 0
            if c > 40 then return "ok", 0, math.Round(c) .. "%" end
            if c > 15 then return "warn", -2, "износ покрытия (" .. math.Round(c) .. "%)" end
            return "bad", -5, "покрытие разрушено"
        end},
        {id = "watch", name = "Наблюдение", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "cameras") then return "ok", 0, "камеры работают" end
            return "warn", -1, "камеры не работают"
        end},
    },
    procedures = {
        {
            id = "coating", name = "Обновление покрытия камеры",
            desc = "Инженер или исследователь наносит антикоррозийное покрытие на стены камеры.",
            duration = 20, cooldown = 300, xp = 15, items = {coating = 1}, roles = {"engineer", "research"},
            rolesText = "выполняют инженеры и научные сотрудники",
            effect = function(st)
                st.data.coating = math.min((st.data.coating or 0) + K.coatingProcedure, 100)
                SCP.adjustIntegrity(ID, SCP.hasUnlock(ID, "coating_v2") and 16 or 8, "coating")
            end,
        },
        {
            id = "lure", name = "Протокол приманки",
            desc = "Воспроизведение записи-приманки возвращает вышедший объект в камеру. Если на карте есть камера приманки, " ..
                "объект забирает находящегося в ней человека в карманное измерение.",
            duration = K.lureTime, cooldown = 240, xp = 30, items = {lure_record = 1}, duringBreach = true,
            roles = {"recontain", "canDetain", "research"}, rolesText = "выполняют МОГ, охрана или научные сотрудники",
            requires = function(st)
                if not st.breached then return false, "объект в камере" end
                local _, hasZone = lureVictim()
                if hasZone and not lureVictim() then return false, "камера приманки пуста" end
                return true
            end,
            during = function(st)
                local ply = SCP.playerOf(ID)
                if ply and not st.data.lureWarned then
                    st.data.lureWarned = true
                    DarkRP.notify(ply, 1, 8, "Вас притягивает звук из камеры содержания.")
                end
                return true
            end,
            effect = function(st, p)
                st.data.lureWarned = nil
                local victim = lureVictim()
                if victim then S106.sendToPocket(victim, SCP.playerOf(ID)) end
                SCP.recontain(ID, p, "lure")
            end,
        },
        {
            id = "inspection", name = "Осмотр камеры", desc = "Проверка покрытия и стабилизаторов.",
            duration = 10, cooldown = 120, xp = 5,
            effect = function() SCP.adjustIntegrity(ID, 2, "inspection") end,
        },
    },
    abilities = abilities,
    onSpawn = function(st, ply)
        ply:SetRunSpeed(200)
        ply:SetWalkSpeed(120)
        st.data.lureWarned = nil
    end,
    onDamage = function(st, ply, dmg)
        if dmg:IsBulletDamage() then dmg:ScaleDamage(K.bulletFactor) end
        if ply:Health() - dmg:GetDamage() <= ply:GetMaxHealth() * K.retreatHealth then
            if st.breached then
                local attacker = dmg:GetAttacker()
                timer.Simple(0, function()
                    if not IsValid(ply) then return end
                    ply:SetHealth(ply:GetMaxHealth())
                    SCP.recontain(ID, IsValid(attacker) and attacker:IsPlayer() and attacker or nil, "retreat")
                end)
            end
            return true
        end
    end,
    publicData = function(st)
        return {coating = math.Round(st.data.coating or 0), victims = U.count(S106.pocket)}
    end,
})

SV.Perf.registry("scp106.pocket", function() return U.count(S106.pocket) end)

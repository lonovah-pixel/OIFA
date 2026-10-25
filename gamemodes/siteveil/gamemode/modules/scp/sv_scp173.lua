--[[---------------------------------------------------------------------------
SCP-173 (server).

Observation is decided only by the server, 10 times per second: a human
observes 173 when 173 is within range, inside the observer's view cone,
visible through at least one of two line-of-sight traces (opaque geometry
only), the observer is not blinking and - in a sector without power - the
observer is close or uses a flashlight. Clients never report "not watched".

Signals for other players: scraping sound while it moves, blink meter for
everyone near it, banging while it breaks a door, flicker on "Затемнение".
Counterplay: keep two observers, alternate blinks, keep the lights on,
recapture with a group (three people, twelve seconds of continuous watch).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SCP = SV.SCP
local U = SV.Util
local C = SV.Config
local K = C.SCP.scp173
local Roles = SV.Roles
local Facility = SV.Facility
local Move = SV.Move
local Medical = SV.Medical

local ID = "scp173"
local blink = {} -- ply -> {nextAt, untilTime}

local S173 = {}
SCP.S173 = S173

--[[---------------------------------------------------------------------------
Blinking (server-side schedule for humans near 173)
---------------------------------------------------------------------------]]
local function blinkInterval()
    if SCP.lowPop() then return math.Rand(K.blinkMinLowPop, K.blinkMaxLowPop) end
    return math.Rand(K.blinkMin, K.blinkMax)
end

local function isBlinking(p, now)
    local b = blink[p]
    return b ~= nil and now >= b.nextAt and now < b.untilTime
end
S173.isBlinking = isBlinking

local function updateBlink(p, now, near)
    local b = blink[p]
    if not near then
        if b then
            blink[p] = nil
            SV.Sync.setFor(p, "self", "blink", nil)
        end
        return
    end
    if not b then
        b = {nextAt = now + blinkInterval()}
        b.untilTime = b.nextAt + K.blinkTime
        blink[p] = b
        SV.Sync.setFor(p, "self", "blink", {nextAt = b.nextAt, duration = K.blinkTime})
    elseif now >= b.untilTime then
        b.nextAt = now + blinkInterval()
        b.untilTime = b.nextAt + K.blinkTime
        SV.Sync.setFor(p, "self", "blink", {nextAt = b.nextAt, duration = K.blinkTime})
    end
end

function S173.forceBlink(p, duration)
    local now = CurTime()
    blink[p] = {nextAt = now, untilTime = now + duration}
    SV.Sync.setFor(p, "self", "blink", {nextAt = now, duration = duration})
end

--[[---------------------------------------------------------------------------
Observation
---------------------------------------------------------------------------]]
local function lineOfSight(from, to, observer, scp)
    local tr = util.TraceLine({start = from, endpos = to, filter = {observer, scp}, mask = MASK_OPAQUE})
    return not tr.Hit
end

--- Players currently observing ply (the SCP-173 player).
function S173.observers(scp)
    local now = CurTime()
    local pos = scp:GetPos()
    local center, head = pos + Vector(0, 0, 36), pos + Vector(0, 0, 62)
    local dark = Facility.power(Facility.sectorAt(pos)) < 0.3
    local rangeSqr = K.observeRange * K.observeRange
    local darkSqr = K.darkRange * K.darkRange
    local list = {}
    for _, p in ipairs(player.GetAll()) do
        if p ~= scp and p:Alive() and p.SVChar and not Roles.isSCP(p) then
            local eye = p:EyePos()
            local dsq = eye:DistToSqr(center)
            updateBlink(p, now, dsq <= 2000 * 2000)
            if dsq <= rangeSqr and not isBlinking(p, now) and not Medical.isIncapacitated(p) then
                local dir = center - eye
                dir:Normalize()
                local facing = p:GetAimVector():Dot(dir) >= K.observeDot and (not dark or dsq <= darkSqr or p:FlashlightIsOn())
                if facing and (lineOfSight(eye, center, p, scp) or lineOfSight(eye, head, p, scp)) then
                    list[#list + 1] = p
                end
            end
        end
    end
    return list
end

local scrape

local function observationTick()
    local scp = SCP.playerOf(ID)
    if not scp or not scp:Alive() then
        if next(blink) then
            for p in pairs(blink) do if IsValid(p) then SV.Sync.setFor(p, "self", "blink", nil) end end
            blink = {}
        end
        return
    end
    local st = SCP.state[ID]
    local obs = S173.observers(scp)
    st.observers = #obs
    local now = CurTime()
    local observed = #obs > 0
    if observed then
        st.lastObserved = now
        Move.set(scp, "173", {frozen = true})
        if scrape then scrape:Stop() end
    elseif now - (st.lastObserved or 0) >= K.moveDelay then
        Move.clear(scp, "173")
        if scp:GetVelocity():Length2D() > 60 then
            if not scrape then scrape = CreateSound(scp, "physics/concrete/concrete_scrape_smooth_loop1.wav") end
            if not scrape:IsPlaying() then scrape:PlayEx(0.9, 100) end
        elseif scrape then
            scrape:Stop()
        end
    end
    scp:SetNW2Bool("sv_173_observed", observed)
end
timer.Create("SiteVeil.SCP173.Observe", 0.1, 0, function() SV.Perf.time("scp173.observe", observationTick) end)

function S173.isObserved()
    local st = SCP.state[ID]
    return st and st.lastObserved and CurTime() - st.lastObserved < K.moveDelay
end

--[[---------------------------------------------------------------------------
Abilities
---------------------------------------------------------------------------]]
local frontTarget = SCP.frontTarget

local abilities = {}

abilities.attack = function(ply, st)
    local now = CurTime()
    if S173.isObserved() then return false end
    if (st.nextAttack or 0) > now then return false end
    local target = frontTarget(ply, K.attackRange)
    if not SCP.validVictim(target) then return false end
    st.nextAttack = now + K.attackCooldown
    target:EmitSound("npc/barnacle/neck_snap1.wav", 80)
    SCP.harm(ply, target, ID)
    return true
end

abilities.blackout = function(ply, st)
    local now = CurTime()
    if (st.nextBlackout or 0) > now then
        DarkRP.notify(ply, 1, 3, "Затемнение будет доступно через " .. math.ceil(st.nextBlackout - now) .. " с.")
        return false
    end
    st.nextBlackout = now + K.blackoutCooldown
    ply:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 85)
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and p:Alive() and U.within(p, ply, K.blackoutRadius) then
            S173.forceBlink(p, K.blackoutBlink)
            SV.Net.send(p, "scp.flicker", {duration = K.blackoutBlink})
        end
    end
    SV.Bus.emit("scp.ability", {scp = ID, ply = ply, ability = "blackout"})
    return true
end

local function isDoor(ent)
    local c = IsValid(ent) and ent:GetClass() or ""
    return c == "prop_door_rotating" or c == "func_door" or c == "func_door_rotating"
end

abilities.breakDoor = function(ply, st)
    if not st.breached and st.stage ~= "escape" then
        DarkRP.notify(ply, 1, 4, "Камера держит: условия содержания ещё не нарушены.")
        return false
    end
    local door = frontTarget(ply, 100)
    if not isDoor(door) then return false end
    local time = SCP.lowPop() and K.doorBreakTimeLowPop or K.doorBreakTime
    local nextBang = 0
    return SV.Actions.start(ply, {
        id = "173door", label = "Взлом двери", duration = time, target = door, maxDist = 130, silent = true,
        canContinue = function(p)
            if S173.isObserved() then return false, "за вами наблюдают" end
            if CurTime() >= nextBang then
                nextBang = CurTime() + 1.5
                door:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 90)
            end
            return p:Alive()
        end,
        onComplete = function(p)
            door:Fire("Unlock", "", 0)
            door:Fire("Open", "", 0)
            if SV.Access then SV.Access.openDoors[door] = CurTime() + 15 end
            door:EmitSound("physics/metal/metal_large_debris2.wav", 95)
            SV.Audit.log("scp", "door", p, nil, {scp = ID, door = door:MapCreationID()})
            SV.Bus.emit("scp.doorBroken", {scp = ID, ply = p, door = door})
        end,
    })
end

-- In the cell: test the containment. Weak conditions are exploited, but the
-- attempt is loud and visible on the containment panel.
abilities.probe = function(ply, st)
    local now = CurTime()
    if st.breached then return false end
    if (st.nextProbe or 0) > now then return false end
    st.nextProbe = now + 60
    local _, list = SCP.evaluate(ID)
    local weak = false
    for _, c in ipairs(list) do if c.status ~= "ok" then weak = true end end
    ply:EmitSound("physics/concrete/concrete_impact_hard" .. math.random(1, 3) .. ".wav", 85)
    st.noiseUntil = now + 60
    if weak then
        SCP.adjustIntegrity(ID, -3, "probe")
        DarkRP.notify(ply, 0, 4, "Камера поддаётся.")
    else
        DarkRP.notify(ply, 1, 4, "Камера держит: условия содержания соблюдены.")
    end
    SV.Bus.emit("scp.ability", {scp = ID, ply = ply, ability = "probe"})
    return true
end

--[[---------------------------------------------------------------------------
Recapture: a group keeps 173 under watch while one person installs the
containment frame.
---------------------------------------------------------------------------]]
local function canRecapture(ply)
    return Roles.hasFlag(ply, "recontain") or (Roles.hasFlag(ply, "canDetain") and SV.Access.hasTag(ply, "containment")) or SV.Admin.isOnDuty(ply)
end

local function recapture(ply, target, st)
    if not canRecapture(ply) then return false, "Повторное содержание проводят МОГ или охрана с допуском к камерам." end
    if not U.within(ply, target, 150) then return false, "Подойдите к объекту." end
    local need = SCP.lowPop() and 1 or K.recaptureObservers
    local function enough()
        local n = 0
        for _, p in ipairs(S173.observers(target)) do
            if p ~= ply then n = n + 1 end
        end
        return n >= need, n
    end
    local ok, n = enough()
    if not ok then return false, "Нужно ещё наблюдателей: " .. (need - n) .. " (не считая вас)." end
    return SV.Actions.start(ply, {
        id = "recapture173", label = "Установка сдерживающего каркаса", duration = K.recaptureTime, target = target, maxDist = 170,
        canContinue = function()
            local ok2, n2 = enough()
            if not ok2 then return false, "наблюдение прервано (" .. n2 .. "/" .. need .. ")" end
            return true
        end,
        onComplete = function(p)
            SCP.recontain(ID, p, "containment frame")
        end,
    })
end

--[[---------------------------------------------------------------------------
Definition
---------------------------------------------------------------------------]]
SCP.register(ID, {
    name = "SCP-173", role = "scp173",
    regen = 1.5,
    setup = function(st)
        st.data.dirt = st.data.dirt or 0
    end,
    tick = function(st, dt)
        st.data.dirt = math.min((st.data.dirt or 0) + K.dirtPerMinute * dt / 60 * SCP.popFactor(), 100)
    end,
    conditions = {
        {id = "watch", name = "Наблюдение за камерой", eval = function()
            local sector = SCP.cellSector(ID)
            local cams = Facility.devicePowered(sector, "cameras")
            if cams or #SCP.peopleInCell(ID).staff > 0 then return "ok", 0, cams and "камеры работают" or "персонал в камере" end
            local rate = SCP.hasUnlock(ID, "watch_protocol") and -3 or -6
            return "bad", rate, "камеры не работают"
        end},
        {id = "dirt", name = "Состояние камеры", eval = function(st)
            local dirt = st.data.dirt or 0
            if dirt > 40 then return "bad", -5, "сильное загрязнение" end
            if dirt > 20 then return "warn", -2, "требуется уборка" end
            return "ok", 0, "чисто"
        end},
        {id = "noise", name = "Акустический контроль", eval = function(st)
            if st.noiseUntil and CurTime() < st.noiseUntil then return "warn", 0, "шум в камере" end
            return "ok", 0, "тихо"
        end},
        {id = "power", name = "Питание замков", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "containment") then return "ok", 0, "норма" end
            return "bad", -8, "замки обесточены"
        end},
    },
    procedures = {
        {
            id = "cleaning", name = "Уборка камеры по протоколу",
            desc = "Сотрудник класса D убирает камеру, двое сотрудников непрерывно наблюдают за объектом. Все участники остаются в камере.",
            duration = 30, cooldown = 300, xp = 15, roles = {"research", "canDetain"}, rolesText = "руководит научный сотрудник или охрана",
            requires = function()
                local people = SCP.peopleInCell(ID)
                if #people.classd < 1 then return false, "в камере нет сотрудника класса D" end
                if #people.staff < 2 then return false, "в камере нужны двое наблюдающих" end
                return true
            end,
            effect = function(st, p)
                st.data.dirt = 0
                SCP.adjustIntegrity(ID, 10, "cleaning")
                if SV.Inv.take(p, "sample_kit", 1) then
                    SV.Inv.add(p, "sample", 1, {force = true, data = {title = "Выделения SCP-173", label = "Образец из камеры SCP-173", scp = ID}})
                    return "Получен образец выделений."
                end
            end,
        },
        {
            id = "inspection", name = "Осмотр камеры",
            desc = "Проверка замков, камер и состояния объекта.",
            duration = 10, cooldown = 120, xp = 5, anywhere = false,
            effect = function() SCP.adjustIntegrity(ID, 2, "inspection") end,
        },
    },
    abilities = abilities,
    recapture = recapture,
    onSpawn = function(st, ply)
        ply:SetRunSpeed(K.runSpeed)
        ply:SetWalkSpeed(K.runSpeed * 0.6)
        ply:SetMaxHealth(1000)
        ply:SetHealth(1000)
        ply:SetColor(Color(170, 160, 150))
        st.lastObserved = nil
    end,
    onLeave = function(_, ply)
        if IsValid(ply) then
            Move.clear(ply, "173")
            ply:SetNW2Bool("sv_173_observed", false)
        end
        if scrape then scrape:Stop() scrape = nil end
    end,
    onDamage = function()
        return true -- concrete: weapons do not harm SCP-173
    end,
    publicData = function(st)
        return {observers = st.observers or 0, dirt = math.Round(st.data.dirt or 0)}
    end,
})

hook.Add("PlayerDisconnected", "SiteVeil.SCP173", function(ply) blink[ply] = nil end)
hook.Add("PlayerDeath", "SiteVeil.SCP173", function(ply)
    if blink[ply] then
        blink[ply] = nil
        SV.Sync.setFor(ply, "self", "blink", nil)
    end
end)

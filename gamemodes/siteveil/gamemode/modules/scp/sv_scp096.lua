--[[---------------------------------------------------------------------------
SCP-096 (server). State machine (st.data.mode):

  calm ──face seen──▶ triggered ──triggerTime──▶ rage ──no targets / rageMax──▶ calming
    ▲                                                                            │
    └──────────────── exhausted ◀──────────────────calmingTime────────────────────┘

Seeing the face is decided by the server (5 times per second): the observer
looks at the head of 096, 096 is turned towards the observer, both line of
sight traces are free, the observer is in range (shorter in darkness unless
using a flashlight) and 096 wears no bag. Targets are removed on death,
disconnect, character switch and role change; when no target is left the
rage ends. The rage always ends after rageMax seconds.

In rage 096 attacks only its targets and breaks doors quickly. A calm or
exhausted 096 can be recaptured by putting a bag over its head (the person
must not be a target).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SCP = SV.SCP
local U = SV.Util
local C = SV.Config
local K = C.SCP.scp096
local Roles = SV.Roles
local Facility = SV.Facility
local Move = SV.Move
local Medical = SV.Medical

local ID = "scp096"
local S096 = {}
SCP.S096 = S096

S096.modeNames = {calm = "спокоен", triggered = "возбуждение", rage = "ярость", calming = "успокоение", exhausted = "истощение"}

local function state()
    return SCP.state[ID]
end

local function publishTarget(p, on)
    if IsValid(p) then SV.Sync.setFor(p, "self", "target096", on or nil) end
end

local function setMode(st, mode, reason)
    local ply = SCP.playerOf(ID)
    local now = CurTime()
    st.data.mode = mode
    st.data.modeSince = now
    st.data.modeUntil = nil
    if IsValid(ply) then
        Move.clear(ply, "096")
        if mode == "triggered" then
            st.data.modeUntil = now + K.triggerTime
            Move.set(ply, "096", {frozen = true, noattack = true})
            ply:EmitSound("npc/stalker/go_alert2a.wav", 95, 80)
        elseif mode == "rage" then
            st.data.rageSince = now
            ply:SetRunSpeed(K.rageSpeed)
            ply:SetWalkSpeed(K.rageSpeed * 0.7)
        elseif mode == "calming" then
            st.data.modeUntil = now + K.calmingTime
            Move.set(ply, "096", {frozen = true, noattack = true})
        elseif mode == "exhausted" then
            st.data.modeUntil = now + K.exhaustedTime
            Move.set(ply, "096", {speed = 0.5, noattack = true})
        end
        if mode ~= "rage" then
            ply:SetRunSpeed(K.calmSpeed)
            ply:SetWalkSpeed(K.calmSpeed * 0.7)
        end
    end
    if mode == "calming" or mode == "calm" then
        for p in pairs(st.data.targets) do publishTarget(p, false) end
        st.data.targets = {}
    end
    SV.Bus.emit("scp096.mode", {mode = mode, reason = reason})
    SCP.publish(ID)
end
S096.setMode = setMode

--- Adds a human target (seen the face, experiment incident ...).
function S096.addTarget(p, reason)
    local st = state()
    if not st or not IsValid(p) or not p:IsPlayer() or not p:Alive() or not p.SVChar or Roles.isSCP(p) then return false end
    if st.data.bagged then return false end
    local ply = SCP.playerOf(ID)
    if not ply or not ply:Alive() then
        -- Unplayed: the cell takes the strain instead.
        SCP.adjustIntegrity(ID, -25, "face seen")
        return false
    end
    if st.data.targets[p] then return false end
    if U.count(st.data.targets) >= K.maxTargets then return false end
    st.data.targets[p] = true
    publishTarget(p, true)
    DarkRP.notify(p, 1, 10, "Вы увидели лицо SCP-096. Бегите и не попадайтесь ему.")
    SV.Audit.log("scp", "096.target", p, nil, {reason = reason})
    SV.Bus.emit("scp096.target", {ply = p, reason = reason})
    local mode = st.data.mode
    if mode == "calm" or mode == "exhausted" or mode == "calming" then setMode(st, "triggered", reason) end
    return true
end

function S096.removeTarget(p)
    local st = state()
    if st and st.data.targets[p] then
        st.data.targets[p] = nil
        publishTarget(p, false)
    end
end

function S096.isTarget(p)
    local st = state()
    return st ~= nil and st.data.targets[p] == true
end

--[[---------------------------------------------------------------------------
Face check and state ticks
---------------------------------------------------------------------------]]
local function seesFace(p, scp, head, dark)
    local eye = p:EyePos()
    local dsq = eye:DistToSqr(head)
    local range = (dark and not p:FlashlightIsOn()) and K.viewRangeDark or K.viewRange
    if dsq > range * range then return false end
    local toHead = head - eye
    toHead:Normalize()
    if p:GetAimVector():Dot(toHead) < K.faceDot then return false end
    local toObserver = eye - head
    toObserver:Normalize()
    if scp:GetAimVector():Dot(toObserver) < K.facingDot then return false end
    local tr = util.TraceLine({start = eye, endpos = head, filter = {p, scp}, mask = MASK_OPAQUE})
    return not tr.Hit
end

local function tick()
    local st = state()
    local scp = SCP.playerOf(ID)
    if not scp or not scp:Alive() then return end
    local now = CurTime()
    local mode = st.data.mode

    -- Invalid targets leave the list.
    for p in pairs(st.data.targets) do
        if not IsValid(p) or not p:Alive() or not p.SVChar or Roles.isSCP(p) then S096.removeTarget(p) end
    end

    if not st.data.bagged then
        local head = scp:EyePos()
        local dark = Facility.power(Facility.sectorAt(scp:GetPos())) < 0.3
        for _, p in ipairs(player.GetAll()) do
            if p ~= scp and p:Alive() and p.SVChar and not Roles.isSCP(p) and not st.data.targets[p] and not Medical.isIncapacitated(p) and seesFace(p, scp, head, dark) then
                S096.addTarget(p, "view")
            end
        end
    end

    if mode == "triggered" and now >= st.data.modeUntil then
        if next(st.data.targets) then setMode(st, "rage", "trigger") else setMode(st, "calming", "no targets") end
    elseif mode == "rage" then
        if not next(st.data.targets) then
            setMode(st, "calming", "targets gone")
        elseif now - st.data.rageSince >= K.rageMax then
            DarkRP.notify(scp, 1, 6, "Ярость иссякла.")
            setMode(st, "calming", "rage limit")
        end
    elseif mode == "calming" and now >= st.data.modeUntil then
        setMode(st, "exhausted", "calming")
    elseif mode == "exhausted" and now >= st.data.modeUntil then
        setMode(st, "calm", "rest")
    end
end
timer.Create("SiteVeil.SCP096", 0.2, 0, function() SV.Perf.time("scp096.tick", tick) end)

local function forget(p) S096.removeTarget(p) end
hook.Add("PlayerDeath", "SiteVeil.SCP096", forget)
hook.Add("PlayerDisconnected", "SiteVeil.SCP096", forget)
hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.SCP096", forget)
hook.Add("SiteVeil.RoleAssigned", "SiteVeil.SCP096", function(p, role)
    if role and role.scp then forget(p) end
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
    if st.data.mode ~= "rage" then return false end
    local now = CurTime()
    if (st.nextAttack or 0) > now then return false end
    local target = SCP.frontTarget(ply, K.attackRange)
    if not SCP.validVictim(target) then return false end
    if not st.data.targets[target] then
        DarkRP.notify(ply, 1, 2, "Это не тот, кто видел ваше лицо.")
        return false
    end
    st.nextAttack = now + K.attackCooldown
    target:EmitSound("npc/zombie/zombie_hit.wav", 85)
    SCP.harm(ply, target, ID)
    -- An incapacitated target no longer drives the rage.
    if not target:Alive() or Medical.isIncapacitated(target) then S096.removeTarget(target) end
    return true
end

abilities.breakDoor = function(ply, st)
    if st.data.mode ~= "rage" then
        DarkRP.notify(ply, 1, 3, "Ломать двери можно только в ярости.")
        return false
    end
    local door = SCP.frontTarget(ply, 100)
    if not isDoor(door) then return false end
    return SV.Actions.start(ply, {
        id = "096door", label = "Взлом двери", duration = K.doorBreakTime, target = door, maxDist = 130, silent = true,
        canContinue = function() return st.data.mode == "rage", "ярость прошла" end,
        onComplete = function(p)
            door:Fire("Unlock", "", 0)
            door:Fire("Open", "", 0)
            if SV.Access then SV.Access.openDoors[door] = CurTime() + 15 end
            door:EmitSound("physics/metal/metal_large_debris2.wav", 95)
            SV.Bus.emit("scp.doorBroken", {scp = ID, ply = p, door = door})
        end,
    })
end

abilities.tearBag = function(ply, st)
    if not st.data.bagged then return false end
    if not st.breached and st.stage ~= "danger" and st.stage ~= "escape" then
        DarkRP.notify(ply, 1, 4, "Мешок держится крепко: условия содержания соблюдены.")
        return false
    end
    return SV.Actions.start(ply, {
        id = "096bag", label = "Сорвать мешок", duration = 8, allowMove = false,
        onComplete = function()
            st.data.bagged = false
            SCP.publish(ID)
        end,
    })
end

--[[---------------------------------------------------------------------------
Recapture: bag over the head of a calm or exhausted 096
---------------------------------------------------------------------------]]
local function recapture(ply, target, st)
    if not (Roles.hasFlag(ply, "recontain") or Roles.hasFlag(ply, "canDetain") or SV.Admin.isOnDuty(ply)) then
        return false, "Повторное содержание проводят МОГ и охрана."
    end
    local mode = st.data.mode
    if mode ~= "calm" and mode ~= "exhausted" then return false, "Объект в ярости — к нему нельзя приближаться." end
    if st.data.targets[ply] then return false, "Вы видели лицо объекта." end
    if not SV.Inv.has(ply, "head_bag") then return false, "Нужен мешок для головы." end
    if not U.within(ply, target, 120) then return false, "Подойдите к объекту." end
    return SV.Actions.start(ply, {
        id = "recapture096", label = "Надеть мешок на SCP-096", duration = K.bagTime, target = target, maxDist = 140,
        canContinue = function(p)
            local m = st.data.mode
            if m ~= "calm" and m ~= "exhausted" then return false, "объект пришёл в ярость" end
            return SV.Inv.has(p, "head_bag"), "нет мешка"
        end,
        onComplete = function(p)
            SV.Inv.take(p, "head_bag", 1)
            st.data.bagged = true
            SCP.recontain(ID, p, "bag")
        end,
    })
end

--[[---------------------------------------------------------------------------
Definition
---------------------------------------------------------------------------]]
SCP.register(ID, {
    name = "SCP-096", role = "scp096",
    regen = 1,
    setup = function(st)
        st.data.mode = st.data.mode or "calm"
        st.data.targets = st.data.targets or {}
    end,
    conditions = {
        {id = "masking", name = "Маскировка камер", eval = function(st)
            if st.data.maskedUntil and CurTime() < st.data.maskedUntil then return "ok", 0, "камеры замаскированы" end
            return "warn", -1, "камеры могут показать лицо"
        end},
        {id = "noise", name = "Шумоизоляция", eval = function()
            if Facility.subsystemOk(SCP.cellSector(ID), "ventilation") then return "ok", 0, "тихо" end
            return "bad", -4, "шум вентиляции тревожит объект"
        end},
        {id = "power", name = "Питание замков", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "containment") then return "ok", 0, "норма" end
            return "bad", -8, "замки обесточены"
        end},
        {id = "calm", name = "Состояние объекта", eval = function(st)
            local mode = st.data.mode or "calm"
            if mode == "rage" or mode == "triggered" then return "bad", -10, S096.modeNames[mode] end
            return "ok", 0, (S096.modeNames[mode] or mode) .. (st.data.bagged and ", в мешке" or "")
        end},
    },
    procedures = {
        {
            id = "mask", name = "Маскировка камер наблюдения",
            desc = "Объективы в камере закрываются фильтрами: изображение лица не попадёт на мониторы.",
            duration = 15, cooldown = 900, xp = 10, roles = {"engineer", "research"}, rolesText = "выполняют инженеры и научные сотрудники",
            requires = function(st)
                if st.data.mode ~= "calm" then return false, "объект неспокоен" end
                return true
            end,
            effect = function(st)
                st.data.maskedUntil = CurTime() + K.maskTime
                SCP.adjustIntegrity(ID, 4, "mask")
            end,
        },
        {
            id = "unbag", name = "Снять мешок",
            desc = "Мешок снимают со спокойного объекта, не глядя на лицо.",
            duration = 6, cooldown = 60, xp = 5, roles = {"research", "recontain"}, rolesText = "выполняют научные сотрудники и МОГ",
            requires = function(st)
                if not st.data.bagged then return false, "мешка нет" end
                if st.data.mode ~= "calm" then return false, "объект неспокоен" end
                return true
            end,
            effect = function(st, p)
                st.data.bagged = false
                SV.Inv.add(p, "head_bag", 1, {force = true})
            end,
        },
        {
            id = "inspection", name = "Осмотр камеры", desc = "Проверка замков по мониторам, без визуального контакта.",
            duration = 10, cooldown = 120, xp = 5,
            effect = function() SCP.adjustIntegrity(ID, 2, "inspection") end,
        },
    },
    abilities = abilities,
    recapture = recapture,
    onSpawn = function(st, ply)
        st.data.targets = {}
        setMode(st, "calm", "spawn")
        ply:SetRunSpeed(K.calmSpeed)
        ply:SetWalkSpeed(K.calmSpeed * 0.7)
    end,
    onLeave = function(st, ply)
        for p in pairs(st.data.targets) do publishTarget(p, false) end
        st.data.targets = {}
        st.data.mode = "calm"
        if IsValid(ply) then Move.clear(ply, "096") end
    end,
    onDamage = function(_, _, dmg)
        if dmg:IsBulletDamage() then dmg:ScaleDamage(0.5) end
    end,
    publicData = function(st)
        return {mode = st.data.mode, modeName = S096.modeNames[st.data.mode], targets = U.count(st.data.targets), bagged = st.data.bagged or false,
            rageLeft = st.data.mode == "rage" and math.max(math.ceil(K.rageMax - (CurTime() - (st.data.rageSince or 0))), 0) or nil}
    end,
})

SV.Perf.registry("scp096.targets", function() return U.count(state().data.targets) end)

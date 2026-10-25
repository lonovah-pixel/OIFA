--[[---------------------------------------------------------------------------
SCP-049 (server) and the temporary role SCP-049-2.

Touch infects (stage 1); after C.SCP.scp049.stageTime the infection reaches
stage 2. Medics stop it with an antiviral while it is at stage 1; a hazmat
suit prevents the touch infection. SCP-049 can "cure" a victim who is
incapacitated or at stage 2: a timed operation, interrupted when 049 is
hurt or moves away.

The cured character dies (normal death: carried items drop) and the player
rises as SCP-049-2 at the same place for at most instanceTime seconds.
Limits: maxInstances at once (fewer on small servers), the same character
once per recureCooldown. When the instance dies or collapses the player
returns to their own character and role through the normal respawn, and a
tissue sample drops (subject of the research protocol p049_tissue).

Recontainment: sustained damage suppresses 049 (below 40% health); a
suppressed 049 can be escorted back with a recapture action.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SCP = SV.SCP
local U = SV.Util
local C = SV.Config
local K = C.SCP.scp049
local Roles = SV.Roles
local Facility = SV.Facility
local Move = SV.Move
local Medical = SV.Medical
local Inv = SV.Inv

local ID = "scp049"
local S049 = {}
SCP.S049 = S049

S049.instances = S049.instances or {} -- ply -> {since, untilTime, charId}
S049.cured = S049.cured or {}         -- char id -> CurTime of conversion
S049.pending = S049.pending or {}     -- ply -> true between the cure and the respawn

function S049.maxInstances()
    return SCP.lowPop() and K.maxInstancesLowPop or K.maxInstances
end

--- Live instances plus conversions still in progress (slot reserved).
function S049.instanceCount()
    local n = 0
    for p in pairs(S049.instances) do
        if IsValid(p) then n = n + 1 else S049.instances[p] = nil end
    end
    for p in pairs(S049.pending) do
        if IsValid(p) then n = n + 1 else S049.pending[p] = nil end
    end
    return n
end

local function suppressed(st)
    return st.data.suppressedUntil ~= nil and CurTime() < st.data.suppressedUntil
end

--[[---------------------------------------------------------------------------
Infection progress
---------------------------------------------------------------------------]]
timer.Create("SiteVeil.SCP049.Infection", 5, 0, function()
    local now = CurTime()
    for _, p in ipairs(player.GetAll()) do
        local inf = Medical.infection(p)
        if inf and inf.stage == 1 and now - inf.since >= K.stageTime then
            Medical.infect(p, inf.source)
            Move.set(p, "infection", {speed = 0.8})
            DarkRP.notify(p, 1, 8, "Слабость и жар усиливаются.")
        end
    end
end)

SV.Bus.on("medical.cured", "scp049", function(data)
    if IsValid(data.ply) then Move.clear(data.ply, "infection") end
end)
hook.Add("PlayerSpawn", "SiteVeil.SCP049", function(ply) Move.clear(ply, "infection") end)

--[[---------------------------------------------------------------------------
Conversion
---------------------------------------------------------------------------]]
local function canConvert(target)
    if not IsValid(target) or not target:Alive() or not target.SVChar or Roles.isSCP(target) then return false, "цель недоступна" end
    local inf = Medical.infection(target)
    if not Medical.isIncapacitated(target) and not (inf and inf.stage >= 2) then return false, "пациент ещё не готов к «лечению»" end
    if S049.instanceCount() >= S049.maxInstances() then return false, "у вас уже достаточно «излечённых»" end
    local last = S049.cured[target.SVChar.id]
    if last and CurTime() - last < K.recureCooldown then return false, "этот пациент недавно уже был «излечён»" end
    return true
end
S049.canConvert = canConvert

function S049.convert(target, doctor)
    local ok = canConvert(target)
    if not ok then return false end
    local pos = target:GetPos()
    local charId = target.SVChar.id
    S049.cured[charId] = CurTime()
    S049.pending[target] = true
    SV.Audit.log("scp", "cure", doctor, target, {scp = ID})
    Medical.kill(target, "scp049")
    timer.Simple(0.2, function()
        S049.pending[target] = nil
        if not IsValid(target) or not target.SVChar or target.SVChar.id ~= charId or target:Alive() then return end
        local role = Roles.get("scp0492")
        local okRole = SV.Chars.assignRole(target, role, {system = true, respawn = false, reason = "scp049"})
        if not okRole then return end
        target.SVRespawnAt = nil
        target:Spawn()
        SCP.teleport(target, pos)
        S049.instances[target] = {since = CurTime(), untilTime = CurTime() + K.instanceTime, charId = charId}
        SV.Sync.setFor(target, "self", "instance", {untilTime = S049.instances[target].untilTime})
        DarkRP.notify(target, 1, 10, "Вы — SCP-049-2. Следуйте за доктором. Через " .. U.formatDuration(K.instanceTime) ..
            " тело не выдержит, и вы вернётесь к своему персонажу.")
        SV.Bus.emit("scp049.converted", {ply = doctor, target = target})
    end)
    return true
end

local function dropSample(pos)
    local item = Inv.createItem("sample", 1, {title = "Ткани SCP-049-2", label = "Образец тканей экземпляра SCP-049-2", scp = "scp0492"}, "world")
    Inv.spawnWorld({item}, pos + Vector(0, 0, 8))
end

--- Ends an instance and returns the player to their character's role.
local function endInstance(ply, dropAt)
    local inst = S049.instances[ply]
    if not inst then return end
    S049.instances[ply] = nil
    if dropAt then dropSample(dropAt) end
    if not IsValid(ply) then return end
    SV.Sync.setFor(ply, "self", "instance", nil)
    local char = ply.SVChar
    if char and char.id == inst.charId then
        local role = Roles.get(char.role) or Roles.get(Roles.getDivision(char.division).defaultRole)
        if role then SV.Chars.assignRole(ply, role, {system = true, restore = true, respawn = false, reason = "scp0492 end"}) end
    end
end
S049.endInstance = endInstance

hook.Add("PlayerDeath", "SiteVeil.SCP049", function(ply)
    if S049.instances[ply] then
        local pos = ply:GetPos()
        timer.Simple(0, function() endInstance(ply, pos) end)
    end
end)

hook.Add("PlayerDisconnected", "SiteVeil.SCP049", function(ply) S049.instances[ply] = nil end)

hook.Add("SiteVeil.CanSwitchCharacter", "SiteVeil.SCP049", function(ply)
    if S049.instances[ply] then return false, "Дождитесь окончания роли SCP-049-2." end
end)

hook.Add("SiteVeil.CanTakeRole", "SiteVeil.SCP049", function(ply, role, opts)
    if S049.instances[ply] and not opts.system then return false, "Вы — SCP-049-2 до окончания действия роли." end
end)

timer.Create("SiteVeil.SCP049.Instances", 1, 0, function()
    local now = CurTime()
    for ply, inst in pairs(S049.instances) do
        if not IsValid(ply) then
            S049.instances[ply] = nil
        elseif ply:Alive() and now >= inst.untilTime then
            DarkRP.notify(ply, 0, 6, "Тело экземпляра не выдержало. Вы возвращаетесь к своему персонажу.")
            ply:Kill()
        end
    end
end)

--- Instances collapse when nobody plays SCP-049 any more.
local function collapseAll()
    for ply in pairs(S049.instances) do
        if IsValid(ply) and ply:Alive() then ply:Kill() end
    end
end

--[[---------------------------------------------------------------------------
Abilities
---------------------------------------------------------------------------]]
local abilities = {}

abilities.touch = function(ply, st)
    local now = CurTime()
    if suppressed(st) then
        DarkRP.notify(ply, 1, 3, "Вы подавлены и не можете действовать.")
        return false
    end
    local target = SCP.frontTarget(ply, K.touchRange)
    if not SCP.validVictim(target) then return false end
    if not st.breached and not SCP.inCell(ID, target:GetPos()) then return false end
    if canConvert(target) then
        return SV.Actions.start(ply, {
            id = "049cure", label = "«Лечение»", duration = K.cureTime, target = target, maxDist = K.cureRange, cancelOnDamage = true,
            canContinue = function()
                if suppressed(st) then return false, "вы подавлены" end
                return canConvert(target)
            end,
            onComplete = function(p) S049.convert(target, p) end,
        })
    end
    local _, why = canConvert(target)
    if (st.nextTouch or 0) > now then
        DarkRP.notify(ply, 1, 3, "Прикосновение доступно через " .. math.ceil(st.nextTouch - now) .. " с.")
        return false
    end
    st.nextTouch = now + K.touchCooldown
    if Inv.isWearing(target, "hazmat") then
        DarkRP.notify(ply, 1, 4, "Защитный костюм мешает прикосновению.")
        DarkRP.notify(target, 0, 4, "Костюм защитил вас от прикосновения SCP-049.")
        return true
    end
    if Medical.infection(target) then
        DarkRP.notify(ply, 0, 4, "Поветрие уже в нём: " .. tostring(why) .. ".")
        return true
    end
    Medical.infect(target, ID)
    DarkRP.notify(target, 1, 8, "Прикосновение SCP-049 оставило жжение. Срочно в медблок.")
    SV.Audit.log("scp", "infect", ply, target, {scp = ID})
    SV.Bus.emit("scp.attack", {scp = ID, ply = ply, target = target, infect = true})
    return true
end

--- SCP-049-2 melee attack (called from the sv_scp0492 weapon).
function S049.zombieAttack(ply)
    if not S049.instances[ply] or not ply:Alive() then return false end
    local now = CurTime()
    if (ply.SVZombieNext or 0) > now then return false end
    local target = SCP.frontTarget(ply, K.zombieRange)
    if not SCP.validVictim(target) then return false end
    ply.SVZombieNext = now + K.zombieCooldown
    local d = DamageInfo()
    d:SetDamage(K.zombieDamage)
    d:SetDamageType(DMG_SLASH)
    d:SetAttacker(ply)
    d:SetInflictor(ply)
    target:TakeDamageInfo(d)
    return true
end

--[[---------------------------------------------------------------------------
Recapture of a suppressed 049
---------------------------------------------------------------------------]]
local function canRecapture(ply)
    return Roles.hasFlag(ply, "recontain") or Roles.hasFlag(ply, "canDetain") or SV.Admin.isOnDuty(ply)
end

local function recapture(ply, target, st)
    if not canRecapture(ply) then return false, "Повторное содержание проводят МОГ и охрана." end
    if not suppressed(st) then return false, "Объект не подавлен: сначала нужно его ослабить." end
    if not U.within(ply, target, 150) then return false, "Подойдите к объекту." end
    return SV.Actions.start(ply, {
        id = "recapture049", label = "Конвоирование SCP-049 в камеру", duration = K.recaptureTime, target = target, maxDist = 170,
        canContinue = function()
            if not st.breached then return false, "объект уже в камере" end
            -- Holding 049 at gunpoint keeps it suppressed.
            st.data.suppressedUntil = math.max(st.data.suppressedUntil or 0, CurTime() + 2)
            return true
        end,
        onComplete = function(p) SCP.recontain(ID, p, "escort") end,
    })
end

--[[---------------------------------------------------------------------------
Definition
---------------------------------------------------------------------------]]
SCP.register(ID, {
    name = "SCP-049", role = "scp049",
    regen = 1,
    setup = function(st)
        st.data.lastInterview = st.data.lastInterview or CurTime()
    end,
    conditions = {
        {id = "interview", name = "Беспокойство объекта", eval = function(st)
            local since = CurTime() - (st.data.lastInterview or 0)
            if since < K.interviewOk then return "ok", 0, "спокоен" end
            if since < K.interviewWarn then return "warn", -2, "требует собеседования" end
            return "bad", -4, "встревожен: давно не было собеседования"
        end},
        {id = "power", name = "Питание замков", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "containment") then return "ok", 0, "норма" end
            return "bad", -8, "замки обесточены"
        end},
        {id = "watch", name = "Наблюдение", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "cameras") then return "ok", 0, "камеры работают" end
            return "warn", -2, "камеры не работают"
        end},
    },
    procedures = {
        {
            id = "literature", name = "Передача медицинской литературы",
            desc = "Объекту передают записи о болезнях. Беспокойство временно снижается.",
            duration = 15, cooldown = 600, xp = 10, items = {notebook = 1}, roles = {"research", "medic"},
            rolesText = "выполняют научные сотрудники и медики",
            effect = function(st)
                st.data.lastInterview = math.max(st.data.lastInterview or 0, CurTime() - K.interviewOk / 2)
                SCP.adjustIntegrity(ID, 6, "literature")
            end,
        },
        {
            id = "inspection", name = "Осмотр камеры", desc = "Проверка замков и состояния объекта.",
            duration = 10, cooldown = 120, xp = 5,
            effect = function() SCP.adjustIntegrity(ID, 2, "inspection") end,
        },
    },
    abilities = abilities,
    recapture = recapture,
    onSpawn = function(st, ply)
        ply:SetRunSpeed(210)
        ply:SetWalkSpeed(120)
        st.data.suppressedUntil = nil
        Move.clear(ply, "049supp")
    end,
    onLeave = function(_, ply)
        if IsValid(ply) then Move.clear(ply, "049supp") end
        collapseAll()
    end,
    onDamage = function(st, ply, dmg)
        if ply:Health() - dmg:GetDamage() <= ply:GetMaxHealth() * K.suppressHealth and not suppressed(st) then
            st.data.suppressedUntil = CurTime() + K.suppressTime
            Move.set(ply, "049supp", {speed = 0.4, noattack = true})
            SV.Actions.cancel(ply, "подавлен")
            DarkRP.notify(ply, 1, K.suppressTime, "Вы подавлены огнём.")
            timer.Create("SiteVeil.SCP049.Supp", K.suppressTime, 1, function()
                if IsValid(ply) and not suppressed(st) then Move.clear(ply, "049supp") end
            end)
        end
    end,
    onRecontain = function(st, ply)
        st.data.suppressedUntil = nil
        if IsValid(ply) then
            Move.clear(ply, "049supp")
            ply:SetHealth(ply:GetMaxHealth())
        end
    end,
    publicData = function(st)
        return {instances = S049.instanceCount(), max = S049.maxInstances(), suppressed = suppressed(st)}
    end,
})

SV.Perf.registry("scp049.instances", S049.instanceCount)

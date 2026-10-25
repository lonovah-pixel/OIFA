--[[---------------------------------------------------------------------------
Medicine (server): wounds, bleeding, fractures, pain, incapacitation,
stabilisation, revival, examination and treatment.

Instead of dying from ordinary damage a character becomes incapacitated
("недееспособен") for a limited time: medics can stabilise and revive. Lethal
cases (head shots above a threshold, big explosions, finishing blows on an
incapacitated body, SCP executions) still kill. Incapacitation always ends:
death after the bleed-out timer, waking up after stabilisation, or the
player's own choice after C.Medical.giveUpAfter seconds.

Medical state is per life and resets on respawn.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Medical = SV.Medical
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local M = C.Medical
local Roles = SV.Roles
local Inv = SV.Inv
local Move = SV.Move

Medical.state = Medical.state or {} -- ply -> state

local function st(ply)
    local s = Medical.state[ply]
    if not s then
        s = {bleed = 0, fracture = false, pain = 0, hot = nil}
        Medical.state[ply] = s
    end
    return s
end
Medical.get = st

local function publish(ply)
    local s = Medical.state[ply]
    if not s then
        SV.Sync.setFor(ply, "self", "med", nil)
        return
    end
    SV.Sync.setFor(ply, "self", "med", {
        bleed = Medical.bleedLevel(s.bleed), fracture = s.fracture, pain = math.Round(s.pain),
        down = s.down and {since = s.down.since, deathAt = s.down.deathAt, stabilised = s.down.stabilised, wakeAt = s.down.wakeAt} or nil,
        infected = s.infected and s.infected.stage or nil,
    })
end
Medical.publish = publish

local function isMedic(ply)
    return Roles.hasFlag(ply, "medic")
end

local function isDoctor(ply)
    return Roles.hasFlag(ply, "doctor")
end

--[[---------------------------------------------------------------------------
Incapacitation
---------------------------------------------------------------------------]]
function Medical.isIncapacitated(ply)
    local s = Medical.state[ply]
    return s ~= nil and s.down ~= nil
end

function Medical.incapacitate(ply, cause, attacker)
    local s = st(ply)
    if s.down then return end
    local time = s.bleed >= M.bleedHeavy and M.bleedoutTimeHeavy or M.bleedoutTime
    s.down = {since = CurTime(), deathAt = CurTime() + time, stabilised = false, cause = cause}
    ply:SetHealth(1)
    ply:SetNW2Bool("sv_down", true)
    Move.set(ply, "down", {cap = M.crawlSpeed, nojump = true, noattack = true, nouse = true})
    if SV.Inv.get(ply) then
        for _, item in pairs(SV.Inv.get(ply).items) do
            if item.equipped then SV.Inv.holster(ply, item) end
        end
    end
    ply:EmitSound("vo/npc/male01/pain0" .. math.random(1, 9) .. ".wav", 70)
    DarkRP.notify(ply, 1, 8, "Вы недееспособны. Помощь медика может спасти жизнь.")
    publish(ply)
    SV.Audit.log("medical", "down", ply, IsValid(attacker) and attacker:IsPlayer() and attacker or nil, {cause = cause})
    SV.Bus.emit("medical.down", {ply = ply, cause = cause, attacker = attacker})
end

local function getUp(ply, health, reason)
    local s = Medical.state[ply]
    if not s or not s.down then return end
    s.down = nil
    ply:SetNW2Bool("sv_down", false)
    Move.clear(ply, "down")
    ply:SetHealth(math.max(health, 1))
    publish(ply)
    SV.Bus.emit("medical.up", {ply = ply, reason = reason})
end
Medical.getUp = getUp

function Medical.kill(ply, reason)
    local s = Medical.state[ply]
    if s then s.forceDeath = true end
    SV.Audit.log("medical", "death", ply, nil, {reason = reason})
    ply:Kill()
end

--[[---------------------------------------------------------------------------
Damage processing
---------------------------------------------------------------------------]]
hook.Add("ScalePlayerDamage", "SiteVeil.Medical", function(ply, hitgroup)
    ply.SVLastHitgroup = hitgroup
end)

--- Marks the next damage taken by ply as lethal (SCP executions). Damage
--- info objects are userdata, so the flag lives on the victim.
function Medical.markLethal(ply)
    ply.SVLethalUntil = CurTime() + 0.5
end

local function lethal(ply, dmg)
    if ply.SVLethalUntil and CurTime() <= ply.SVLethalUntil then
        ply.SVLethalUntil = nil
        return true
    end
    local amount = dmg:GetDamage()
    if dmg:IsBulletDamage() and ply.SVLastHitgroup == HITGROUP_HEAD and amount >= M.headshotLethal then return true end
    if dmg:IsExplosionDamage() and amount >= M.explosionLethal then return true end
    if dmg:IsDamageType(DMG_DIRECT) or dmg:IsDamageType(DMG_DISSOLVE) then return true end
    return false
end

hook.Add("EntityTakeDamage", "SiteVeil.Medical", function(ply, dmg)
    if not ply:IsPlayer() or not ply:Alive() or not ply.SVChar then return end
    if Roles.isSCP(ply) then return end
    local amount = dmg:GetDamage()
    if amount <= 0 then return end
    local s = st(ply)

    -- Wounds
    if dmg:IsBulletDamage() or dmg:IsDamageType(DMG_SLASH) then
        if amount >= 35 then s.bleed = math.min(s.bleed + M.bleedHeavy, M.bleedMax)
        elseif amount >= 15 then s.bleed = math.min(s.bleed + M.bleedLight, M.bleedMax) end
    end
    if dmg:IsFallDamage() and amount >= M.fractureFallDamage and not s.fracture then
        s.fracture = true
        Move.set(ply, "fracture", {speed = M.fractureSpeed})
        DarkRP.notify(ply, 1, 6, "Перелом ноги. Нужна шина.")
    end
    if dmg:IsExplosionDamage() and amount >= 40 and not s.fracture then
        s.fracture = true
        Move.set(ply, "fracture", {speed = M.fractureSpeed})
    end
    s.pain = math.min(s.pain + amount * M.painPerDamage, 100)

    if s.down then
        -- A wounded body: further serious damage kills.
        if amount >= 10 or lethal(ply, dmg) then
            dmg:SetDamage(ply:Health() + 100)
            s.forceDeath = true
        else
            dmg:SetDamage(0)
        end
        publish(ply)
        return
    end

    if ply:Health() - amount <= 0 then
        if lethal(ply, dmg) then
            s.forceDeath = true
        else
            -- incapacitate() sets health to 1 itself; the engine must not
            -- subtract anything after this hook.
            Medical.incapacitate(ply, dmg:IsBulletDamage() and "ранение" or "травма", dmg:GetAttacker())
            dmg:SetDamage(0)
            return
        end
    end
    publish(ply)
end)

--[[---------------------------------------------------------------------------
Ticks: bleeding, bleed-out, waking up, heal-over-time
---------------------------------------------------------------------------]]
local function tick()
    local now = CurTime()
    for ply, s in pairs(Medical.state) do
        if not IsValid(ply) or not ply:Alive() then
            Medical.state[ply] = nil
        else
            if s.bleed > 0 and not (s.down and s.down.stabilised) then
                if s.down then
                    -- Bleeding while down shortens the remaining time.
                    s.down.deathAt = s.down.deathAt - s.bleed
                elseif ply:Health() - s.bleed <= 0 then
                    Medical.incapacitate(ply, "кровопотеря")
                else
                    ply:SetHealth(ply:Health() - s.bleed)
                    if math.random() < 0.3 then ply:EmitSound("player/pl_pain" .. math.random(5, 7) .. ".wav", 55) end
                end
            end
            if s.down then
                if not s.down.stabilised and now >= s.down.deathAt then
                    DarkRP.notify(ply, 1, 6, "Вы погибли от полученных ран.")
                    Medical.kill(ply, "bleedout")
                elseif s.down.stabilised and now >= s.down.wakeAt then
                    getUp(ply, M.wakeHealth, "wake")
                    DarkRP.notify(ply, 0, 6, "Вы пришли в себя. Обратитесь в медблок.")
                end
            end
            if s.hot and ply:Alive() and not s.down then
                local h = s.hot
                local step = h.perTick
                ply:SetHealth(math.min(ply:Health() + step, ply:GetMaxHealth()))
                h.left = h.left - step
                if h.left <= 0 then s.hot = nil end
            end
            s.pain = math.max(s.pain - 1, 0)
            publish(ply)
        end
    end
end
timer.Create("SiteVeil.Medical", M.tick, 0, function() SV.Perf.time("medical.tick", tick) end)

--[[---------------------------------------------------------------------------
Death / respawn / disconnect
---------------------------------------------------------------------------]]
local function clear(ply)
    Medical.state[ply] = nil
    if IsValid(ply) then
        ply:SetNW2Bool("sv_down", false)
        Move.clear(ply, "down")
        Move.clear(ply, "fracture")
        Move.clear(ply, "stun")
        publish(ply)
    end
end
Medical.clear = clear

hook.Add("PlayerDeath", "SiteVeil.Medical", function(ply) clear(ply) end)
hook.Add("PlayerSpawn", "SiteVeil.Medical", function(ply) clear(ply) end)

-- Leaving the game while incapacitated counts as death for the character's
-- carried items (prevents escaping a lost fight by disconnecting).
hook.Add("SiteVeil.ShouldDropOnDisconnect", "SiteVeil.Medical", function(ply)
    if Medical.isIncapacitated(ply) then
        SV.Audit.log("medical", "disconnect.down", ply)
        return true
    end
end)

-- Cleared one tick later so that other disconnect handlers can still read it.
hook.Add("PlayerDisconnected", "SiteVeil.Medical", function(ply)
    timer.Simple(0, function() Medical.state[ply] = nil end)
end)

hook.Add("SiteVeil.CanUseAction", "SiteVeil.Medical", function(ply, name)
    if Medical.isIncapacitated(ply) and name ~= "med.giveup" and name ~= "action.cancel" and not string.find(name, "^char%.") and not string.find(name, "^tasks%.") then
        return false, "Вы недееспособны."
    end
end)

hook.Add("SiteVeil.CanSpeak", "SiteVeil.Medical", function(ply)
    local s = Medical.state[ply]
    if s and s.down and not s.down.stabilised and CurTime() - s.down.since < 5 then
        return false, "Вы без сознания."
    end
end)

hook.Add("SiteVeil.CanSwitchCharacter", "SiteVeil.Medical", function(ply)
    if Medical.isIncapacitated(ply) then return false, "Нельзя сменить персонажа в недееспособном состоянии." end
end)

hook.Add("SiteVeil.CanSuicide", "SiteVeil.Medical", function(ply)
    if Medical.isIncapacitated(ply) then return false end
end)

Net.handle("med.giveup", function(ply)
    local s = Medical.state[ply]
    if not s or not s.down then return false, "Вы не ранены." end
    if CurTime() - s.down.since < M.giveUpAfter then
        return false, "Это возможно через " .. math.ceil(M.giveUpAfter - (CurTime() - s.down.since)) .. " с."
    end
    Medical.kill(ply, "gaveup")
    return true
end)

--[[---------------------------------------------------------------------------
Examination
---------------------------------------------------------------------------]]
function Medical.report(target, examiner)
    local s = Medical.state[target] or {bleed = 0, pain = 0}
    local hp = target:Health() / math.max(target:GetMaxHealth(), 1)
    local lines = {}
    local condition = s.down and (s.down.stabilised and "без сознания, состояние стабильно" or "без сознания, критическое") or
        (hp < 0.3 and "тяжёлое" or (hp < 0.7 and "средней тяжести" or "удовлетворительное"))
    lines[#lines + 1] = "Состояние: " .. condition
    lines[#lines + 1] = "Кровотечение: " .. Medical.bleedNames[Medical.bleedLevel(s.bleed or 0)]
    lines[#lines + 1] = "Переломы: " .. (s.fracture and "закрытый перелом ноги" or "не выявлены")
    lines[#lines + 1] = "Болевой синдром: " .. ((s.pain or 0) > 60 and "выраженный" or ((s.pain or 0) > 25 and "умеренный" or "слабый"))
    if s.down and not s.down.stabilised then
        lines[#lines + 1] = "Без помощи: около " .. math.max(math.ceil(s.down.deathAt - CurTime()), 0) .. " с"
    end
    if s.infected and isDoctor(examiner) then
        lines[#lines + 1] = "Неизвестная инфекция: кашель, лихорадка (стадия " .. s.infected.stage .. ")"
    elseif s.infected then
        lines[#lines + 1] = "Симптомы: кашель, лихорадка"
    end
    local advice = {}
    if s.down and not s.down.stabilised then advice[#advice + 1] = "остановить кровотечение (стабилизация)" end
    if s.down then advice[#advice + 1] = "реанимация адреналином (врач)" end
    if (s.bleed or 0) >= M.bleedHeavy then advice[#advice + 1] = "жгут" elseif (s.bleed or 0) > 0 then advice[#advice + 1] = "перевязка" end
    if s.fracture then advice[#advice + 1] = "шина" end
    if hp < 0.7 and not s.down then advice[#advice + 1] = "аптечка" end
    if s.infected then advice[#advice + 1] = "антивирус (до 2-й стадии)" end
    return {name = SV.Chars.displayName(target), health = math.Round(hp * 100), lines = lines, advice = advice}
end

Net.handle("med.examine", function(ply, target)
    if not IsValid(target) or not target:IsPlayer() or not target.SVChar then return false, "Нет пациента." end
    if not U.within(ply, target, 110) then return false, "Подойдите к пациенту." end
    if not isMedic(ply) and target ~= ply then
        Net.send(ply, "med.report", {self = false, name = SV.Chars.displayName(target),
            lines = {Medical.isIncapacitated(target) and "Лежит без движения, дышит." or "Видимых тяжёлых травм нет."}, advice = {}})
        return
    end
    Net.send(ply, "med.report", Medical.report(target, ply))
    ply.SVExamined = ply.SVExamined or {}
    local last = ply.SVExamined[target]
    if target ~= ply and (not last or CurTime() - last > M.examineCooldown) then
        ply.SVExamined[target] = CurTime()
        SV.Bus.emit("medical.examined", {ply = ply, target = target})
    end
end)

--[[---------------------------------------------------------------------------
Treatment
---------------------------------------------------------------------------]]
local effects = {}

effects.bleed = function(medic, target, tr, s)
    if s.bleed <= 0 then return false, "кровотечения нет" end
    local amount = tr.amount * (isMedic(medic) and M.medicBonus or 1)
    s.bleed = math.max(s.bleed - amount, 0)
    if s.down and s.bleed <= 0 then
        s.down.stabilised = true
        s.down.wakeAt = CurTime() + M.stabilisedMax
    end
    return true
end

effects.fracture = function(_, target, _, s)
    if not s.fracture then return false, "перелома нет" end
    s.fracture = false
    Move.clear(target, "fracture")
    return true
end

effects.pain = function(_, _, tr, s)
    if s.pain <= 5 then return false, "боли нет" end
    s.pain = math.max(s.pain - tr.amount, 0)
    return true
end

effects.heal = function(medic, target, _, s)
    if s.down then return false, "сначала стабилизация и реанимация" end
    if target:Health() >= target:GetMaxHealth() then return false, "пациент здоров" end
    local total = M.medkitHeal * (isMedic(medic) and M.medicBonus or 1)
    s.hot = {left = total, perTick = total / (M.medkitDuration / M.tick)}
    return true
end

effects.revive = function(_, target, _, s)
    if not s.down then return false, "пациент в сознании" end
    if s.bleed >= M.bleedHeavy then return false, "сначала остановите сильное кровотечение" end
    getUp(target, M.reviveHealth, "revive")
    DarkRP.notify(target, 0, 6, "Вас вывели из недееспособности.")
    return true
end

effects.cure = function(_, target, _, s)
    if not s.infected then return false, "инфекции нет" end
    if s.infected.stage > 1 then return false, "инфекция слишком развилась" end
    s.infected = nil
    SV.Bus.emit("medical.cured", {ply = target})
    return true
end

--- Applies a treatment item from medic's inventory to target (may be self).
function Medical.treat(medic, target, itemId)
    local tr = C.Treatments[itemId]
    if not tr then return false, "Это не медицинское средство." end
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or not target.SVChar then return false, "Нет пациента." end
    if Roles.isSCP(target) then return false, "Объект SCP не лечится." end
    if target ~= medic and not U.within(medic, target, 90) then return false, "Подойдите к пациенту." end
    if tr.medicOnly and not isMedic(medic) then return false, "Применять может только медицинская служба." end
    if tr.doctor and not isDoctor(medic) then return false, "Реанимацию проводит врач." end
    if not Inv.has(medic, itemId) then return false, "Нет: " .. C.Items[itemId].name .. "." end
    if Medical.isIncapacitated(medic) then return false, "Вы недееспособны." end
    local s = st(target)
    local time = tr.time * (target == medic and 1.5 or 1) / (isMedic(medic) and 1.3 or 1)
    return SV.Actions.start(medic, {
        id = "treat", label = tr.label .. (target ~= medic and (": " .. SV.Chars.displayName(target)) or ""), duration = time,
        target = target ~= medic and target or nil, maxDist = 100,
        canContinue = function(p) return Inv.has(p, itemId), "средство закончилось" end,
        onComplete = function(p)
            if not IsValid(target) or not target:Alive() then return end
            local ok, why = effects[tr.effect](p, target, tr, s)
            if not ok then
                DarkRP.notify(p, 1, 4, tr.label .. ": " .. why .. ".")
                return
            end
            Inv.take(p, itemId, 1)
            publish(target)
            SV.Audit.log("medical", "treat", p, target, {item = itemId})
            if target ~= p then
                p.SVTreated = p.SVTreated or {}
                local key = tostring(target:EntIndex()) .. ":" .. tr.effect
                if not p.SVTreated[key] or CurTime() - p.SVTreated[key] > M.treatCooldown then
                    p.SVTreated[key] = CurTime()
                    SV.Bus.emit("medical.treated", {ply = p, target = target, effect = tr.effect})
                    if isMedic(p) then SV.Chars.addXP(p, tr.effect == "revive" and 20 or 8, "medical") end
                end
            end
        end,
    })
end

Net.handle("med.treat", function(ply, target, itemId)
    return Medical.treat(ply, target, itemId)
end)

Inv.registerUse("medical", function(ply, item, _, target)
    return Medical.treat(ply, IsValid(target) and target or ply, item.id)
end)

--- Infection used by SCP-049 (stage 1 = symptoms, stage 2 = advanced).
function Medical.infect(ply, source)
    local s = st(ply)
    if s.infected then
        s.infected.stage = math.min(s.infected.stage + 1, 2)
    else
        s.infected = {stage = 1, since = CurTime(), source = source}
    end
    publish(ply)
    return s.infected.stage
end

function Medical.infection(ply)
    local s = Medical.state[ply]
    return s and s.infected
end

--- Non-lethal stun (baton): several hits in a short time knock out.
function Medical.stunHit(ply, attacker)
    local s = st(ply)
    local now = CurTime()
    s.stunHits = s.stunHits or {}
    table.insert(s.stunHits, now)
    while s.stunHits[1] and s.stunHits[1] < now - M.stunWindow do table.remove(s.stunHits, 1) end
    Move.set(ply, "stun", {speed = 0.5, noattack = true})
    timer.Create("SiteVeil.Stun." .. ply:EntIndex(), 2, 1, function()
        if IsValid(ply) and not (Medical.state[ply] and Medical.state[ply].knockedOut) then Move.clear(ply, "stun") end
    end)
    if #s.stunHits >= M.stunHits and not s.down then
        s.stunHits = {}
        s.knockedOut = true
        Move.set(ply, "stun", {frozen = true, noattack = true, nouse = true})
        ply:ScreenFade(SCREENFADE.OUT, Color(0, 0, 0, 230), 0.5, M.stunTime - 1)
        DarkRP.notify(ply, 1, M.stunTime, "Вы оглушены.")
        SV.Bus.emit("medical.stunned", {ply = ply, attacker = attacker})
        timer.Create("SiteVeil.Stun." .. ply:EntIndex(), M.stunTime, 1, function()
            if not IsValid(ply) then return end
            local cur = Medical.state[ply]
            if cur then cur.knockedOut = nil end
            Move.clear(ply, "stun")
        end)
    end
end

function Medical.isStunned(ply)
    local s = Medical.state[ply]
    return s ~= nil and s.knockedOut == true
end

SV.Perf.registry("medical.patients", function() return U.count(Medical.state) end)

SV.DarkRP.chatCommand({command = "giveup", description = "Сдаться в недееспособном состоянии.", delay = 2}, function(ply)
    local ok, msg = Net.handlers["med.giveup"](ply)
    if msg then DarkRP.notify(ply, ok and 0 or 1, 4, msg) end
    return ""
end)

--[[---------------------------------------------------------------------------
Medical terminal: incapacitated personnel with sector and remaining time.
Locations come from the facility's vital-signs monitors, so they work only
in sectors with power and functional surveillance.
---------------------------------------------------------------------------]]
SV.Facility.registerTerminal("medical", {
    name = "Медицинский терминал", req = {clearance = 1, tags = {"medical"}}, power = 0.5,
    open = function(ply, ent)
        local list = {}
        for p, s in pairs(Medical.state) do
            if IsValid(p) and p:Alive() and s.down and p.SVChar then
                local sector = SV.Facility.sectorAt(p:GetPos())
                local tracked = SV.Facility.devicePowered(sector, "cameras")
                list[#list + 1] = {name = SV.Chars.displayName(p), sector = tracked and sector or nil, stabilised = s.down.stabilised,
                    left = not s.down.stabilised and math.max(math.ceil(s.down.deathAt - CurTime()), 0) or nil}
            end
        end
        table.sort(list, function(a, b) return (a.left or 1e9) < (b.left or 1e9) end)
        local stock = {}
        for _, id in ipairs({"bandage", "tourniquet", "splint", "painkillers", "medkit", "stimulant", "antiviral"}) do
            stock[#stock + 1] = {name = C.Items[id].name, count = SV.Supply.stock("medical", id)}
        end
        Net.send(ply, "med.terminal", {patients = list, stock = stock})
    end,
})

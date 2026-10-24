--[[---------------------------------------------------------------------------
Facility states (server).

Global state machine:
    normal ──▶ breach ──▶ evacuation ──▶ recovery ──▶ normal
                 └──────────────────────▶ recovery ──▶ breach (new breach)
Per sector flags: local alert (expires), lockdown (limited duration).

Every transition has: authority (role flag) or an automatic trigger,
conditions, notifications (banner, sound, chat) and consequences (budget,
recovery goals, evacuation credit). See ARCHITECTURE.md "Состояния комплекса".
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local F = C.Facility
local Roles = SV.Roles

Facility.state = Facility.state or {id = "normal", since = 0, reason = "", by = nil}
Facility.flags = Facility.flags or {}      -- sector -> {alert = {untilTime, reason}, lockdown = {...}}
Facility.recovery = Facility.recovery or nil
Facility.evacuated = Facility.evacuated or {}

local transitions = {
    normal = {breach = "declareBreach"},
    breach = {evacuation = "declareEvac", recovery = "declareRecovery"},
    evacuation = {recovery = "declareRecovery"},
    recovery = {normal = "declareRecovery", breach = "declareBreach"},
}

local function announce(text, sound, kind)
    Net.send(nil, "facility.announce", {text = text, sound = sound and C.Sounds[sound] or nil, kind = kind or "info"})
end
Facility.announce = announce

local function publishState()
    SV.Sync.set("facility", "state", {id = Facility.state.id, since = Facility.state.since, reason = Facility.state.reason})
    local alerts, lockdowns = {}, {}
    for sector, f in pairs(Facility.flags) do
        if f.alert then alerts[sector] = {untilTime = f.alert.untilTime, reason = f.alert.reason} end
        if f.lockdown then lockdowns[sector] = {untilTime = f.lockdown.untilTime} end
    end
    SV.Sync.set("facility", "alerts", alerts)
    SV.Sync.set("facility", "lockdowns", lockdowns)
    SV.Sync.set("facility", "recovery", Facility.recovery and {
        repairs = Facility.recovery.repairs, needed = Facility.recovery.needed, since = Facility.recovery.since,
    } or nil)
end
Facility.publishState = publishState

local function isAdminDuty(ply)
    return IsValid(ply) and SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply)
end

local function breachedSCPs()
    return SV.SCP and SV.SCP.breachedCount and SV.SCP.breachedCount() or 0
end

--- Changes the global state. actor nil = automatic. Returns ok, reason.
function Facility.setState(newId, actor, reason, opts)
    opts = opts or {}
    local cur = Facility.state.id
    if cur == newId then return false, "Режим уже действует." end
    local flag = transitions[cur] and transitions[cur][newId]
    if not flag and not opts.force then return false, "Недопустимый переход: " .. F.states[cur].name .. " → " .. (F.states[newId] and F.states[newId].name or newId) end
    if IsValid(actor) and not opts.force then
        if not Roles.hasFlag(actor, flag) and not isAdminDuty(actor) then return false, "Нет полномочий для этого решения." end
        if CurTime() - Facility.state.since < F.stateCooldown then
            return false, "Режим был изменён недавно. Повторное решение через " .. math.ceil(F.stateCooldown - (CurTime() - Facility.state.since)) .. " с."
        end
        if newId == "recovery" and breachedSCPs() > 0 then
            return false, "Объекты вне камер: " .. breachedSCPs() .. ". Восстановление объявляется после повторного содержания."
        end
        if newId == "normal" then
            local rec = Facility.recovery
            if rec and CurTime() - rec.since < F.recoveryMinTime then
                return false, "Восстановление длится не менее " .. U.formatDuration(F.recoveryMinTime) .. "."
            end
        end
    end
    reason = U.cleanText(reason or "", 200)
    local old = cur
    Facility.state = {id = newId, since = CurTime(), reason = reason, by = IsValid(actor) and actor:Nick() or "автоматически"}

    local who = IsValid(actor) and (SV.Chars.displayName(actor) .. ": ") or ""
    if newId == "breach" then
        announce("ВНИМАНИЕ: НАРУШЕНИЕ УСЛОВИЙ СОДЕРЖАНИЯ. " .. who .. (reason ~= "" and reason or "Персоналу следовать протоколу укрытия."), "alarmBreach", "breach")
        for div, amount in pairs(F.breachPenalty) do
            if SV.Supply then
                local take = math.min(amount, SV.Supply.budget(div))
                if take > 0 then SV.Supply.adjustBudget(div, -take, "Штраф: нарушение содержания", nil) end
            end
        end
        Facility.recovery = nil
    elseif newId == "evacuation" then
        announce("ОБЪЯВЛЕНА ЭВАКУАЦИЯ. " .. who .. "Персоналу проследовать в зоны эвакуации.", "alarmEvac", "evacuation")
        Facility.evacuated = {}
        -- Lockdowns are lifted so that people can leave.
        for sector, f in pairs(Facility.flags) do
            if f.lockdown then Facility.setLockdown(sector, nil, false, "эвакуация", true) end
        end
    elseif newId == "recovery" then
        local damaged = 0
        for _, n in pairs(Facility.nodes) do
            if n.health < F.healthOk or n.fault then damaged = damaged + 1 end
        end
        Facility.recovery = {since = CurTime(), repairs = 0, needed = math.Clamp(damaged, 0, 6)}
        announce("Режим ВОССТАНОВЛЕНИЯ. " .. who .. "Инженерам — восстановить узлы, охране — осмотреть секторы, медикам — помощь пострадавшим.", "announce", "recovery")
    elseif newId == "normal" then
        local rec = Facility.recovery
        if rec and rec.repairs >= rec.needed then
            for div, amount in pairs(F.recoveryBonus) do
                if SV.Supply then SV.Supply.adjustBudget(div, amount, "Премия: восстановление комплекса", nil) end
            end
        end
        Facility.recovery = nil
        announce("Комплекс возвращён в ШТАТНЫЙ РЕЖИМ.", "announce", "normal")
    end

    SV.Audit.log("facility", "state", actor, nil, {from = old, to = newId, reason = reason, auto = not IsValid(actor)})
    SV.Bus.emit("facility.stateChanged", {from = old, to = newId, actor = actor, reason = reason})
    publishState()
    return true
end

function Facility.stateId()
    return Facility.state.id
end

--[[---------------------------------------------------------------------------
Sector flags
---------------------------------------------------------------------------]]
local function sectorName(id)
    local s = Facility.sectors[id]
    return s and s.name or tostring(id)
end

function Facility.isLockedDown(sector)
    local f = sector and Facility.flags[sector]
    return f ~= nil and f.lockdown ~= nil
end

function Facility.hasAlert(sector)
    local f = sector and Facility.flags[sector]
    return f ~= nil and f.alert ~= nil
end

function Facility.setAlert(sector, actor, on, reason)
    if not Facility.sectors[sector] then return false, "Сектор не найден." end
    if IsValid(actor) and not Roles.hasFlag(actor, "declareAlert") and not isAdminDuty(actor) then return false, "Нет полномочий объявлять тревогу." end
    Facility.flags[sector] = Facility.flags[sector] or {}
    if on then
        Facility.flags[sector].alert = {untilTime = CurTime() + F.alertDuration, reason = U.cleanText(reason or "", 200)}
        announce("ЛОКАЛЬНАЯ ТРЕВОГА: " .. sectorName(sector) .. (reason and reason ~= "" and (". " .. reason) or ""), "alarmLocal", "alert")
    else
        Facility.flags[sector].alert = nil
        announce("Локальная тревога снята: " .. sectorName(sector), nil, "info")
    end
    SV.Audit.log("facility", on and "alert" or "alert.clear", actor, nil, {sector = sector, reason = reason})
    SV.Bus.emit("facility.alertChanged", {sector = sector, on = on, actor = actor})
    publishState()
    return true
end

function Facility.setLockdown(sector, actor, on, reason, silent)
    if not Facility.sectors[sector] then return false, "Сектор не найден." end
    if IsValid(actor) and not Roles.hasFlag(actor, "lockdown") and not isAdminDuty(actor) then return false, "Нет полномочий блокировать секторы." end
    Facility.flags[sector] = Facility.flags[sector] or {}
    local f = Facility.flags[sector]
    if on then
        if Facility.state.id == "evacuation" then return false, "Во время эвакуации секторы не блокируются." end
        if f.lockdown then
            if f.lockdown.extended >= F.lockdownExtendMax then return false, "Блокировку можно продлить только " .. F.lockdownExtendMax .. " раз." end
            f.lockdown.extended = f.lockdown.extended + 1
            f.lockdown.untilTime = CurTime() + F.lockdownMax
            announce("Блокировка сектора продлена: " .. sectorName(sector), nil, "lockdown")
        else
            f.lockdown = {untilTime = CurTime() + F.lockdownMax, extended = 0, by = IsValid(actor) and actor:Nick() or "система"}
            announce("БЛОКИРОВКА СЕКТОРА: " .. sectorName(sector) .. ". Проход по картам с допуском 4 и выше.", "alarmLocal", "lockdown")
        end
    else
        if not f.lockdown then return false, "Сектор не заблокирован." end
        f.lockdown = nil
        if not silent then announce("Блокировка снята: " .. sectorName(sector), nil, "info") end
    end
    SV.Audit.log("facility", on and "lockdown" or "lockdown.clear", actor, nil, {sector = sector, reason = reason})
    SV.Bus.emit("facility.lockdownChanged", {sector = sector, on = on, actor = actor})
    publishState()
    return true
end

--[[---------------------------------------------------------------------------
Automatic transitions and expiry
---------------------------------------------------------------------------]]
SV.Bus.on("scp.breached", "facility", function(data)
    local st = Facility.state.id
    if st == "normal" or st == "recovery" then
        Facility.setState("breach", nil, (data.name or "Объект") .. " покинул камеру содержания.")
    end
end)

SV.Bus.on("scp.recontained", "facility", function()
    local st = Facility.state.id
    if (st == "breach" or st == "evacuation") and breachedSCPs() == 0 then
        Facility.setState("recovery", nil, "Все объекты возвращены в камеры.")
    end
end)

SV.Bus.on("node.repaired", "facility.recovery", function()
    local rec = Facility.recovery
    if rec then
        rec.repairs = rec.repairs + 1
        publishState()
    end
end)

local function evacuationTick()
    for _, zone in ipairs(SV.MapCfg.zones("evac")) do
        for _, ply in ipairs(player.GetAll()) do
            if ply.SVChar and ply:Alive() and not Roles.isSCP(ply) and not Facility.evacuated[ply.SVChar.id]
                and SV.MapCfg.zoneContains(zone, ply:GetPos()) then
                Facility.evacuated[ply.SVChar.id] = true
                local xp = SV.Chars.addXP(ply, F.evacuationXP, "evacuation")
                DarkRP.notify(ply, 0, 6, "Вы эвакуированы в «" .. (zone.name or "зону эвакуации") .. "»." .. (xp > 0 and (" +" .. xp .. " опыта") or ""))
                SV.Bus.emit("facility.evacuated", {ply = ply, zone = zone.id})
            end
        end
    end
end

timer.Create("SiteVeil.Facility.States", 2, 0, function()
    local now = CurTime()
    for sector, f in pairs(Facility.flags) do
        if f.alert and now >= f.alert.untilTime then
            f.alert = nil
            announce("Локальная тревога истекла: " .. sectorName(sector), nil, "info")
            SV.Bus.emit("facility.alertChanged", {sector = sector, on = false})
            publishState()
        end
        if f.lockdown and now >= f.lockdown.untilTime then
            f.lockdown = nil
            announce("Блокировка снята по истечении времени: " .. sectorName(sector), nil, "info")
            SV.Bus.emit("facility.lockdownChanged", {sector = sector, on = false})
            publishState()
        end
    end
    local st = Facility.state.id
    if st == "evacuation" then evacuationTick() end
    if st == "recovery" and Facility.recovery then
        local rec = Facility.recovery
        local age = now - rec.since
        if age >= F.recoveryMaxTime or (age >= F.recoveryMinTime and rec.repairs >= rec.needed and Facility.averageHealth() >= F.recoveryInfraTarget) then
            Facility.setState("normal", nil, "Восстановление завершено.")
        end
    end
end)

--[[---------------------------------------------------------------------------
Network
---------------------------------------------------------------------------]]
Net.handle("facility.declare", function(ply, what, target, reason)
    if what == "state" then
        return Facility.setState(target, ply, reason)
    elseif what == "alert" or what == "alertoff" then
        return Facility.setAlert(target, ply, what == "alert", reason)
    elseif what == "lockdown" or what == "unlock" then
        return Facility.setLockdown(target, ply, what == "lockdown", reason)
    end
    Net.violation(ply, "unknown facility declaration")
    return false
end)

Net.handle("facility.status", function(ply)
    local sectors = {}
    for id, s in pairs(Facility.sectors) do sectors[#sectors + 1] = {id = id, name = s.name} end
    table.sort(sectors, function(a, b) return a.name < b.name end)
    local flags = {}
    for _, f in ipairs({"declareAlert", "declareBreach", "declareEvac", "declareRecovery", "lockdown"}) do
        flags[f] = Roles.hasFlag(ply, f) or isAdminDuty(ply)
    end
    local allowed = {}
    for to in pairs(transitions[Facility.state.id] or {}) do allowed[#allowed + 1] = to end
    table.sort(allowed)
    Net.send(ply, "facility.status", {sectors = sectors, flags = flags, allowed = allowed, breached = breachedSCPs(),
        mySector = Facility.sectorOf(ply)})
end)

hook.Add("SiteVeil.DatabaseReady", "SiteVeil.Facility.State", function()
    Facility.state = {id = "normal", since = CurTime(), reason = "", by = nil}
    publishState()
end)

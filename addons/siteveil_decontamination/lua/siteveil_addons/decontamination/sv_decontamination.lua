--[[---------------------------------------------------------------------------
Sector decontamination (server).

Ordered by staff with declareBreach / declareEvac (or an admin on duty).
Phases: warning (countdown, doors still open) -> gas (sector lockdown,
damage to unprotected people) -> end (lockdown lifted). Cannot be ordered
during an evacuation; one at a time; per-sector cooldown; cancellable by the
same authority. Every step is announced and audited.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Decon = SV.Decon
local Net = SV.Net
local K = SV.Config.Decontamination
local Facility = SV.Facility
local Roles = SV.Roles

Decon.active = Decon.active or nil       -- {sector, phase, at, by, lockedByUs}
Decon.lastAt = Decon.lastAt or {}        -- sector -> CurTime of the end

local function sectorName(id)
    local s = Facility.sectors[id]
    return s and s.name or tostring(id)
end

local function authorized(ply)
    if SV.Admin.isOnDuty(ply) then return true end
    for _, f in ipairs(K.flags) do
        if Roles.hasFlag(ply, f) then return true end
    end
    return false
end

local function publish()
    local a = Decon.active
    SV.Sync.set("decon", "state", a and {sector = a.sector, name = sectorName(a.sector), phase = a.phase, at = a.at} or nil)
end

--- Why decontamination of sector cannot be ordered now (nil = can).
function Decon.blockedReason(sector)
    if not Facility.sectors[sector] then return "сектор не найден" end
    if Decon.active then return "обеззараживание уже идёт (" .. sectorName(Decon.active.sector) .. ")" end
    if Facility.stateId() == "evacuation" then return "идёт эвакуация" end
    local last = Decon.lastAt[sector]
    if last and CurTime() - last < K.cooldown then
        return "повтор через " .. SV.Util.formatDuration(K.cooldown - (CurTime() - last))
    end
    return nil
end

function Decon.start(sector, by)
    local why = Decon.blockedReason(sector)
    if why then return false, "Обеззараживание невозможно: " .. why .. "." end
    Decon.active = {sector = sector, phase = "warn", at = CurTime() + K.warnTime, by = by, announced = {}}
    Facility.announce("ОБЕЗЗАРАЖИВАНИЕ СЕКТОРА «" .. sectorName(sector) .. "» через " .. K.warnTime .. " с. Покиньте сектор или наденьте средства защиты.",
        "alarmLocal", "alert")
    SV.Audit.log("decontamination", "order", by, nil, {sector = sector})
    SV.Bus.emit("decon.ordered", {ply = by, sector = sector})
    publish()
    return true
end

local function finish(reason, by)
    local a = Decon.active
    if not a then return end
    Decon.active = nil
    if a.lockedByUs and Facility.isLockedDown(a.sector) then Facility.setLockdown(a.sector, nil, false, "decontamination end", true) end
    Decon.lastAt[a.sector] = CurTime()
    Facility.announce("Обеззараживание сектора «" .. sectorName(a.sector) .. "» " .. (reason == "cancel" and "отменено." or "завершено."), nil, "info")
    SV.Audit.log("decontamination", reason, by, nil, {sector = a.sector})
    SV.Bus.emit("decon.finished", {sector = a.sector, reason = reason})
    publish()
end
Decon.finish = finish

local function protected(p)
    for _, item in ipairs(K.protection) do
        if SV.Inv.isWearing(p, item) then return true end
    end
    return false
end

local function affected(p, sector)
    if not p:Alive() or not p.SVChar or SV.Admin.isOnDuty(p) then return false end
    if Roles.isSCP(p) and not K.affectsRoles[Roles.ofPlayer(p).id] then return false end
    if Facility.sectorAt(p:GetPos()) ~= sector then return false end
    return not protected(p)
end

local nextDamage = 0
timer.Create("SiteVeil.Decon", 0.5, 0, function()
    local a = Decon.active
    if not a then return end
    local now = CurTime()
    if a.phase == "warn" then
        local left = math.ceil(a.at - now)
        for _, t in ipairs(K.announceAt) do
            if left <= t and not a.announced[t] then
                a.announced[t] = true
                Facility.announce("Обеззараживание «" .. sectorName(a.sector) .. "» через " .. t .. " с.", "alarmLocal", "alert")
            end
        end
        if now >= a.at then
            a.phase = "gas"
            a.at = now + K.duration
            if not Facility.isLockedDown(a.sector) then
                a.lockedByUs = Facility.setLockdown(a.sector, nil, true, "Обеззараживание") == true
            end
            Facility.announce("ОБЕЗЗАРАЖИВАНИЕ: сектор «" .. sectorName(a.sector) .. "» заблокирован, подаётся газ.", "alarmLocal", "lockdown")
            nextDamage = now
            publish()
        end
    elseif a.phase == "gas" then
        if now >= a.at then
            finish("end")
            return
        end
        if now >= nextDamage then
            nextDamage = now + K.tick
            for _, p in ipairs(player.GetAll()) do
                if affected(p, a.sector) then
                    local d = DamageInfo()
                    d:SetDamage(K.damage)
                    d:SetDamageType(DMG_NERVEGAS)
                    d:SetAttacker(game.GetWorld())
                    d:SetInflictor(game.GetWorld())
                    p:TakeDamageInfo(d)
                end
            end
        end
    end
end)

Net.handle("decon.start", function(ply, sector)
    if not authorized(ply) then return false, "Обеззараживание объявляют командование комплекса и службы безопасности." end
    return Decon.start(sector, ply)
end)

Net.handle("decon.cancel", function(ply, sector)
    if not authorized(ply) then return false, "Нет полномочий." end
    if not Decon.active or Decon.active.sector ~= sector then return false, "Обеззараживание этого сектора не идёт." end
    finish("cancel", ply)
    return true
end)

--[[---------------------------------------------------------------------------
Access control (server): card registry, credentials, doors, buttons,
temporary passes, revocation, access logs, emergency opening.

Source of truth for permissions to pass doors and use terminals. Physical
cards (inventory items) carry only a serial; clearance and zone tags are
stored in sv_cards and checked on every use, so revoking a serial instantly
disables every copy of that card.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Access = SV.Access
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local Roles = SV.Roles
local Inv = SV.Inv


Access.cards = Access.cards or {}     -- serial -> card (cache)
Access.creds = Access.creds or {}     -- ply -> {clearance, tags, serials}
Access.logs = Access.logs or {}       -- key -> ring buffer
Access.openDoors = Access.openDoors or {}  -- door -> close time

DB.registerMigrations("access", {
    {1, "card registry", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_cards (
            serial TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            char_id INTEGER,
            holder_name TEXT,
            holder_number TEXT,
            clearance INTEGER NOT NULL,
            tags TEXT NOT NULL,
            issued_by INTEGER,
            issued_at INTEGER NOT NULL,
            expires_at INTEGER,
            revoked_at INTEGER,
            revoked_by INTEGER,
            reason TEXT
        )]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_cards_char ON sv_cards (char_id, kind)")
    end},
})

--[[---------------------------------------------------------------------------
Registry
---------------------------------------------------------------------------]]
local function newSerial()
    for _ = 1, 50 do
        local s = string.format("%04X-%04X", math.random(0, 65535), math.random(0, 65535))
        if not DB.queryValue("SELECT 1 FROM sv_cards WHERE serial = ?", s) then return s end
    end
    error("cannot allocate card serial")
end

local function rowToCard(row)
    local tags = {}
    for _, t in ipairs(DB.decode(row.tags)) do tags[t] = true end
    return {
        serial = row.serial, kind = row.kind, charId = tonumber(row.char_id), holderName = row.holder_name,
        holderNumber = row.holder_number, clearance = tonumber(row.clearance), tags = tags, tagList = DB.decode(row.tags),
        issuedAt = tonumber(row.issued_at), expiresAt = tonumber(row.expires_at), revokedAt = tonumber(row.revoked_at),
        reason = row.reason,
    }
end

function Access.card(serial)
    if not isstring(serial) then return nil end
    local card = Access.cards[serial]
    if card then return card end
    local row = DB.queryRow("SELECT * FROM sv_cards WHERE serial = ?", serial)
    if not row then return nil end
    card = rowToCard(row)
    Access.cards[serial] = card
    return card
end

function Access.cardValid(card)
    if not card then return false, "карта не зарегистрирована" end
    if card.revokedAt then return false, "карта аннулирована" end
    if card.expiresAt and os.time() >= card.expiresAt then return false, "срок действия истёк" end
    return true
end

function Access.registerCard(kind, char, clearance, tagList, issuer, minutes)
    local serial = newSerial()
    local expires = minutes and (os.time() + minutes * 60) or nil
    DB.query([[INSERT INTO sv_cards (serial, kind, char_id, holder_name, holder_number, clearance, tags, issued_by, issued_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], serial, kind, char and char.id, char and char.name, char and char.number,
        clearance, DB.encode(tagList), issuer and issuer.SVChar and issuer.SVChar.id or nil, os.time(), expires)
    Access.cards[serial] = nil
    return serial, expires
end

function Access.revokeCard(serial, actor, reason)
    local card = Access.card(serial)
    if not card then return false, "карта не найдена" end
    if card.revokedAt then return false, "карта уже аннулирована" end
    DB.query("UPDATE sv_cards SET revoked_at = ?, revoked_by = ?, reason = ? WHERE serial = ?",
        os.time(), IsValid(actor) and actor.SVChar and actor.SVChar.id or nil, reason or "", serial)
    Access.cards[serial] = nil
    Access.invalidateAll()
    SV.Audit.log("access", "card.revoke", actor, nil, {serial = serial, reason = reason})
    SV.Bus.emit("access.cardRevoked", {serial = serial, ply = actor, reason = reason})
    return true
end

--[[---------------------------------------------------------------------------
Service ID cards follow the role
---------------------------------------------------------------------------]]
local function roleTags(role)
    local list = {}
    for _, t in ipairs(role.tags or {}) do list[#list + 1] = t end
    return list
end

local function issueIdCardData(ply, item)
    local char = ply.SVChar
    local role = Roles.ofPlayer(ply)
    if not char or not role then return end
    local serial = Access.registerCard("id", char, role.clearance, roleTags(role), nil, nil)
    item.data = {serial = serial, holder = char.name, number = char.number, role = role.id}
    Inv.saveItem(item)
end

hook.Add("SiteVeil.ItemCreated", "SiteVeil.Access", function(ply, item)
    if item.id == "id_card" then issueIdCardData(ply, item) end
end)

--- Makes sure the character's own ID card matches the current role; the old
--- serial is revoked when the role changed.
function Access.syncIdCard(ply)
    local char = ply.SVChar
    local role = Roles.ofPlayer(ply)
    if not char or not role or role.scp then return end
    for _, item in ipairs(Inv.find(ply, function(it) return it.id == "id_card" and it.issuedTo == char.id end)) do
        local card = Access.card(item.data.serial)
        if not card or card.revokedAt or item.data.role ~= role.id then
            if card and not card.revokedAt then Access.revokeCard(card.serial, nil, "Смена должности") end
            issueIdCardData(ply, item)
            Inv.changed(ply)
        end
    end
    Access.invalidate(ply)
end

hook.Add("SiteVeil.RoleSpawn", "SiteVeil.Access", function(ply)
    -- Runs after the kit is ensured (inventory registers its hook first in the
    -- manifest; ensureKit is idempotent anyway).
    timer.Simple(0, function() if IsValid(ply) then Access.syncIdCard(ply) end end)
end)

--[[---------------------------------------------------------------------------
Credentials
---------------------------------------------------------------------------]]
function Access.invalidate(ply)
    Access.creds[ply] = nil
    if IsValid(ply) then
        timer.Simple(0, function()
            if IsValid(ply) then
                local cr = Access.credentials(ply)
                SV.Sync.setFor(ply, "self", "clearance", cr.clearance)
            end
        end)
    end
end

function Access.invalidateAll()
    for ply in pairs(Access.creds) do Access.invalidate(ply) end
end

--- Best clearance and the union of tags of all valid cards the player holds.
function Access.credentials(ply)
    local cached = Access.creds[ply]
    if cached and cached.validUntil > os.time() then return cached end
    local cr = {clearance = 0, tags = {}, serials = {}, validUntil = os.time() + 30}
    if SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply) then
        cr.clearance = 5
        for t in pairs(Access.TAG_NAMES) do cr.tags[t] = true end
        cr.admin = true
    elseif ply.SVChar and Inv.get(ply) then
        for _, item in ipairs(Inv.find(ply, function(it, def) return def.category == "keycard" end)) do
            local card = Access.card(item.data.serial)
            if Access.cardValid(card) then
                cr.serials[#cr.serials + 1] = card.serial
                cr.clearance = math.max(cr.clearance, card.clearance)
                for t in pairs(card.tags) do cr.tags[t] = true end
                if card.expiresAt then cr.validUntil = math.min(cr.validUntil, card.expiresAt) end
            end
        end
    end
    Access.creds[ply] = cr
    return cr
end

function Access.clearance(ply)
    return Access.credentials(ply).clearance
end

function Access.hasTag(ply, tag)
    return Access.credentials(ply).tags[tag] == true
end

hook.Add("SiteVeil.InventoryChanged", "SiteVeil.Access", function(ply) Access.invalidate(ply) end)
hook.Add("PlayerDisconnected", "SiteVeil.Access", function(ply) Access.creds[ply] = nil end)

--- Full check used by doors, buttons and terminals. Returns ok, reason, serial.
function Access.check(ply, req)
    if not req then return true end
    if Roles.isSCP(ply) then return false, "объект SCP" end
    local cr = Access.credentials(ply)
    if #cr.serials == 0 and not cr.admin then return false, "нет действующей карты доступа" end
    local ok, reason = Access.meets(req, cr.clearance, cr.tags)
    return ok, reason, cr.serials[1]
end

--[[---------------------------------------------------------------------------
Logs
---------------------------------------------------------------------------]]
local function sectorOf(ent, cfg)
    if cfg and cfg.sector then return cfg.sector end
    local zone = SV.MapCfg.sectorAt(ent:GetPos())
    return zone and zone.id or nil
end
Access.sectorOf = sectorOf

local function recordingWorks(sectorId)
    local fac = SV.Facility
    if not fac or not fac.subsystemOk then return true end
    return fac.subsystemOk(sectorId, "security")
end

--- Appends an access log entry. Exact data go to the audit log; the game log
--- keeps the card serial and a rounded time, and nothing at all while the
--- sector's security subsystem is down.
function Access.logEntry(key, ply, ok, reason, serial, sectorId, kind)
    local buf = Access.logs[key] or {}
    Access.logs[key] = buf
    local recorded = recordingWorks(sectorId)
    table.insert(buf, {t = os.time(), serial = recorded and serial or nil, ok = ok, reason = reason, recorded = recorded, kind = kind})
    while #buf > C.Access.logSize do table.remove(buf, 1) end
    SV.Audit.log("access", ok and "granted" or "denied", ply, nil, {key = key, serial = serial, reason = reason, kind = kind, sector = sectorId})
    SV.Bus.emit("access.used", {ply = ply, key = key, ok = ok, serial = serial, sector = sectorId, kind = kind})
end

--- Game view of a log (for terminals): rounded times, gaps for missing data.
function Access.gameLog(key)
    local out = {}
    for i = #(Access.logs[key] or {}), 1, -1 do
        local e = Access.logs[key][i]
        if e.recorded then
            out[#out + 1] = {time = U.clockString(e.t, C.Access.logTimePrecision), serial = e.serial or "—", ok = e.ok, kind = e.kind}
        else
            out[#out + 1] = {time = U.clockString(e.t, 30), serial = "—", gap = true}
        end
    end
    return out
end

--[[---------------------------------------------------------------------------
Doors
---------------------------------------------------------------------------]]
local function doorKey(ent)
    return "door:" .. tostring(ent:MapCreationID())
end
Access.doorKey = doorKey

local function isButton(ent)
    local c = ent:GetClass()
    return c == "func_button" or c == "func_rot_button" or c == "momentary_rot_button"
end

local function doorOpen(ent, seconds)
    ent:Fire("Unlock", "", 0)
    ent:Fire("Open", "", 0)
    Access.openDoors[ent] = CurTime() + seconds
end
Access.openDoor = doorOpen

local function doorClose(ent)
    Access.openDoors[ent] = nil
    if not IsValid(ent) then return end
    ent:Fire("Close", "", 0)
    ent:Fire("Lock", "", 0.5)
end

function Access.doorPowerState(ent, cfg)
    local fac = SV.Facility
    local sector = sectorOf(ent, cfg)
    local powered = not fac or not fac.devicePowered or fac.devicePowered(sector, "doors")
    local lockdown = fac and fac.isLockedDown and fac.isLockedDown(sector) or false
    return powered, lockdown, sector
end

--- Applies the resting state of every configured door (start, cleanup,
--- power changes): controlled doors locked, fail-safe doors without power
--- unlocked.
function Access.applyDoorStates()
    if not SV.MapCfg.cfg then return end
    for key, cfg in pairs(SV.MapCfg.cfg.doors) do
        local ent = ents.GetMapCreatedEntity(tonumber(key))
        if IsValid(ent) and not isButton(ent) and cfg.policy ~= "open" and not Access.openDoors[ent] then
            local powered = Access.doorPowerState(ent, cfg)
            if not powered and cfg.failMode == "safe" then
                ent:Fire("Unlock", "", 0)
            else
                ent:Fire("Close", "", 0)
                ent:Fire("Lock", "", 0.2)
            end
        end
    end
end

hook.Add("SiteVeil.MapEntitiesSpawned", "SiteVeil.Access", Access.applyDoorStates)
SV.Bus.on("facility.powerChanged", "access", function() Access.applyDoorStates() end)
SV.Bus.on("facility.lockdownChanged", "access", function() Access.applyDoorStates() end)

timer.Create("SiteVeil.Access.Doors", 0.5, 0, function()
    local now = CurTime()
    for ent, closeAt in pairs(Access.openDoors) do
        if not IsValid(ent) then Access.openDoors[ent] = nil
        elseif now >= closeAt then doorClose(ent) end
    end
end)

local function canEmergency(ply)
    return Roles.hasFlag(ply, "emergencyOverride")
end

--- Handles E on a configured door or button. Returns the PlayerUse result.
function Access.useDoor(ply, ent, cfg)
    if cfg.policy == "open" then return nil end
    local now = CurTime()
    if (ply.SVNextDoorUse or 0) > now then return false end
    ply.SVNextDoorUse = now + C.Access.useThrottle

    local button = isButton(ent)
    if not button and Access.openDoors[ent] then return false end -- already open, closes automatically

    local key = doorKey(ent)
    local powered, lockdown, sector = Access.doorPowerState(ent, cfg)
    local name = cfg.name or (button and "Кнопка" or "Дверь")

    if not powered then
        if cfg.failMode == "safe" then return nil end
        Access.logEntry(key, ply, false, "нет питания", nil, sector, "use")
        local canCrank = Roles.hasFlag(ply, "engineer") or canEmergency(ply)
        DarkRP.notify(ply, 1, 4, name .. ": нет питания, считыватель не работает." .. (canCrank and " Используйте ручной привод (инструмент техника)." or ""))
        Net.send(ply, "access.denied", {ent = ent:EntIndex(), name = name, reason = "нет питания", crank = canCrank and not button})
        return false
    end

    if cfg.policy == "locked" and not canEmergency(ply) then
        Access.logEntry(key, ply, false, "закрыто постоянно", nil, sector, "use")
        DarkRP.notify(ply, 1, 4, name .. ": проход закрыт.")
        return false
    end

    local req = {clearance = cfg.clearance or 0, tags = cfg.tags, tagMode = cfg.tagMode}
    if lockdown and not cfg.lockdownExempt then
        req.clearance = math.max(req.clearance, 4)
    end
    local ok, reason, serial = Access.check(ply, req)
    if cfg.policy == "locked" then ok, reason = false, "закрыто постоянно" end

    Access.logEntry(key, ply, ok, reason, serial, sector, "use")
    if ok then
        ent:EmitSound(C.Sounds.granted, 65)
        if button then return nil end
        doorOpen(ent, cfg.autoClose or C.Access.autoClose)
        return false
    end

    ent:EmitSound(C.Sounds.denied, 65)
    local text = name .. ": доступ запрещён (" .. tostring(reason) .. ")" .. (lockdown and ". Сектор заблокирован." or "")
    DarkRP.notify(ply, 1, 4, text)
    Net.send(ply, "access.denied", {ent = ent:EntIndex(), name = name, reason = reason, emergency = canEmergency(ply) and not button})
    return false
end

hook.Add("PlayerUse", "SiteVeil.Access", function(ply, ent)
    if not ply.SVChar then return false end
    local cfg = SV.MapCfg.doorConfig(ent)
    if not cfg then return end
    return Access.useDoor(ply, ent, cfg)
end)

Net.handle("access.emergency", function(ply, ent)
    if not IsValid(ent) then return false, "Дверь не найдена." end
    local cfg = SV.MapCfg.doorConfig(ent)
    if not cfg or isButton(ent) then return false, "Это не управляемая дверь." end
    if not canEmergency(ply) then
        SV.Net.violation(ply, "emergency open without authority")
        return false, "Нет полномочий для аварийного открытия."
    end
    if not U.within(ply, ent, 140) then return false, "Подойдите к двери." end
    local now = CurTime()
    if (ply.SVNextEmergency or 0) > now then
        return false, "Повторное аварийное открытие через " .. math.ceil(ply.SVNextEmergency - now) .. " с."
    end
    ply.SVNextEmergency = now + C.Access.emergencyCooldown
    local _, _, sector = Access.doorPowerState(ent, cfg)
    doorOpen(ent, C.Access.emergencyOpenTime)
    ent:EmitSound(C.Sounds.alarmLocal, 70)
    local cr = Access.credentials(ply)
    Access.logEntry(doorKey(ent), ply, true, "аварийное открытие", cr.serials[1], sector, "emergency")
    SV.Bus.emit("access.emergency", {ply = ply, door = ent, sector = sector, name = cfg.name})
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and Roles.hasFlag(p, "canDetain") then
            DarkRP.notify(p, 3, 6, "Аварийное открытие: " .. (cfg.name or "дверь") .. (sector and SV.MapCfg.zone(sector) and (" (" .. SV.MapCfg.zone(sector).name .. ")") or ""))
        end
    end
    return true, "Дверь открыта аварийно. Действие записано."
end)

Net.handle("access.crank", function(ply, ent)
    if not IsValid(ent) then return false, "Дверь не найдена." end
    local cfg = SV.MapCfg.doorConfig(ent)
    if not cfg or isButton(ent) then return false, "Ручной привод недоступен." end
    if not (Roles.hasFlag(ply, "engineer") or canEmergency(ply)) then return false, "Нужен техник или аварийные полномочия." end
    if not ply:HasWeapon("sv_toolkit") and not canEmergency(ply) then return false, "Нужен инструмент техника." end
    local powered = Access.doorPowerState(ent, cfg)
    if powered then return false, "Дверь под питанием: используйте карту." end
    return SV.Actions.start(ply, {
        id = "crank", label = "Ручной привод двери", duration = C.Access.crankTime, target = ent, maxDist = 140,
        onComplete = function(p)
            doorOpen(ent, C.Access.crankOpenTime)
            Access.logEntry(doorKey(ent), p, true, "ручной привод", nil, Access.sectorOf(ent, cfg), "crank")
            SV.Bus.emit("access.cranked", {ply = p, door = ent})
        end,
    })
end)

--[[---------------------------------------------------------------------------
Temporary passes and revocation
---------------------------------------------------------------------------]]
Net.handle("access.issuePass", function(ply, target, clearance, tagCsv, minutes)
    if not Roles.hasFlag(ply, "issuePasses") then return false, "Нет полномочий выдавать пропуска." end
    if not IsValid(target) or not target:IsPlayer() or not target.SVChar or target == ply then return false, "Выберите сотрудника рядом с собой." end
    if not U.within(ply, target, 200) then return false, "Сотрудник слишком далеко." end
    local role = Roles.ofPlayer(ply)
    local maxClear = math.min(role.clearance, C.Access.passMaxClearance)
    if clearance > maxClear then return false, "Можно выдать допуск не выше " .. maxClear .. "." end
    minutes = math.Clamp(minutes, 1, C.Access.passMaxMinutes)
    local tags = {}
    local issuerTags = U.set(role.tags)
    for t in string.gmatch(tagCsv or "", "[^,%s]+") do
        if not issuerTags[t] then return false, "Нельзя выдать доступ к зоне, которой нет у вас: " .. (Access.TAG_NAMES[t] or t) end
        tags[#tags + 1] = t
    end
    local serial, expires = Access.registerCard("temp", target.SVChar, clearance, tags, ply, minutes)
    local ok, reason = Inv.add(target, "temp_pass", 1, {force = true, data = {serial = serial, expires = expires, label = "Допуск " .. clearance}})
    if not ok then return false, reason end
    SV.Audit.log("access", "pass.issue", ply, target, {serial = serial, clearance = clearance, tags = tags, minutes = minutes})
    SV.Bus.emit("access.passIssued", {ply = ply, target = target, serial = serial})
    DarkRP.notify(target, 0, 6, "Вам выдан временный пропуск " .. serial .. " на " .. minutes .. " мин.")
    return true, "Пропуск " .. serial .. " выдан."
end)

Net.handle("access.revoke", function(ply, serial, reason)
    serial = string.upper(U.cleanText(serial, 16))
    local card = Access.card(serial)
    if not card then return false, "Карта " .. serial .. " не найдена в реестре." end
    local allowed = Roles.hasFlag(ply, "revokeCards") or (card.kind == "temp" and Roles.hasFlag(ply, "issuePasses"))
        or (SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply))
    if not allowed then return false, "Нет полномочий аннулировать карты." end
    local ok, err = Access.revokeCard(serial, ply, U.cleanText(reason, 120))
    if not ok then return false, err end
    return true, "Карта " .. serial .. " аннулирована."
end)

--- Registry overview for the security terminal.
Net.handle("access.cards", function(ply)
    local canSee = Roles.hasFlag(ply, "issuePasses") or Roles.hasFlag(ply, "revokeCards") or Roles.hasFlag(ply, "investigator")
    if not canSee then return false, "Реестр карт доступен службе безопасности." end
    local now = os.time()
    local passes = DB.query("SELECT serial, holder_name, holder_number, clearance, tags, expires_at FROM sv_cards WHERE kind = 'temp' AND revoked_at IS NULL AND expires_at > ? ORDER BY issued_at DESC LIMIT 50", now) or {}
    local revoked = DB.query("SELECT serial, holder_name, holder_number, kind, revoked_at, reason FROM sv_cards WHERE revoked_at IS NOT NULL ORDER BY revoked_at DESC LIMIT 30") or {}
    for _, r in ipairs(revoked) do r.revoked = U.clockString(tonumber(r.revoked_at)) r.revoked_at = nil end
    for _, p in ipairs(passes) do p.left = math.max(tonumber(p.expires_at) - now, 0) p.expires_at = nil end
    Net.send(ply, "access.cards", {passes = passes, revoked = revoked})
end)

--- Game access log of the door the player is looking at (security only).
Net.handle("access.log", function(ply, ent)
    if not (Roles.hasFlag(ply, "investigator") or Roles.hasFlag(ply, "issuePasses")) then return false, "Журналы доступа доступны службе безопасности." end
    if not IsValid(ent) or not SV.MapCfg.doorConfig(ent) then return false, "Это не управляемая дверь." end
    if not U.within(ply, ent, 200) then return false, "Подойдите к считывателю." end
    Net.send(ply, "access.log", {name = SV.MapCfg.doorConfig(ent).name or "Дверь", entries = Access.gameLog(doorKey(ent))})
end)

timer.Create("SiteVeil.Access.Expiry", 15, 0, function()
    local now = os.time()
    for ply, cr in pairs(Access.creds) do
        if not IsValid(ply) then Access.creds[ply] = nil
        elseif cr.validUntil <= now then Access.invalidate(ply) end
    end
end)

SV.Perf.registry("access.openDoors", function() return U.count(Access.openDoors) end)
SV.Perf.registry("access.cachedCards", function() return U.count(Access.cards) end)

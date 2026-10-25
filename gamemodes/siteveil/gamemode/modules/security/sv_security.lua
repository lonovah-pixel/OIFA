--[[---------------------------------------------------------------------------
Security (server): restraints, escort, search and confiscation, detention,
identity checks, surrender, non-lethal stun.

Limits that prevent endless immobilisation:
  * restraints release automatically after C.Security.restrainMax;
  * a target released that way is protected for C.Security.reRestrainGrace
    unless they attack someone;
  * a restrained player left alone (no one able to detain nearby) can free
    themselves with a timed struggle;
  * detention has a maximum length per authority level and ends on death;
  * remaining detention time is stored with the character, so reconnecting
    does not shorten it.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Security = SV.Security
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local SC = C.Security
local Roles = SV.Roles
local Inv = SV.Inv
local Move = SV.Move

Security.restrained = Security.restrained or {} -- ply -> {by, since, untilTime}
Security.detained = Security.detained or {}     -- ply -> {id, untilTime, zone}

DB.registerMigrations("security", {
    {1, "confiscations and detentions", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_confiscations (
            id INTEGER PRIMARY KEY AUTOINCREMENT, item_uid INTEGER, item_id TEXT NOT NULL, count INTEGER NOT NULL,
            from_char INTEGER, from_name TEXT, by_char INTEGER, by_name TEXT, reason TEXT, time INTEGER NOT NULL, case_id INTEGER)]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_detentions (
            id INTEGER PRIMARY KEY AUTOINCREMENT, char_id INTEGER NOT NULL, char_name TEXT, by_char INTEGER, by_name TEXT,
            reason TEXT, started_at INTEGER NOT NULL, minutes INTEGER NOT NULL, released_at INTEGER, release_reason TEXT)]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_detentions_char ON sv_detentions (char_id, released_at)")
    end},
})

local function canDetain(ply)
    return Roles.hasFlag(ply, "canDetain") or SV.Admin.isOnDuty(ply)
end
Security.canDetainRole = canDetain

local function nearbyDetainers(ply, radius)
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and p:Alive() and canDetain(p) and U.within(p, ply, radius) then return true end
    end
    return false
end

--[[---------------------------------------------------------------------------
Restraints
---------------------------------------------------------------------------]]
function Security.isDetained(ply)
    return Security.detained[ply] ~= nil
end

local function holsterAll(ply)
    local cont = Inv.get(ply)
    if not cont then return end
    for _, item in pairs(cont.items) do
        if item.equipped then Inv.holster(ply, item) end
    end
end

function Security.restrain(target, by)
    if Security.restrained[target] then return false, "уже в наручниках" end
    Security.restrained[target] = {by = by, since = CurTime(), untilTime = CurTime() + SC.restrainMax, lastHelper = CurTime()}
    target:SetNW2Bool("sv_cuffed", true)
    holsterAll(target)
    Move.set(target, "restrained", {speed = SC.restrainedSpeed, nojump = true, noattack = true, nouse = true})
    target.SVSurrendered = nil
    target:SetNW2Bool("sv_surrender", false)
    target:EmitSound("weapons/357/357_reload1.wav", 60)
    SV.Audit.log("security", "restrain", by, target)
    SV.Bus.emit("security.restrained", {ply = by, target = target})
    DarkRP.notify(target, 1, 6, "На вас надели наручники.")
    return true
end

function Security.unrestrain(target, by, reason)
    if not Security.restrained[target] then return false, "не в наручниках" end
    Security.restrained[target] = nil
    if IsValid(target) then
        target:SetNW2Bool("sv_cuffed", false)
        target:SetNW2Entity("sv_escort", NULL)
        Move.clear(target, "restrained")
        if reason == "auto" then target.SVRestrainGraceUntil = CurTime() + SC.reRestrainGrace end
        DarkRP.notify(target, 0, 5, reason == "auto" and "Наручники сняты: истёк предельный срок удержания." or "С вас сняли наручники.")
    end
    SV.Audit.log("security", "unrestrain", by, target, {reason = reason})
    SV.Bus.emit("security.released", {ply = by, target = target, reason = reason})
    return true
end

local function restrainCheck(actor, target)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or not target.SVChar then return false, "Нет цели." end
    if target == actor then return false, "Нельзя." end
    if not U.within(actor, target, SC.restrainDistance) then return false, "Подойдите ближе." end
    local override = hook.Run("SiteVeil.CanRestrain", actor, target)
    if override == false then return false, "Этого нельзя сковать." end
    if Roles.isSCP(target) and override ~= true then return false, "Объект SCP невозможно сковать наручниками." end
    if Security.restrained[target] then return false, "Уже в наручниках." end
    if target.SVRestrainGraceUntil and CurTime() < target.SVRestrainGraceUntil and CurTime() - (target.SVLastAttack or -1000) > 30 then
        return false, "Сотрудник недавно освобождён по истечении срока; повторное задержание возможно через " .. math.ceil(target.SVRestrainGraceUntil - CurTime()) .. " с."
    end
    return true
end

Net.handle("sec.restrain", function(ply, target)
    if not canDetain(ply) then return false, "Нет полномочий задерживать." end
    if not ply:HasWeapon("sv_restraints") and not SV.Admin.isOnDuty(ply) then return false, "Нужны наручники." end
    local ok, why = restrainCheck(ply, target)
    if not ok then return false, why end
    local easy = (SV.Medical.isIncapacitated(target) or target.SVSurrendered or SV.Medical.isStunned(target))
    if easy then return Security.restrain(target, ply), "Задержанный скован." end
    DarkRP.notify(target, 1, 4, SV.Chars.displayName(ply) .. " пытается надеть на вас наручники!")
    return SV.Actions.start(ply, {
        id = "restrain", label = "Надеть наручники", duration = SC.restrainTime, target = target, maxDist = SC.restrainDistance,
        canContinue = function() return target:Alive(), "цель недоступна" end,
        onComplete = function(p)
            local ok2, why2 = restrainCheck(p, target)
            if not ok2 then DarkRP.notify(p, 1, 4, why2) return end
            Security.restrain(target, p)
        end,
    })
end)

Net.handle("sec.release", function(ply, target)
    if not IsValid(target) or not Security.restrained[target] then return false, "Цель не в наручниках." end
    if not canDetain(ply) then return false, "Нет ключа от наручников." end
    if not U.within(ply, target, SC.restrainDistance + 20) then return false, "Подойдите ближе." end
    return Security.unrestrain(target, ply, "manual")
end)

Net.handle("sec.escort", function(ply, target)
    if not IsValid(target) then return false, "Нет цели." end
    local escortable = Security.restrained[target] or hook.Run("SiteVeil.CanEscort", ply, target) == true
    if not escortable then return false, "Сопровождать можно только скованного." end
    if not canDetain(ply) then return false, "Нет полномочий." end
    local current = target:GetNW2Entity("sv_escort")
    if current == ply then
        target:SetNW2Entity("sv_escort", NULL)
        return true, "Сопровождение прекращено."
    end
    if not U.within(ply, target, SC.restrainDistance + 20) then return false, "Подойдите ближе." end
    target:SetNW2Entity("sv_escort", ply)
    SV.Bus.emit("security.escort", {ply = ply, target = target})
    return true, "Вы ведёте " .. SV.Chars.displayName(target) .. "."
end)

Net.handle("sec.struggle", function(ply)
    local r = Security.restrained[ply]
    if not r then return false, "Вы не в наручниках." end
    if IsValid(ply:GetNW2Entity("sv_escort")) then return false, "Вас конвоируют." end
    if nearbyDetainers(ply, SC.selfReleaseRadius) then return false, "Рядом охрана — освободиться незаметно не получится." end
    if CurTime() - r.lastHelper < SC.selfReleaseAlone then
        return false, "Нужно дождаться, пока рядом никого не будет (" .. math.ceil(SC.selfReleaseAlone - (CurTime() - r.lastHelper)) .. " с)."
    end
    return SV.Actions.start(ply, {
        id = "struggle", label = "Освобождение от наручников", duration = SC.selfReleaseTime, allowMove = false,
        canContinue = function(p) return not nearbyDetainers(p, SC.selfReleaseRadius), "кто-то приближается" end,
        onComplete = function(p) Security.unrestrain(p, nil, "struggle") end,
    })
end)

Net.handle("sec.surrender", function(ply)
    if Security.restrained[ply] then return false end
    ply.SVSurrendered = not ply.SVSurrendered
    ply:SetNW2Bool("sv_surrender", ply.SVSurrendered == true)
    if ply.SVSurrendered then holsterAll(ply) end
    return true, ply.SVSurrendered and "Вы подняли руки." or "Вы опустили руки."
end)

-- Attacking cancels surrender and marks combat (for the re-restrain rule).
hook.Add("EntityTakeDamage", "SiteVeil.Security.Combat", function(ent, dmg)
    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() and ent:IsPlayer() and attacker ~= ent then
        attacker.SVLastAttack = CurTime()
        if attacker.SVSurrendered then
            attacker.SVSurrendered = nil
            attacker:SetNW2Bool("sv_surrender", false)
        end
    end
end)

hook.Add("PlayerSwitchWeapon", "SiteVeil.Security", function(ply)
    if Security.restrained[ply] then return true end
end)

hook.Add("SiteVeil.CanUseAction", "SiteVeil.Security", function(ply, name)
    if Security.restrained[ply] then
        if name == "sec.struggle" or name == "action.cancel" or string.find(name, "^char%.") or name == "tasks.list" or name == "inv.answer" then return end
        return false, "Вы в наручниках."
    end
end)

hook.Add("SiteVeil.CanEquip", "SiteVeil.Security", function(ply)
    if Security.restrained[ply] or ply.SVSurrendered then return false, "Руки заняты." end
end)

hook.Add("PlayerUse", "SiteVeil.Security", function(ply)
    if Security.restrained[ply] then return false end
end)

hook.Add("SiteVeil.CanSwitchCharacter", "SiteVeil.Security", function(ply)
    if Security.restrained[ply] then return false, "Нельзя сменить персонажа в наручниках." end
    if Security.detained[ply] then return false, "Нельзя сменить персонажа во время задержания." end
end)

hook.Add("SiteVeil.CanTakeRole", "SiteVeil.Security", function(ply)
    if Security.restrained[ply] or Security.detained[ply] then return false, "Смена должности невозможна во время задержания." end
end)

--[[---------------------------------------------------------------------------
Search and confiscation
---------------------------------------------------------------------------]]
local function canSearch(ply)
    return Roles.hasFlag(ply, "search") or SV.Admin.isOnDuty(ply)
end

local function searchable(target)
    return Security.restrained[target] or SV.Medical.isIncapacitated(target) or target.SVSurrendered or SV.Medical.isStunned(target)
end

function Security.searchView(target)
    local list = {}
    for _, item in ipairs(Inv.find(target, function() return true end)) do
        local def = C.Items[item.id]
        if not def.hidden then
            list[#list + 1] = {uid = item.uid, id = item.id, count = item.count, title = item.data.title, serial = item.data.serial,
                contraband = def.contraband or nil, noConfiscate = def.noConfiscate or nil}
        end
    end
    return list
end

Net.handle("sec.search", function(ply, target)
    if not canSearch(ply) then return false, "Нет полномочий на обыск." end
    if not IsValid(target) or not target:IsPlayer() or not target.SVChar then return false, "Нет цели." end
    if not searchable(target) then return false, "Обыск возможен, если человек скован, сдался или без сознания." end
    if not U.within(ply, target, SC.searchDistance) then return false, "Подойдите ближе." end
    return SV.Actions.start(ply, {
        id = "search", label = "Обыск", duration = SC.searchTime, target = target, maxDist = SC.searchDistance,
        onComplete = function(p)
            p.SVSearching = {target = target, at = CurTime()}
            Net.send(p, "sec.search", {target = target:EntIndex(), name = SV.Chars.displayName(target), items = Security.searchView(target)})
            SV.Audit.log("security", "search", p, target)
            SV.Bus.emit("security.searched", {ply = p, target = target})
            DarkRP.notify(target, 3, 4, "Вас обыскали.")
        end,
    })
end)

Net.handle("sec.confiscate", function(ply, target, uid, reason)
    local search = ply.SVSearching
    if not search or search.target ~= target or CurTime() - search.at > 90 or not IsValid(target) then return false, "Сначала проведите обыск." end
    if not canSearch(ply) or not searchable(target) then return false, "Изъятие невозможно." end
    if not U.within(ply, target, SC.searchDistance + 20) then return false, "Подойдите ближе." end
    local item = Inv.getItem(target, uid)
    if not item then return false, "Предмета уже нет." end
    local def = C.Items[item.id]
    if def.noConfiscate then return false, "Этот предмет не изымается." end
    reason = U.cleanText(reason, 120)
    local ok, why = Inv.transfer(target, ply, uid, item.count, {force = true, reason = "confiscation"})
    if not ok then return false, why end
    if item.issuedTo == target.SVChar.id then
        target.SVChar.data.confiscated = target.SVChar.data.confiscated or {}
        target.SVChar.data.confiscated[item.id] = true
        SV.Chars.save(target.SVChar)
    end
    DB.query([[INSERT INTO sv_confiscations (item_uid, item_id, count, from_char, from_name, by_char, by_name, reason, time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], uid, item.id, item.count, target.SVChar.id, target.SVChar.name, ply.SVChar and ply.SVChar.id,
        ply.SVChar and ply.SVChar.name or ply:SteamName(), reason, os.time())
    SV.Audit.log("security", "confiscate", ply, target, {item = item.id, uid = uid, reason = reason})
    SV.Bus.emit("security.confiscated", {ply = ply, target = target, item = item, reason = reason})
    Net.send(ply, "sec.search", {target = target:EntIndex(), name = SV.Chars.displayName(target), items = Security.searchView(target)})
    return true, "Изъято: " .. def.name
end)

-- A kit item that returns to its owner lifts the re-issue block.
hook.Add("SiteVeil.InventoryChanged", "SiteVeil.Security.Confiscation", function(ply)
    local char = ply.SVChar
    if not char or not char.data.confiscated then return end
    for itemId in pairs(char.data.confiscated) do
        for _, item in ipairs(Inv.find(ply, function(it) return it.id == itemId and it.issuedTo == char.id end)) do
            if item then
                char.data.confiscated[itemId] = nil
                SV.Chars.save(char)
            end
        end
    end
end)

SV.Bus.on("shift.started", "security.confiscation", function()
    for _, ply in ipairs(player.GetAll()) do
        if ply.SVChar and ply.SVChar.data.confiscated then
            ply.SVChar.data.confiscated = nil
            SV.Chars.save(ply.SVChar)
        end
    end
end)

--[[---------------------------------------------------------------------------
Detention
---------------------------------------------------------------------------]]
local function detentionZoneAt(pos)
    return SV.MapCfg.zoneAt(pos, "detention")
end

local function maxMinutes(ply)
    if SV.Admin.isOnDuty(ply) then return 60 end
    if Roles.hasFlag(ply, "divisionHead") or Roles.hasFlag(ply, "approveTransfers") then return SC.detainMaxChief end
    return SC.detainMax
end

function Security.detain(target, by, minutes, reason, resume)
    local zone = detentionZoneAt(target:GetPos())
    local id = resume and resume.id
    if not id then
        DB.query("INSERT INTO sv_detentions (char_id, char_name, by_char, by_name, reason, started_at, minutes) VALUES (?, ?, ?, ?, ?, ?, ?)",
            target.SVChar.id, target.SVChar.name, IsValid(by) and by.SVChar and by.SVChar.id or nil, IsValid(by) and by:Nick() or "система",
            reason, os.time(), minutes)
        id = DB.lastInsertId()
    end
    Security.detained[target] = {id = id, untilTime = CurTime() + minutes * 60, zone = zone and zone.id or nil, reason = reason,
        anchor = target:GetPos()}
    if Security.restrained[target] then Security.unrestrain(target, by, "detained") end
    target:SetNW2Bool("sv_detained", true)
    SV.Sync.setFor(target, "self", "detention", {untilTime = Security.detained[target].untilTime, reason = reason})
    SV.Audit.log("security", "detain", by, target, {minutes = minutes, reason = reason, id = id})
    SV.Bus.emit("security.detained", {ply = by, target = target, minutes = minutes})
    DarkRP.notify(target, 1, 8, "Вы задержаны на " .. minutes .. " мин. Основание: " .. reason)
    return true
end

function Security.release(target, by, reason)
    local d = Security.detained[target]
    if not d then
        if Security.restrained[target] then return Security.unrestrain(target, by, reason) end
        return false, "Не задержан."
    end
    Security.detained[target] = nil
    DB.query("UPDATE sv_detentions SET released_at = ?, release_reason = ? WHERE id = ?", os.time(), reason or "", d.id)
    if IsValid(target) then
        target:SetNW2Bool("sv_detained", false)
        SV.Sync.setFor(target, "self", "detention", nil)
        if target.SVChar then
            target.SVChar.data.detention = nil
            SV.Chars.save(target.SVChar)
        end
        DarkRP.notify(target, 0, 6, "Задержание окончено: " .. (reason or "освобождён"))
    end
    SV.Audit.log("security", "release", by, target, {reason = reason, id = d.id})
    SV.Bus.emit("security.releasedDetention", {ply = by, target = target, reason = reason})
    return true
end

--- Used by the DarkRP arrest() compatibility shim.
function Security.adminDetain(target, by, seconds, reason)
    if not IsValid(target) or not target.SVChar then return false end
    return Security.detain(target, by, math.Clamp(math.ceil((seconds or 120) / 60), 1, 60), reason)
end

Net.handle("sec.detain", function(ply, target, minutes, reason)
    if not canDetain(ply) then return false, "Нет полномочий." end
    if not IsValid(target) or not target.SVChar or not Security.restrained[target] then return false, "Задержать можно только скованного." end
    if Security.detained[target] then return false, "Уже задержан." end
    if not U.within(ply, target, SC.detainDistance) then return false, "Задержанный слишком далеко." end
    reason = U.cleanText(reason, 200)
    if U.utf8len(reason) < 5 then return false, "Укажите основание задержания." end
    local cells = SV.MapCfg.zones("detention")
    if #cells > 0 and not detentionZoneAt(target:GetPos()) then return false, "Доставьте задержанного в камеру задержания." end
    minutes = math.Clamp(minutes, 1, maxMinutes(ply))
    return Security.detain(target, ply, minutes, reason), "Задержание оформлено на " .. minutes .. " мин."
end)

Net.handle("sec.unDetain", function(ply, target, reason)
    if not canDetain(ply) then return false, "Нет полномочий." end
    if not IsValid(target) then return false, "Нет цели." end
    return Security.release(target, ply, U.cleanText(reason, 200) ~= "" and U.cleanText(reason, 200) or "решение охраны")
end)

Net.handle("sec.detentions", function(ply)
    if not canDetain(ply) then return false, "Нет полномочий." end
    local list = {}
    for target, d in pairs(Security.detained) do
        if IsValid(target) then
            list[#list + 1] = {name = SV.Chars.displayName(target), left = math.max(math.ceil(d.untilTime - CurTime()), 0), reason = d.reason, ent = target:EntIndex()}
        end
    end
    local history = DB.query("SELECT char_name, by_name, reason, started_at, minutes, release_reason FROM sv_detentions ORDER BY id DESC LIMIT 20") or {}
    for _, h in ipairs(history) do h.when = U.clockString(tonumber(h.started_at)) h.started_at = nil end
    Net.send(ply, "sec.detentions", {active = list, history = history})
end)

-- Detention and restraint bookkeeping.
timer.Create("SiteVeil.Security", 1, 0, function()
    local now = CurTime()
    for target, r in pairs(Security.restrained) do
        if not IsValid(target) or not target:Alive() then
            Security.restrained[target] = nil
            if IsValid(target) then
                target:SetNW2Bool("sv_cuffed", false)
                Move.clear(target, "restrained")
            end
        else
            if now >= r.untilTime then Security.unrestrain(target, nil, "auto")
            else
                if nearbyDetainers(target, SC.selfReleaseRadius) or IsValid(target:GetNW2Entity("sv_escort")) then r.lastHelper = now end
                local escort = target:GetNW2Entity("sv_escort")
                if IsValid(escort) and (not escort:Alive() or not U.within(escort, target, SC.escortBreak)) then
                    target:SetNW2Entity("sv_escort", NULL)
                end
            end
        end
    end
    for target, d in pairs(Security.detained) do
        if not IsValid(target) then
            Security.detained[target] = nil
        elseif now >= d.untilTime then
            Security.release(target, nil, "срок истёк")
        elseif d.zone then
            local zone = SV.MapCfg.zone(d.zone)
            if zone and not SV.MapCfg.zoneContains(zone, target:GetPos()) and not d.escaped then
                d.escaped = true
                SV.Bus.emit("security.escape", {target = target})
                for _, p in ipairs(player.GetAll()) do
                    if canDetain(p) then DarkRP.notify(p, 1, 8, "ПОБЕГ: " .. SV.Chars.displayName(target) .. " покинул камеру задержания.") end
                end
            end
        end
    end
end)

hook.Add("PlayerDeath", "SiteVeil.Security", function(ply)
    if Security.restrained[ply] then Security.unrestrain(ply, nil, "death") end
    if Security.detained[ply] then Security.release(ply, nil, "смерть задержанного") end
    for target in pairs(Security.restrained) do
        if IsValid(target) and target:GetNW2Entity("sv_escort") == ply then target:SetNW2Entity("sv_escort", NULL) end
    end
    ply.SVSurrendered = nil
    ply:SetNW2Bool("sv_surrender", false)
end)

-- Leaving restrained or detained: remaining time stays with the character.
hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.Security", function(ply, char)
    local d = Security.detained[ply]
    if d then
        char.data.detention = {id = d.id, remaining = math.max(d.untilTime - CurTime(), 60), reason = d.reason}
    elseif Security.restrained[ply] then
        char.data.detention = {remaining = SC.detainDefault * 60, reason = "Уход от задержания (отключение в наручниках)"}
    end
    -- Cleared one tick later: other unloading handlers still need the state.
    timer.Simple(0, function()
        Security.detained[ply] = nil
        Security.restrained[ply] = nil
    end)
end)

hook.Add("SiteVeil.ShouldDropOnDisconnect", "SiteVeil.Security", function(ply)
    if Security.restrained[ply] then return true end
end)

hook.Add("SiteVeil.RoleSpawn", "SiteVeil.Security", function(ply)
    local char = ply.SVChar
    local saved = char and char.data.detention
    if not saved then return end
    char.data.detention = nil
    timer.Simple(0.5, function()
        if not IsValid(ply) or not ply.SVChar then return end
        local cells = SV.MapCfg.zones("detention")
        if #cells > 0 then
            local box = cells[1].boxes[1]
            local center = Vector((box.min[1] + box.max[1]) / 2, (box.min[2] + box.max[2]) / 2, box.min[3] + 8)
            ply:SetPos(DarkRP.findEmptyPos(center, {ply}, 200, 30, Vector(16, 16, 64)))
        end
        Security.detain(ply, nil, math.max(math.ceil(saved.remaining / 60), 1), saved.reason, saved.id and {id = saved.id} or nil)
        DarkRP.notify(ply, 1, 8, "Вы вернулись под задержание: осталось " .. math.ceil(saved.remaining / 60) .. " мин.")
    end)
end)

--[[---------------------------------------------------------------------------
Identity check
---------------------------------------------------------------------------]]
Net.handle("sec.checkId", function(ply, target)
    if not IsValid(target) or not target:IsPlayer() or not target.SVChar then return false, "Нет цели." end
    if not U.within(ply, target, 120) then return false, "Подойдите ближе." end
    local cards = {}
    for _, item in ipairs(Inv.find(target, function(it, def) return def.category == "keycard" end)) do
        local card = SV.Access.card(item.data.serial)
        local valid, why = SV.Access.cardValid(card)
        cards[#cards + 1] = {
            kind = item.id == "id_card" and "Удостоверение" or "Временный пропуск",
            serial = item.data.serial or "—", holder = card and card.holderName or item.data.holder or "?",
            number = card and card.holderNumber or item.data.number or "?", clearance = card and card.clearance or 0,
            valid = valid, reason = why,
            mismatch = card and card.holderName ~= target.SVChar.name or nil,
        }
    end
    Net.send(ply, "sec.idcard", {name = SV.Chars.displayName(target), cards = cards})
    DarkRP.notify(target, 0, 4, SV.Chars.displayName(ply) .. " проверил ваши документы.")
    if canDetain(ply) then
        ply.SVIdChecked = ply.SVIdChecked or {}
        local last = ply.SVIdChecked[target]
        if not last or CurTime() - last > SC.idCheckCooldown then
            ply.SVIdChecked[target] = CurTime()
            SV.Bus.emit("security.idChecked", {ply = ply, target = target})
        end
    end
end)

SV.Perf.registry("security.restrained", function() return U.count(Security.restrained) end)
SV.Perf.registry("security.detained", function() return U.count(Security.detained) end)

SV.DarkRP.chatCommand({command = "surrender", description = "Поднять / опустить руки.", delay = 1}, function(ply)
    local _, msg = Net.handlers["sec.surrender"](ply)
    if msg then DarkRP.notify(ply, 0, 3, msg) end
    return ""
end)

SV.DarkRP.chatCommand({command = "struggle", description = "Попытаться освободиться от наручников.", delay = 2}, function(ply)
    local ok, msg = Net.handlers["sec.struggle"](ply)
    if msg then DarkRP.notify(ply, ok and 0 or 1, 4, msg) end
    return ""
end)

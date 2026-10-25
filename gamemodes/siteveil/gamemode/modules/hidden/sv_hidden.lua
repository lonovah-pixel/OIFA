--[[---------------------------------------------------------------------------
"Двойные задачи" (server). See config/sv_hidden.lua for the rules.

Offers go only to opted-in characters (char.data.hiddenOptIn). The task is
known to its holder only; completion leaves evidence for the other side
(stash traces, leak records) but never reveals the holder automatically.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Hidden = SV.Hidden
local Net = SV.Net
local DB = SV.DB
local U = SV.Util
local C = SV.Config
local H = C.Hidden
local Roles = SV.Roles
local MapCfg = SV.MapCfg

Hidden.defs = {}
for _, t in ipairs(C.HiddenTasks) do Hidden.defs[t.id] = t end

Hidden.active = Hidden.active or {}   -- ply -> task run
Hidden.offers = Hidden.offers or {}   -- ply -> {def, expires}
Hidden.round = Hidden.round or 0

local convar = CreateConVar("sv_hidden_tasks", "1", FCVAR_ARCHIVE, "SITE-VEIL: hidden optional tasks (0 = off)")

DB.registerMigrations("hidden", {
    {1, "hidden task log", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_hidden_log (id INTEGER PRIMARY KEY AUTOINCREMENT, char_id INTEGER NOT NULL,
            task TEXT NOT NULL, shift INTEGER, offered_at INTEGER NOT NULL, outcome TEXT, ended_at INTEGER)]])
    end},
})

function Hidden.enabled()
    return H.enabled and convar:GetBool() and SV.Settings.get("hidden.enabled", true) ~= false
end

local function optedIn(ply)
    return ply.SVChar ~= nil and ply.SVChar.data.hiddenOptIn == true
end

local function doneThisShift(ply)
    return tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_hidden_log WHERE char_id = ? AND shift = ? AND outcome IS NOT 'declined'",
        ply.SVChar.id, SV.Shift.id)) or 0
end

local function suits(ply, def)
    local char = ply.SVChar
    if def.divisions then
        local ok = false
        for _, d in ipairs(def.divisions) do if char.division == d then ok = true end end
        if not ok then return false end
    end
    if def.flags then
        local ok = false
        for _, f in ipairs(def.flags) do if Roles.hasFlag(ply, f) then ok = true end end
        if not ok then return false end
    end
    if def.type == "stash" and #MapCfg.points("stash") == 0 then return false end
    if def.type == "visit" and #MapCfg.points(def.points[1]) == 0 then return false end
    return true
end

--- Why ply cannot receive an offer now (nil = can).
function Hidden.blockedReason(ply)
    if not Hidden.enabled() then return "система отключена" end
    if not optedIn(ply) then return "не дано согласие" end
    if not ply:Alive() or Roles.isSCP(ply) or Roles.isLobby(ply) then return "не на смене" end
    if Hidden.active[ply] or Hidden.offers[ply] then return "уже есть предложение или задание" end
    if SV.Security.restrained[ply] or SV.Security.isDetained(ply) then return "задержан" end
    if CurTime() - (ply.SVRoleSince or CurTime()) < H.minOnShift then return "слишком мало времени на смене" end
    if (ply.SVHiddenDeclined or -1e9) + H.declineCooldown > CurTime() then return "недавний отказ" end
    if doneThisShift(ply) >= H.perShift then return "лимит за смену" end
    if U.count(Hidden.active) >= H.maxActive then return "лимит сервера" end
    return nil
end

--[[---------------------------------------------------------------------------
Offers
---------------------------------------------------------------------------]]
local function publish(ply)
    local run = Hidden.active[ply]
    SV.Sync.setFor(ply, "self", "hidden", run and {name = run.def.name, text = run.def.text, endsAt = run.endsAt,
        progress = run.def.hold and math.floor((run.progress or 0) / run.def.hold * 100) or nil, target = run.targetName} or nil)
end

function Hidden.offer(ply, def)
    Hidden.offers[ply] = {def = def, expires = CurTime() + H.offerTimeout}
    DB.query("INSERT INTO sv_hidden_log (char_id, task, shift, offered_at) VALUES (?, ?, ?, ?)", ply.SVChar.id, def.id, SV.Shift.id, os.time())
    Hidden.offers[ply].logId = DB.lastInsertId()
    Net.send(ply, "hidden.offer", {name = def.name, text = def.text, timeLimit = H.timeLimit})
end

local function endLog(logId, outcome)
    DB.query("UPDATE sv_hidden_log SET outcome = ?, ended_at = ? WHERE id = ?", outcome, os.time(), logId)
end

local function pickTarget(ply)
    local list = {}
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and p:Alive() and p.SVChar and not Roles.isSCP(p) and not Roles.isLobby(p) then list[#list + 1] = p end
    end
    table.sort(list, function(a, b) return a:EntIndex() < b:EntIndex() end)
    if #list == 0 then return nil end
    return list[SV.RNG.new(SV.RNG.seedFor("hidden.target", ply.SVChar.id + Hidden.round)):int(1, #list)]
end

function Hidden.accept(ply)
    local o = Hidden.offers[ply]
    if not o or o.expires < CurTime() then return false, "Предложение больше не действует." end
    Hidden.offers[ply] = nil
    local run = {def = o.def, logId = o.logId, endsAt = CurTime() + H.timeLimit, progress = 0, char = ply.SVChar.id}
    if o.def.type == "shadow" then
        run.target = pickTarget(ply)
        if not run.target then
            endLog(o.logId, "declined")
            return false, "Подходящего сотрудника сейчас нет."
        end
        run.targetName = SV.Chars.displayName(run.target)
    elseif o.def.type == "visit" then
        local mine = SV.Facility.sectorOf(ply)
        local points = {}
        for _, p in ipairs(MapCfg.points(o.def.points[1])) do
            if SV.Facility.sectorAt(MapCfg.toVec(p.pos)) ~= mine then points[#points + 1] = p end
        end
        if #points == 0 then points = MapCfg.points(o.def.points[1]) end
        table.sort(points, function(a, b) return a.id < b.id end)
        run.point = MapCfg.toVec(points[SV.RNG.new(SV.RNG.seedFor("hidden.point", ply.SVChar.id + Hidden.round)):int(1, #points)].pos)
        run.targetName = "пост в секторе " .. tostring(SV.Facility.sectorAt(run.point) or "—")
    end
    Hidden.active[ply] = run
    publish(ply)
    SV.Audit.log("hidden", "accept", ply, nil, {task = o.def.id})
    return true, "Задание принято. Его можно бросить в любой момент без последствий."
end

local function finish(ply, outcome)
    local run = Hidden.active[ply]
    if not run then return end
    Hidden.active[ply] = nil
    endLog(run.logId, outcome)
    SV.Audit.log("hidden", outcome, ply, nil, {task = run.def.id})
    if IsValid(ply) then
        publish(ply)
        if outcome == "done" then
            SV.Chars.addXP(ply, run.def.xp or 20, H.xpSource)
            DarkRP.notify(ply, 0, 8, "Задание «" .. run.def.name .. "» выполнено.")
            SV.Bus.emit("hidden.completed", {ply = ply, task = run.def.id})
        elseif outcome == "expired" then
            DarkRP.notify(ply, 3, 6, "Задание «" .. run.def.name .. "» больше не актуально.")
        end
    end
end
Hidden.finish = finish

Net.handle("hidden.answer", function(ply, accept)
    local o = Hidden.offers[ply]
    if not o then return false, "Предложений нет." end
    if not accept then
        Hidden.offers[ply] = nil
        ply.SVHiddenDeclined = CurTime()
        endLog(o.logId, "declined")
        return true, "Вы отказались. Это ни на что не влияет."
    end
    return Hidden.accept(ply)
end)

Net.handle("hidden.abandon", function(ply)
    if not Hidden.active[ply] then return false, "Нет задания." end
    finish(ply, "abandoned")
    return true, "Задание брошено."
end)

Net.handle("hidden.optin", function(ply, on)
    if not ply.SVChar then return false end
    ply.SVChar.data.hiddenOptIn = on or nil
    SV.Chars.save(ply.SVChar)
    if not on then
        if Hidden.active[ply] then finish(ply, "abandoned") end
        Hidden.offers[ply] = nil
    end
    Net.send(ply, "hidden.optin", {on = on})
    return true, on and "Вы можете получать скрытые задания." or "Скрытые задания отключены."
end)

Net.handle("hidden.state", function(ply)
    publish(ply)
    Net.send(ply, "hidden.optin", {on = optedIn(ply), enabled = Hidden.enabled(), blocked = Hidden.blockedReason(ply)})
end)

Net.handle("hidden.toggle", function(ply, on)
    if not SV.Admin.can(ply, "SiteVeil_Admin") then return false, "Нет прав." end
    SV.Settings.set("hidden.enabled", on)
    SV.Audit.log("admin", "hidden.toggle", ply, nil, {on = on})
    if not on then
        for p in pairs(Hidden.active) do finish(p, "withdrawn") end
        Hidden.offers = {}
    end
    return true, on and "Скрытые задания включены." or "Скрытые задания выключены."
end)

--[[---------------------------------------------------------------------------
Progress
---------------------------------------------------------------------------]]
local function nearStash(pos)
    for _, p in ipairs(MapCfg.points("stash")) do
        local sp = MapCfg.toVec(p.pos)
        if sp:DistToSqr(pos) <= H.stashRadius * H.stashRadius then return sp end
    end
    return nil
end

local function printedBy(serial, charId)
    return DB.queryValue("SELECT 1 FROM sv_document_prints WHERE serial = ? AND char_id = ?", serial, charId) ~= nil
end

local function stashItemMatches(run, item)
    local def = run.def
    if item.id ~= def.item then return false end
    if def.item == "document" then
        return (tonumber(item.data.clearance) or 0) >= (def.minClearance or 0) and printedBy(item.data.serial, run.char)
    end
    return true
end

-- Items left at a stash are taken by the "courier" and leave a trace.
local function checkStash(ply, run)
    local stash = nearStash(ply:GetPos())
    if not stash then return false end
    for ent, entry in pairs(SV.Inv.world) do
        if IsValid(ent) and ent:GetPos():DistToSqr(stash) <= H.stashRadius * H.stashRadius then
            for _, item in ipairs(entry.items) do
                if stashItemMatches(run, item) then
                    SV.Inv.destroyWorldEntry(ent, "hidden stash")
                    if SV.Evidence then
                        SV.Evidence.addTrace("stash", stash, {attacker = {char = ply.SVChar.id, name = ply.SVChar.name, division = ply.SVChar.division}, item = item.id})
                    end
                    return true
                end
            end
        end
    end
    return false
end

local function unseen(ply, radius)
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and p:Alive() and Roles.hasFlag(p, "canDetain") and U.within(p, ply, radius) then return false end
    end
    return true
end

local function tickRun(ply, run)
    local def = run.def
    if CurTime() >= run.endsAt then
        finish(ply, "expired")
        return
    end
    if def.type == "stash" then
        if checkStash(ply, run) then finish(ply, "done") end
    elseif def.type == "visit" then
        if ply:GetPos():DistToSqr(run.point) <= 150 * 150 and unseen(ply, def.unseenRadius) then
            run.progress = run.progress + 1
            publish(ply)
            if run.progress >= def.hold then finish(ply, "done") end
        end
    elseif def.type == "shadow" then
        local t = run.target
        if not IsValid(t) or not t:Alive() or not t.SVChar then
            finish(ply, "expired")
            return
        end
        if U.within(ply, t, def.radius) and SV.MapCfg.lineOfSight(ply:GetPos(), t:GetPos()) then
            run.progress = run.progress + 1
            publish(ply)
            if run.progress >= def.hold then finish(ply, "done") end
        end
    end
end

timer.Create("SiteVeil.Hidden", 1, 0, function()
    local now = CurTime()
    for p, o in pairs(Hidden.offers) do
        if not IsValid(p) or o.expires < now then
            Hidden.offers[p] = nil
            endLog(o.logId, "declined")
        end
    end
    for p, run in pairs(Hidden.active) do
        if not IsValid(p) or not p.SVChar or p.SVChar.id ~= run.char then
            Hidden.active[p] = nil
            endLog(run.logId, "abandoned")
        elseif p:Alive() then
            tickRun(p, run)
        end
    end
end)

-- Event objectives.
local watched = {}
for _, def in ipairs(C.HiddenTasks) do
    if def.type == "event" and not watched[def.event] then
        watched[def.event] = true
        SV.Bus.on(def.event, "hidden", function(data)
            local ply = data.ply
            local run = IsValid(ply) and Hidden.active[ply]
            if not run or run.def.event ~= def.event then return end
            for k, v in pairs(run.def.match or {}) do
                if data[k] ~= v then return end
            end
            finish(ply, "done")
        end)
    end
end

-- Offer rounds.
timer.Create("SiteVeil.Hidden.Offers", H.offerInterval, 0, function()
    if not Hidden.enabled() or U.onlineCount() < H.minOnline then return end
    Hidden.round = Hidden.round + 1
    for _, p in ipairs(player.GetAll()) do
        if not Hidden.blockedReason(p) then
            local rng = SV.RNG.new(SV.RNG.seedFor("hidden.offer", p.SVChar.id * 1000 + Hidden.round))
            if rng:chance(H.offerChance) then
                local weights = {}
                for _, def in ipairs(C.HiddenTasks) do
                    if suits(p, def) then weights[def.id] = def.weight end
                end
                local pick = rng:weighted(weights)
                if pick then Hidden.offer(p, Hidden.defs[pick]) end
            end
        end
    end
end)

hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.Hidden", function(ply)
    if Hidden.active[ply] then finish(ply, "abandoned") end
    Hidden.offers[ply] = nil
end)

SV.Perf.registry("hidden.active", function() return U.count(Hidden.active) end)

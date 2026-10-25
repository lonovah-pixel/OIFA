--[[---------------------------------------------------------------------------
Administration panel (server). Every action is checked against CAMI
privileges and written to the audit log.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Admin = SV.Admin
local Net = SV.Net
local U = SV.Util
local Roles = SV.Roles
local Comms = SV.Comms

local function need(ply, priv)
    if not Admin.can(ply, priv) then return false, "Нет прав." end
    return true
end

Net.handle("admin.players", function(ply)
    local ok, why = need(ply, "SiteVeil_Admin")
    if not ok then return false, why end
    local list = {}
    for _, p in ipairs(player.GetHumans()) do
        local role = Roles.ofPlayer(p)
        list[#list + 1] = {steamid = p:SteamID64(), steam = p:SteamName(), char = p.SVChar and p.SVChar.name or nil,
            number = p.SVChar and p.SVChar.number or nil, division = p.SVChar and p.SVChar.division or nil,
            role = role and role.name or "—", alive = p:Alive(), duty = Admin.isOnDuty(p), ping = p:Ping()}
    end
    table.sort(list, function(a, b) return a.steam < b.steam end)
    Net.send(ply, "admin.players", {list = list})
end)

local scopes = {division = true, role = true}

Net.handle("admin.whitelist", function(ply, steamid, scope, value, grant, note)
    local ok, why = need(ply, "SiteVeil_Whitelist")
    if not ok then return false, why end
    if not string.match(steamid, "^%d+$") then return false, "Неверный SteamID64." end
    if not scopes[scope] then return false, "Неверная область допуска." end
    if scope == "division" and not Roles.getDivision(value) then return false, "Нет такого подразделения." end
    if scope == "role" and not Roles.get(value) then return false, "Нет такой роли." end
    if grant then
        SV.Chars.grantWhitelist(steamid, scope, value, ply, U.cleanText(note, 120))
    else
        SV.Chars.revokeWhitelist(steamid, scope, value, ply)
    end
    Net.send(ply, "admin.whitelistOf", {steamid = steamid, list = SV.Chars.whitelistFor(steamid)})
    return true, grant and "Допуск выдан." or "Допуск отозван."
end)

Net.handle("admin.whitelistOf", function(ply, steamid)
    local ok, why = need(ply, "SiteVeil_Whitelist")
    if not ok then return false, why end
    Net.send(ply, "admin.whitelistOf", {steamid = steamid, list = SV.Chars.whitelistFor(steamid)})
end)

local function ticketList()
    local list = {}
    for _, t in pairs(Comms.tickets) do
        list[#list + 1] = {id = t.id, name = t.name, status = t.status, claimedBy = t.claimedBy, created = U.clockString(t.created),
            messages = t.messages}
    end
    table.sort(list, function(a, b)
        if (a.status == "closed") ~= (b.status == "closed") then return b.status == "closed" end
        return a.id > b.id
    end)
    return list
end

Net.handle("admin.tickets", function(ply)
    local ok, why = need(ply, "SiteVeil_Admin")
    if not ok then return false, why end
    Net.send(ply, "admin.tickets", {list = ticketList()})
end)

Net.handle("admin.ticket", function(ply, id, action, reply)
    local ok, why = need(ply, "SiteVeil_Admin")
    if not ok then return false, why end
    local t = Comms.tickets[id]
    if not t then return false, "Обращение не найдено." end
    reply = U.cleanText(reply, 300)
    local author = player.GetBySteamID64(t.sid)
    if action == "claim" then
        t.claimedBy = ply:SteamName()
        t.status = "claimed"
        if author then DarkRP.notify(author, 0, 6, "Ваше обращение #" .. id .. " рассматривает " .. ply:SteamName() .. ".") end
    elseif action == "reply" then
        if reply == "" then return false, "Пустой ответ." end
        t.messages[#t.messages + 1] = {from = ply:SteamName(), text = reply, t = os.time()}
        if author then DarkRP.talkToPerson(author, Color(230, 120, 60), "[Ответ на обращение #" .. id .. "] " .. ply:SteamName(), color_white, reply, ply) end
    elseif action == "close" then
        t.status = "closed"
        if author then DarkRP.notify(author, 0, 6, "Обращение #" .. id .. " закрыто." .. (reply ~= "" and (" " .. reply) or "")) end
    else
        return false
    end
    SV.Audit.log("admin", "ticket." .. action, ply, author or nil, {id = id, reply = reply})
    Net.send(ply, "admin.tickets", {list = ticketList()})
    return true
end)

Net.handle("admin.audit", function(ply, raw)
    local ok, why = need(ply, "SiteVeil_Admin")
    if not ok then return false, why end
    local f = istable(raw) and raw or {}
    local filter = {limit = 60}
    if isstring(f.category) and f.category ~= "" then filter.category = string.sub(f.category, 1, 24) end
    if isstring(f.actor) and string.match(f.actor, "^%d+$") then filter.actor = f.actor end
    if isstring(f.text) and f.text ~= "" then filter.text = string.sub(f.text, 1, 48) end
    if tonumber(f.minutes) then filter.since = os.time() - math.Clamp(tonumber(f.minutes), 1, 10080) * 60 end
    local rows = SV.Audit.search(filter)
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {when = os.date("%d.%m %H:%M:%S", tonumber(r.time)), category = r.category, action = r.action,
            actor = r.actor_name, actorSid = r.actor_sid, target = r.target_sid, details = string.sub(r.details or "", 1, 300)}
    end
    Net.send(ply, "admin.audit", {list = out})
end)

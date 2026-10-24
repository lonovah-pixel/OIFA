--[[---------------------------------------------------------------------------
Text chat (server).

Plain text is local in-character speech. Commands are DarkRP chat commands
declared through SiteVeil.DarkRP.chatCommand, so they also work from the
console ("darkrp me ..."). Every channel has its own rate limit; messages
are cleaned (control characters) and truncated to C.Chat.maxLength.

    text            local IC speech (C.Chat.talkDistance)
    /w /y           whisper / yell
    /me /do         action / scene description
    /r text         radio on the current transmit channel; team chat too
    // or /ooc      global out-of-character (can be disabled)
    /looc           local out-of-character
    /pm name text   private OOC message
    @text, /report  request to administrators
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Comms = SV.Comms
local Bridge = SV.DarkRP
local Net = SV.Net
local U = SV.Util
local C = SV.Config

local IC_COLOR = Color(230, 230, 230)
local ME_COLOR = Color(200, 170, 255)
local DO_COLOR = Color(160, 200, 160)
local OOC_COLOR = Color(150, 150, 150)
local ADMIN_COLOR = Color(255, 120, 90)

function Comms.divisionColor(ply)
    local div = ply:getDarkRPVar("sv_div")
    local d = div and SV.Roles.getDivision(div)
    return d and d.color or Color(200, 200, 200)
end

local function limited(ply, key, rate)
    if Net.takeToken(ply, "chat." .. key, rate) then return false end
    DarkRP.notify(ply, 1, 3, "Не так быстро.")
    return true
end

local function muted(ply)
    if ply.FAdmin_GetGlobal and ply:FAdmin_GetGlobal("FAdmin_chatmuted") then return true end
    return ply.SVChatMuted == true
end

local function clean(text)
    return U.cleanText(text, C.Chat.maxLength)
end

--- Sends `prefix: text` to everyone in range of the speaker.
function Comms.say(ply, prefix, text, dist, col1, col2)
    local origin = ply:EyePos()
    local distSqr = dist * dist
    local n = 0
    for _, other in ipairs(player.GetHumans()) do
        if (other.SVChar or other == ply) and other:EyePos():DistToSqr(origin) <= distSqr then
            DarkRP.talkToPerson(other, col1, prefix, col2 or IC_COLOR, text, ply)
            n = n + 1
        end
    end
    return n
end

local function requireIC(ply)
    if not ply.SVChar then
        DarkRP.notify(ply, 1, 4, "Сначала выберите персонажа (F4).")
        return false
    end
    if not ply:Alive() then
        DarkRP.notify(ply, 1, 4, "Мёртвые не говорят. Используйте OOC: // текст")
        return false
    end
    local veto, reason = hook.Run("SiteVeil.CanSpeak", ply)
    if veto == false then
        DarkRP.notify(ply, 1, 4, reason or "Вы не можете говорить.")
        return false
    end
    return true
end

local function icSay(ply, text, dist, verb)
    if muted(ply) or not requireIC(ply) then return end
    text = clean(text)
    if text == "" or limited(ply, "ic", C.Chat.icRate) then return end
    local name = SV.Chars.displayName(ply)
    Comms.say(ply, verb and (name .. " " .. verb) or name, text, dist, Comms.divisionColor(ply))
    SV.Audit.log("chat", "ic", ply, nil, {text = text, dist = dist})
    SV.Bus.emit("comms.said", {ply = ply, text = text, dist = dist})
end
Comms.icSay = icSay

--[[---------------------------------------------------------------------------
Commands
---------------------------------------------------------------------------]]
Bridge.chatCommand({command = "w", description = "Сказать шёпотом.", delay = 0.5}, function(ply, args)
    icSay(ply, args, C.Chat.whisperDistance, "(шёпотом)")
    return ""
end)

Bridge.chatCommand({command = "y", description = "Крикнуть.", delay = 0.5}, function(ply, args)
    icSay(ply, args, C.Chat.yellDistance, "(кричит)")
    return ""
end)

Bridge.chatCommand({command = "me", description = "Описать действие персонажа.", delay = 0.5}, function(ply, args)
    if muted(ply) or not requireIC(ply) then return "" end
    local text = clean(args)
    if text == "" or limited(ply, "ic", C.Chat.icRate) then return "" end
    Comms.say(ply, "* " .. SV.Chars.displayName(ply) .. " " .. text, "", C.Chat.meDistance, ME_COLOR)
    SV.Audit.log("chat", "me", ply, nil, {text = text})
    return ""
end)

Bridge.chatCommand({command = "do", description = "Описать обстановку.", delay = 0.5}, function(ply, args)
    if muted(ply) or not requireIC(ply) then return "" end
    local text = clean(args)
    if text == "" or limited(ply, "ic", C.Chat.icRate) then return "" end
    Comms.say(ply, "** " .. text .. " (" .. SV.Chars.displayName(ply) .. ")", "", C.Chat.meDistance, DO_COLOR)
    SV.Audit.log("chat", "do", ply, nil, {text = text})
    return ""
end)

Bridge.chatCommand({command = "r", description = "Сообщение по рации (текущий канал).", delay = 0.5}, function(ply, args)
    if muted(ply) or not requireIC(ply) then return "" end
    local text = clean(args)
    if text == "" or limited(ply, "radio", C.Chat.radioRate) then return "" end
    local ok, reason = Comms.transmit(ply, text)
    if not ok then DarkRP.notify(ply, 1, 4, reason) end
    return ""
end)

local function ooc(ply, args)
    if muted(ply) then return "" end
    if not C.Chat.oocEnabled or Comms.oocDisabled then
        DarkRP.notify(ply, 1, 4, "Глобальный OOC отключён администрацией. Используйте /looc.")
        return ""
    end
    local text = clean(args)
    if text == "" or limited(ply, "ooc", C.Chat.oocRate) then return "" end
    local prefix = "[OOC] " .. ply:SteamName()
    for _, other in ipairs(player.GetHumans()) do
        DarkRP.talkToPerson(other, OOC_COLOR, prefix, OOC_COLOR, text, ply)
    end
    SV.Audit.log("chat", "ooc", ply, nil, {text = text})
    return ""
end
Bridge.chatCommand({command = "ooc", description = "Глобальный внеигровой чат.", delay = 1}, ooc)
Bridge.chatCommand({command = "/", description = "Глобальный внеигровой чат.", delay = 1}, ooc)

Bridge.chatCommand({command = "looc", description = "Локальный внеигровой чат.", delay = 0.5}, function(ply, args)
    if muted(ply) then return "" end
    local text = clean(args)
    if text == "" or limited(ply, "ic", C.Chat.icRate) then return "" end
    Comms.say(ply, "[LOOC] " .. ply:SteamName(), text, C.Chat.talkDistance, OOC_COLOR, OOC_COLOR)
    SV.Audit.log("chat", "looc", ply, nil, {text = text})
    return ""
end)

local function findPlayer(name)
    name = U.lowerRu(name or "")
    if name == "" then return nil end
    for _, p in ipairs(player.GetHumans()) do
        if string.find(U.lowerRu(p:Nick()), name, 1, true) or string.find(U.lowerRu(p:SteamName()), name, 1, true) then return p end
    end
    return nil
end
Comms.findPlayer = findPlayer

Bridge.chatCommand({command = "pm", description = "Личное внеигровое сообщение: /pm имя текст", delay = 1}, function(ply, args)
    if muted(ply) then return "" end
    local name, text = string.match(args or "", "^(%S+)%s+(.+)$")
    local target = findPlayer(name)
    if not target then
        DarkRP.notify(ply, 1, 4, "Игрок не найден.")
        return ""
    end
    text = clean(text)
    if text == "" or limited(ply, "ooc", C.Chat.oocRate) then return "" end
    DarkRP.talkToPerson(target, OOC_COLOR, "[ЛС от " .. ply:SteamName() .. "]", color_white, text, ply)
    DarkRP.talkToPerson(ply, OOC_COLOR, "[ЛС для " .. target:SteamName() .. "]", color_white, text, ply)
    SV.Audit.log("chat", "pm", ply, target, {text = text})
    return ""
end)

--[[---------------------------------------------------------------------------
Requests to administrators (tickets)
---------------------------------------------------------------------------]]
Comms.tickets = Comms.tickets or {}
Comms.nextTicket = Comms.nextTicket or 1

local function adminsOnline()
    local out = {}
    for _, p in ipairs(player.GetHumans()) do
        if p:IsAdmin() then out[#out + 1] = p end
    end
    return out
end

function Comms.openTicket(ply, text)
    text = clean(text)
    if U.utf8len(text) < 5 then return false, "Опишите проблему подробнее." end
    for _, t in pairs(Comms.tickets) do
        if t.sid == ply:SteamID64() and t.status ~= "closed" then
            t.messages[#t.messages + 1] = {from = ply:SteamName(), text = text, t = os.time()}
            for _, a in ipairs(adminsOnline()) do DarkRP.talkToPerson(a, ADMIN_COLOR, "[Обращение #" .. t.id .. "] " .. ply:SteamName(), color_white, text, ply) end
            return true, "Дополнение к обращению #" .. t.id .. " отправлено."
        end
    end
    local id = Comms.nextTicket
    Comms.nextTicket = id + 1
    Comms.tickets[id] = {id = id, sid = ply:SteamID64(), name = ply:SteamName(), status = "open", created = os.time(),
        messages = {{from = ply:SteamName(), text = text, t = os.time()}}}
    SV.Audit.log("admin", "ticket.open", ply, nil, {id = id, text = text})
    local admins = adminsOnline()
    for _, a in ipairs(admins) do
        DarkRP.talkToPerson(a, ADMIN_COLOR, "[Обращение #" .. id .. "] " .. ply:SteamName(), color_white, text, ply)
    end
    hook.Run("SiteVeil.TicketsChanged")
    if #admins == 0 then
        return true, "Обращение #" .. id .. " сохранено. Сейчас нет администраторов в сети, оно будет рассмотрено позже."
    end
    return true, "Обращение #" .. id .. " отправлено администраторам."
end

Bridge.chatCommand({command = "report", description = "Обращение к администрации.", delay = 2}, function(ply, args)
    local ok, msg = Comms.openTicket(ply, args)
    DarkRP.notify(ply, ok and 0 or 1, 5, msg)
    return ""
end)

Net.handle("comms.ticket", function(ply, text)
    return Comms.openTicket(ply, text)
end)

--[[---------------------------------------------------------------------------
Plain text and team chat
---------------------------------------------------------------------------]]
hook.Add("PlayerSay", "SiteVeil.Chat", function(ply, text, teamOnly)
    if string.sub(text, 1, 1) == "@" then
        local ok, msg = Comms.openTicket(ply, string.sub(text, 2))
        DarkRP.notify(ply, ok and 0 or 1, 5, msg)
        return ""
    end
    if string.sub(text, 1, 1) == "/" or string.sub(text, 1, 1) == "!" then return end -- commands
    if teamOnly then
        if muted(ply) or not requireIC(ply) then return "" end
        local clean_ = clean(text)
        if clean_ ~= "" and not limited(ply, "radio", C.Chat.radioRate) then
            local ok, reason = Comms.transmit(ply, clean_)
            if not ok then DarkRP.notify(ply, 1, 4, reason) end
        end
        return ""
    end
    icSay(ply, text, C.Chat.talkDistance, nil)
    return ""
end)

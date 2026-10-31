--[[---------------------------------------------------------------------------
Emotes (server). Gestures are validated here (alive, free hands, not
incapacitated, cooldown) and broadcast to clients nearby. Dice are rolled
on the server so nobody can fake a result.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Emotes = SV.Emotes
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Emotes

Emotes.offers = Emotes.offers or {}   -- target -> {from, expires}

local function blocked(ply)
    if SV.Medical.isIncapacitated(ply) or SV.Medical.isStunned(ply) then return "вы не можете двигаться" end
    if SV.Security.restrained[ply] then return "руки скованы" end
    if SV.Roles.isSCP(ply) then return "недоступно объекту SCP" end
    return nil
end
Emotes.blocked = blocked

local function broadcast(ply, act)
    local list = {}
    for _, p in ipairs(player.GetHumans()) do
        if p:GetPos():DistToSqr(ply:GetPos()) <= K.animRange * K.animRange then list[#list + 1] = p end
    end
    Net.send(list, "emote.anim", {ent = ply:EntIndex(), act = act})
end

local function narrate(ply, text)
    SV.Comms.say(ply, "* " .. SV.Chars.displayName(ply), text, K.textRange, Color(200, 170, 255), Color(200, 170, 255))
end
Emotes.narrate = narrate

function Emotes.play(ply, id)
    local e = Emotes.byId[id]
    if not e then return false end
    local why = blocked(ply)
    if why then return false, "Жест недоступен: " .. why .. "." end
    if (ply.SVEmoteAt or -1e9) + K.cooldown > CurTime() then return false end
    ply.SVEmoteAt = CurTime()
    broadcast(ply, e.act)
    narrate(ply, e.text)
    return true
end

Net.handle("emote.play", function(ply, id) return Emotes.play(ply, id) end)

-- Handshake: needs the other person's consent.
Net.handle("emote.offer", function(ply, target)
    if not IsValid(target) or not target:IsPlayer() or target == ply or not target.SVChar then return false, "Нет собеседника." end
    if not U.within(ply, target, 90) then return false, "Подойдите ближе." end
    local why = blocked(ply) or blocked(target)
    if why then return false, "Невозможно: " .. why .. "." end
    Emotes.offers[target] = {from = ply, expires = CurTime() + K.offerTimeout}
    Net.send(target, "emote.offer", {name = SV.Chars.displayName(ply)})
    return true, "Вы протягиваете руку."
end)

Net.handle("emote.answer", function(ply, accept)
    local o = Emotes.offers[ply]
    Emotes.offers[ply] = nil
    if not o or o.expires < CurTime() or not IsValid(o.from) then return false, "Предложение больше не действует." end
    if not accept then
        DarkRP.notify(o.from, 3, 4, SV.Chars.displayName(ply) .. " не пожимает руку.")
        return true
    end
    if not U.within(ply, o.from, 120) then return false, "Вы разошлись слишком далеко." end
    broadcast(ply, "ACT_GMOD_GESTURE_ITEM_GIVE")
    broadcast(o.from, "ACT_GMOD_GESTURE_ITEM_GIVE")
    SV.Comms.say(ply, "* " .. SV.Chars.displayName(o.from) .. " и " .. SV.Chars.displayName(ply), "пожимают руки", K.textRange,
        Color(200, 170, 255), Color(200, 170, 255))
    SV.Bus.emit("emote.handshake", {ply = o.from, target = ply})
    return true
end)

hook.Add("PlayerDisconnected", "SiteVeil.Emotes", function(ply) Emotes.offers[ply] = nil end)

local function command(name, description, fn)
    SV.DarkRP.chatCommand({command = name, description = description, delay = 2}, function(ply, args)
        if not ply.SVChar or not ply:Alive() then return "" end
        fn(ply, args or "")
        return ""
    end)
end

command("roll", "Бросить кубик: /roll [граней, по умолчанию 100].", function(ply, args)
    local sides = math.Clamp(math.floor(tonumber(string.match(args, "%d+")) or 100), 2, 1000)
    narrate(ply, "бросает кубик d" .. sides .. ": " .. math.random(1, sides))
end)

command("try", "Попытка действия с исходом 50/50: /try действие.", function(ply, args)
    local text = U.cleanText(args, 120)
    if text == "" then
        DarkRP.notify(ply, 1, 3, "Опишите действие: /try открыть ящик")
        return
    end
    narrate(ply, "пытается " .. text .. " — " .. (math.random() < 0.5 and "удачно" or "неудачно"))
end)

command("emote", "Жест: /emote wave|salute|agree|disagree|beckon|halt|forward|group|bow|laugh.", function(ply, args)
    local ok, msg = Emotes.play(ply, string.lower(U.cleanText(args, 16)))
    if not ok and msg then DarkRP.notify(ply, 1, 3, msg) end
end)

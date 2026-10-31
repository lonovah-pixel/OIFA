--[[---------------------------------------------------------------------------
Emotes (client): gesture menu (console sv_emotes, also in the interaction
menu), handshake offer, gesture playback.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local Net = SV.Net
local K = SV.Config.Emotes

local allowedActs = {ACT_GMOD_GESTURE_ITEM_GIVE = true}
for _, e in ipairs(K.list) do allowedActs[e.act] = true end

Net.on("emote.anim", function(data)
    local ply = Entity(data.ent)
    local act = allowedActs[data.act] and _G[data.act]
    if IsValid(ply) and ply:IsPlayer() and act then ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, act, true) end
end)

function SV.Emotes.openMenu()
    local options = {}
    for _, e in ipairs(K.list) do options[#options + 1] = {e.name, e.id} end
    UI.choose("ЖЕСТЫ", "Также: /roll, /try действие, /emote id.", options, function(id) Net.call("emote.play", id) end)
end

concommand.Add("sv_emotes", function() SV.Emotes.openMenu() end)

Net.on("emote.offer", function(data)
    UI.choose("РУКОПОЖАТИЕ", data.name .. " протягивает вам руку.", {{"Пожать руку", true}, {"Отказаться", false}}, function(v)
        Net.call("emote.answer", v)
    end)
end)

UI.registerInteraction{
    id = "handshake", name = "Пожать руку", order = 3,
    visible = function(target) return not SV.Roles.isSCP(target) end,
    action = function(target) Net.call("emote.offer", target) end,
}
UI.registerInteraction{
    id = "emotes", name = "Жесты…", order = 99,
    action = function() SV.Emotes.openMenu() end,
}

table.insert(UI.helpSections, {"Жесты", {
    "Консоль sv_emotes или меню взаимодействия → «Жесты…»; /emote wave|salute|agree|…",
    "ПКМ пустыми руками по человеку → «Пожать руку» (нужно согласие).",
    "/roll [граней] — бросок кубика, /try действие — попытка 50 на 50 (бросает сервер).",
}})

--[[---------------------------------------------------------------------------
Communication (client): radio push-to-talk binding, radio HUD indicator and
the "Связь" tab.

Push-to-talk: bind a key to +sv_radio (default suggestion: ALT), e.g.
    bind alt +sv_radio
While held, normal voice chat (+voicerecord) is started and the server
routes your voice to the current radio channel.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

local pttDown = false

concommand.Add("+sv_radio", function()
    if pttDown then return end
    pttDown = true
    Net.call("comms.ptt", true)
    permissions.EnableVoiceChat(true)
end)

concommand.Add("-sv_radio", function()
    if not pttDown then return end
    pttDown = false
    Net.call("comms.ptt", false)
    permissions.EnableVoiceChat(false)
end)

UI.hudElement("radio", 20, function()
    local radio = SV.Sync.get("self", "radio")
    if not radio or not radio.tx then return end
    local name
    for _, ch in ipairs(radio.channels or {}) do
        if ch.id == radio.tx then name = ch.name end
    end
    if not name then return end
    local text = "Рация: " .. name .. (radio.ptt and "  ● ПЕРЕДАЧА" or "")
    local w = UI.textSize("SV.HUDSmall", text) + S(20)
    local x, y = S(20), ScrH() - S(124) - S(20) - S(34)
    UI.drawPanel(x, y, w, S(28), C.panel)
    draw.SimpleText(text, "SV.HUDSmall", x + S(10), y + S(14), radio.ptt and C.danger or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

UI.registerTab{
    id = "comms", name = "Связь", order = 40,
    build = function(panel)
        local scroll = UI.scroll(panel)
        local radio = SV.Sync.get("self", "radio")
        local card = UI.card(scroll, "Рация")
        if not radio or #(radio.channels or {}) == 0 then
            UI.text(card, "У вас нет рации или доступных каналов. Рации выдаются со снаряжением должности и через снабжение.", "SV.Small", C.dim)
        else
            UI.text(card, "Передача ведётся на выбранном канале: /r текст, командный чат (U) или голосом при удержании клавиши +sv_radio.", "SV.Small", C.dim)
            for _, ch in ipairs(radio.channels) do
                local row = UI.row(card, S(34))
                local lbl = vgui.Create("DLabel", row)
                lbl:Dock(FILL)
                lbl:SetFont("SV.Body")
                lbl:SetTextColor(ch.id == radio.tx and C.accent or C.text)
                lbl:SetText(ch.name .. "  (" .. ch.freq .. ")" .. (ch.id == radio.tx and "  — передача" or ""))
                local tx = UI.button(row, "Передавать", function() Net.call("comms.channel", ch.id) end)
                tx:Dock(RIGHT) tx:SetWide(S(140))
                if not ch.tx then tx:SetBlocked("только приём (перехват)") elseif ch.id == radio.tx then tx:SetBlocked("уже выбран") end
                local lst = UI.button(row, ch.listen and "Не слушать" or "Слушать", function() Net.call("comms.listen", ch.id, not ch.listen) end, "ghost")
                lst:Dock(RIGHT) lst:SetWide(S(140)) lst:DockMargin(0, 0, S(6), 0)
            end
        end
        local keys = UI.card(scroll, "Голосовая рация")
        local bound = input.LookupBinding("+sv_radio")
        UI.text(keys, bound and ("Клавиша рации: " .. string.upper(bound)) or "Клавиша рации не назначена. Введите в консоли: bind alt +sv_radio", "SV.Body", bound and C.text or C.warn)

        local report = UI.card(scroll, "Обращение к администрации")
        local entry = vgui.Create("SVEntry", report)
        entry:Dock(TOP)
        entry:SetHint("Опишите ситуацию (можно также написать в чат: @ текст)")
        local send = UI.button(report, "Отправить", function()
            Net.call("comms.ticket", entry:GetValue())
            entry:SetValue("")
        end, "primary")
        send:Dock(TOP)
        send:DockMargin(0, S(6), 0, 0)
    end,
}

hook.Add("SiteVeil.Sync", "SiteVeil.UI.Comms", function(channel, key)
    if channel == "self" and key == "radio" then UI.refreshTab("comms") end
end)

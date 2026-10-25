--[[---------------------------------------------------------------------------
Hidden tasks (client): consent switch, offer dialog, current task.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Hidden = SV.Hidden

Hidden.info = Hidden.info or nil

Net.on("hidden.optin", function(data)
    Hidden.info = data
    UI.refreshTab("hidden")
end)

Net.on("hidden.offer", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ЛИЧНОЕ СООБЩЕНИЕ")
    f:SetSize(S(500), S(260))
    f:Center()
    f:MakePopup()
    UI.text(f, data.name, "SV.Sub", C.warn)
    UI.text(f, data.text)
    UI.text(f, "Срок: " .. math.floor(data.timeLimit / 60) .. " мин. Отказ и отказ от задания позже ни на что не влияют.", "SV.Small", C.dim)
    local row = UI.row(f, S(36))
    row:Dock(BOTTOM)
    local yes = UI.button(row, "Согласиться", function() Net.call("hidden.answer", true) f:Close() end, "primary")
    yes:Dock(RIGHT)
    yes:SetWide(S(160))
    local no = UI.button(row, "Отказаться", function() Net.call("hidden.answer", false) f:Close() end)
    no:Dock(RIGHT)
    no:SetWide(S(140))
    no:DockMargin(0, 0, S(8), 0)
end)

UI.hudElement("hidden", 33, function()
    local h = SV.Sync.get("self", "hidden")
    if not h then return end
    local left = math.max(math.ceil(h.endsAt - CurTime()), 0)
    local text = "Личное: " .. h.name .. (h.target and (" · " .. h.target) or "") .. (h.progress and (" · " .. h.progress .. "%") or "") ..
        string.format(" · %d:%02d", math.floor(left / 60), left % 60)
    draw.SimpleText(text, "SV.Tiny", S(20), S(150), C.warn)
end)

UI.registerTab{
    id = "hidden", name = "Личное", order = 19,
    visible = function() local c = UI.myChar() return c and not c.isSCP end,
    build = function(panel)
        local scroll = UI.scroll(panel)
        local info = Hidden.info
        if not info then
            UI.text(scroll, "Загрузка…", "SV.Body", C.dim)
            Net.call("hidden.state")
            return
        end
        Hidden.info = nil
        local card = UI.card(scroll, "Скрытые задания")
        UI.text(card, "Необязательные задания с двойным дном: утечки, контрабанда, негласные проверки. Они никогда не требуют убивать, " ..
            "калечить или уничтожать. Каждое оставляет следы, по которым его могут раскрыть. Отказ ничем не наказывается.", "SV.Small", C.dim)
        if info.enabled == false then UI.text(card, "Сейчас отключены администрацией.", "SV.Small", C.warn) end
        local b = UI.button(card, info.on and "Не предлагать мне скрытые задания" or "Согласен получать скрытые задания", function()
            Net.call("hidden.optin", not info.on)
        end, info.on and "ghost" or "primary")
        b:Dock(TOP)
        if info.on and info.blocked then UI.text(card, "Новые предложения: нет (" .. info.blocked .. ").", "SV.Tiny", C.faint) end
        local h = SV.Sync.get("self", "hidden")
        local cur = UI.card(scroll, "Текущее задание")
        if not h then
            UI.text(cur, "Нет.", "SV.Small", C.dim)
        else
            UI.text(cur, h.name, "SV.Sub", C.warn)
            UI.text(cur, h.text, "SV.Body")
            if h.target then UI.text(cur, "Цель: " .. h.target, "SV.Small") end
            local ab = UI.button(cur, "Бросить задание", function() Net.call("hidden.abandon") end, "danger")
            ab:Dock(TOP)
        end
    end,
}

hook.Add("SiteVeil.AdminTab", "SiteVeil.Hidden", function(scroll)
    local card = UI.card(scroll, "Скрытые задания")
    local row = UI.row(card, S(32))
    local on = UI.button(row, "Включить", function() Net.call("hidden.toggle", true) end)
    on:Dock(LEFT)
    on:SetWide(S(140))
    local off = UI.button(row, "Выключить", function() Net.call("hidden.toggle", false) end, "danger")
    off:Dock(LEFT)
    off:SetWide(S(140))
    off:DockMargin(S(6), 0, 0, 0)
    if not SV.Admin.isOnDuty(LocalPlayer()) then
        on:SetBlocked("заступите на дежурство")
        off:SetBlocked("заступите на дежурство")
    end
end)

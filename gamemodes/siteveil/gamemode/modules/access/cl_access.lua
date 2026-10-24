--[[---------------------------------------------------------------------------
Access (client): denied prompt with emergency opening / manual drive, door
access log window, temporary pass issuing from the interaction menu, card
registry window.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Access = SV.Access

Net.on("access.denied", function(data)
    if not data.emergency and not data.crank then return end
    if IsValid(UI.accessPrompt) then UI.accessPrompt:Remove() end
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    UI.accessPrompt = f
    f:SetHeader("ДОСТУП ЗАПРЕЩЁН", data.name)
    f:SetSize(S(460), S(200))
    f:SetPos(ScrW() / 2 - S(230), ScrH() * 0.62)
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    UI.text(f, "Причина: " .. tostring(data.reason), "SV.Body")
    if data.emergency then
        UI.text(f, "Аварийное открытие будет записано в журнал и сообщено охране.", "SV.Small", C.warn)
        local b = UI.button(f, "Аварийное открытие", function() Net.call("access.emergency", ent) f:Close() end, "danger")
        b:Dock(TOP)
    end
    if data.crank then
        local b = UI.button(f, "Ручной привод", function() Net.call("access.crank", ent) f:Close() end, "primary")
        b:Dock(TOP)
        b:DockMargin(0, S(6), 0, 0)
    end
    timer.Simple(8, function() if IsValid(f) then f:Close() end end)
end)

Net.on("access.log", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ЖУРНАЛ СЧИТЫВАТЕЛЯ", data.name)
    f:SetSize(S(520), S(520))
    f:Center()
    f:MakePopup()
    UI.text(f, "Время округлено системой записи. Пропуски означают сбой записи (нет питания подсистемы безопасности).", "SV.Tiny", C.dim)
    local scroll = UI.scroll(f)
    for _, e in ipairs(data.entries) do
        if e.gap then
            UI.text(scroll, "~" .. e.time .. "  — нет данных —", "SV.Mono", C.faint)
        else
            UI.text(scroll, string.format("%s  карта %s  %s%s", e.time, e.serial, e.ok and "ДОПУСК" or "ОТКАЗ", e.kind == "emergency" and " (АВАРИЙНО)" or ""), "SV.Mono", e.ok and C.ok or C.danger)
        end
    end
end)

Net.on("access.cards", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("РЕЕСТР КАРТ ДОСТУПА")
    f:SetSize(S(640), S(600))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    local rv = UI.card(scroll, "Аннулировать карту")
    local serial = vgui.Create("SVEntry", rv)
    serial:Dock(TOP)
    serial:SetHint("Серийный номер, например 1A2B-3C4D")
    local reason = vgui.Create("SVEntry", rv)
    reason:Dock(TOP)
    reason:DockMargin(0, S(6), 0, S(6))
    reason:SetHint("Основание")
    local b = UI.button(rv, "Аннулировать", function() Net.call("access.revoke", serial:GetValue(), reason:GetValue()) f:Close() end, "danger")
    b:Dock(TOP)

    local passes = UI.card(scroll, "Действующие временные пропуска")
    if #data.passes == 0 then UI.text(passes, "Нет действующих пропусков.", "SV.Small", C.dim) end
    for _, p in ipairs(data.passes) do
        UI.text(passes, string.format("%s · %s (№ %s) · допуск %s · осталось %s", p.serial, p.holder_name or "?", p.holder_number or "?", p.clearance, SV.Util.formatDuration(p.left)), "SV.Small")
    end
    local revoked = UI.card(scroll, "Аннулированные", C.danger)
    for _, r in ipairs(data.revoked) do
        UI.text(revoked, string.format("%s · %s · %s · %s", r.revoked, r.serial, r.holder_name or "?", r.reason or ""), "SV.Tiny", C.dim)
    end
end)

local function myRole() return SV.Roles.ofPlayer(LocalPlayer()) end

UI.registerInteraction{
    id = "pass", name = "Выдать временный пропуск", order = 30,
    visible = function() local r = myRole() return r and r.flags.issuePasses end,
    action = function(target)
        local role = myRole()
        local f = vgui.Create("SVFrame")
        f:SetHeader("ВРЕМЕННЫЙ ПРОПУСК", SV.Chars.displayName(target))
        f:SetSize(S(500), S(420))
        f:Center()
        f:MakePopup()
        UI.text(f, "Допуск", "SV.Small", C.dim)
        local clear = vgui.Create("DComboBox", f)
        clear:Dock(TOP)
        clear:SetTall(S(30))
        for lvl = 0, math.min(role.clearance, SV.Config.Access and SV.Config.Access.passMaxClearance or 3) do
            clear:AddChoice(Access.CLEARANCE_NAMES[lvl], lvl, lvl == 1)
        end
        UI.text(f, "Зоны (только из ваших)", "SV.Small", C.dim):DockMargin(0, S(6), 0, 0)
        local chosen = {}
        for _, t in ipairs(role.tags) do
            local cb = vgui.Create("DCheckBoxLabel", f)
            cb:Dock(TOP)
            cb:DockMargin(0, S(2), 0, S(2))
            cb:SetText(Access.TAG_NAMES[t] or t)
            cb:SetFont("SV.Small")
            cb:SetTextColor(C.text)
            cb.OnChange = function(_, v) chosen[t] = v or nil end
        end
        UI.text(f, "Срок, минут", "SV.Small", C.dim):DockMargin(0, S(6), 0, 0)
        local mins = vgui.Create("DNumberWang", f)
        mins:Dock(TOP)
        mins:SetMin(1)
        mins:SetMax(SV.Config.Access and SV.Config.Access.passMaxMinutes or 30)
        mins:SetValue(15)
        local issue = UI.button(f, "Выдать", function()
            local _, lvl = clear:GetSelected()
            local tags = {}
            for t in pairs(chosen) do tags[#tags + 1] = t end
            Net.call("access.issuePass", target, lvl or 0, table.concat(tags, ","), math.Clamp(math.floor(mins:GetValue()), 1, 60))
            f:Close()
        end, "primary")
        issue:Dock(BOTTOM)
    end,
}

-- Security staff: show the card registry and door logs from the look-at.
concommand.Add("sv_cards", function() Net.call("access.cards") end)
concommand.Add("sv_doorlog", function()
    local ent = LocalPlayer():GetEyeTrace().Entity
    if IsValid(ent) then Net.call("access.log", ent) end
end)

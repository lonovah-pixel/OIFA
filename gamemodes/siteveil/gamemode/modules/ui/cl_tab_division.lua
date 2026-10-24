--[[---------------------------------------------------------------------------
Tab "Подразделение": roles of the own division with availability reasons,
division transfer requests and (for approvers) pending transfers.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

UI.registerTab{
    id = "division", name = "Подразделение", order = 15,
    visible = function() local c = UI.myChar() return c and not c.isSCP end,
    build = function(panel)
        local char = UI.myChar()
        local data = UI.roleData
        if not data then
            UI.text(panel, "Загрузка…", "SV.Body", C.dim)
            Net.call("char.roles")
            return
        end
        local div = SV.Roles.getDivision(char.division)
        local scroll = UI.scroll(panel)
        UI.text(scroll, div and div.name or "", "SV.Header", UI.divisionColor(char.division))
        UI.text(scroll, "Онлайн: " .. (data.online or 0) .. ". Число мест в ролях зависит от онлайна.", "SV.Small", C.dim)

        for _, r in ipairs(data.roles or {}) do
            local role = SV.Roles.get(r.id)
            local card = UI.card(scroll, role.name .. (r.current and "  (текущая)" or ""), r.ok and C.ok or C.faint)
            UI.text(card, role.description, "SV.Small")
            local info = string.format("Допуск %d · Звание от «%s» · Занято %d%s", role.clearance,
                SV.Roles.rankName(role.division, role.minRank), r.count, r.slots and (" из " .. r.slots) or "")
            UI.text(card, info, "SV.Tiny", C.dim)
            if not r.current then
                local b = UI.button(card, "Занять должность", function() Net.call("char.takeRole", r.id) end, "primary")
                b:Dock(TOP)
                if not r.ok then b:SetBlocked(r.reason or "недоступно") end
            end
        end

        local tr = UI.card(scroll, "Перевод в другое подразделение")
        UI.text(tr, "Перевод рассматривает администрация комплекса. После перевода звание начинается с первого.", "SV.Small", C.dim)
        local combo = vgui.Create("DComboBox", tr)
        combo:Dock(TOP)
        combo:SetTall(S(32))
        combo:SetFont("SV.Body")
        for _, d in ipairs(data.transferTargets or {}) do combo:AddChoice(d.name, d.id) end
        local reason = vgui.Create("SVEntry", tr)
        reason:Dock(TOP)
        reason:DockMargin(0, S(6), 0, S(6))
        reason:SetHint("Причина перевода")
        local send = UI.button(tr, "Подать запрос", function()
            local _, id = combo:GetSelected()
            if not id then UI.notify("Выберите подразделение.", 1) return end
            Net.call("char.transfer", id, reason:GetValue())
        end)
        send:Dock(TOP)
        if data.pendingTransfer then send:SetBlocked("запрос уже рассматривается") end

        if data.transfers and #data.transfers > 0 then
            local ap = UI.card(scroll, "Запросы на перевод", C.warn)
            for _, t in ipairs(data.transfers) do
                local from = SV.Roles.getDivision(t.from_division)
                local to = SV.Roles.getDivision(t.to_division)
                UI.text(ap, string.format("%s: %s → %s. %s", t.char_name, from and from.name or "?", to and to.name or "?", t.reason), "SV.Small")
                local row = UI.row(ap, S(32))
                local yes = UI.button(row, "Одобрить", function() Net.call("char.transferDecide", tonumber(t.id), true) end, "primary")
                yes:Dock(LEFT) yes:SetWide(S(140))
                local no = UI.button(row, "Отклонить", function() Net.call("char.transferDecide", tonumber(t.id), false) end, "danger")
                no:Dock(LEFT) no:SetWide(S(140)) no:DockMargin(S(8), 0, 0, 0)
            end
        end
    end,
}

hook.Add("OnPlayerChangedTeam", "SiteVeil.UI.Roles", function()
    UI.roleData = nil
end)

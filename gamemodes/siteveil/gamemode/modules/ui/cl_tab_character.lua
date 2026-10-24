--[[---------------------------------------------------------------------------
Tab "Удостоверение": service ID, rank progress, character switching.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

UI.roleData = UI.roleData or nil

local function drawIdCard(panel, char, role)
    local card = vgui.Create("DPanel", panel)
    card:Dock(TOP)
    card:SetTall(S(190))
    card:DockMargin(0, 0, 0, S(10))
    local div = SV.Roles.getDivision(char.division)
    local mdl = vgui.Create("DModelPanel", card)
    mdl:Dock(LEFT)
    mdl:SetWide(S(150))
    mdl:SetModel(LocalPlayer():GetModel())
    mdl:SetFOV(22)
    mdl:SetCamPos(Vector(50, 0, 64))
    mdl:SetLookAt(Vector(0, 0, 62))
    function mdl:LayoutEntity() end

    card.Paint = function(_, w, h)
        UI.drawPanel(0, 0, w, h, C.panel2)
        surface.SetDrawColor(div and div.color or C.accent)
        surface.DrawRect(0, 0, w, S(6))
        local x = S(170)
        draw.SimpleText("ФОНД SCP · КОМПЛЕКС SITE-VEIL", "SV.Tiny", x, S(16), C.dim)
        draw.SimpleText(SV.Chars.displayName(LocalPlayer()), "SV.Title", x, S(34), C.text)
        draw.SimpleText("Служебный номер: " .. char.number, "SV.Body", x, S(76), C.text)
        draw.SimpleText("Подразделение: " .. (div and div.name or "—"), "SV.Body", x, S(100), C.text)
        draw.SimpleText("Должность: " .. (role and role.name or "—"), "SV.Body", x, S(124), C.text)
        draw.SimpleText("Звание: " .. SV.Roles.rankName(char.division, char.rank), "SV.Body", x, S(148), C.text)
        local clearance = SV.Sync.get("self", "clearance") or (role and role.clearance) or 0
        draw.SimpleText("ДОПУСК " .. clearance, "SV.Title", w - S(20), S(34), clearance >= 3 and C.warn or C.accent, TEXT_ALIGN_RIGHT)
    end
end

UI.registerTab{
    id = "character", name = "Удостоверение", order = 10,
    build = function(panel)
        local char = UI.myChar()
        if not char then return end
        local role = SV.Roles.ofPlayer(LocalPlayer())
        local scroll = UI.scroll(panel)
        drawIdCard(scroll, char, role)

        local stats = UI.card(scroll, "Служба")
        UI.text(stats, string.format("Опыт: %d · Время на службе: %.1f ч", char.xp, char.playtime / 3600), "SV.Body")

        local promo = UI.card(scroll, "Повышение")
        local data = UI.roleData
        if data and data.promotion then
            local p = data.promotion
            if p.max then
                UI.text(promo, "Достигнуто высшее звание подразделения.", "SV.Body", C.dim)
            else
                UI.text(promo, "Следующее звание: " .. (p.rankName or "—"), "SV.Body")
                for _, cond in ipairs(p.conditions or {}) do
                    UI.text(promo, (cond.met and "✔ " or "✖ ") .. cond.text, "SV.Small", cond.met and C.ok or (cond.approval and C.warn or C.danger))
                end
                local btn = UI.button(promo, "Получить звание", function() Net.call("char.promote", LocalPlayer()) end, "primary")
                btn:Dock(TOP)
                if not p.possible then
                    btn:SetBlocked("условия повышения не выполнены")
                elseif p.needsApproval then
                    btn:SetBlocked("звание присваивает старший по званию через меню взаимодействия")
                end
            end
        else
            UI.text(promo, "Загрузка данных…", "SV.Small", C.dim)
            Net.call("char.roles")
        end

        if role then
            local duties = UI.card(scroll, "Обязанности: " .. role.name)
            for _, d in ipairs(role.duties) do UI.text(duties, "• " .. d, "SV.Small") end
            local alarm = UI.card(scroll, "При тревоге", C.warn)
            for _, d in ipairs(role.alarm) do UI.text(alarm, "• " .. d, "SV.Small") end
        end

        local switch = UI.card(scroll, "Персонаж")
        local b = UI.button(switch, "Сменить персонажа", function()
            UI.closeMenu()
            Net.call("char.unload")
        end)
        b:Dock(TOP)
        UI.text(switch, "Смена персонажа недоступна во время боя и сразу после предыдущей смены.", "SV.Tiny", C.faint)
    end,
}

Net.on("char.roles", function(data)
    UI.roleData = data
    UI.refreshTab("character")
    UI.refreshTab("division")
end)

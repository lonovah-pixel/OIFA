--[[---------------------------------------------------------------------------
Facility (client): state banner, sector status, power symptoms, node panel,
infrastructure terminal and the "Комплекс" tab.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Facility = SV.Facility
local F = SV.Config.Facility
local Sync = SV.Sync

local bucketColor = {ok = C.ok, degraded = C.warn, damaged = C.danger, offline = C.faint, unknown = C.faint}
local subOrder = {"power", "comms", "ventilation", "surveillance", "security"}
local subShort = {power = "ПИТ", comms = "СВЯЗЬ", ventilation = "ВЕНТ", surveillance = "НАБЛ", security = "БЕЗ"}

--[[---------------------------------------------------------------------------
Announcements
---------------------------------------------------------------------------]]
UI.banners = UI.banners or {}

Net.on("facility.announce", function(data)
    table.insert(UI.banners, 1, {text = data.text, kind = data.kind, born = RealTime()})
    while #UI.banners > 3 do table.remove(UI.banners) end
    if data.sound then surface.PlaySound(data.sound) end
    chat.AddText(UI.StateColors[data.kind] or C.accent, "[КОМПЛЕКС] ", color_white, data.text)
end)

local function mySectorId()
    return Sync.get("self", "sector")
end

UI.hudElement("facility", 5, function()
    local char = UI.myChar()
    if not char then return end
    local st = Sync.get("facility", "state") or {id = "normal"}
    local col = UI.StateColors[st.id] or C.ok
    local name = F.states[st.id] and F.states[st.id].name or st.id
    local w = S(420)
    local x, y = ScrW() / 2 - w / 2, S(12)
    local flash = st.id ~= "normal" and st.id ~= "recovery" and math.floor(RealTime() * 2) % 2 == 0
    UI.drawPanel(x, y, w, S(34), flash and ColorAlpha(col, 60) or C.panel, col)
    draw.SimpleText(name, "SV.Sub", ScrW() / 2, y + S(17), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    y = y + S(38)

    local sector = mySectorId()
    local alerts = Sync.get("facility", "alerts") or {}
    local lockdowns = Sync.get("facility", "lockdowns") or {}
    if sector and alerts[sector] then
        draw.SimpleText("ЛОКАЛЬНАЯ ТРЕВОГА В СЕКТОРЕ", "SV.HUDSmall", ScrW() / 2, y, UI.StateColors.alert, TEXT_ALIGN_CENTER)
        y = y + S(20)
    end
    if sector and lockdowns[sector] then
        draw.SimpleText("СЕКТОР ЗАБЛОКИРОВАН", "SV.HUDSmall", ScrW() / 2, y, UI.StateColors.lockdown, TEXT_ALIGN_CENTER)
        y = y + S(20)
    end
    local rec = Sync.get("facility", "recovery")
    if st.id == "recovery" and rec then
        draw.SimpleText(string.format("Восстановление: отремонтировано узлов %d / %d", rec.repairs, rec.needed), "SV.HUDSmall", ScrW() / 2, y, C.info, TEXT_ALIGN_CENTER)
        y = y + S(20)
    end

    local now = RealTime()
    for i = #UI.banners, 1, -1 do
        if now - UI.banners[i].born > 10 then table.remove(UI.banners, i) end
    end
    for _, b in ipairs(UI.banners) do
        local lines = UI.wrap("SV.HUDSmall", b.text, S(620))
        for _, line in ipairs(lines) do
            draw.SimpleText(line, "SV.HUDSmall", ScrW() / 2, y, UI.StateColors[b.kind] or C.text, TEXT_ALIGN_CENTER)
            y = y + S(18)
        end
        y = y + S(4)
    end
end)

UI.hudElement("sector", 6, function()
    local char = UI.myChar()
    local sector = mySectorId()
    if not char or not sector then return end
    local s = Sync.get("sectors", sector)
    if not s then return end
    local x, y = S(20), S(20)
    local w = S(300)
    UI.drawPanel(x, y, w, S(66), C.panel)
    draw.SimpleText(s.name, "SV.HUDSmall", x + S(10), y + S(6), C.text)
    local power = math.Round((s.power or 1) * 100)
    draw.SimpleText("Питание " .. power .. "%" .. (s.backup and " (резерв, топливо " .. s.fuel .. "%)" or ""), "SV.Tiny", x + w - S(10), y + S(8),
        power >= 70 and C.dim or C.warn, TEXT_ALIGN_RIGHT)
    local bx = x + S(10)
    for _, sub in ipairs(subOrder) do
        local b = s.subs and s.subs[sub] or "unknown"
        local col = bucketColor[b]
        surface.SetDrawColor(ColorAlpha(col, 50))
        surface.DrawRect(bx, y + S(32), S(52), S(24))
        surface.SetDrawColor(col)
        surface.DrawOutlinedRect(bx, y + S(32), S(52), S(24))
        draw.SimpleText(subShort[sub], "SV.Tiny", bx + S(26), y + S(44), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        bx = bx + S(56)
    end
    if s.contaminated then
        draw.SimpleText("ВОЗДУХ ЗАГРЯЗНЁН — НАДЕНЬТЕ ПРОТИВОГАЗ", "SV.HUDSmall", x, y + S(72), C.danger)
    end
end)

-- Power symptom: dim and flicker the view in sectors with low power.
hook.Add("RenderScreenspaceEffects", "SiteVeil.Facility.Brownout", function()
    local sector = mySectorId()
    local s = sector and Sync.get("sectors", sector)
    if not s or not UI.myChar() then return end
    local p = s.power or 1
    if p >= 0.65 then return end
    local dim = (0.65 - p) * 0.55
    if s.backup and math.sin(RealTime() * 13) > 0.92 then dim = dim + 0.15 end
    if p < 0.3 and math.random() < 0.02 then dim = dim + 0.3 end
    DrawColorModify({
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = -dim, ["$pp_colour_contrast"] = 1 - dim * 0.4,
        ["$pp_colour_colour"] = 1 - dim * 0.6,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
    })
end)

--[[---------------------------------------------------------------------------
Node panel
---------------------------------------------------------------------------]]
Net.on("infra.node", function(data)
    if IsValid(UI.nodePanel) then UI.nodePanel:Remove() end
    local ent = Entity(data.ent)
    local v = data.view
    local f = vgui.Create("SVFrame")
    UI.nodePanel = f
    f:SetHeader(string.upper(v.name), v.sector)
    f:SetSize(S(520), S(470))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    local scroll = UI.scroll(f)
    UI.text(scroll, "Подсистема: " .. v.subsystem, "SV.Body")
    UI.text(scroll, "Внешний осмотр: " .. v.indicator, "SV.Body", C.dim)
    if v.health then
        UI.text(scroll, "Диагностика: исправность " .. v.health .. "%", "SV.Sub", v.health >= F.healthOk and C.ok or C.warn)
        UI.text(scroll, "Неисправность: " .. (v.fault or "не обнаружена"), "SV.Body")
        if v.hint then UI.text(scroll, "Рекомендация: " .. v.hint, "SV.Small", C.dim) end
        if v.parts then
            UI.text(scroll, "Ремонт: запчастей " .. v.parts.parts .. (v.parts.item and (", " .. SV.Config.Items[v.parts.item].name) or "") .. ", около " .. v.parts.time .. " с", "SV.Small", C.dim)
        end
        if v.bypass then UI.text(scroll, "Временный обход: откажет через " .. SV.Util.formatDuration(v.bypass), "SV.Small", C.warn) end
    elseif v.engineer then
        UI.text(scroll, "Точное состояние неизвестно: выполните диагностику.", "SV.Small", C.warn)
    end
    if v.fuel then UI.text(scroll, "Топливо резервного генератора сектора: " .. v.fuel .. "%", "SV.Body") end

    local function action(label, id, blocked, style)
        local b = UI.button(scroll, label, function() Net.call("infra.action", ent, id) f:Close() end, style)
        b:Dock(TOP)
        b:DockMargin(0, S(4), 0, 0)
        if blocked then b:SetBlocked(blocked) end
    end
    local needTool = not v.tool and "нужен инструмент техника" or nil
    local needEng = not v.engineer and "только для инженерной службы" or nil
    action("Диагностика", "diagnose", needEng or needTool, "primary")
    action("Ремонт", "repair", needEng or needTool or (not v.health and "сначала выполните диагностику") or nil)
    action("Временный обход", "bypass", needEng or needTool or (v.health and v.health >= F.healthDegraded and "узел работоспособен") or nil)
    if v.fuel then action("Заправить резервный генератор", "refuel", nil) end
    action("Вмешаться в оборудование", "sabotage", nil, "danger")
end)

--[[---------------------------------------------------------------------------
Infrastructure terminal
---------------------------------------------------------------------------]]
Net.on("infra.overview", function(msg)
    local data = msg.data
    local ent = Entity(msg.ent)
    local reopen = IsValid(UI.infraPanel)
    if reopen then UI.infraPanel:Remove() end
    local f = vgui.Create("SVFrame")
    UI.infraPanel = f
    f:SetHeader("ИНФРАСТРУКТУРА КОМПЛЕКСА", "мощность " .. data.capacity .. " / " .. data.max)
    f:SetSize(math.min(ScrW() - S(40), S(1000)), math.min(ScrH() - S(40), S(700)))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    UI.text(scroll, "Главный генератор: " .. Facility.bucketNames[data.generator], "SV.Sub", bucketColor[data.generator])
    UI.text(scroll, "Мощность распределяется по приоритету: 1 — высший, 3 — низший, 0 — сектор обесточен. Точные данные об узлах доступны после диагностики на месте.", "SV.Small", C.dim)
    for _, s in ipairs(data.sectors) do
        local card = UI.card(scroll, s.name, s.power >= 70 and C.ok or (s.power >= 30 and C.warn or C.danger))
        UI.text(card, string.format("Питание %d%% (выделено %d%% от потребности %d)%s. Резерв: топливо %d%%.", s.power, s.alloc, s.demand,
            s.backup and ", РАБОТАЕТ РЕЗЕРВНЫЙ ГЕНЕРАТОР" or "", s.fuel), "SV.Small")
        local parts = {}
        for _, sub in ipairs(subOrder) do parts[#parts + 1] = Facility.subsystems[sub].name .. ": " .. Facility.bucketNames[s.subs[sub] or "unknown"] end
        UI.text(card, table.concat(parts, " · "), "SV.Tiny", C.dim)
        if s.contaminated then UI.text(card, "Загрязнение вентиляции!", "SV.Small", C.danger) end
        for _, line in ipairs(s.suspected) do UI.text(card, "⚠ " .. line, "SV.Small", C.warn) end
        local row = UI.row(card, S(32))
        for prio = 0, 3 do
            local b = UI.button(row, prio == 0 and "Обесточить" or ("Приоритет " .. prio), function() Net.call("infra.priority", ent, s.id, prio) end, s.priority == prio and "primary" or "default")
            b:Dock(LEFT)
            b:SetWide(S(130))
            b:DockMargin(0, 0, S(4), 0)
            if not data.canControl then b:SetBlocked("распределение мощности — для инженеров") end
            if s.priority == prio then b:SetBlocked("текущий режим") end
        end
    end
end)

--[[---------------------------------------------------------------------------
Tab "Комплекс": state and declarations
---------------------------------------------------------------------------]]
UI.facilityStatus = UI.facilityStatus or nil

UI.registerTab{
    id = "facility", name = "Комплекс", order = 30,
    build = function(panel)
        local data = UI.facilityStatus
        if not data then
            UI.text(panel, "Загрузка…", "SV.Body", C.dim)
            Net.call("facility.status")
            return
        end
        UI.facilityStatus = nil -- refresh on next open
        local scroll = UI.scroll(panel)
        local st = Sync.get("facility", "state") or {id = "normal"}
        local card = UI.card(scroll, "Режим: " .. (F.states[st.id] and F.states[st.id].name or st.id), UI.StateColors[st.id])
        if st.reason and st.reason ~= "" then UI.text(card, "Основание: " .. st.reason, "SV.Small", C.dim) end
        if data.breached > 0 then UI.text(card, "Объектов вне камер: " .. data.breached, "SV.Body", C.danger) end

        local reason = vgui.Create("SVEntry", card)
        reason:Dock(TOP)
        reason:SetHint("Основание решения (будет объявлено)")
        reason:DockMargin(0, S(6), 0, S(6))
        local flagFor = {breach = "declareBreach", evacuation = "declareEvac", recovery = "declareRecovery", normal = "declareRecovery"}
        local labels = {breach = "Объявить нарушение содержания", evacuation = "Объявить эвакуацию", recovery = "Объявить восстановление", normal = "Завершить восстановление"}
        for _, to in ipairs(data.allowed) do
            local b = UI.button(card, labels[to] or to, function() Net.call("facility.declare", "state", to, reason:GetValue()) end, to == "breach" and "danger" or "primary")
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, S(4))
            if not data.flags[flagFor[to]] then b:SetBlocked("нет полномочий") end
            if to == "recovery" and data.breached > 0 then b:SetBlocked("объекты ещё вне камер") end
        end

        local alerts = Sync.get("facility", "alerts") or {}
        local lockdowns = Sync.get("facility", "lockdowns") or {}
        local secCard = UI.card(scroll, "Секторы")
        for _, s in ipairs(data.sectors) do
            local row = UI.row(secCard, S(32))
            local lbl = vgui.Create("DLabel", row)
            lbl:Dock(FILL)
            lbl:SetFont("SV.Body")
            lbl:SetTextColor(C.text)
            lbl:SetText(s.name .. (alerts[s.id] and "  · тревога" or "") .. (lockdowns[s.id] and "  · блокировка" or "") .. (data.mySector == s.id and "  (вы здесь)" or ""))
            local a = UI.button(row, alerts[s.id] and "Снять тревогу" or "Тревога", function()
                Net.call("facility.declare", alerts[s.id] and "alertoff" or "alert", s.id, reason:GetValue())
            end)
            a:Dock(RIGHT) a:SetWide(S(150))
            if not data.flags.declareAlert then a:SetBlocked("нет полномочий") end
            local l = UI.button(row, lockdowns[s.id] and "Снять блокировку" or "Блокировка", function()
                Net.call("facility.declare", lockdowns[s.id] and "unlock" or "lockdown", s.id, reason:GetValue())
            end, "danger")
            l:Dock(RIGHT) l:SetWide(S(170)) l:DockMargin(0, 0, S(6), 0)
            if not data.flags.lockdown then l:SetBlocked("нет полномочий") end
        end
    end,
}

Net.on("facility.status", function(data)
    UI.facilityStatus = data
    UI.refreshTab("facility")
end)

hook.Add("SiteVeil.SyncChannel", "SiteVeil.UI.FacilityTab", function(channel)
    if channel == "facility" and IsValid(UI.menuPanel) and UI.menuPanel.tabs.active == "facility" then
        Net.call("facility.status")
    end
end)

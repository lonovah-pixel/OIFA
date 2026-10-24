--[[---------------------------------------------------------------------------
Administration (client): admin tab, server status, map editor window and
world overlay of the map configuration while the map tool is held.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local MapCfg = SV.MapCfg

UI.adminStatus = UI.adminStatus or nil
UI.mapData = UI.mapData or nil

--- Parses "key=value; key2=a,b" into a table (numbers converted, "tags" -> list).
local function parseProps(text)
    local out = {}
    for pair in string.gmatch(text or "", "[^;]+") do
        local k, v = string.match(pair, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then
            if k == "tags" then
                local list = {}
                for t in string.gmatch(v, "[^,%s]+") do list[#list + 1] = t end
                out[k] = list
            elseif tonumber(v) then out[k] = tonumber(v)
            elseif v == "true" or v == "false" then out[k] = v == "true"
            else out[k] = v end
        end
    end
    return out
end

local function propsText(props)
    local parts = {}
    for k, v in pairs(props or {}) do
        if k ~= "auto" then parts[#parts + 1] = k .. "=" .. (istable(v) and table.concat(v, ",") or tostring(v)) end
    end
    table.sort(parts)
    return table.concat(parts, "; ")
end

--[[---------------------------------------------------------------------------
Admin tab
---------------------------------------------------------------------------]]
UI.registerTab{
    id = "admin", name = "Администрирование", order = 95,
    visible = function(ply) return ply:IsAdmin() end,
    build = function(panel)
        local scroll = UI.scroll(panel)
        local duty = UI.card(scroll, "Режим дежурства")
        local on = SV.Admin.isOnDuty(LocalPlayer())
        UI.text(duty, on and "Вы на дежурстве: бессмертие, noclip, физган и полный доступ. Все действия записываются." or "Вы не на дежурстве: права ограничены ролью персонажа.", "SV.Small", on and C.warn or C.dim)
        local b = UI.button(duty, on and "Завершить дежурство" or "Заступить на дежурство", function() Net.call("admin.duty") end, on and "danger" or "primary")
        b:Dock(TOP)
        local map = UI.button(duty, "Редактор карты", function() UI.openMapEditor() end)
        map:Dock(TOP)
        map:DockMargin(0, S(6), 0, 0)
        if not LocalPlayer():IsSuperAdmin() then map:SetBlocked("нужны права суперадминистратора")
        elseif not on then map:SetBlocked("заступите на дежурство") end

        hook.Run("SiteVeil.AdminTab", scroll)

        local st = UI.adminStatus
        local card = UI.card(scroll, "Состояние сервера")
        if not st then
            UI.text(card, "Загрузка…", "SV.Small", C.dim)
            Net.call("admin.status")
            return
        end
        UI.adminStatus = nil
        UI.text(card, string.format("SITE-VEIL %s · смена %d · режим %s · карта: %s", st.version, st.shift, st.state, st.mapSource), "SV.Small")
        UI.text(card, string.format("БД: %s, запросов %d, ошибок %d, самый долгий %.2f мс", st.db.ready and "готова" or "НЕДОСТУПНА", st.db.queries, st.db.errors, st.db.slowestMs), "SV.Small", st.db.ready and C.text or C.danger)
        UI.text(card, "Интеграция DarkRP: " .. (st.darkrpVerified and "проверена" or "есть проблемы"), "SV.Small", st.darkrpVerified and C.ok or C.danger)
        for _, e in ipairs(st.loaderErrors or {}) do UI.text(card, "Ошибка загрузки: " .. e, "SV.Tiny", C.danger) end
        for _, e in ipairs(st.mapReport and st.mapReport.errors or {}) do UI.text(card, "Карта: " .. e, "SV.Tiny", C.danger) end
        for _, w in ipairs(st.mapReport and st.mapReport.warnings or {}) do UI.text(card, "Карта: " .. w, "SV.Tiny", C.warn) end
        local perf = UI.card(scroll, "Диагностика производительности")
        for _, line in ipairs(st.perf or {}) do UI.text(perf, line, "SV.Mono", C.dim) end
        local logs = UI.card(scroll, "Последние предупреждения")
        for i = #(st.recentLog or {}), math.max(#(st.recentLog or {}) - 15, 1), -1 do
            local e = st.recentLog[i]
            UI.text(logs, os.date("%H:%M:%S", e.time) .. "  " .. e.msg, "SV.Tiny", e.level == "error" and C.danger or C.warn)
        end
    end,
}

Net.on("admin.status", function(data)
    UI.adminStatus = data
    UI.refreshTab("admin")
end)

--[[---------------------------------------------------------------------------
Map editor
---------------------------------------------------------------------------]]
local function combo(parent, choices, default)
    local c = vgui.Create("DComboBox", parent)
    c:SetTall(S(30))
    c:SetFont("SV.Small")
    c:SetSortItems(false)
    for _, ch in ipairs(choices) do c:AddChoice(ch[2], ch[1], ch[1] == default) end
    return c
end

local function kindChoices(kinds)
    local out = {}
    for id, def in pairs(kinds) do out[#out + 1] = {id, def.name .. " (" .. id .. ")"} end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local function buildEditor(f, data)
    f.content:Clear()
    local scroll = UI.scroll(f.content)
    local cfg = data.cfg

    local head = UI.card(scroll, "Карта " .. data.map .. " · источник: " .. data.source)
    UI.text(head, "ЛКМ/ПКМ инструментом — углы объёма. Позиции точек берутся на сервере по вашей позиции или взгляду.", "SV.Small", C.dim)
    local c1 = data.corners and data.corners[1]
    local c2 = data.corners and data.corners[2]
    UI.text(head, "Угол 1: " .. (c1 and table.concat(c1, " ") or "—") .. "   Угол 2: " .. (c2 and table.concat(c2, " ") or "—"), "SV.Mono")
    for _, e in ipairs(data.report.errors) do UI.text(head, "✖ " .. e, "SV.Tiny", C.danger) end
    for _, w in ipairs(data.report.warnings) do UI.text(head, "⚠ " .. w, "SV.Tiny", C.warn) end
    local cmds = UI.row(head, S(32))
    for _, cmd in ipairs({{"save", "Сохранить"}, {"reload", "Перечитать"}, {"validate", "Проверить"}, {"respawn", "Пересоздать сущности"}, {"auto", "Автомакет"}, {"export", "Экспорт"}}) do
        local b = UI.button(cmds, cmd[2], function() Net.call("mapcfg.command", cmd[1]) end, cmd[1] == "save" and "primary" or "default")
        b:Dock(LEFT)
        b:SetWide(S(150))
        b:DockMargin(0, 0, S(4), 0)
    end

    -- Zones
    local zc = UI.card(scroll, "Зоны (" .. #cfg.zones .. ")")
    local zrow = UI.row(zc, S(32))
    local zkind = combo(zrow, kindChoices(MapCfg.zoneKinds), "sector")
    zkind:Dock(LEFT) zkind:SetWide(S(260))
    local zid = vgui.Create("SVEntry", zrow) zid:Dock(LEFT) zid:SetWide(S(140)) zid:SetHint("id") zid:DockMargin(S(4), 0, 0, 0)
    local zname = vgui.Create("SVEntry", zrow) zname:Dock(FILL) zname:SetHint("Название") zname:DockMargin(S(4), 0, 0, 0)
    local zprops = vgui.Create("SVEntry", zc) zprops:Dock(TOP) zprops:SetHint("Параметры: priority=1; demand=20; scp=scp173")
    local zadd = UI.button(zc, "Создать зону из отмеченных углов", function()
        local _, kind = zkind:GetSelected()
        Net.call("mapcfg.addZone", kind or "sector", zid:GetValue(), zname:GetValue(), parseProps(zprops:GetValue()))
    end, "primary")
    zadd:Dock(TOP) zadd:DockMargin(0, S(4), 0, S(6))
    if not (c1 and c2) then zadd:SetBlocked("отметьте два угла") end
    for _, z in ipairs(cfg.zones) do
        local row = UI.row(zc, S(30))
        local lbl = vgui.Create("DLabel", row) lbl:Dock(FILL) lbl:SetFont("SV.Small") lbl:SetTextColor(C.text)
        lbl:SetText(string.format("%s · %s · %s · объёмов %d · %s", z.id, z.kind, z.name or "", #z.boxes, propsText(z.props)))
        local del = UI.button(row, "Удалить", function() Net.call("mapcfg.removeZone", z.id) end, "danger") del:Dock(RIGHT) del:SetWide(S(100))
        local add = UI.button(row, "+ объём", function() Net.call("mapcfg.addBox", z.id) end) add:Dock(RIGHT) add:SetWide(S(100)) add:DockMargin(0, 0, S(4), 0)
        if not (c1 and c2) then add:SetBlocked("отметьте два угла") end
    end

    -- Points
    local pc = UI.card(scroll, "Точки (" .. #cfg.points .. ")")
    local prow = UI.row(pc, S(32))
    local pkind = combo(prow, kindChoices(MapCfg.pointKinds), "spawn")
    pkind:Dock(LEFT) pkind:SetWide(S(300))
    local pprops = vgui.Create("SVEntry", prow) pprops:Dock(FILL) pprops:SetHint("group=security; terminal=research; subsystem=power; locker=armory; scp=scp173; name=...") pprops:DockMargin(S(4), 0, 0, 0)
    local pbtns = UI.row(pc, S(32))
    local here = UI.button(pbtns, "Добавить на моём месте", function()
        local _, kind = pkind:GetSelected()
        Net.call("mapcfg.addPoint", kind or "spawn", parseProps(pprops:GetValue()), false)
    end, "primary")
    here:Dock(LEFT) here:SetWide(S(260))
    local eye = UI.button(pbtns, "Добавить по взгляду", function()
        local _, kind = pkind:GetSelected()
        Net.call("mapcfg.addPoint", kind or "spawn", parseProps(pprops:GetValue()), true)
    end)
    eye:Dock(LEFT) eye:SetWide(S(260)) eye:DockMargin(S(4), 0, 0, 0)
    for _, p in ipairs(cfg.points) do
        local row = UI.row(pc, S(30))
        local lbl = vgui.Create("DLabel", row) lbl:Dock(FILL) lbl:SetFont("SV.Small") lbl:SetTextColor(p.props.auto and C.dim or C.text)
        lbl:SetText(string.format("%s · %s · %s", p.id, p.kind, propsText(p.props)))
        local del = UI.button(row, "Удалить", function() Net.call("mapcfg.removePoint", p.id) end, "danger") del:Dock(RIGHT) del:SetWide(S(100))
    end

    -- Doors
    local dc = UI.card(scroll, "Двери и кнопки")
    UI.text(dc, "Посмотрите на дверь или кнопку и нажмите «Настроить дверь по взгляду».", "SV.Small", C.dim)
    local drow = UI.row(dc, S(32))
    local dname = vgui.Create("SVEntry", drow) dname:Dock(LEFT) dname:SetWide(S(220)) dname:SetHint("Название")
    local dclear = combo(drow, {{0, "Допуск 0"}, {1, "Допуск 1"}, {2, "Допуск 2"}, {3, "Допуск 3"}, {4, "Допуск 4"}, {5, "Допуск 5"}}, 1)
    dclear:Dock(LEFT) dclear:SetWide(S(120)) dclear:DockMargin(S(4), 0, 0, 0)
    local dpolicy = combo(drow, {{"card", "По карте"}, {"open", "Свободно"}, {"locked", "Закрыто"}}, "card")
    dpolicy:Dock(LEFT) dpolicy:SetWide(S(130)) dpolicy:DockMargin(S(4), 0, 0, 0)
    local dfail = combo(drow, {{"secure", "Без питания: заперта"}, {"safe", "Без питания: открыта"}}, "secure")
    dfail:Dock(FILL) dfail:DockMargin(S(4), 0, 0, 0)
    local dtags = vgui.Create("SVEntry", dc) dtags:Dock(TOP) dtags:SetHint("Зоны доступа через запятую: security,armory (пусто — только допуск)")
    local dsector = vgui.Create("SVEntry", dc) dsector:Dock(TOP) dsector:SetHint("Сектор (id, необязательно)") dsector:DockMargin(0, S(4), 0, 0)
    local dbtns = UI.row(dc, S(32))
    local set = UI.button(dbtns, "Настроить дверь по взгляду", function()
        local ent = LocalPlayer():GetEyeTrace().Entity
        local _, clr = dclear:GetSelected()
        local _, pol = dpolicy:GetSelected()
        local _, fail = dfail:GetSelected()
        local tags = {}
        for t in string.gmatch(dtags:GetValue(), "[^,%s]+") do tags[#tags + 1] = t end
        Net.call("mapcfg.setDoor", ent, {name = dname:GetValue(), clearance = clr or 0, policy = pol or "card", failMode = fail or "secure",
            tags = tags, sector = dsector:GetValue() ~= "" and dsector:GetValue() or nil})
    end, "primary")
    set:Dock(LEFT) set:SetWide(S(300))
    local unset = UI.button(dbtns, "Снять требования с двери по взгляду", function()
        Net.call("mapcfg.removeDoor", LocalPlayer():GetEyeTrace().Entity)
    end, "danger")
    unset:Dock(LEFT) unset:SetWide(S(340)) unset:DockMargin(S(4), 0, 0, 0)
    local configured = 0
    for _, d in ipairs(data.doors) do
        if d.cfg then
            configured = configured + 1
            UI.text(dc, string.format("#%s %s · %s · допуск %s · %s%s", d.id, d.class, d.cfg.name or "", d.cfg.clearance or 0, d.cfg.policy or "card",
                d.cfg.tags and #d.cfg.tags > 0 and (" · " .. table.concat(d.cfg.tags, ",")) or ""), "SV.Tiny")
        end
    end
    UI.text(dc, "Дверей и кнопок на карте: " .. #data.doors .. ", настроено: " .. configured, "SV.Small", C.dim)
end

function UI.openMapEditor()
    if IsValid(UI.mapEditor) then UI.mapEditor:Remove() end
    local f = vgui.Create("SVFrame")
    UI.mapEditor = f
    f:SetHeader("РЕДАКТОР КАРТЫ", game.GetMap())
    f:SetSize(math.min(ScrW() - S(40), S(1180)), math.min(ScrH() - S(40), S(780)))
    f:Center()
    f:MakePopup()
    f.content = vgui.Create("DPanel", f)
    f.content:Dock(FILL)
    f.content.Paint = function() end
    if UI.mapData then buildEditor(f, UI.mapData) else UI.text(f.content, "Загрузка…", "SV.Body", C.dim) end
    Net.call("mapcfg.get")
end

Net.on("mapcfg.data", function(data)
    UI.mapData = data
    if IsValid(UI.mapEditor) then buildEditor(UI.mapEditor, data) end
end)

--[[---------------------------------------------------------------------------
World overlay while holding the map tool
---------------------------------------------------------------------------]]
local zoneColors = {sector = Color(79, 163, 217), evac = Color(76, 175, 122), detention = Color(230, 120, 40), cell = Color(217, 83, 79),
    pocket = Color(140, 60, 160), lure = Color(160, 60, 120), testchamber = Color(224, 176, 64), safe = Color(120, 200, 120)}

hook.Add("PostDrawTranslucentRenderables", "SiteVeil.MapEditor", function(depth, skybox)
    if depth or skybox then return end
    local wep = LocalPlayer():GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "sv_mapper" or not UI.mapData then return end
    local cfg = UI.mapData.cfg
    for _, z in ipairs(cfg.zones) do
        local col = zoneColors[z.kind] or color_white
        for _, b in ipairs(z.boxes) do
            if math.abs(b.max[1] - b.min[1]) < 60000 then
                local mn, mx = MapCfg.toVec(b.min), MapCfg.toVec(b.max)
                render.DrawWireframeBox(Vector(0, 0, 0), Angle(0, 0, 0), mn, mx, col, true)
            end
        end
    end
    for _, p in ipairs(cfg.points) do
        local pos = MapCfg.toVec(p.pos)
        render.DrawWireframeSphere(pos, 10, 6, 6, p.props.auto and Color(150, 150, 150) or Color(255, 220, 80), true)
    end
    local c = UI.mapData.corners
    if c and c[1] then render.DrawWireframeSphere(MapCfg.toVec(c[1]), 6, 6, 6, Color(255, 80, 80), true) end
    if c and c[2] then render.DrawWireframeSphere(MapCfg.toVec(c[2]), 6, 6, 6, Color(80, 255, 80), true) end
end)

hook.Add("HUDPaint", "SiteVeil.MapEditor.Labels", function()
    local wep = LocalPlayer():GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "sv_mapper" or not UI.mapData then return end
    local eye = LocalPlayer():EyePos()
    for _, p in ipairs(UI.mapData.cfg.points) do
        local pos = MapCfg.toVec(p.pos)
        if pos:DistToSqr(eye) < 1500 * 1500 then
            local sp = (pos + Vector(0, 0, 16)):ToScreen()
            if sp.visible then draw.SimpleText(p.kind .. " · " .. p.id, "SV.Tiny", sp.x, sp.y, color_white, TEXT_ALIGN_CENTER) end
        end
    end
end)

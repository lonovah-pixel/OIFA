--[[---------------------------------------------------------------------------
Evidence (client): scan markers, analysis reports, security terminal and
the "Расследования" tab with case files.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Evidence = SV.Evidence

Evidence.scanned = Evidence.scanned or {}   -- last scan results
Evidence.scannedAt = Evidence.scannedAt or 0
Evidence.cases = Evidence.cases or nil

local SCAN_SHOW = 40

Net.on("evidence.scan", function(data)
    Evidence.scanned = data.list
    Evidence.scannedAt = CurTime()
end)

--- Nearest scanned trace in front of the player (used by the kit's RMB).
function Evidence.traceInSight()
    local ply = LocalPlayer()
    local best, bestDot
    for _, t in ipairs(Evidence.scanned) do
        local pos = Vector(t.pos[1], t.pos[2], t.pos[3])
        local dir = pos - ply:EyePos()
        local dist = dir:Length()
        dir:Normalize()
        local dot = ply:GetAimVector():Dot(dir)
        if dist < 200 and dot > 0.8 and (not bestDot or dot > bestDot) then best, bestDot = t, dot end
    end
    return best
end

UI.hudElement("evidence", 32, function()
    if CurTime() - Evidence.scannedAt > SCAN_SHOW then return end
    for _, t in ipairs(Evidence.scanned) do
        local scr = Vector(t.pos[1], t.pos[2], t.pos[3] + 6):ToScreen()
        if scr.visible then
            draw.SimpleText("● " .. t.name .. (t.count > 1 and (" ×" .. t.count) or ""), "SV.Tiny", scr.x, scr.y, C.warn, TEXT_ALIGN_CENTER)
            draw.SimpleText(t.age, "SV.Tiny", scr.x, scr.y + S(14), C.dim, TEXT_ALIGN_CENTER)
        end
    end
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep:GetClass() == "sv_evidence_kit" then
        local t = Evidence.traceInSight()
        draw.SimpleText(t and ("ПКМ — собрать: " .. t.name) or "ЛКМ — осмотр места", "SV.HUDSmall", ScrW() / 2, ScrH() * 0.62, t and C.accent or C.dim, TEXT_ALIGN_CENTER)
    end
end)

Net.on("evidence.report", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ЗАКЛЮЧЕНИЕ ПО УЛИКЕ №" .. data.id, data.name)
    f:SetSize(S(560), S(300))
    f:Center()
    f:MakePopup()
    UI.text(f, "Уровень анализа: " .. data.level .. " из 2", "SV.Small", C.dim)
    UI.text(f, data.text, "SV.Body")
    UI.text(f, "Выводы экспертизы ограничены точностью методов. Сопоставьте их с показаниями и журналами доступа.", "SV.Tiny", C.faint)
end)

--[[---------------------------------------------------------------------------
Security terminal
---------------------------------------------------------------------------]]
Net.on("evidence.terminal", function(msg)
    if IsValid(UI.securityTerminal) then UI.securityTerminal:Remove() end
    local ent = Entity(msg.ent)
    local f = vgui.Create("SVFrame")
    UI.securityTerminal = f
    f:SetHeader("ТЕРМИНАЛ СЛУЖБЫ БЕЗОПАСНОСТИ")
    f:SetSize(S(640), math.min(S(720), ScrH() * 0.9))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    local lab = UI.card(scroll, "Экспертиза улик")
    if #msg.bags == 0 then UI.text(lab, "У вас нет пакетов с уликами.", "SV.Small", C.dim) end
    for _, b in ipairs(msg.bags) do
        UI.text(lab, b.title .. " · анализ: " .. b.level .. "/2", "SV.Body")
        if b.report then UI.text(lab, b.report, "SV.Small", C.dim) end
        local btn = UI.button(lab, b.next and ("Провести: " .. b.next) or "Исследована полностью", function()
            Net.call("evidence.analyze", b.uid, ent)
            f:Close()
        end, "primary")
        btn:Dock(TOP)
        btn:DockMargin(0, 0, 0, S(8))
        if not msg.investigator then btn:SetBlocked("анализ проводят следователи")
        elseif not b.next then btn:SetBlocked("больше нечего исследовать")
        elseif b.level >= 1 and not msg.hasSensor then btn:SetBlocked("нужен набор датчиков") end
    end
    local det = UI.card(scroll, "Задержанные")
    if #msg.detentions == 0 then UI.text(det, "Задержанных нет.", "SV.Small", C.dim) end
    for _, d in ipairs(msg.detentions) do
        UI.text(det, string.format("%s · осталось %d:%02d · %s", d.name, math.floor(d.left / 60), d.left % 60, d.reason or ""), "SV.Small")
    end
    local conf = UI.card(scroll, "Журнал изъятий")
    if #msg.confiscations == 0 then UI.text(conf, "Записей нет.", "SV.Small", C.dim) end
    for _, c in ipairs(msg.confiscations) do
        UI.text(conf, string.format("%s · %s у %s, изъял %s: %s", c.when, c.item, c.from_name or "?", c.by_name or "?", c.reason or ""), "SV.Tiny", C.dim)
    end
    local cases = UI.button(scroll, "Открыть дела (вкладка «Расследования»)", function()
        f:Close()
        UI.openMenu("cases")
    end)
    cases:Dock(TOP)
    if not msg.investigator then cases:SetBlocked("доступно следователям") end
end)

--[[---------------------------------------------------------------------------
Cases tab
---------------------------------------------------------------------------]]
local function openCase(v)
    if IsValid(UI.caseFrame) then UI.caseFrame:Remove() end
    local f = vgui.Create("SVFrame")
    UI.caseFrame = f
    f:SetHeader("ДЕЛО №" .. v.id, v.status == "open" and "открыто" or "закрыто")
    f:SetSize(S(640), math.min(S(760), ScrH() * 0.9))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    UI.text(scroll, v.title, "SV.Header")
    UI.text(scroll, "Ведёт: " .. (v.lead or "—") .. " · заведено " .. v.created, "SV.Small", C.dim)
    if v.verdict then UI.text(scroll, "Заключение: " .. v.verdict, "SV.Body", C.ok) end
    local ev = UI.card(scroll, "Улики")
    if #v.evidence == 0 then UI.text(ev, "Улик нет.", "SV.Small", C.dim) end
    for _, e in ipairs(v.evidence) do
        UI.text(ev, "№" .. e.id .. " · " .. e.name .. " · сектор " .. (e.sector or "—") .. " · собрал " .. (e.collector or "?") .. " · анализ " .. e.level .. "/2", "SV.Small")
        UI.text(ev, e.report or "Не исследована.", "SV.Tiny", C.dim)
    end
    local notes = UI.card(scroll, "Материалы дела")
    for _, n in ipairs(v.notes) do
        UI.text(notes, n.when .. " · " .. n.author .. ": " .. n.text, "SV.Small")
    end
    if v.status == "open" then
        local entry = vgui.Create("SVEntry", notes)
        entry:Dock(TOP)
        entry:SetHint("Показания, выводы, ссылки на журналы доступа")
        local add = UI.button(notes, "Добавить запись", function() Net.call("case.note", v.id, entry:GetValue()) end)
        add:Dock(TOP)
        add:DockMargin(0, S(4), 0, 0)
        local close = UI.button(scroll, "Закрыть дело с заключением", function()
            UI.confirm("ЗАКРЫТИЕ ДЕЛА", "Опишите заключение по делу (не менее 10 символов). Закрытое дело нельзя дополнить.",
                function(text) Net.call("case.close", v.id, text or "") end, "заключение")
        end, "danger")
        close:Dock(TOP)
        close:DockMargin(0, S(8), 0, 0)
    end
end

Net.on("case.view", openCase)

Net.on("case.list", function(data)
    Evidence.cases = data
    UI.refreshTab("cases")
end)

UI.registerTab{
    id = "cases", name = "Расследования", order = 40,
    visible = function(ply) return SV.Roles.hasFlag(ply, "investigator") or SV.Admin.isOnDuty(ply) end,
    build = function(panel)
        local data = Evidence.cases
        if not data then
            UI.text(panel, "Загрузка…", "SV.Body", C.dim)
            Net.call("case.list")
            return
        end
        Evidence.cases = nil
        local scroll = UI.scroll(panel)
        local new = UI.card(scroll, "Новое дело")
        local title = vgui.Create("SVEntry", new)
        title:Dock(TOP)
        title:SetHint("Название: что, где, когда")
        local create = UI.button(new, "Завести дело", function() Net.call("case.create", title:GetValue()) end, "primary")
        create:Dock(TOP)
        create:DockMargin(0, S(4), 0, 0)
        local list = UI.card(scroll, "Дела")
        if #data.list == 0 then UI.text(list, "Дел нет.", "SV.Small", C.dim) end
        for _, c in ipairs(data.list) do
            local row = UI.row(list, S(32))
            local lbl = vgui.Create("DLabel", row)
            lbl:Dock(FILL)
            lbl:SetFont("SV.Small")
            lbl:SetTextColor(c.status == "open" and C.text or C.faint)
            lbl:SetText("№" .. c.id .. " · " .. c.title .. " · " .. (c.lead or "—") .. " · " .. c.created)
            local open = UI.button(row, "Открыть", function() Net.call("case.view", c.id) end)
            open:Dock(RIGHT)
            open:SetWide(S(100))
            if c.status == "open" and #data.bags > 0 then
                local attach = UI.button(row, "Приобщить улику", function()
                    local options = {}
                    for _, b in ipairs(data.bags) do options[#options + 1] = {b.title, b.uid} end
                    UI.choose("ПРИОБЩИТЬ УЛИКУ", "Пакет перейдёт в архив дела.", options, function(uid) Net.call("case.attach", c.id, uid) end)
                end, "ghost")
                attach:Dock(RIGHT)
                attach:SetWide(S(170))
                attach:DockMargin(0, 0, S(4), 0)
            end
        end
        UI.text(scroll, "Улики собирают набором криминалиста (ЛКМ — осмотр, ПКМ — сбор) и исследуют на терминале службы безопасности.", "SV.Tiny", C.faint)
    end,
}

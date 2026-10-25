--[[---------------------------------------------------------------------------
Research (client): research terminal (protocol list, pending approvals,
history), experiment window (participants, requirements, steps, abort),
invitations and results.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Research = SV.Research

Research.current = Research.current or nil

local dangerColors = {C.ok, C.info, C.warn, C.danger, C.critical}
local statusNames = {
    draft = "подготовка", pending = "ожидает согласования", approved = "согласован", running = "идёт",
    completed = "завершён", emergency = "аварийное прекращение", aborted = "прекращён", cancelled = "отменён", interrupted = "прерван",
}
local kindColors = {data = C.ok, partial = C.info, discovery = C.accent, none = C.dim, incident = C.danger}

local function okLine(parent, ok, text)
    UI.text(parent, (ok and "✔ " or "✖ ") .. text, "SV.Small", ok and C.ok or C.danger)
end

--[[---------------------------------------------------------------------------
Experiment window
---------------------------------------------------------------------------]]
local function inviteNearby(v)
    local options = {}
    for _, p in ipairs(UI.nearbyPlayers(400)) do
        local blocked
        if SV.Roles.isSCP(p) then blocked = "объект SCP" end
        for _, m in ipairs(v.members) do
            if m.ent == p:EntIndex() then blocked = "уже участвует" end
        end
        options[#options + 1] = {SV.Chars.displayName(p), p, blocked}
    end
    if #options == 0 then
        UI.notify("Рядом нет сотрудников (до 400 единиц).", 1)
        return
    end
    UI.choose("ПРИГЛАСИТЬ", "Сотрудник получит приглашение на 60 секунд.", options, function(p)
        if IsValid(p) then Net.call("research.invite", p) end
    end)
end

local function buildExperiment(f, v)
    -- The frame's own children (close button) stay; only the body is rebuilt.
    if IsValid(f.body) then f.body:Remove() end
    f.body = vgui.Create("DPanel", f)
    f.body:Dock(FILL)
    f.body:SetPaintBackground(false)
    local me = LocalPlayer()
    local lead = false
    for _, m in ipairs(v.members) do
        if m.lead and m.ent == me:EntIndex() then lead = true end
    end
    local scroll = UI.scroll(f.body)
    UI.text(scroll, v.name, "SV.Header")
    UI.text(scroll, "Опасность " .. v.danger .. "/5 · " .. (statusNames[v.status] or v.status) .. " · руководитель: " .. v.lead .. " · риск: " .. v.risk,
        "SV.Small", dangerColors[v.danger] or C.dim)
    UI.text(scroll, v.desc, "SV.Body", C.dim)

    local approval = UI.card(scroll, "Согласование")
    if not v.needsApproval then
        UI.text(approval, "Не требуется (опасность ниже 3).", "SV.Small", C.dim)
    elseif v.approved then
        UI.text(approval, "Согласовано: " .. (v.approvedBy or "—"), "SV.Small", C.ok)
    elseif v.status == "pending" then
        UI.text(approval, "Запрос отправлен, ожидается решение.", "SV.Small", C.warn)
    else
        UI.text(approval, "Требуется согласование (руководитель научного отдела, директор или дежурный администратор).", "SV.Small", C.warn)
        if lead then
            local b = UI.button(approval, "Запросить согласование", function() Net.call("research.requestApproval") end, "primary")
            b:Dock(TOP)
            if not v.approverOnline then b:SetBlocked("на смене нет согласующих") end
        end
    end

    local req = UI.card(scroll, "Готовность")
    okLine(req, v.people.ok, v.people.ok and "Участники в зоне эксперимента" or ("Участники: " .. tostring(v.people.text)))
    okLine(req, v.equipment.ok, v.equipment.ok and "Обязательное оборудование на месте" or ("Нет оборудования: " .. table.concat(v.equipment.missing, ", ")))
    okLine(req, v.subject.ok, v.subject.ok and "Объект исследования доступен" or ("Объект: " .. tostring(v.subject.text)))
    for _, e in ipairs(v.environment) do okLine(req, e.ok, e.text) end
    if #v.equipment.optional > 0 then
        UI.text(req, "Дополнительное оборудование (повышает качество данных):", "SV.Small", C.dim)
        for _, o in ipairs(v.equipment.optional) do okLine(req, o.have, o.name) end
    end
    if #v.safety > 0 then
        UI.text(req, "Меры безопасности (снижают риск):", "SV.Small", C.dim)
        for _, s in ipairs(v.safety) do okLine(req, s.ok, s.name) end
    end

    local people = UI.card(scroll, "Участники")
    for _, m in ipairs(v.members) do
        UI.text(people, (m.lead and "★ " or "• ") .. m.name .. (m.inZone and "" or " — вне зоны"), "SV.Small", m.inZone and C.text or C.warn)
    end

    local steps = UI.card(scroll, "Шаги протокола")
    for i, s in ipairs(v.steps) do
        local who = s.by == "lead" and "руководитель" or (s.by == "classd" and "испытуемый" or "любой участник")
        local col = s.done and C.ok or (s.current and C.accent or C.dim)
        UI.text(steps, string.format("%d. %s (%s, %d с)%s", i, s.name, who, s.time, s.critical and " — КРИТИЧЕСКИЙ" or ""), "SV.Small", col)
    end

    local row = UI.row(scroll, S(36))
    if v.status == "running" then
        local cur = v.steps[v.step]
        local stepBtn = UI.button(row, "Выполнить шаг", function() Net.call("research.step", v.id) end, "primary")
        stepBtn:Dock(LEFT)
        stepBtn:SetWide(S(180))
        if cur and cur.by == "lead" and not lead then stepBtn:SetBlocked("шаг выполняет руководитель") end
        local abort = UI.button(row, "Прекратить", function()
            UI.confirm("ПРЕКРАЩЕНИЕ ЭКСПЕРИМЕНТА", "Прекращение во время критического шага считается аварийным и может привести к инциденту. Укажите причину.",
                function(reason) Net.call("research.abort", v.id, reason or "") end, "причина")
        end, "danger")
        abort:Dock(RIGHT)
        abort:SetWide(S(160))
    elseif lead then
        local start = UI.button(row, "Начать", function() Net.call("research.start") end, "primary")
        start:Dock(LEFT)
        start:SetWide(S(140))
        if v.needsApproval and not v.approved then start:SetBlocked("требуется согласование")
        elseif not v.people.ok then start:SetBlocked("не хватает участников")
        elseif not v.equipment.ok then start:SetBlocked("нет оборудования")
        elseif not v.subject.ok then start:SetBlocked("объект недоступен")
        elseif v.environmentBlocked then start:SetBlocked(v.environmentBlocked) end
        local invite = UI.button(row, "Пригласить", function() inviteNearby(v) end)
        invite:Dock(LEFT)
        invite:SetWide(S(140))
        invite:DockMargin(S(6), 0, 0, 0)
        local cancel = UI.button(row, "Отменить", function() Net.call("research.cancel") end, "ghost")
        cancel:Dock(RIGHT)
        cancel:SetWide(S(120))
    else
        local leave = UI.button(row, "Выйти из эксперимента", function() Net.call("research.leave") end, "ghost")
        leave:Dock(RIGHT)
        leave:SetWide(S(220))
    end
    local refresh = UI.button(scroll, "Обновить", function() Net.call("research.state") end, "ghost")
    refresh:Dock(TOP)
    refresh:DockMargin(0, S(6), 0, 0)
end

local function openExperiment(v)
    Research.current = v
    local f = UI.researchFrame
    if not IsValid(f) then
        f = vgui.Create("SVFrame")
        UI.researchFrame = f
        f:SetSize(S(640), math.min(S(760), ScrH() * 0.9))
        f:Center()
        f:MakePopup()
    end
    f:SetHeader("ЭКСПЕРИМЕНТ №" .. v.id, statusNames[v.status] or v.status)
    buildExperiment(f, v)
end

Net.on("research.state", function(v)
    -- An open window is refreshed; a closed one is reopened only by the player.
    Research.current = v
    if IsValid(UI.researchFrame) or v.status == "draft" and not Research.seen then
        Research.seen = true
        openExperiment(v)
    end
end)

Net.on("research.closed", function(data)
    if Research.current and Research.current.id == data.id then Research.current = nil end
    Research.seen = nil
    if IsValid(UI.researchFrame) then UI.researchFrame:Close() end
end)

Net.on("research.result", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("РЕЗУЛЬТАТ ЭКСПЕРИМЕНТА №" .. data.id)
    f:SetSize(S(520), S(240))
    f:Center()
    f:MakePopup()
    UI.text(f, data.name, "SV.Header", kindColors[data.kind] or C.text)
    UI.text(f, data.text or "", "SV.Body")
    UI.text(f, "Запись сохранена в журнале экспериментов.", "SV.Small", C.dim)
end)

Net.on("research.invite", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ПРИГЛАШЕНИЕ В ЭКСПЕРИМЕНТ")
    f:SetSize(S(480), S(220))
    f:Center()
    f:MakePopup()
    UI.text(f, data.lead .. " приглашает вас участвовать: " .. data.name .. ".")
    UI.text(f, "Опасность " .. data.danger .. "/5. Участие добровольно; отказ не наказывается системой.", "SV.Small", dangerColors[data.danger] or C.dim)
    local row = UI.row(f, S(36))
    row:Dock(BOTTOM)
    local yes = UI.button(row, "Участвовать", function() Net.call("research.join", data.id, true) f:Close() end, "primary")
    yes:Dock(RIGHT)
    yes:SetWide(S(160))
    local no = UI.button(row, "Отказаться", function() Net.call("research.join", data.id, false) f:Close() end)
    no:Dock(RIGHT)
    no:SetWide(S(140))
    no:DockMargin(0, 0, S(8), 0)
end)

--[[---------------------------------------------------------------------------
Terminal
---------------------------------------------------------------------------]]
local function buildProtocols(parent, msg)
    local ent = Entity(msg.ent)
    local scroll = UI.scroll(parent)
    if msg.current then
        local b = UI.button(scroll, "Открыть текущий эксперимент №" .. msg.current, function() Net.call("research.state") end, "primary")
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, S(8))
    end
    if #msg.pending > 0 then
        local card = UI.card(scroll, "Запросы на согласование", C.warn)
        for _, p in ipairs(msg.pending) do
            UI.text(card, string.format("№%d · %s · руководитель %s · опасность %d/5", p.id, p.name, p.lead, p.danger), "SV.Body")
            local row = UI.row(card, S(32))
            local note = vgui.Create("SVEntry", row)
            note:Dock(FILL)
            note:SetHint("Комментарий (обязателен при отказе)")
            local no = UI.button(row, "Отказать", function()
                if note:GetValue() == "" then UI.notify("Укажите причину отказа.", 1) return end
                Net.call("research.approve", p.id, false, note:GetValue())
                Net.call("research.protocols", ent)
            end, "danger")
            no:Dock(RIGHT) no:SetWide(S(110)) no:DockMargin(S(6), 0, 0, 0)
            local yes = UI.button(row, "Согласовать", function()
                Net.call("research.approve", p.id, true, note:GetValue())
                Net.call("research.protocols", ent)
            end, "primary")
            yes:Dock(RIGHT) yes:SetWide(S(130)) yes:DockMargin(S(6), 0, 0, 0)
        end
    end
    for _, p in ipairs(msg.list) do
        local card = UI.card(scroll, p.name, dangerColors[p.danger] or C.accent)
        UI.text(card, "Опасность " .. p.danger .. "/5 · допуск " .. p.clearance .. (p.approval and " · требуется согласование" or ""), "SV.Small", dangerColors[p.danger] or C.dim)
        UI.text(card, p.desc, "SV.Body", C.dim)
        UI.text(card, "Участники: " .. table.concat(p.participants, ", "), "SV.Small")
        if #p.equipment > 0 then UI.text(card, "Оборудование: " .. table.concat(p.equipment, ", "), "SV.Small") end
        local b = UI.button(card, "Создать эксперимент", function()
            Net.call("research.create", ent, p.id)
            if IsValid(UI.researchTerminal) then UI.researchTerminal:Close() end
        end, "primary")
        b:Dock(TOP)
        if not p.ok then b:SetBlocked(p.reason) end
    end
end

local function buildHistory(parent, list)
    local scroll = UI.scroll(parent)
    if #list == 0 then UI.text(scroll, "Записей нет.", "SV.Body", C.dim) end
    for _, r in ipairs(list) do
        local card = UI.card(scroll, "№" .. r.id .. " · " .. r.name)
        UI.text(card, (statusNames[r.status] or r.status) .. " · " .. (r.lead or "—") .. " · " .. (r.when or "") ..
            (r.approvedBy and r.approvedBy ~= "" and (" · согласовал " .. r.approvedBy) or ""), "SV.Small", C.dim)
        if r.outcome then UI.text(card, r.outcome, "SV.Body") end
        if r.notes and r.notes ~= "" then UI.text(card, r.notes, "SV.Small", C.dim) end
    end
end

Net.on("research.protocols", function(msg)
    if IsValid(UI.researchTerminal) then UI.researchTerminal:Remove() end
    local f = vgui.Create("SVFrame")
    UI.researchTerminal = f
    f:SetHeader("ИССЛЕДОВАТЕЛЬСКИЙ ТЕРМИНАЛ", "Протоколы испытаний")
    f:SetSize(S(680), math.min(S(760), ScrH() * 0.9))
    f:Center()
    f:MakePopup()
    local tabs = vgui.Create("SVTabs", f)
    tabs:Dock(FILL)
    tabs:AddTab("protocols", "Протоколы", function(panel) buildProtocols(panel, msg) end)
    tabs:AddTab("history", "Журнал", function(panel)
        if Research.historyList then
            buildHistory(panel, Research.historyList)
        else
            UI.text(panel, "Загрузка…", "SV.Body", C.dim)
            Net.call("research.history", Entity(msg.ent))
        end
    end)
    tabs:Select("protocols")
    f.tabs = tabs
    Research.historyList = nil
end)

Net.on("research.history", function(data)
    Research.historyList = data.list
    local f = UI.researchTerminal
    if IsValid(f) and f.tabs then f.tabs:Select("history") end
end)

-- Experiment state is also reachable from the HUD when a window was closed.
UI.hudElement("experiment", 30, function()
    local v = Research.current
    if not v or v.status ~= "running" then return end
    local cur = v.steps[v.step]
    local text = "Эксперимент №" .. v.id .. ": шаг " .. v.step .. "/" .. #v.steps .. (cur and (" — " .. cur.name) or "")
    draw.SimpleText(text, "SV.HUDSmall", ScrW() - S(20), S(140), cur and cur.critical and C.warn or C.text, TEXT_ALIGN_RIGHT)
    draw.SimpleText("Окно эксперимента: консоль sv_experiment", "SV.Tiny", ScrW() - S(20), S(160), C.faint, TEXT_ALIGN_RIGHT)
end)

concommand.Add("sv_experiment", function()
    if Research.current then openExperiment(Research.current) else UI.notify("Вы не участвуете в эксперименте.", 1) end
end)

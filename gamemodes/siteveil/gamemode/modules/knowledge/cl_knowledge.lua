--[[---------------------------------------------------------------------------
Knowledge (client): dossier list and viewer (personal and terminal mode),
report submission, review, printing, document reader.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local K = SV.Knowledge

UI.dossierList = UI.dossierList or nil

local statusColors = {confirmed = C.ok, refuted = C.danger, hypothesis = C.info, proposed = C.warn}

local function viewDossier(parent, v)
    local scroll = UI.scroll(parent)
    UI.text(scroll, v.title, "SV.Header")
    UI.text(scroll, "Класс: " .. (v.class or "—") .. (v.mode == "terminal" and ("   ·   просмотр с терминала, допуск карты " .. v.clearance) or "   ·   личный доступ: только открытые сведения и известное вам"), "SV.Small", C.dim)

    for _, s in ipairs(v.sections) do
        local card = UI.card(scroll, s.title .. "  [" .. (K.kindNames[s.kind] or s.kind) .. ", допуск " .. s.clearance .. "]", s.locked and C.faint or C.accent)
        if s.locked then
            UI.text(card, "ЗАСЕКРЕЧЕНО — требуется допуск " .. s.clearance .. (v.mode ~= "terminal" and " (только с терминала)" or ""), "SV.Body", C.faint)
        else
            UI.text(card, s.text, "SV.Body")
            if v.terminal then
                local b = UI.button(card, "Распечатать раздел", function() Net.call("know.print", v.id, s.id, Entity(v.terminal)) end, "ghost")
                b:Dock(TOP)
            end
        end
    end

    if #v.known > 0 then
        local known = UI.card(scroll, "Известно вашему персонажу", C.info)
        for _, k in ipairs(v.known) do
            UI.text(known, k.title .. ": " .. k.text, "SV.Small")
        end
    end

    local entries = UI.card(scroll, "Наблюдения, гипотезы и отчёты")
    if #v.entries == 0 then UI.text(entries, "Записей нет.", "SV.Small", C.dim) end
    for _, e in ipairs(v.entries) do
        if e.locked then
            UI.text(entries, "№" .. e.id .. " — подтверждённое наблюдение, требуется допуск " .. e.clearance, "SV.Small", C.faint)
        else
            UI.text(entries, string.format("№%d · %s · %s · автор %s, %s%s", e.id, K.kindNames[e.status] or e.status, e.title or "", e.author or "?", e.created,
                e.reviewed and (" · рецензия: " .. e.reviewed) or ""), "SV.Small", statusColors[e.status] or C.text)
            UI.text(entries, e.text, "SV.Body")
            if e.note and e.note ~= "" then UI.text(entries, "Комментарий: " .. e.note, "SV.Tiny", C.dim) end
            if v.canReview and not e.own and v.terminal then
                local row = UI.row(entries, S(30))
                for _, d in ipairs({{"confirm", "Подтвердить"}, {"refute", "Опровергнуть"}, {"hypothesis", "В гипотезы"}}) do
                    local b = UI.button(row, d[2], function() Net.call("know.review", e.id, d[1], "", Entity(v.terminal)) end)
                    b:Dock(LEFT)
                    b:SetWide(S(150))
                    b:DockMargin(0, 0, S(4), 0)
                    if e.status == ({confirm = "confirmed", refute = "refuted", hypothesis = "hypothesis"})[d[1]] then b:SetBlocked("уже установлено") end
                end
            end
        end
    end

    local sub = UI.card(scroll, "Новый отчёт")
    if not v.canSubmit then
        UI.text(sub, "Отчёты в досье вносят научные сотрудники и следователи.", "SV.Small", C.dim)
        return
    end
    local kind = vgui.Create("DComboBox", sub)
    kind:Dock(TOP)
    kind:SetTall(S(30))
    kind:AddChoice("Наблюдение", "observation", true)
    kind:AddChoice("Гипотеза", "hypothesis")
    local lvl = vgui.Create("DComboBox", sub)
    lvl:Dock(TOP)
    lvl:SetTall(S(30))
    lvl:DockMargin(0, S(4), 0, 0)
    for i = 0, 5 do lvl:AddChoice("Гриф: допуск " .. i, i, i == 1) end
    local text = vgui.Create("DTextEntry", sub)
    text:Dock(TOP)
    text:SetTall(S(110))
    text:SetMultiline(true)
    text:SetFont("SV.Body")
    text:DockMargin(0, S(4), 0, S(4))
    local send = UI.button(sub, "Внести отчёт", function()
        local _, k = kind:GetSelected()
        local _, l = lvl:GetSelected()
        Net.call("know.submit", v.id, k or "observation", l or 1, text:GetValue(), v.terminal and Entity(v.terminal) or NULL)
    end, "primary")
    send:Dock(TOP)
    if not v.terminal then UI.text(sub, "Без терминала отчёт можно внести, имея рабочий журнал.", "SV.Tiny", C.faint) end
end

local function openViewer(v)
    if IsValid(UI.dossierPanel) then UI.dossierPanel:Remove() end
    local f = vgui.Create("SVFrame")
    UI.dossierPanel = f
    f:SetHeader("ДОСЬЕ", v.mode == "terminal" and "архивный доступ" or "личный доступ")
    f:SetSize(math.min(ScrW() - S(40), S(980)), math.min(ScrH() - S(40), S(760)))
    f:Center()
    f:MakePopup()
    viewDossier(f, v)
end

Net.on("know.view", openViewer)

UI.registerTab{
    id = "dossiers", name = "Досье", order = 35,
    visible = function() local c = UI.myChar() return c and not c.isSCP end,
    build = function(panel)
        if not UI.dossierList then
            UI.text(panel, "Загрузка…", "SV.Body", C.dim)
            Net.call("know.list")
            return
        end
        local scroll = UI.scroll(panel)
        UI.text(scroll, "Здесь доступны открытые сведения и то, что ваш персонаж узнал сам. Сведения по допуску — на архивных и исследовательских терминалах.", "SV.Small", C.dim)
        for _, d in ipairs(UI.dossierList) do
            local b = UI.button(scroll, d.title .. "  (" .. d.class .. ")", function() Net.call("know.open", d.id, NULL) end)
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, S(6))
        end
    end,
}

Net.on("know.list", function(data)
    UI.dossierList = data.list
    UI.refreshTab("dossiers")
end)

Net.on("know.terminal", function(data)
    if IsValid(UI.recordsPanel) then UI.recordsPanel:Remove() end
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    UI.recordsPanel = f
    f:SetHeader("АРХИВ ФОНДА", "допуск карты: " .. data.clearance)
    f:SetSize(S(560), S(520))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    for _, d in ipairs(data.list) do
        local b = UI.button(scroll, d.title .. "  (" .. d.class .. ")", function() Net.call("know.open", d.id, ent) f:Close() end)
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, S(6))
    end
end)

Net.on("know.document", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ДОКУМЕНТ", data.serial)
    f:SetSize(S(620), S(460))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    UI.text(scroll, data.title, "SV.Sub")
    if data.clearance then UI.text(scroll, "ГРИФ: ДОПУСК " .. data.clearance, "SV.Small", C.warn) end
    UI.text(scroll, data.text, "SV.Body")
end)

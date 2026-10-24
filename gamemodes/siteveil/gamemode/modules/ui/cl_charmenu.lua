--[[---------------------------------------------------------------------------
Character selection and creation screen ("Кадровый терминал").

Opens automatically after joining (the server pushes "char.list") and from
F4 → Персонаж → "Сменить персонажа". All decisions are made by the server;
the client only pre-validates the name for immediate feedback.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

UI.charData = UI.charData or nil

local function modelsFor(divId)
    local div = SV.Roles.getDivision(divId)
    local role = div and div.defaultRole and SV.Roles.get(div.defaultRole)
    return role and role.models or {SV.Config.FallbackModel}
end

local function closeCharMenu()
    if IsValid(UI.charMenu) then UI.charMenu:Remove() end
    UI.charMenu = nil
end
UI.closeCharMenu = closeCharMenu

local function buildList(parent, data)
    local list = UI.scroll(parent)

    UI.text(list, "Персонажи (" .. #data.chars .. " / " .. data.slots .. ")", "SV.Sub")

    if #data.chars == 0 then
        UI.text(list, "У вас пока нет персонажей. Заполните анкету справа, чтобы поступить на службу.", "SV.Body", C.dim)
    end

    for _, ch in ipairs(data.chars) do
        local card = vgui.Create("DPanel", list)
        card:Dock(TOP)
        card:SetTall(S(104))
        card:DockMargin(0, 0, S(6), S(8))
        card.Paint = function(_, w, h)
            UI.drawPanel(0, 0, w, h, data.current == ch.id and C.panelHover or C.panel2)
            UI.drawAccent(0, 0, h, UI.divisionColor(ch.division))
            draw.SimpleText(ch.name, "SV.Sub", S(14), S(10), C.text)
            draw.SimpleText("№ " .. ch.number .. " · " .. ch.divisionName, "SV.Small", S(14), S(36), C.dim)
            draw.SimpleText(ch.roleName .. " · " .. ch.rankName, "SV.Small", S(14), S(56), C.dim)
            draw.SimpleText(string.format("На службе: %.1f ч", (ch.playtime or 0) / 3600), "SV.Tiny", S(14), S(78), C.faint)
        end

        local btns = vgui.Create("DPanel", card)
        btns:Dock(RIGHT)
        btns:SetWide(S(150))
        btns:DockPadding(S(6), S(10), S(10), S(10))
        btns.Paint = function() end

        local sel = UI.button(btns, data.current == ch.id and "Текущий" or "На смену", function()
            Net.call("char.select", ch.id)
        end, "primary")
        sel:Dock(TOP)
        if data.current == ch.id then sel:SetBlocked("этот персонаж уже на смене") end
        if ch.active and data.current ~= ch.id then sel:SetBlocked("персонаж используется") end

        if not ch.isSCP then
            local del = UI.button(btns, "Удалить", function()
                UI.confirm("Удаление персонажа", "Персонаж «" .. ch.name .. "» и его снаряжение будут удалены безвозвратно.", function(word)
                    Net.call("char.delete", ch.id, word or "")
                end, ch.name)
            end, "danger")
            del:Dock(TOP)
            del:DockMargin(0, S(8), 0, 0)
            if data.current == ch.id then del:SetBlocked("нельзя удалить персонажа на смене") end
        end
    end

    if data.scp and #data.scp > 0 then
        UI.text(list, "Аномальные объекты", "SV.Sub"):DockMargin(0, S(12), 0, S(4))
        UI.text(list, "Игра за SCP доступна по допуску администрации и при достаточном онлайне.", "SV.Small", C.dim)
        for _, scp in ipairs(data.scp) do
            local row = UI.row(list, S(38))
            row:DockMargin(0, 0, S(6), S(6))
            local b = UI.button(row, scp.name, function() Net.call("char.selectSCP", scp.id) end, "danger")
            b:Dock(FILL)
            if not scp.ok then b:SetBlocked(scp.reason or "недоступно") end
        end
    end
end

local function buildCreate(parent, data)
    local wrap = UI.scroll(parent)
    UI.text(wrap, "Анкета нового сотрудника", "SV.Sub")

    local regular = 0
    for _, ch in ipairs(data.chars) do if not ch.isSCP then regular = regular + 1 end end
    local slotsFull = regular >= data.slots

    UI.text(wrap, "Имя и фамилия", "SV.Small", C.dim)
    local name = vgui.Create("SVEntry", wrap)
    name:Dock(TOP)
    name:SetHint("Например: Анна Левченко")
    name:DockMargin(0, 0, 0, S(4))
    local nameStatus = UI.text(wrap, "", "SV.Small", C.dim)

    UI.text(wrap, "Подразделение", "SV.Small", C.dim):DockMargin(0, S(8), 0, S(4))
    local div = vgui.Create("DComboBox", wrap)
    div:Dock(TOP)
    div:SetTall(S(34))
    div:SetFont("SV.Body")
    div:SetSortItems(false)
    for _, d in ipairs(data.divisions) do
        div:AddChoice(d.name .. (d.whitelisted and "  (допуск)" or ""), d.id)
    end
    local divInfo = UI.text(wrap, "", "SV.Small", C.dim)

    UI.text(wrap, "Внешность", "SV.Small", C.dim):DockMargin(0, S(8), 0, S(4))
    local modelRow = UI.row(wrap, S(220))
    local preview = vgui.Create("DModelPanel", modelRow)
    preview:Dock(FILL)
    preview:SetFOV(32)
    preview:SetCamPos(Vector(70, 0, 50))
    preview:SetLookAt(Vector(0, 0, 38))
    function preview:LayoutEntity(ent) ent:SetAngles(Angle(0, RealTime() * 25 % 360, 0)) end

    local modelIndex = 1
    local currentDiv
    local function refreshModel()
        local models = modelsFor(currentDiv)
        modelIndex = ((modelIndex - 1) % #models) + 1
        preview:SetModel(models[modelIndex])
    end

    local prev = UI.button(modelRow, "<", function() modelIndex = modelIndex - 1 refreshModel() end)
    prev:Dock(LEFT)
    prev:SetWide(S(40))
    local nxt = UI.button(modelRow, ">", function() modelIndex = modelIndex + 1 refreshModel() end)
    nxt:Dock(RIGHT)
    nxt:SetWide(S(40))

    local create = UI.button(wrap, "Поступить на службу", nil, "primary")
    create:Dock(TOP)
    create:DockMargin(0, S(12), 0, 0)
    create:SetTall(S(40))

    local function validate()
        if slotsFull then create:SetBlocked("все слоты персонажей заняты") return end
        local cleaned, why = SV.Chars.validateName(name:GetValue())
        if not cleaned then
            nameStatus:SetText(why or "")
            nameStatus:SetTextColor(C.warn)
            create:SetBlocked(why or "неверное имя")
            return
        end
        nameStatus:SetText("Имя подходит.")
        nameStatus:SetTextColor(C.ok)
        if not currentDiv then create:SetBlocked("выберите подразделение") return end
        create:SetBlocked(nil)
    end

    name.OnChange = validate
    name:SetUpdateOnType(true)
    function div:OnSelect(_, _, id)
        currentDiv = id
        local d = SV.Roles.getDivision(id)
        local role = d and SV.Roles.get(d.defaultRole)
        divInfo:SetText(role and ("Начальная должность: " .. role.name .. ". " .. role.description) or "")
        modelIndex = 1
        refreshModel()
        validate()
    end
    if data.divisions[1] then div:ChooseOptionID(1) end

    create.OnPressed = function()
        Net.call("char.create", name:GetValue(), currentDiv, modelIndex)
    end
    validate()
end

function UI.openCharMenu(data)
    data = data or UI.charData
    if not data then
        Net.call("char.list")
        return
    end
    closeCharMenu()
    if IsValid(UI.menuPanel) then UI.menuPanel:Close() end

    local f = vgui.Create("SVFrame")
    UI.charMenu = f
    f:SetHeader("КАДРОВЫЙ ТЕРМИНАЛ", "SITE-VEIL · Фонд SCP")
    f:SetSize(math.min(ScrW() - S(40), S(1180)), math.min(ScrH() - S(40), S(760)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)

    local hasChar = UI.myChar() ~= nil
    -- Without a character the screen cannot be closed: there is nothing to return to.
    f.close:SetVisible(hasChar)
    f.OnKeyCodePressed = function(self, key)
        if key == KEY_ESCAPE and hasChar then self:Close() end
    end
    f.OnClose = function() UI.charMenu = nil end

    local left = vgui.Create("DPanel", f)
    left:Dock(LEFT)
    left:SetWide(f:GetWide() * 0.48)
    left:DockPadding(S(12), S(12), S(6), S(12))
    left.Paint = function(_, w, h) UI.drawPanel(0, 0, w, h, C.panel) end
    buildList(left, data)

    local right = vgui.Create("DPanel", f)
    right:Dock(FILL)
    right:DockMargin(S(10), 0, 0, 0)
    right:DockPadding(S(12), S(12), S(12), S(12))
    right.Paint = function(_, w, h) UI.drawPanel(0, 0, w, h, C.panel) end
    buildCreate(right, data)
end

-- Full-screen backdrop while no character is selected: the lobby view must
-- not reveal the map.
UI.hudElement("lobby", 0, function()
    if UI.myChar() then return end
    surface.SetDrawColor(6, 8, 11, 255)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    draw.SimpleText("SITE-VEIL", "SV.Title", ScrW() / 2, ScrH() * 0.12, C.accent, TEXT_ALIGN_CENTER)
    draw.SimpleText("Закрытый комплекс Фонда SCP · служебная информационная система", "SV.Small", ScrW() / 2, ScrH() * 0.12 + S(38), C.dim, TEXT_ALIGN_CENTER)
    if not IsValid(UI.charMenu) then
        draw.SimpleText("Нажмите F4, чтобы открыть кадровый терминал", "SV.Body", ScrW() / 2, ScrH() * 0.5, C.text, TEXT_ALIGN_CENTER)
    end
end)

Net.on("char.list", function(data)
    UI.charData = data
    if not UI.myChar() or IsValid(UI.charMenu) then
        UI.openCharMenu(data)
    end
end)

Net.on("char.selected", function()
    closeCharMenu()
end)

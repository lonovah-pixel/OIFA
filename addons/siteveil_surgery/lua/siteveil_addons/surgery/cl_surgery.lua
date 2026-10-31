--[[---------------------------------------------------------------------------
Surgery (client): table window, step window, consent.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

Net.on("surgery.open", function(data)
    local bed = Entity(data.bed)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ОПЕРАЦИОННЫЙ СТОЛ")
    f:SetSize(S(560), S(420))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    if #data.patients == 0 then UI.text(scroll, "На столе нет пациента.", "SV.Body", C.dim) end
    for _, p in ipairs(data.patients) do
        local card = UI.card(scroll, p.name)
        for _, op in ipairs(p.ops) do
            local b = UI.button(card, op.name, function()
                Net.call("surgery.start", bed, Entity(p.ent), op.id)
                f:Close()
            end, "primary")
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, S(4))
            if op.blocked then b:SetBlocked(op.blocked) end
        end
    end
end)

Net.on("surgery.step", function(data)
    if IsValid(UI.surgeryFrame) then UI.surgeryFrame:Remove() end
    local f = vgui.Create("SVFrame")
    UI.surgeryFrame = f
    f:SetHeader(string.upper(data.name), "шаг " .. data.step .. " / " .. data.steps)
    f:SetSize(S(560), S(240))
    f:Center()
    f:MakePopup()
    UI.text(f, "Нужен инструмент: " .. data.tools[data.tool], "SV.Header", C.accent)
    UI.text(f, "Осложнения: " .. data.complications .. " / " .. data.allowed .. ". Не торопитесь и не медлите.", "SV.Small",
        data.complications > 0 and C.warn or C.dim)
    local row = UI.row(f, S(44))
    row:Dock(BOTTOM)
    for i, name in ipairs(data.tools) do
        local b = UI.button(row, name, function()
            Net.call("surgery.step", data.id, i)
            f:Close()
        end)
        b:Dock(LEFT)
        b:SetWide(S(130))
        b:DockMargin(0, 0, S(4), 0)
    end
end)

Net.on("surgery.done", function(data)
    if IsValid(UI.surgeryFrame) then UI.surgeryFrame:Remove() end
    UI.notify(data.ok and "Операция прошла успешно." or ("Операция не удалась: " .. tostring(data.reason)), data.ok and 0 or 1)
end)

Net.on("surgery.consent", function(data)
    UI.choose("ОПЕРАЦИЯ", data.doctor .. " предлагает операцию: " .. data.name .. ".", {{"Согласиться", true}, {"Отказаться", false}},
        function(v) Net.call("surgery.consent", v) end)
end)

table.insert(UI.helpSections, {"Хирургия", {
    "Врач у операционного стола (E) выбирает пациента на столе и операцию. Каждый шаг — нужный инструмент, без спешки и промедления.",
    "Только операция излечивает вторую стадию заражения SCP-049. Медик рядом даёт право на ещё одно осложнение.",
}})

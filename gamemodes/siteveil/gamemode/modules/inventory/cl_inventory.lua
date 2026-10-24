--[[---------------------------------------------------------------------------
Inventory (client): tab "Инвентарь", handover offers, death bags, item
inspection.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Items = SV.Config.Items

local categoryNames = {
    keycard = "Документы доступа", weapon = "Оружие", ammo = "Боеприпасы", equipment = "Снаряжение",
    consumable = "Расходные материалы", tool = "Инструменты", document = "Документы", evidence = "Улики",
    quest = "Образцы", anomaly = "Аномальные объекты", contraband = "Контрабанда",
}
local categoryOrder = {"keycard", "weapon", "ammo", "equipment", "consumable", "tool", "document", "evidence", "quest", "anomaly", "contraband"}

local function giveDialog(item)
    local options = {}
    for _, p in ipairs(UI.nearbyPlayers(140)) do
        options[#options + 1] = {SV.Chars.displayName(p), p}
    end
    if #options == 0 then
        UI.notify("Рядом нет сотрудников, которым можно передать предмет.", 1)
        return
    end
    UI.choose("Передать: " .. (Items[item.id] and Items[item.id].name or item.id), "Получатель должен подтвердить передачу.", options, function(p)
        if IsValid(p) then Net.call("inv.offer", item.uid, math.min(item.count, 255), p) end
    end)
end

local function itemRow(parent, item)
    local def = Items[item.id] or {name = item.id, category = "quest"}
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(S(58))
    row:DockMargin(0, 0, 0, S(4))
    local title = def.name .. (item.title and (": " .. item.title) or "") .. (item.count > 1 and ("  ×" .. item.count) or "")
    local sub = (item.kit and "служебное · " or "") .. (item.equipped and "в руках · " or "") .. (item.worn and "надето · " or "")
        .. (item.serial and ("№ " .. item.serial .. " · ") or "") .. string.format("%.2f кг", def.weight * item.count)
    row.Paint = function(_, w, h)
        UI.drawPanel(0, 0, w, h, C.panel2)
        if item.equipped or item.worn then UI.drawAccent(0, 0, h, C.accent) end
        draw.SimpleText(title, "SV.Body", S(12), S(8), item.locked and C.dim or C.text)
        draw.SimpleText(sub, "SV.Tiny", S(12), S(34), C.faint)
    end

    local function addBtn(label, fn, blocked, style)
        local b = UI.button(row, label, fn, style)
        b:Dock(RIGHT)
        b:SetWide(S(118))
        b:DockMargin(S(4), S(12), 0, S(12))
        if blocked then b:SetBlocked(blocked) end
        return b
    end

    local locked = item.locked and "предмет предлагается к передаче" or nil
    addBtn("Выбросить", function() Net.call("inv.drop", item.uid, math.min(item.count, 255)) end, locked or (def.noDrop and "служебный предмет нельзя выбросить"), "ghost")
    addBtn("Передать", function() giveDialog(item) end, locked or (def.noDrop and "служебный предмет нельзя передать"))
    if def.weapon then
        addBtn(item.equipped and "Убрать" or "Взять в руки", function() Net.call("inv.equip", item.uid) end, locked, "primary")
    elseif def.use then
        local label = ({armor = "Надеть", ammo = "Зарядить", medical = "Применить", read = "Читать", wear = item.worn and "Снять" or "Надеть"})[def.use] or "Использовать"
        addBtn(label, function() Net.call("inv.use", item.uid) end, locked, "primary")
    end
    addBtn("Осмотреть", function() Net.call("inv.inspect", item.uid) end, nil, "ghost")
end

UI.registerTab{
    id = "inventory", name = "Инвентарь", order = 20,
    visible = function() local c = UI.myChar() return c and not c.isSCP end,
    build = function(panel)
        local inv = SV.Sync.get("self", "inv")
        if not inv then
            UI.text(panel, "Инвентарь недоступен.", "SV.Body", C.dim)
            return
        end
        local head = UI.row(panel, S(30))
        head.Paint = function(_, w, h)
            draw.SimpleText(string.format("Ячейки: %d / %d     Вес: %.1f / %d кг", inv.slots, inv.maxSlots, inv.weight, inv.maxWeight), "SV.Sub", 0, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local scroll = UI.scroll(panel)
        local groups = {}
        for _, item in ipairs(inv.items) do
            local cat = Items[item.id] and Items[item.id].category or "quest"
            groups[cat] = groups[cat] or {}
            table.insert(groups[cat], item)
        end
        if #inv.items == 0 then UI.text(scroll, "Инвентарь пуст.", "SV.Body", C.dim) end
        for _, cat in ipairs(categoryOrder) do
            if groups[cat] then
                UI.text(scroll, categoryNames[cat] or cat, "SV.Sub", C.dim):DockMargin(0, S(6), 0, S(4))
                for _, item in ipairs(groups[cat]) do itemRow(scroll, item) end
            end
        end
    end,
}

hook.Add("SiteVeil.Sync", "SiteVeil.UI.Inventory", function(channel, key)
    if channel == "self" and key == "inv" then UI.refreshTab("inventory") end
end)

--[[---------------------------------------------------------------------------
Offers
---------------------------------------------------------------------------]]
UI.offerPanels = UI.offerPanels or {}

Net.on("inv.offer", function(data)
    local def = Items[data.item]
    local f = vgui.Create("SVFrame")
    UI.offerPanels[data.id] = f
    f:SetHeader("ПЕРЕДАЧА ПРЕДМЕТА")
    f:SetSize(S(440), S(190))
    f:SetPos(ScrW() - S(460), ScrH() * 0.55)
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    UI.text(f, data.fromName .. " передаёт вам: " .. (def and def.name or data.item) .. (data.title and (" «" .. data.title .. "»") or "") .. (data.count > 1 and (" ×" .. data.count) or ""))
    local row = UI.row(f, S(36))
    row:Dock(BOTTOM)
    local yes = UI.button(row, "Принять", function() Net.call("inv.answer", data.id, true) f:Close() end, "primary")
    yes:Dock(LEFT) yes:SetWide(S(190))
    local no = UI.button(row, "Отказаться", function() Net.call("inv.answer", data.id, false) f:Close() end)
    no:Dock(RIGHT) no:SetWide(S(190))
    f.OnClose = function() UI.offerPanels[data.id] = nil end
end)

Net.on("inv.offerClosed", function(data)
    local f = UI.offerPanels[data.id]
    if IsValid(f) then f:Close() end
end)

--[[---------------------------------------------------------------------------
Bags and inspection
---------------------------------------------------------------------------]]
Net.on("inv.bag", function(data)
    if IsValid(UI.bagPanel) then UI.bagPanel:Remove() end
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    UI.bagPanel = f
    f:SetHeader("ЛИЧНЫЕ ВЕЩИ", data.owner ~= "" and data.owner or nil)
    f:SetSize(S(520), S(420))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    for _, item in ipairs(data.items) do
        local def = Items[item.id]
        local row = UI.row(scroll, S(36))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Body")
        lbl:SetTextColor(C.text)
        lbl:SetText((def and def.name or item.id) .. (item.count > 1 and (" ×" .. item.count) or ""))
        local take = UI.button(row, "Забрать", function() Net.call("inv.bagTake", ent, item.uid) end, "primary")
        take:Dock(RIGHT)
        take:SetWide(S(120))
    end
end)

Net.on("inv.inspect", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ОСМОТР ПРЕДМЕТА")
    f:SetSize(S(480), S(260))
    f:Center()
    f:MakePopup()
    UI.text(f, data.name, "SV.Sub")
    UI.text(f, data.desc or "", "SV.Small", C.dim)
    local d = data.data or {}
    if d.serial then UI.text(f, "Серийный номер: " .. d.serial, "SV.Body") end
    if d.label then UI.text(f, d.label, "SV.Body") end
    if d.expires then UI.text(f, "Действует до: " .. os.date("%H:%M", d.expires), "SV.Body") end
    if d.case then UI.text(f, "Дело №" .. d.case, "SV.Body") end
end)

UI.registerInteraction{
    id = "give", name = "Передать предмет", order = 10,
    action = function(target)
        local inv = SV.Sync.get("self", "inv")
        local options = {}
        for _, item in ipairs(inv and inv.items or {}) do
            local def = Items[item.id]
            if def then
                options[#options + 1] = {def.name .. (item.count > 1 and (" ×" .. item.count) or ""), item, def.noDrop and "служебный предмет" or (item.locked and "уже предлагается" or nil)}
            end
        end
        if #options == 0 then UI.notify("Инвентарь пуст.", 1) return end
        UI.choose("Передать: " .. SV.Chars.displayName(target), nil, options, function(item)
            Net.call("inv.offer", item.uid, math.min(item.count, 255), target)
        end)
    end,
}

--[[---------------------------------------------------------------------------
Supply (client): tab "Снабжение" (budget, stock, requests, ledger) and the
equipment locker window.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Items = SV.Config.Items

UI.supplyData = UI.supplyData or nil

local statusNames = {
    pending = {"на рассмотрении", C.warn}, approved = {"одобрена, в пути", C.info}, arrived = {"на площадке", C.accent},
    delivered = {"доставлена", C.ok}, rejected = {"отклонена", C.danger}, cancelled = {"отменена", C.faint},
}

local function linesText(lines)
    local parts = {}
    for id, n in pairs(lines or {}) do parts[#parts + 1] = (Items[id] and Items[id].name or id) .. " ×" .. n end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function requestForm(parent, data)
    local card = UI.card(parent, "Новая заявка")
    if not data.canRequest then
        UI.text(card, "Подача заявок недоступна: " .. tostring(data.requestBlocked), "SV.Small", C.warn)
        return
    end
    UI.text(card, "Выберите количество. Цены определяет логистика; итог списывается с бюджета подразделения после одобрения.", "SV.Small", C.dim)
    local counts = {}
    local total = UI.text(card, "Итого: 0 ед.", "SV.Sub")
    local function recalc()
        local sum = 0
        for id, n in pairs(counts) do sum = sum + (Items[id].price or 0) * n end
        total:SetText("Итого: " .. sum .. " ед. (бюджет: " .. data.budget .. ")")
        total:SetTextColor(sum > data.budget and C.danger or C.text)
    end
    for _, entry in ipairs(data.catalog) do
        local def = Items[entry.id]
        local row = UI.row(card, S(32))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Small")
        lbl:SetTextColor(C.text)
        lbl:SetText(def.name .. " — " .. entry.price .. " ед.")
        local wang = vgui.Create("DNumberWang", row)
        wang:Dock(RIGHT)
        wang:SetWide(S(70))
        wang:SetMin(0)
        wang:SetMax(20)
        wang:SetValue(0)
        wang.OnValueChanged = function(_, v)
            v = math.Clamp(math.floor(tonumber(v) or 0), 0, 20)
            counts[entry.id] = v > 0 and v or nil
            recalc()
        end
    end
    local reason = vgui.Create("SVEntry", card)
    reason:Dock(TOP)
    reason:DockMargin(0, S(6), 0, S(6))
    reason:SetHint("Обоснование заявки")
    local send = UI.button(card, "Подать заявку", function()
        if next(counts) == nil then UI.notify("Заявка пуста.", 1) return end
        Net.call("supply.request", counts, reason:GetValue())
        UI.supplyData = nil
    end, "primary")
    send:Dock(TOP)
end

UI.registerTab{
    id = "supply", name = "Снабжение", order = 25,
    visible = function() local c = UI.myChar() return c and not c.isSCP and c.division ~= "chaos" end,
    build = function(panel)
        local data = UI.supplyData
        if not data then
            UI.text(panel, "Загрузка…", "SV.Body", C.dim)
            Net.call("supply.overview")
            return
        end
        local div = SV.Roles.getDivision(data.division)
        local scroll = UI.scroll(panel)
        local head = UI.card(scroll, "Бюджет: " .. (div and div.name or data.division))
        UI.text(head, data.budget .. " ед.", "SV.Title", C.accent)
        if data.blocked then UI.text(head, "Логистика нарушена: поставки задерживаются.", "SV.Small", C.warn) end
        UI.text(head, "Время доставки после одобрения: около " .. data.delay .. " с.", "SV.Small", C.dim)

        local stock = UI.card(scroll, "Склад подразделения")
        local parts = {}
        for id, n in pairs(data.stock) do parts[#parts + 1] = (Items[id] and Items[id].name or id) .. ": " .. n end
        table.sort(parts)
        UI.text(stock, #parts > 0 and table.concat(parts, " · ") or "Склад пуст.", "SV.Small")

        requestForm(scroll, data)

        local reqs = UI.card(scroll, "Заявки")
        if #data.requests == 0 then UI.text(reqs, "Заявок нет.", "SV.Small", C.dim) end
        for _, r in ipairs(data.requests) do
            local st = statusNames[r.status] or {r.status, C.dim}
            local rdiv = SV.Roles.getDivision(r.division)
            UI.text(reqs, string.format("#%s · %s · %s · %s ед. · %s", r.id, rdiv and rdiv.short or r.division, r.requester_name, r.cost, st[1]), "SV.Body", st[2])
            UI.text(reqs, linesText(r.lines) .. ". Обоснование: " .. r.reason .. (r.note and r.note ~= "" and (". Решение: " .. r.note) or ""), "SV.Tiny", C.dim)
            if r.canDecide then
                local row = UI.row(reqs, S(32))
                local note = vgui.Create("SVEntry", row)
                note:Dock(FILL)
                note:SetHint("Комментарий (обязателен при отказе)")
                local yes = UI.button(row, "Одобрить", function() Net.call("supply.decide", tonumber(r.id), true, note:GetValue()) UI.supplyData = nil end, "primary")
                yes:Dock(RIGHT) yes:SetWide(S(120)) yes:DockMargin(S(6), 0, 0, 0)
                if tonumber(r.cost) > data.budget and r.division == data.division then yes:SetBlocked("недостаточно бюджета") end
                local no = UI.button(row, "Отклонить", function() Net.call("supply.decide", tonumber(r.id), false, note:GetValue()) UI.supplyData = nil end, "danger")
                no:Dock(RIGHT) no:SetWide(S(120)) no:DockMargin(S(6), 0, 0, 0)
            elseif r.own and r.status == "pending" then
                local cancel = UI.button(reqs, "Отозвать заявку", function() Net.call("supply.cancel", tonumber(r.id)) UI.supplyData = nil end, "ghost")
                cancel:Dock(TOP)
            end
        end

        local ledger = UI.card(scroll, "Журнал бюджета")
        for _, l in ipairs(data.ledger) do
            local delta = tonumber(l.delta)
            UI.text(ledger, string.format("%s  %s%d  → %s  · %s (%s)", l.when, delta > 0 and "+" or "", delta, l.balance, l.reason, l.actor_name or "—"), "SV.Tiny", delta >= 0 and C.ok or C.dim)
        end
    end,
}

Net.on("supply.overview", function(data)
    UI.supplyData = data
    UI.refreshTab("supply")
end)

hook.Add("SiteVeil.Sync", "SiteVeil.UI.Supply", function(channel)
    if channel == "budgets" and IsValid(UI.menuPanel) and UI.menuPanel.tabs.active == "supply" then
        Net.call("supply.overview")
    end
end)

--[[---------------------------------------------------------------------------
Locker window
---------------------------------------------------------------------------]]
Net.on("supply.locker", function(data)
    if IsValid(UI.lockerPanel) then UI.lockerPanel:Remove() end
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    UI.lockerPanel = f
    f:SetHeader(string.upper(data.name), "склад: " .. data.stockOwner)
    f:SetSize(S(640), S(560))
    f:Center()
    f:MakePopup()
    if not data.ok then UI.text(f, "Доступ запрещён: " .. tostring(data.reason), "SV.Body", C.danger) end
    local scroll = UI.scroll(f)
    UI.text(scroll, "Выдача", "SV.Sub")
    for _, it in ipairs(data.items) do
        local def = Items[it.id]
        local row = UI.row(scroll, S(36))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Body")
        lbl:SetTextColor(C.text)
        lbl:SetText(string.format("%s — на складе %d, получено за смену %d из %d", def and def.name or it.id, it.stock, it.used, it.quota))
        local take = UI.button(row, "Получить", function() Net.call("supply.lockerTake", ent, it.id) end, "primary")
        take:Dock(RIGHT)
        take:SetWide(S(120))
        if not data.ok then take:SetBlocked(data.reason)
        elseif it.used >= it.quota then take:SetBlocked("лимит за смену исчерпан")
        elseif it.stock <= 0 then take:SetBlocked("нет на складе — подайте заявку") end
    end
    UI.text(scroll, "Сдать на склад", "SV.Sub"):DockMargin(0, S(10), 0, S(4))
    local inv = SV.Sync.get("self", "inv")
    local any = false
    for _, item in ipairs(inv and inv.items or {}) do
        local quota
        for _, it in ipairs(data.items) do if it.id == item.id then quota = true end end
        if quota and not item.kit then
            any = true
            local row = UI.row(scroll, S(34))
            local lbl = vgui.Create("DLabel", row)
            lbl:Dock(FILL)
            lbl:SetFont("SV.Small")
            lbl:SetTextColor(C.text)
            lbl:SetText((Items[item.id] and Items[item.id].name or item.id) .. " ×" .. item.count)
            local ret = UI.button(row, "Сдать", function() Net.call("supply.lockerReturn", ent, item.uid) end)
            ret:Dock(RIGHT)
            ret:SetWide(S(120))
        end
    end
    if not any then UI.text(scroll, "Нет предметов для сдачи. Служебное снаряжение должности сдавать не нужно.", "SV.Small", C.dim) end
end)

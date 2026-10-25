--[[---------------------------------------------------------------------------
Security (client): interaction entries, search window, ID check, status HUD.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Security = SV.Security
local Items = SV.Config.Items

local function myRole() return SV.Roles.ofPlayer(LocalPlayer()) end
local function canDetain() local r = myRole() return r and r.flags.canDetain end

UI.registerInteraction{
    id = "checkid", name = "Проверить документы", order = 5,
    action = function(target) Net.call("sec.checkId", target) end,
}

UI.registerInteraction{
    id = "cuff", name = "Надеть / снять наручники", order = 40,
    visible = function() return canDetain() end,
    blocked = function() return not LocalPlayer():HasWeapon("sv_restraints") and "нужны наручники" or nil end,
    action = function(target)
        Net.call(Security.isRestrained(target) and "sec.release" or "sec.restrain", target)
    end,
}

UI.registerInteraction{
    id = "escort", name = "Вести / отпустить", order = 41,
    visible = function() return canDetain() end,
    action = function(target) Net.call("sec.escort", target) end,
}

UI.registerInteraction{
    id = "search", name = "Обыскать", order = 42,
    visible = function() local r = myRole() return r and r.flags.search end,
    action = function(target) Net.call("sec.search", target) end,
}

UI.registerInteraction{
    id = "detain", name = "Оформить задержание", order = 43,
    visible = function() return canDetain() end,
    blocked = function(target) return not Security.isRestrained(target) and "сначала наденьте наручники" or nil end,
    action = function(target)
        local f = vgui.Create("SVFrame")
        f:SetHeader("ЗАДЕРЖАНИЕ", SV.Chars.displayName(target))
        f:SetSize(S(480), S(260))
        f:Center()
        f:MakePopup()
        UI.text(f, "Срок, минут (предел зависит от полномочий)", "SV.Small", C.dim)
        local mins = vgui.Create("DNumberWang", f)
        mins:Dock(TOP)
        mins:SetMin(1)
        mins:SetMax(SV.Config.Security.detainMaxChief)
        mins:SetValue(SV.Config.Security.detainDefault)
        local reason = vgui.Create("SVEntry", f)
        reason:Dock(TOP)
        reason:DockMargin(0, S(6), 0, S(6))
        reason:SetHint("Основание задержания")
        local b = UI.button(f, "Оформить", function()
            Net.call("sec.detain", target, math.Clamp(math.floor(mins:GetValue()), 1, 60), reason:GetValue())
            f:Close()
        end, "primary")
        b:Dock(BOTTOM)
    end,
}

UI.registerInteraction{
    id = "undetain", name = "Освободить из-под задержания", order = 44,
    visible = function(target) return canDetain() and target:GetNW2Bool("sv_detained", false) end,
    action = function(target) Net.call("sec.unDetain", target, "решение охраны") end,
}

Net.on("sec.search", function(data)
    if IsValid(UI.searchPanel) then UI.searchPanel:Remove() end
    local target = Entity(data.target)
    local f = vgui.Create("SVFrame")
    UI.searchPanel = f
    f:SetHeader("ОБЫСК", data.name)
    f:SetSize(S(600), S(520))
    f:Center()
    f:MakePopup()
    local reason = vgui.Create("SVEntry", f)
    reason:Dock(TOP)
    reason:SetHint("Основание изъятия (в журнал)")
    reason:DockMargin(0, 0, 0, S(6))
    local scroll = UI.scroll(f)
    if #data.items == 0 then UI.text(scroll, "Ничего не найдено.", "SV.Body", C.dim) end
    for _, it in ipairs(data.items) do
        local def = Items[it.id]
        local row = UI.row(scroll, S(36))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Body")
        lbl:SetTextColor(it.contraband and C.danger or C.text)
        lbl:SetText((def and def.name or it.id) .. (it.title and (": " .. it.title) or "") .. (it.count > 1 and (" ×" .. it.count) or "")
            .. (it.serial and ("  № " .. it.serial) or "") .. (it.contraband and "  — КОНТРАБАНДА" or ""))
        local b = UI.button(row, "Изъять", function() Net.call("sec.confiscate", target, it.uid, reason:GetValue()) end, "danger")
        b:Dock(RIGHT)
        b:SetWide(S(110))
        if it.noConfiscate then b:SetBlocked("не изымается") end
    end
end)

Net.on("sec.idcard", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ПРОВЕРКА ДОКУМЕНТОВ", data.name)
    f:SetSize(S(520), S(360))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    if #data.cards == 0 then UI.text(scroll, "Документы отсутствуют.", "SV.Sub", C.danger) end
    for _, c in ipairs(data.cards) do
        local card = UI.card(scroll, c.kind .. " № " .. c.serial, c.valid and C.ok or C.danger)
        UI.text(card, "Владелец по реестру: " .. c.holder .. " (№ " .. c.number .. ")", "SV.Body")
        UI.text(card, "Допуск: " .. c.clearance, "SV.Body")
        if not c.valid then UI.text(card, "НЕДЕЙСТВИТЕЛЬНА: " .. tostring(c.reason), "SV.Body", C.danger) end
        if c.mismatch then UI.text(card, "Имя владельца не совпадает с предъявителем!", "SV.Body", C.warn) end
    end
end)

UI.hudElement("security", 13, function(ply)
    if not UI.myChar() or not ply:Alive() then return end
    local y = ScrH() * 0.72
    if Security.isRestrained(ply) then
        draw.SimpleText("ВЫ В НАРУЧНИКАХ", "SV.Sub", ScrW() / 2, y, C.warn, TEXT_ALIGN_CENTER)
        draw.SimpleText("Если вас оставили одного, попробуйте освободиться: /struggle", "SV.HUDSmall", ScrW() / 2, y + S(22), C.dim, TEXT_ALIGN_CENTER)
    end
    local d = SV.Sync.get("self", "detention")
    if d then
        local left = math.max(d.untilTime - CurTime(), 0)
        draw.SimpleText("Задержание: осталось " .. SV.Util.formatClock(left), "SV.HUDSmall", ScrW() / 2, y + S(46), C.warn, TEXT_ALIGN_CENTER)
    end
    if ply:GetNW2Bool("sv_surrender", false) then
        draw.SimpleText("Вы подняли руки (/surrender — опустить)", "SV.HUDSmall", ScrW() / 2, y + S(68), C.dim, TEXT_ALIGN_CENTER)
    end
end)

hook.Add("SiteVeil.HUDTargetInfo", "SiteVeil.Security", function(ent, x, y)
    if Security.isRestrained(ent) then draw.SimpleText("в наручниках", "SV.HUDSmall", x, y, C.warn, TEXT_ALIGN_CENTER) end
    if ent:GetNW2Bool("sv_surrender", false) then draw.SimpleText("руки подняты", "SV.HUDSmall", x, y + S(18), C.dim, TEXT_ALIGN_CENTER) end
    if SV.Medical.isDown(ent) then draw.SimpleText("без сознания", "SV.HUDSmall", x, y + S(36), C.danger, TEXT_ALIGN_CENTER) end
end)

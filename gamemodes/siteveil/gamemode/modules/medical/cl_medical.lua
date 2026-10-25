--[[---------------------------------------------------------------------------
Medicine (client): injury indicators, incapacitation screen, pain effect,
examination report and treatment menu.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Medical = SV.Medical
local Items = SV.Config.Items

UI.hudElement("medical", 12, function(ply)
    local med = SV.Sync.get("self", "med")
    if not med or not UI.myChar() or not ply:Alive() then return end
    local x, y = S(20) + S(370), ScrH() - S(20) - S(28)
    local function chip(text, col)
        local w = UI.textSize("SV.HUDSmall", text) + S(16)
        UI.drawPanel(x, y, w, S(26), ColorAlpha(col, 40), col)
        draw.SimpleText(text, "SV.HUDSmall", x + w / 2, y + S(13), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        y = y - S(30)
    end
    if med.bleed and med.bleed > 0 then chip("Кровотечение: " .. Medical.bleedNames[med.bleed], med.bleed >= 3 and C.danger or C.warn) end
    if med.fracture then chip("Перелом ноги", C.warn) end
    if med.pain and med.pain > 60 then chip("Сильная боль", C.warn) end
    if med.infected then chip("Кашель, жар", C.danger) end
end)

UI.hudElement("down", 48, function(ply)
    local med = SV.Sync.get("self", "med")
    if not med or not med.down or not ply:Alive() then return end
    surface.SetDrawColor(40, 0, 0, 150)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    draw.SimpleText("ВЫ НЕДЕЕСПОСОБНЫ", "SV.Banner", ScrW() / 2, ScrH() * 0.35, C.danger, TEXT_ALIGN_CENTER)
    local text
    if med.down.stabilised then
        text = "Состояние стабильно. Вы придёте в себя через " .. math.max(math.ceil((med.down.wakeAt or 0) - CurTime()), 0) .. " с или после реанимации."
    else
        text = "Без помощи медика: " .. math.max(math.ceil(med.down.deathAt - CurTime()), 0) .. " с. Зовите на помощь (/w, рация недоступна)."
    end
    draw.SimpleText(text, "SV.HUD", ScrW() / 2, ScrH() * 0.35 + S(40), C.text, TEXT_ALIGN_CENTER)
    local giveup = CurTime() - med.down.since >= SV.Config.Medical.giveUpAfter
    draw.SimpleText(giveup and "Сдаться и погибнуть: команда /giveup" or "", "SV.HUDSmall", ScrW() / 2, ScrH() * 0.35 + S(70), C.dim, TEXT_ALIGN_CENTER)
end)

hook.Add("RenderScreenspaceEffects", "SiteVeil.Medical.Pain", function()
    local med = SV.Sync.get("self", "med")
    if not med then return end
    if med.down then
        DrawMotionBlur(0.15, 0.8, 0.02)
        DrawColorModify({["$pp_colour_colour"] = 0.2, ["$pp_colour_brightness"] = -0.1, ["$pp_colour_contrast"] = 0.9,
            ["$pp_colour_addr"] = 0.05, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0, ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0})
    elseif med.pain and med.pain > SV.Config.Medical.painBlur then
        DrawMotionBlur(0.3, (med.pain - 60) / 80, 0.01)
    end
end)

concommand.Add("sv_giveup", function() Net.call("med.giveup") end)

Net.on("med.report", function(data)
    if IsValid(UI.medReport) then UI.medReport:Remove() end
    local f = vgui.Create("SVFrame")
    UI.medReport = f
    f:SetHeader("МЕДИЦИНСКИЙ ОСМОТР", data.name)
    f:SetSize(S(480), S(380))
    f:SetPos(ScrW() - S(500), ScrH() * 0.3)
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    if data.health then UI.text(f, "Общее состояние: " .. data.health .. "%", "SV.Sub", data.health < 30 and C.danger or C.text) end
    for _, line in ipairs(data.lines or {}) do UI.text(f, line, "SV.Body") end
    if data.advice and #data.advice > 0 then UI.text(f, "Рекомендовано: " .. table.concat(data.advice, ", "), "SV.Small", C.accent) end
end)

--- Treatment menu for a target (self when target is the local player).
function UI.openTreatment(target)
    local inv = SV.Sync.get("self", "inv")
    local options = {}
    for _, item in ipairs(inv and inv.items or {}) do
        local tr = SV.Config.Treatments[item.id]
        if tr then
            local role = SV.Roles.ofPlayer(LocalPlayer())
            local blocked
            if tr.medicOnly and not (role and role.flags.medic) then blocked = "только медицинская служба" end
            if tr.doctor and not (role and role.flags.doctor) then blocked = "только врач" end
            options[#options + 1] = {tr.label .. " (" .. Items[item.id].name .. " ×" .. item.count .. ")", item.id, blocked}
        end
    end
    if #options == 0 then UI.notify("У вас нет медицинских средств.", 1) return end
    UI.choose("Помощь: " .. SV.Chars.displayName(target), nil, options, function(itemId)
        Net.call("med.treat", target, itemId)
    end)
end

UI.registerInteraction{
    id = "treat", name = "Оказать помощь", order = 20,
    action = function(target) UI.openTreatment(target) end,
}

UI.registerInteraction{
    id = "examine", name = "Осмотреть", order = 21,
    action = function(target) Net.call("med.examine", target) end,
}

Net.on("med.terminal", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("МЕДИЦИНСКИЙ ТЕРМИНАЛ")
    f:SetSize(UI.S(560), UI.S(520))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    local p = UI.card(scroll, "Недееспособные сотрудники")
    if #data.patients == 0 then UI.text(p, "Нет данных о пострадавших.", "SV.Small", UI.Colors.dim) end
    for _, x in ipairs(data.patients) do
        UI.text(p, x.name .. " · " .. (x.sector and ("сектор " .. x.sector) or "местоположение неизвестно (нет наблюдения)") ..
            (x.stabilised and " · стабилен" or (" · без помощи ~" .. x.left .. " с")), "SV.Small", x.stabilised and UI.Colors.ok or UI.Colors.danger)
    end
    local s = UI.card(scroll, "Склад медблока")
    for _, it in ipairs(data.stock) do UI.text(s, it.name .. ": " .. it.count, "SV.Small") end
end)

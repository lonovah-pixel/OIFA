--[[---------------------------------------------------------------------------
SCP framework (client): HUD of the SCP player, blink meter, flicker effect,
containment panel window, recapture interaction.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local SCP = SV.SCP

local stageColors = {stable = C.ok, signs = C.info, degrading = C.warn, danger = C.danger, escape = C.critical}
local statusColors = {ok = C.ok, warn = C.warn, bad = C.danger}

SCP.hints = {
    scp173 = {"ЛКМ — атака (вне наблюдения)", "ПКМ — взлом двери / проверка камеры", "R — «Затемнение»"},
    scp106 = {"ЛКМ — касание: карманное измерение", "ПКМ — пройти сквозь дверь", "R — перемещение (вне камеры)"},
    scp049 = {"ЛКМ — прикосновение (заражение)", "ЛКМ по недееспособному — «лечение»"},
    scp096 = {"ЛКМ — атака цели (в ярости)", "ПКМ — взлом двери (в ярости)", "R — сорвать мешок"},
}

--- Extra status line from the SCP's public data.
local function extraLine(info)
    local d = info.data
    if not d then return nil end
    if info.id == "scp173" then return "Наблюдают: " .. (d.observers or 0) .. " · загрязнение " .. (d.dirt or 0) .. "%" end
    if info.id == "scp106" then return "Покрытие камеры: " .. (d.coating or 0) .. "% · в измерении: " .. (d.victims or 0) end
    if info.id == "scp049" then return "«Излечённые»: " .. (d.instances or 0) .. " / " .. (d.max or 0) .. (d.suppressed and " · ПОДАВЛЕН" or "") end
    if info.id == "scp096" then
        return "Состояние: " .. (d.modeName or d.mode or "?") .. " · цели: " .. (d.targets or 0) .. (d.bagged and " · мешок" or "") ..
            (d.rageLeft and (" · ярость ещё " .. d.rageLeft .. " с") or "")
    end
    return nil
end

UI.hudElement("scp_self", 8, function(ply)
    local info = SV.Sync.get("self", "scp")
    if not info or not ply:Alive() or not SCP.of(ply) then return end
    local x, y, w = S(20), ScrH() - S(250), S(360)
    local lines = info.conditions or {}
    local extra = extraLine(info)
    local h = S(64) + #lines * S(20) + #(SCP.hints[info.id] or {}) * S(18) + S(10) + (extra and S(20) or 0)
    UI.drawPanel(x, y, w, h, C.panel)
    UI.drawAccent(x, y, h, stageColors[info.stage] or C.dim)
    draw.SimpleText(SV.Roles.ofPlayer(ply).name .. (info.breached and " · ВНЕ КАМЕРЫ" or ""), "SV.HUD", x + S(12), y + S(8), info.breached and C.danger or C.text)
    draw.SimpleText("Содержание: " .. info.integrity .. "% · " .. SCP.stageName(info.stage), "SV.HUDSmall", x + S(12), y + S(32), stageColors[info.stage] or C.dim)
    local yy = y + S(56)
    if extra then
        draw.SimpleText(extra, "SV.Tiny", x + S(12), yy, C.text)
        yy = yy + S(20)
    end
    for _, c in ipairs(lines) do
        draw.SimpleText("• " .. c.name .. ": " .. (c.text or ""), "SV.Tiny", x + S(12), yy, statusColors[c.status] or C.dim)
        yy = yy + S(20)
    end
    for _, hint in ipairs(SCP.hints[info.id] or {}) do
        draw.SimpleText(hint, "SV.Tiny", x + S(12), yy, C.faint)
        yy = yy + S(18)
    end
    if info.id == "scp173" then
        local observed = ply:GetNW2Bool("sv_173_observed", false)
        draw.SimpleText(observed and "ЗА ВАМИ НАБЛЮДАЮТ" or "ВНЕ НАБЛЮДЕНИЯ", "SV.Banner", ScrW() / 2, ScrH() * 0.8, observed and C.danger or C.ok, TEXT_ALIGN_CENTER)
    end
end)

-- Blink meter for humans near SCP-173.
UI.hudElement("blink", 14, function()
    local b = SV.Sync.get("self", "blink")
    if not b then return end
    local now = CurTime()
    local w, h = S(240), S(14)
    local x, y = ScrW() / 2 - w / 2, ScrH() - S(110)
    if now >= b.nextAt and now < b.nextAt + b.duration then
        surface.SetDrawColor(0, 0, 0, 252)
        surface.DrawRect(0, 0, ScrW(), ScrH())
        return
    end
    local left = math.max(b.nextAt - now, 0)
    UI.hudBar(x, y, w, h, math.Clamp(left / 7, 0, 1), left < 1.5 and C.danger or C.accent)
    draw.SimpleText("Моргание через " .. string.format("%.1f", left) .. " с", "SV.Tiny", ScrW() / 2, y - S(16), C.dim, TEXT_ALIGN_CENTER)
end)

-- Victims: pocket dimension, SCP-096 target, SCP-049-2 instance timer.
UI.hudElement("scp_victim", 15, function()
    local now = CurTime()
    local pocket = SV.Sync.get("self", "pocket")
    if pocket then
        draw.SimpleText(pocket.fallback and "ВАС ЗАТЯНУЛО ВО ТЬМУ" or "КАРМАННОЕ ИЗМЕРЕНИЕ — ИЩИТЕ ВЫХОД", "SV.Banner", ScrW() / 2, ScrH() * 0.25, C.warn, TEXT_ALIGN_CENTER)
        draw.SimpleText("Выброс не позже чем через " .. math.max(math.ceil(pocket.untilTime - now), 0) .. " с", "SV.HUDSmall", ScrW() / 2, ScrH() * 0.25 + S(40), C.dim, TEXT_ALIGN_CENTER)
    end
    if SV.Sync.get("self", "target096") then
        local flash = math.floor(RealTime() * 3) % 2 == 0
        draw.SimpleText("ВЫ ВИДЕЛИ ЛИЦО SCP-096", "SV.Banner", ScrW() / 2, ScrH() * 0.18, flash and C.critical or C.danger, TEXT_ALIGN_CENTER)
    end
    local inst = SV.Sync.get("self", "instance")
    if inst then
        draw.SimpleText("SCP-049-2 · до возвращения к персонажу: " .. math.max(math.ceil(inst.untilTime - now), 0) .. " с", "SV.HUDSmall", ScrW() / 2, ScrH() - S(140), C.warn, TEXT_ALIGN_CENTER)
    end
end)

local flickerUntil = 0
Net.on("scp.flicker", function(data)
    flickerUntil = CurTime() + (data.duration or 1)
end)

hook.Add("RenderScreenspaceEffects", "SiteVeil.SCP.Flicker", function()
    if CurTime() < flickerUntil then
        DrawColorModify({["$pp_colour_brightness"] = -0.6, ["$pp_colour_contrast"] = 0.5, ["$pp_colour_colour"] = 0.3,
            ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0, ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0})
    end
end)

Net.on("scp.panel", function(msg)
    if IsValid(UI.scpPanel) then UI.scpPanel:Remove() end
    local v = msg.view
    local ent = Entity(msg.ent)
    local f = vgui.Create("SVFrame")
    UI.scpPanel = f
    f:SetHeader("ПАНЕЛЬ СОДЕРЖАНИЯ", v.name)
    f:SetSize(S(620), S(620))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    UI.text(scroll, "Стадия: " .. v.stageName .. (v.integrity and (" (" .. v.integrity .. "%)") or "") .. (v.breached and " — ОБЪЕКТ ВНЕ КАМЕРЫ" or ""), "SV.Sub", stageColors[v.stage])
    UI.text(scroll, v.played and "Объект активен." or "Объект пассивен (не воплощён игроком): нарушение условий приведёт к инциденту в камере.", "SV.Small", C.dim)
    if v.conditions then
        local card = UI.card(scroll, "Условия содержания")
        for _, c in ipairs(v.conditions) do
            UI.text(card, c.name .. ": " .. (c.text or c.status), "SV.Body", statusColors[c.status])
        end
    else
        UI.text(scroll, "Подробные данные доступны научному отделу, охране, инженерам и МОГ.", "SV.Small", C.dim)
    end
    local procs = UI.card(scroll, "Процедуры")
    for _, p in ipairs(v.procedures) do
        UI.text(procs, p.name .. " (" .. p.duration .. " с)", "SV.Sub")
        UI.text(procs, p.desc, "SV.Small", C.dim)
        local b = UI.button(procs, "Начать", function() Net.call("scp.procedure", ent, p.id) f:Close() end, "primary")
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, S(8))
        if not p.ok then b:SetBlocked(p.reason) end
    end
end)

UI.registerInteraction{
    id = "recapture", name = "Повторное содержание объекта", order = 1,
    visible = function(target) return SCP.of(target) ~= nil and target:GetNW2Bool("sv_scp_breached", false) end,
    action = function(target) Net.call("scp.recapture", target) end,
}

-- The interaction menu is opened with sv_hands; SCP players have none, so a
-- console command is provided for staff holding weapons too.
concommand.Add("sv_interact", function()
    local ent = LocalPlayer():GetEyeTrace().Entity
    if IsValid(ent) and ent:IsPlayer() then UI.openInteraction(ent) end
end)

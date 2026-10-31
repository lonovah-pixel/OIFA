--[[---------------------------------------------------------------------------
Drills (client): HUD objective, results, organiser card in "Комплекс".
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local K = SV.Config.Drills

local reachedAt

Net.on("drill.reached", function(data)
    reachedAt = data.seconds
    UI.notify("Учения: вы успели за " .. data.seconds .. " с.", 0)
end)
Net.on("drill.result", function(data)
    reachedAt = nil
    UI.notify(data.ok and ("Учения засчитаны (" .. data.seconds .. " с).") or "Учения: вы не успели.", data.ok and 0 or 1)
end)

UI.hudElement("drill", 9, function()
    local d = SV.Sync.get("drill", "state")
    if not d then
        reachedAt = nil
        return
    end
    local left = math.max(math.ceil(d.endsAt - CurTime()), 0)
    draw.SimpleText("УЧЕНИЯ: " .. d.name .. " · " .. left .. " с" .. (reachedAt and " · ВЫ НА МЕСТЕ" or ""), "SV.HUDSmall", ScrW() / 2, S(140),
        reachedAt and C.ok or C.warn, TEXT_ALIGN_CENTER)
    if not reachedAt then draw.SimpleText(d.text, "SV.Tiny", ScrW() / 2, S(160), C.text, TEXT_ALIGN_CENTER) end
    if d.pos and not reachedAt then
        local scr = Vector(d.pos[1], d.pos[2], d.pos[3] + 50):ToScreen()
        if scr.visible then draw.SimpleText("◆ Пункт сбора", "SV.Tiny", scr.x, scr.y, C.warn, TEXT_ALIGN_CENTER) end
    end
end)

hook.Add("SiteVeil.FacilityTab", "SiteVeil.Drills", function(scroll)
    local ply = LocalPlayer()
    local allowed = SV.Admin.isOnDuty(ply)
    for _, f in ipairs(K.flags) do if SV.Roles.hasFlag(ply, f) then allowed = true end end
    if not allowed then return end
    local card = UI.card(scroll, "Учения")
    local active = SV.Sync.get("drill", "state")
    if active then
        local b = UI.button(card, "Отменить учения", function() Net.call("drill.cancel") end, "ghost")
        b:Dock(TOP)
        return
    end
    for id, def in SortedPairs(K.kinds) do
        local b = UI.button(card, def.name .. " (" .. def.time .. " с)", function() Net.call("drill.start", id) end)
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, S(4))
    end
    UI.text(card, "Сервер проверит штатный режим, онлайн и перезарядку (" .. math.floor(K.cooldown / 60) .. " мин).", "SV.Tiny", C.faint)
end)

--[[---------------------------------------------------------------------------
Reinforcement waves (client): queue status in the lobby / HUD and the call
button for command staff in the "Комплекс" tab.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local R = SV.Config.Reinforcements

UI.hudElement("reinforcements", 34, function()
    local waves = SV.Sync.get("reinforcements", "waves")
    if not waves then return end
    local y = S(170)
    for kind, w in pairs(waves) do
        if w.pending and (kind == "mtf" or (UI.myChar() and UI.myChar().division == kind)) then
            local left = math.max(math.ceil(w.pending - CurTime()), 0)
            draw.SimpleText(R[kind].name .. ": прибытие через " .. left .. " с", "SV.HUDSmall", S(20), y, C.info)
            y = y + S(20)
        end
    end
end)

hook.Add("SiteVeil.FacilityTab", "SiteVeil.Reinforcements", function(scroll)
    local ply = LocalPlayer()
    if not (SV.Roles.hasFlag(ply, "callReinforcements") or SV.Admin.isOnDuty(ply)) then return end
    local waves = SV.Sync.get("reinforcements", "waves") or {}
    local card = UI.card(scroll, "Подкрепление")
    for kind, cfg in pairs(R) do
        if cfg.called then
            local w = waves[kind] or {queued = 0, active = 0}
            UI.text(card, cfg.name .. ": в очереди " .. w.queued .. ", на объекте " .. w.active, "SV.Small")
            local b = UI.button(card, "Вызвать " .. cfg.name, function() Net.call("reinf.call", kind) end, "primary")
            b:Dock(TOP)
            if w.pending then b:SetBlocked("группа уже в пути")
            elseif w.queued == 0 then b:SetBlocked("нет бойцов в очереди") end
        end
    end
    UI.text(card, "Вызов возможен при нарушении содержания, блокировке сектора или эвакуации; сервер проверит все условия.", "SV.Tiny", C.faint)
end)

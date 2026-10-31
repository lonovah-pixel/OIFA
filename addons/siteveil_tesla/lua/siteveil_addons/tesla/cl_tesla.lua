--[[---------------------------------------------------------------------------
Tesla gates (client): warning near a charging gate, disable card in the
"Комплекс" tab.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local K = SV.Config.Tesla

UI.hudElement("tesla", 36, function(ply)
    for _, ent in ipairs(ents.FindByClass("sv_tesla_gate")) do
        if IsValid(ent) and ent.GetCharging and ent:GetCharging() and ent:GetPos():DistToSqr(ply:GetPos()) < 400 * 400 then
            draw.SimpleText("ТЕСЛА-ВОРОТА: РАЗРЯД!", "SV.Banner", ScrW() / 2, ScrH() * 0.7, C.critical, TEXT_ALIGN_CENTER)
            return
        end
    end
end)

hook.Add("SiteVeil.FacilityTab", "SiteVeil.Tesla", function(scroll)
    local ply = LocalPlayer()
    local allowed = SV.Admin.isOnDuty(ply)
    for _, f in ipairs(K.disableFlags) do if SV.Roles.hasFlag(ply, f) then allowed = true end end
    if not allowed then return end
    local card = UI.card(scroll, "Тесла-ворота")
    local disabled = SV.Sync.get("tesla", "disabled") or {}
    local sectors = SV.Sync.all("sectors")
    local ids = {}
    for id in pairs(sectors) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local row = UI.row(card, S(32))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Small")
        local off = disabled[id] and disabled[id] > CurTime()
        lbl:SetTextColor(off and C.warn or C.text)
        lbl:SetText((sectors[id].name or id) .. (off and (" · отключены ещё " .. math.ceil(disabled[id] - CurTime()) .. " с") or " · активны"))
        local b = UI.button(row, "Отключить на 60 с", function() Net.call("tesla.disable", id, 60) end, "ghost")
        b:Dock(RIGHT)
        b:SetWide(S(180))
        if off then b:SetBlocked("уже отключены") end
    end
    UI.text(card, "Ворота не срабатывают на сотрудников с допуском " .. K.bypass.clearance .. " и зоной «security»; объекты SCP задерживают всегда.", "SV.Tiny", C.faint)
end)

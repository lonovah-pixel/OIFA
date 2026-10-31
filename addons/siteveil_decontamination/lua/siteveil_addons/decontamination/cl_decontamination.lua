--[[---------------------------------------------------------------------------
Sector decontamination (client): countdown and the order card in the
"Комплекс" tab.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local K = SV.Config.Decontamination

UI.hudElement("decon", 7, function()
    local st = SV.Sync.get("decon", "state")
    if not st then return end
    local left = math.max(math.ceil(st.at - CurTime()), 0)
    local here = SV.Sync.get("self", "sector") == st.sector
    local text = st.phase == "warn" and ("ОБЕЗЗАРАЖИВАНИЕ «" .. st.name .. "» ЧЕРЕЗ " .. left .. " С") or ("ИДЁТ ОБЕЗЗАРАЖИВАНИЕ «" .. st.name .. "» · " .. left .. " С")
    draw.SimpleText(text, here and "SV.Banner" or "SV.HUDSmall", ScrW() / 2, here and ScrH() * 0.3 or S(120), here and C.critical or C.warn, TEXT_ALIGN_CENTER)
    if here then
        draw.SimpleText(st.phase == "warn" and "Покиньте сектор или наденьте противогаз / защитный костюм" or "Газ в секторе", "SV.HUDSmall",
            ScrW() / 2, ScrH() * 0.3 + S(44), C.text, TEXT_ALIGN_CENTER)
    end
end)

hook.Add("SiteVeil.FacilityTab", "SiteVeil.Decon", function(scroll)
    local ply = LocalPlayer()
    local allowed = SV.Admin.isOnDuty(ply)
    for _, f in ipairs(K.flags) do if SV.Roles.hasFlag(ply, f) then allowed = true end end
    if not allowed then return end
    local card = UI.card(scroll, "Обеззараживание сектора", C.danger)
    UI.text(card, "Предупреждение " .. K.warnTime .. " с, затем сектор блокируется и заполняется газом на " .. K.duration ..
        " с. Пострадают все без противогаза или защитного костюма.", "SV.Small", C.dim)
    local st = SV.Sync.get("decon", "state")
    local sectors = SV.Sync.all("sectors")
    local ids = {}
    for id in pairs(sectors) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then UI.text(card, "Нет данных о секторах.", "SV.Small", C.dim) end
    for _, id in ipairs(ids) do
        local row = UI.row(card, S(32))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Small")
        lbl:SetTextColor(C.text)
        lbl:SetText(sectors[id].name or id)
        if st and st.sector == id then
            local b = UI.button(row, "Отменить", function()
                UI.confirm("ОТМЕНА ОБЕЗЗАРАЖИВАНИЯ", "Отменить обеззараживание сектора?", function() Net.call("decon.cancel", id) end)
            end, "ghost")
            b:Dock(RIGHT)
            b:SetWide(S(140))
        else
            local b = UI.button(row, "Обеззаразить", function()
                UI.confirm("ОБЕЗЗАРАЖИВАНИЕ", "Сектор «" .. (sectors[id].name or id) .. "» будет заблокирован и заполнен газом. Подтвердите решение.",
                    function() Net.call("decon.start", id) end, "газ")
            end, "danger")
            b:Dock(RIGHT)
            b:SetWide(S(140))
            if st then b:SetBlocked("уже идёт в другом секторе") end
        end
    end
end)

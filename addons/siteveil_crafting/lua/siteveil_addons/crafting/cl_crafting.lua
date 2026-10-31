--[[---------------------------------------------------------------------------
Crafting (client): bench window.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

Net.on("craft.open", function(data)
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    f:SetHeader(string.upper(data.title))
    f:SetSize(S(560), math.min(S(520), ScrH() * 0.8))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    for _, r in ipairs(data.recipes) do
        local card = UI.card(scroll, r.name .. " · " .. r.time .. " с")
        UI.text(card, "Нужно: " .. r.inputs, "SV.Small", C.dim)
        local b = UI.button(card, "Изготовить", function() Net.call("craft.make", ent, r.id) f:Close() end, "primary")
        b:Dock(TOP)
        if r.blocked then b:SetBlocked(r.blocked) end
    end
end)

table.insert(UI.helpSections, {"Мастерская", {
    "Верстаки (E): рецепты зависят от верстака и вашей специальности. Металлолом иногда остаётся после работ класса D.",
    "Отмычка: используйте из инвентаря, глядя на дверь допуска не выше 1. Шумно, может сломаться, оставляет след.",
}})

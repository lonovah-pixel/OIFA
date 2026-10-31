--[[---------------------------------------------------------------------------
Polygraph (client).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

UI.registerInteraction{
    id = "polygraph", name = "Проверка на полиграфе", order = 46,
    visible = function(target) return not SV.Roles.isSCP(target) end,
    action = function(target)
        UI.prompt("ПОЛИГРАФ", "Один вопрос, на который человек отвечает «да» или «нет». Скованных и задержанных проверяют без согласия.",
            "Вопрос", function(q) Net.call("poly.start", target, q) end)
    end,
}

Net.on("poly.consent", function(data)
    UI.choose("ПОЛИГРАФ", data.name .. " просит пройти проверку: «" .. data.question .. "»", {{"Согласиться", true}, {"Отказаться", false}},
        function(v) Net.call("poly.consent", v) end)
end)

Net.on("poly.result", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ПОЛИГРАФ", data.name)
    f:SetSize(S(500), S(220))
    f:Center()
    f:MakePopup()
    UI.text(f, "Вопрос: «" .. data.question .. "»", "SV.Body")
    UI.text(f, "Результат: " .. data.reaction, "SV.Sub", string.find(data.reaction, "выраженная", 1, true) and C.warn or C.ok)
    UI.text(f, "Полиграф ошибается. Результат — повод проверить, а не доказательство.", "SV.Tiny", C.faint)
end)

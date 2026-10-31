--[[---------------------------------------------------------------------------
Notes and notice boards (client).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local K = SV.Config.Notes

function SV.Notes.openEditor()
    local f = vgui.Create("SVFrame")
    f:SetHeader("ЗАПИСКА")
    f:SetSize(S(520), S(340))
    f:Center()
    f:MakePopup()
    UI.text(f, "Записка появится перед вами. Её может прочитать любой; автор для игроков не указывается. Срок — " .. math.floor(K.lifetime / 60) .. " мин.", "SV.Small", C.dim)
    local title = vgui.Create("SVEntry", f)
    title:Dock(TOP)
    title:SetHint("Заголовок (необязательно)")
    local text = vgui.Create("SVEntry", f)
    text:Dock(TOP)
    text:DockMargin(0, S(6), 0, 0)
    text:SetMultiline(true)
    text:SetTall(S(120))
    text:SetHint("Текст (до " .. K.textMax .. " символов)")
    local b = UI.button(f, "Оставить записку", function()
        Net.call("notes.write", title:GetValue(), text:GetValue())
        f:Close()
    end, "primary")
    b:Dock(BOTTOM)
end
concommand.Add("sv_note", function() SV.Notes.openEditor() end)

Net.on("notes.text", function(data)
    local f = vgui.Create("SVFrame")
    f:SetHeader(string.upper(data.title), data.minutes .. " мин назад")
    f:SetSize(S(480), S(320))
    f:Center()
    f:MakePopup()
    UI.text(f, data.text, "SV.Body")
    if data.author then UI.text(f, "Автор (видно администрации): " .. data.author, "SV.Tiny", C.warn) end
    if data.canTake then
        local b = UI.button(f, data.own and "Забрать записку" or "Изъять записку", function() Net.call("notes.take", Entity(data.ent)) f:Close() end, "ghost")
        b:Dock(BOTTOM)
    end
end)

Net.on("board.view", function(data)
    if IsValid(UI.boardFrame) then UI.boardFrame:Remove() end
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    UI.boardFrame = f
    f:SetHeader(string.upper(data.title))
    f:SetSize(S(560), math.min(S(640), ScrH() * 0.85))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    local new = UI.card(scroll, "Новое объявление")
    local entry = vgui.Create("SVEntry", new)
    entry:Dock(TOP)
    entry:SetHint("Текст объявления (подписывается именем персонажа)")
    local post = UI.button(new, "Повесить", function() Net.call("board.post", ent, entry:GetValue()) end, "primary")
    post:Dock(TOP)
    post:DockMargin(0, S(4), 0, 0)
    if not data.canPost then post:SetBlocked("доска другого подразделения") end
    if #data.posts == 0 then UI.text(scroll, "Объявлений нет.", "SV.Small", C.dim) end
    for _, p in ipairs(data.posts) do
        local card = UI.card(scroll, p.author .. (p.division ~= "" and (" · " .. p.division) or "") .. " · " .. p.when)
        UI.text(card, p.text, "SV.Body")
        if p.canRemove then
            local rm = UI.button(card, "Снять", function() Net.call("board.remove", ent, p.id) end, "ghost")
            rm:Dock(TOP)
        end
    end
end)

UI.registerInteraction{
    id = "note", name = "Оставить записку…", order = 98,
    action = function() SV.Notes.openEditor() end,
}

table.insert(UI.helpSections, {"Записки и объявления", {
    "Консоль sv_note или меню взаимодействия → «Оставить записку…». Автор для игроков не указывается.",
    "Доски объявлений: E — читать и повесить своё (подписывается именем персонажа).",
}})

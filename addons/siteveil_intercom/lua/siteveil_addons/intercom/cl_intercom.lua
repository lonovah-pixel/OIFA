--[[---------------------------------------------------------------------------
Intercom (client): terminal window and the "on air" indicator.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

Net.on("intercom.open", function(data)
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ИНТЕРКОМ", "громкая связь комплекса")
    f:SetSize(S(520), S(300))
    f:Center()
    f:MakePopup()
    if data.blocked then UI.text(f, "Сейчас недоступно: " .. data.blocked .. ".", "SV.Small", C.warn) end
    UI.text(f, "Голосовое обращение длится " .. data.voiceTime .. " с; вас слышат все сотрудники. Не отходите от терминала.", "SV.Small", C.dim)
    local voice = UI.button(f, "Выйти в эфир (голос)", function() Net.call("intercom.voice", ent) f:Close() end, "primary")
    voice:Dock(TOP)
    local entry = vgui.Create("SVEntry", f)
    entry:Dock(TOP)
    entry:DockMargin(0, S(8), 0, 0)
    entry:SetHint("Текстовое обращение (до " .. data.textMax .. " символов)")
    local text = UI.button(f, "Передать текст", function() Net.call("intercom.text", ent, entry:GetValue()) f:Close() end)
    text:Dock(TOP)
    text:DockMargin(0, S(4), 0, 0)
    if data.blocked then
        voice:SetBlocked(data.blocked)
        text:SetBlocked(data.blocked)
    end
end)

UI.hudElement("intercom", 35, function(ply)
    local air = SV.Sync.get("intercom", "air")
    if not air then return end
    local left = math.max(math.ceil(air.untilTime - CurTime()), 0)
    local mine = air.name == SV.Chars.displayName(ply)
    draw.SimpleText((mine and "ВЫ В ЭФИРЕ" or ("ИНТЕРКОМ: " .. air.name)) .. " · " .. left .. " с", "SV.HUDSmall", ScrW() / 2, S(96),
        mine and C.danger or C.info, TEXT_ALIGN_CENTER)
end)

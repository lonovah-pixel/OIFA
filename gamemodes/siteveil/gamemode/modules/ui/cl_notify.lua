--[[---------------------------------------------------------------------------
Notifications. Receives DarkRP's "_Notify" user message (DarkRP.notify on
the server) because DarkRP's own HUD module, which normally displays it, is
disabled. Also used directly by client code through UI.notify().

Types follow DarkRP/sandbox: 0 info, 1 error, 2 undo, 3 hint, 4 cleanup.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S

UI.toasts = UI.toasts or {}
local MAX_TOASTS = 6

local typeColors = {
    [0] = C.accent, [1] = C.danger, [2] = C.dim, [3] = C.warn, [4] = C.ok,
}

function UI.notify(text, kind, length)
    kind = kind or 0
    table.insert(UI.toasts, 1, {text = tostring(text), kind = kind, born = RealTime(), life = math.Clamp(length or 5, 2, 15)})
    while #UI.toasts > MAX_TOASTS do table.remove(UI.toasts) end
    MsgC(Color(79, 163, 217), "[SITE-VEIL] ", color_white, tostring(text), "\n")
end

usermessage.Hook("_Notify", function(msg)
    local text = msg:ReadString()
    local kind = msg:ReadShort()
    local len = msg:ReadLong()
    UI.notify(text, kind, len)
    surface.PlaySound(kind == 1 and SV.Config.Sounds.denied or SV.Config.Sounds.notify)
end)

-- GAMEMODE:AddNotify is used by sandbox tools (undo, cleanup).
function GM:AddNotify(text, kind, length)
    UI.notify(text, kind, length)
end

function UI.drawToasts()
    local now = RealTime()
    local width = S(420)
    local x = ScrW() - width - S(20)
    local y = S(120)
    for i = #UI.toasts, 1, -1 do
        local t = UI.toasts[i]
        if now - t.born > t.life then table.remove(UI.toasts, i) end
    end
    for _, t in ipairs(UI.toasts) do
        local lines = UI.wrap("SV.Small", t.text, width - S(24))
        local h = #lines * S(18) + S(14)
        local age = now - t.born
        local alpha = math.Clamp(math.min(age * 6, (t.life - age) * 2), 0, 1)
        surface.SetAlphaMultiplier(alpha)
        UI.drawPanel(x, y, width, h, C.panel)
        UI.drawAccent(x, y, h, typeColors[t.kind] or C.accent)
        for j, line in ipairs(lines) do
            draw.SimpleText(line, "SV.Small", x + S(14), y + S(7) + (j - 1) * S(18), C.text)
        end
        surface.SetAlphaMultiplier(1)
        y = y + h + S(6)
    end
end

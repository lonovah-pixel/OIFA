--[[---------------------------------------------------------------------------
UI theme: palette, scaling and fonts of the facility information system.

Scale = screen height / 1080, clamped to [0.75, 2], multiplied by the user's
sv_ui_scale convar. Fonts are rebuilt when the resolution changes.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.UI = SV.UI or {}
local UI = SV.UI

local scaleConvar = CreateClientConVar("sv_ui_scale", "1", true, false, "SITE-VEIL: масштаб интерфейса (0.7 - 1.5)", 0.7, 1.5)

UI.Colors = {
    bg = Color(11, 14, 18, 245),
    panel = Color(20, 25, 32, 240),
    panel2 = Color(27, 33, 42, 245),
    panelHover = Color(34, 42, 54, 245),
    border = Color(46, 56, 70),
    text = Color(214, 221, 230),
    dim = Color(138, 150, 166),
    faint = Color(92, 102, 116),
    accent = Color(79, 163, 217),
    ok = Color(76, 175, 122),
    warn = Color(224, 176, 64),
    danger = Color(217, 83, 79),
    critical = Color(179, 38, 30),
    info = Color(110, 150, 220),
    disabled = Color(60, 66, 76),
    black = Color(0, 0, 0, 230),
}

-- Facility state colours (modules/facility).
UI.StateColors = {
    normal = UI.Colors.ok,
    alert = UI.Colors.warn,
    breach = UI.Colors.critical,
    evacuation = Color(196, 70, 160),
    recovery = UI.Colors.info,
    lockdown = Color(230, 120, 40),
}

function UI.scaleFactor()
    return math.Clamp(ScrH() / 1080, 0.75, 2) * math.Clamp(scaleConvar:GetFloat(), 0.7, 1.5)
end

function UI.S(px)
    return math.max(1, math.Round(px * UI.scaleFactor()))
end

local FONT = "Roboto"
local MONO = "Consolas"

local function makeFonts()
    local s = UI.scaleFactor()
    local function f(name, size, weight, font)
        surface.CreateFont(name, {font = font or FONT, size = math.max(10, math.Round(size * s)), weight = weight or 500, antialias = true, extended = true})
    end
    f("SV.Title", 30, 700)
    f("SV.Header", 22, 600)
    f("SV.Sub", 19, 600)
    f("SV.Body", 18, 400)
    f("SV.Small", 15, 400)
    f("SV.Tiny", 13, 400)
    f("SV.Mono", 16, 400, MONO)
    f("SV.HUDBig", 26, 700)
    f("SV.HUD", 18, 500)
    f("SV.HUDSmall", 15, 500)
    f("SV.Banner", 24, 800)
    UI.fontsBuiltFor = ScrW() .. "x" .. ScrH() .. "@" .. s
end

makeFonts()

hook.Add("OnScreenSizeChanged", "SiteVeil.UI.Fonts", function()
    makeFonts()
    hook.Run("SiteVeil.UIRescaled")
end)

cvars.AddChangeCallback("sv_ui_scale", function()
    timer.Simple(0, function()
        makeFonts()
        hook.Run("SiteVeil.UIRescaled")
    end)
end, "SiteVeil.UI")

--- Draws a flat panel with a 1px border.
function UI.drawPanel(x, y, w, h, col, border)
    surface.SetDrawColor(col or UI.Colors.panel)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(border or UI.Colors.border)
    surface.DrawOutlinedRect(x, y, w, h)
end

--- Thin left accent strip used for status rows.
function UI.drawAccent(x, y, h, col)
    surface.SetDrawColor(col)
    surface.DrawRect(x, y, UI.S(3), h)
end

function UI.textSize(font, text)
    surface.SetFont(font)
    return surface.GetTextSize(text)
end

--- Wraps text to a pixel width. Returns list of lines (UTF-8 safe, by words).
function UI.wrap(font, text, width)
    surface.SetFont(font)
    local lines = {}
    for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
        local line = ""
        for word in string.gmatch(paragraph, "%S+") do
            local candidate = line == "" and word or (line .. " " .. word)
            if surface.GetTextSize(candidate) > width and line ~= "" then
                lines[#lines + 1] = line
                line = word
            else
                line = candidate
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

function UI.divisionColor(divId)
    local div = divId and SV.Roles.getDivision(divId)
    return div and div.color or UI.Colors.dim
end

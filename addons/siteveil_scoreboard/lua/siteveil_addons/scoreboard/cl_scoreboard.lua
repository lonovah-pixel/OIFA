--[[---------------------------------------------------------------------------
Scoreboard (client). Replaces the FAdmin/DarkRP scoreboard on TAB; the
FAdmin menu stays available through the +FAdmin_menu bind.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Scoreboard = SV.Scoreboard

local GROUP_LOBBY, GROUP_UNKNOWN = "_lobby", "_unknown"

--- Rows grouped by division in division order, then strangers, then lobby.
function Scoreboard.groups()
    local me = LocalPlayer()
    local byGroup = {}
    for _, p in ipairs(player.GetAll()) do
        local row = Scoreboard.row(me, p)
        byGroup[row.group] = byGroup[row.group] or {}
        table.insert(byGroup[row.group], row)
    end
    local out = {}
    for _, div in ipairs(SV.Roles.divisions) do
        if byGroup[div.id] then out[#out + 1] = {name = div.name, color = div.color, rows = byGroup[div.id]} end
    end
    if byGroup[GROUP_UNKNOWN] then out[#out + 1] = {name = "Посторонние", color = C.faint, rows = byGroup[GROUP_UNKNOWN]} end
    if byGroup[GROUP_LOBBY] then out[#out + 1] = {name = "На экране персонажей", color = C.dim, rows = byGroup[GROUP_LOBBY]} end
    for _, g in ipairs(out) do table.sort(g.rows, function(a, b) return (a.name or "") < (b.name or "") end) end
    return out
end

local function build(f)
    if IsValid(f.body) then f.body:Remove() end
    f.body = vgui.Create("DPanel", f)
    f.body:Dock(FILL)
    f.body:SetPaintBackground(false)
    local scroll = UI.scroll(f.body)
    local total = #player.GetAll()
    f:SetHeader(SV.Config.ServerName or "SITE-VEIL", "на объекте: " .. total)
    for _, g in ipairs(Scoreboard.groups()) do
        local card = UI.card(scroll, g.name .. " · " .. #g.rows, g.color)
        for _, r in ipairs(g.rows) do
            local parts = {r.name}
            if r.number then parts[#parts + 1] = "№ " .. r.number end
            if r.rank and r.rank ~= "—" then parts[#parts + 1] = r.rank end
            if r.role then parts[#parts + 1] = r.role end
            if r.steam then parts[#parts + 1] = "(" .. r.steam .. ", " .. r.sid .. ")" end
            if r.duty then parts[#parts + 1] = "[дежурный администратор]" end
            UI.text(card, table.concat(parts, " · ") .. "   " .. r.ping .. " мс", "SV.Small", r.duty and C.warn or (r.hidden and C.faint or C.text))
        end
    end
end

function GM:ScoreboardShow()
    if IsValid(UI.scoreboard) then UI.scoreboard:Remove() end
    local f = vgui.Create("SVFrame")
    UI.scoreboard = f
    f:SetSize(math.min(S(760), ScrW() - 40), math.min(S(720), ScrH() - 80))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    build(f)
    f.nextRefresh = RealTime() + SV.Config.Scoreboard.refresh
    f.Think = function(panel)
        if RealTime() >= panel.nextRefresh then
            panel.nextRefresh = RealTime() + SV.Config.Scoreboard.refresh
            build(panel)
        end
    end
    return true
end

function GM:ScoreboardHide()
    if IsValid(UI.scoreboard) then UI.scoreboard:Remove() end
    return true
end

-- FAdmin's scoreboard hook would otherwise take TAB.
local function removeFAdmin()
    hook.Remove("ScoreboardShow", "FAdmin_scoreboard")
    hook.Remove("ScoreboardHide", "FAdmin_scoreboard")
end
removeFAdmin()
hook.Add("InitPostEntity", "SiteVeil.Scoreboard", removeFAdmin)

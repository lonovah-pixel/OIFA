--[[---------------------------------------------------------------------------
Scoreboard (shared): what the scoreboard shows to whom.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Scoreboard = SV.Scoreboard or {}
local Scoreboard = SV.Scoreboard

SV.Config.Scoreboard = {
    hiddenDivisions = {chaos = true},  -- shown as "Посторонние" without names to other players
    refresh = 1,
}

--- Row for `target` as seen by `viewer` (pure function of networked vars).
function Scoreboard.row(viewer, target)
    local div = target:getDarkRPVar("sv_div")
    local admin = viewer:IsAdmin()
    local row = {ping = target:Ping(), steam = admin and target:SteamName() or nil, sid = admin and target:SteamID() or nil,
        duty = SV.Admin.isOnDuty(target)}
    if not div then
        row.group, row.name = "_lobby", target:SteamName()
        return row
    end
    local viewerDiv = viewer:getDarkRPVar("sv_div")
    if SV.Config.Scoreboard.hiddenDivisions[div] and not admin and viewerDiv ~= div then
        row.group, row.name, row.hidden = "_unknown", "Неизвестный", true
        return row
    end
    row.group = div
    row.name = target:getDarkRPVar("rpname") or target:Nick()
    row.number = target:getDarkRPVar("sv_num")
    row.rank = SV.Roles.rankName(div, target:getDarkRPVar("sv_rank"))
    row.role = target:getDarkRPVar("job")
    return row
end

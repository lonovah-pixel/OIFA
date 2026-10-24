--[[---------------------------------------------------------------------------
Terminals (server). A terminal entity (sv_terminal) has a kind; the kind's
module registers the screen with Facility.registerTerminal. Using a terminal
requires sector power, the kind's access requirement and proximity; every
use is logged (access log + terminal event for investigations).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local U = SV.Util

SV.Terminals = SV.Terminals or {}
local Terminals = SV.Terminals

function Terminals.key(ent)
    local p = ent.SVPoint
    return "term:" .. (p and p.id or tostring(ent:EntIndex()))
end

--- Validates terminal use. Notifies the player on failure.
function Terminals.canUse(ply, ent, kind, silent)
    local function fail(msg)
        if not silent then DarkRP.notify(ply, 1, 4, msg) end
        return false, msg
    end
    if not IsValid(ent) or ent:GetClass() ~= "sv_terminal" then return fail("Терминал не найден.") end
    if kind and ent:GetTerminalKind() ~= kind then return fail("Это терминал другого типа.") end
    local def = Facility.terminals[ent:GetTerminalKind()]
    if not def then return fail("Терминал не настроен.") end
    if not U.within(ply, ent, 130) then return fail("Подойдите к терминалу.") end
    if not ply.SVChar then return fail("Нет персонажа.") end
    local sector = Facility.sectorAt(ent:GetPos())
    if Facility.power(sector) < (def.power or 0.5) then return fail("Терминал обесточен.") end
    local admin = SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply)
    local point = ent.SVPoint
    local req = point and point.props.clearance and {clearance = tonumber(point.props.clearance), tags = point.props.tags} or def.req
    if not admin then
        local ok, reason = SV.Access.check(ply, req)
        if not ok then return fail("Доступ к терминалу запрещён: " .. tostring(reason)) end
    end
    return true
end

function Terminals.use(ply, ent)
    local kind = ent:GetTerminalKind()
    local def = Facility.terminals[kind]
    local ok, reason = Terminals.canUse(ply, ent, nil)
    local sector = Facility.sectorAt(ent:GetPos())
    local serial = SV.Access.credentials(ply).serials[1]
    SV.Access.logEntry(Terminals.key(ent), ply, ok, reason, serial, sector, "terminal")
    if not ok then return end
    SV.Bus.emit("terminal.used", {ply = ply, ent = ent, kind = kind, sector = sector})
    def.open(ply, ent)
end

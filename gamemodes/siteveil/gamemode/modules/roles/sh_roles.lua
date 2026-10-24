--[[---------------------------------------------------------------------------
Role and division registry (shared, boot stage).

Indexes config/sh_roles.lua. Pure data helpers only: this file runs before
DarkRP is loaded, so it must not call DarkRP functions.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

SV.Roles = SV.Roles or {}
local Roles = SV.Roles

Roles.list = {}
Roles.byId = {}
Roles.byTeam = {}
Roles.divisions = {}
Roles.divisionById = {}

for i, div in ipairs(C.Divisions) do
    div.index = i
    div.roles = {}
    Roles.divisions[i] = div
    Roles.divisionById[div.id] = div
end

for i, role in ipairs(C.Roles) do
    assert(isstring(role.id), "role without id at index " .. i)
    assert(not Roles.byId[role.id], "duplicate role id " .. role.id)

    role.index = i
    role.flags = role.flags or {}
    role.tags = role.tags or {}
    role.kit = role.kit or {}
    role.weapons = role.weapons or {}
    role.duties = role.duties or {}
    role.alarm = role.alarm or {}
    role.minRank = role.minRank or 1
    role.clearance = role.clearance or 0

    if role.division then
        local div = Roles.divisionById[role.division]
        assert(div, "role " .. role.id .. " references unknown division " .. tostring(role.division))
        table.insert(div.roles, role)
    end

    Roles.list[i] = role
    Roles.byId[role.id] = role
end

for _, div in ipairs(Roles.divisions) do
    if div.defaultRole then
        assert(Roles.byId[div.defaultRole], "division " .. div.id .. " has unknown default role " .. div.defaultRole)
    end
end

function Roles.get(id)
    return Roles.byId[id]
end

function Roles.getDivision(id)
    return Roles.divisionById[id]
end

--- Role of a player, resolved through the DarkRP team (the team is the
--- networked representation of the role).
function Roles.ofPlayer(ply)
    if not IsValid(ply) then return nil end
    return Roles.byTeam[ply:Team()]
end

function Roles.hasFlag(ply, flag)
    local role = Roles.ofPlayer(ply)
    return role ~= nil and role.flags[flag] == true
end

function Roles.rankName(divisionId, rank)
    local div = Roles.divisionById[divisionId]
    if not div then return "—" end
    return div.ranks[math.Clamp(rank or 1, 1, #div.ranks)] or "—"
end

function Roles.maxRank(divisionId)
    local div = Roles.divisionById[divisionId]
    return div and #div.ranks or 1
end

--- Number of slots for a role at the given population. nil = unlimited.
function Roles.quotaFor(role, online)
    local q = role.quota
    if not q then return nil end
    if q.minOnline and online < q.minOnline then return 0 end
    local slots = (q.base or 0) + math.floor(online / math.max(q.per or 1, 1))
    if q.max then slots = math.min(slots, q.max) end
    return math.max(slots, 0)
end

function Roles.isSCP(ply)
    return Roles.hasFlag(ply, "scp")
end

function Roles.isLobby(ply)
    local role = Roles.ofPlayer(ply)
    return role == nil or role.id == C.LobbyRole
end

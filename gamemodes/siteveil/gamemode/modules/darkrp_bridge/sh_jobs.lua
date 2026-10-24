--[[---------------------------------------------------------------------------
Role -> DarkRP job generation (shared, boot stage; executed from the
"DarkRPFinishedLoading" hook, i.e. after DarkRP's modules, before DarkRP merges
categories).

Each SITE-VEIL role becomes exactly one DarkRP job. The DarkRP team number is
the networked representation of the role (SiteVeil.Roles.byTeam). Jobs are
created with max = 0, salary = 0 and vote = false: quotas, salaries and votes
are not DarkRP's responsibility in SITE-VEIL. Job change is only possible
through modules/characters (see playerCanChangeTeam in sv_gate.lua).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Bridge = SV.DarkRP
local Roles = SV.Roles

local SERVICE_CATEGORY = "Служебное"

local function jobCommand(role)
    return "sv_role_" .. role.id
end
Bridge.jobCommand = jobCommand

function Bridge.createJobs()
    if Bridge.jobsCreated then return end

    -- Categories: one per division plus a hidden service category.
    DarkRP.createCategory{
        name = SERVICE_CATEGORY,
        categorises = "jobs",
        startExpanded = false,
        color = Color(80, 80, 80),
        canSee = function() return false end,
        sortOrder = 1000,
    }
    for i, div in ipairs(Roles.divisions) do
        DarkRP.createCategory{
            name = div.name,
            categorises = "jobs",
            startExpanded = true,
            color = div.color,
            sortOrder = i,
        }
    end

    for i, role in ipairs(Roles.list) do
        local div = role.division and Roles.getDivision(role.division)
        local teamId = DarkRP.createJob(role.name, {
            color = div and div.color or Color(120, 120, 120),
            model = role.models,
            description = role.description,
            weapons = role.weapons,
            command = jobCommand(role),
            max = 0,
            salary = 0,
            admin = 0,
            vote = false,
            hasLicense = false,
            candemote = false,
            medic = role.flags.medic == true,
            category = div and div.name or SERVICE_CATEGORY,
            sortOrder = i,
            siteVeilRole = role.id,
        })

        if not teamId then
            error("SITE-VEIL: DarkRP refused to create job for role " .. role.id)
        end

        role.team = teamId
        Roles.byTeam[teamId] = role
    end

    local lobby = Roles.get(SV.Config.LobbyRole)
    local gm = GM or GAMEMODE
    gm.DefaultTeam = lobby.team
    Bridge.lobbyTeam = lobby.team
    Bridge.jobsCreated = true
end

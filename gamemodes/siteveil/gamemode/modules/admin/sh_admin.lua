--[[---------------------------------------------------------------------------
Administration (shared): privileges, duty state, network schema.

Privileges are registered with CAMI so that any admin mod (FAdmin, ULX, SAM,
...) can grant them; the check is server-side for every action.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Admin = SV.Admin or {}
local Admin = SV.Admin
local Net = SV.Net

Admin.privileges = {
    SiteVeil_Admin = "admin",          -- duty mode, players, tickets, director, logs
    SiteVeil_Whitelist = "admin",      -- whitelist and role management
    SiteVeil_MapConfig = "superadmin", -- map configuration tool
    SiteVeil_Diagnostics = "admin",    -- performance report
}

for name, min in pairs(Admin.privileges) do
    CAMI.RegisterPrivilege({Name = name, MinAccess = min, Description = "SITE-VEIL"})
end

--- Synchronous privilege check through CAMI usergroup inheritance.
function Admin.can(ply, priv)
    if not IsValid(ply) then return true end -- server console
    local min = Admin.privileges[priv] or "superadmin"
    local group = ply:GetUserGroup()
    if min == "admin" and ply:IsAdmin() then return true end
    if min == "superadmin" and ply:IsSuperAdmin() then return true end
    return CAMI.UsergroupInherits(group, min) == true
end

function Admin.isOnDuty(ply)
    return IsValid(ply) and ply:GetNW2Bool("sv_admin_duty", false) and ply:IsAdmin()
end

Net.define("admin.duty", {args = {}, allowNoChar = true, ignoreStates = true, rate = {burst = 2, refill = 0.2}})
Net.define("admin.status", {args = {}, allowNoChar = true, ignoreStates = true, admin = true, rate = {burst = 3, refill = 0.5}})
Net.define("mapcfg.get", {args = {}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 3, refill = 0.5}})
Net.define("mapcfg.addPoint", {args = {"str:24", "json:1024", "bool"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 6, refill = 2}})
Net.define("mapcfg.removePoint", {args = {"str:48"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 6, refill = 2}})
Net.define("mapcfg.addZone", {args = {"str:24", "str:32", "str:64", "json:1024"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 6, refill = 2}})
Net.define("mapcfg.addBox", {args = {"str:32"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 6, refill = 2}})
Net.define("mapcfg.removeZone", {args = {"str:32"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 6, refill = 2}})
Net.define("mapcfg.setDoor", {args = {"ent", "json:1024"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 6, refill = 2}})
Net.define("mapcfg.removeDoor", {args = {"ent"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 6, refill = 2}})
Net.define("mapcfg.command", {args = {"str:16"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 3, refill = 0.5}})
Net.define("mapcfg.corner", {args = {"u8"}, allowNoChar = true, ignoreStates = true, admin = "superadmin", rate = {burst = 10, refill = 4}})

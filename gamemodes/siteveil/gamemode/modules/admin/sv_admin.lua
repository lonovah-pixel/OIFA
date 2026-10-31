--[[---------------------------------------------------------------------------
Administration (server): duty mode and server status.

Duty mode ("/adminduty"): administrators act out of character with god mode,
noclip, physgun/toolgun and full access. Every toggle is audited. Admin
powers outside duty are limited to what their character's role grants.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Admin = SV.Admin
local Net = SV.Net
local Bridge = SV.DarkRP

Admin.dutyTools = {"weapon_physgun", "gmod_tool"}

function Admin.setDuty(ply, on)
    if not ply:IsAdmin() then return false, "Режим администратора доступен только администраторам." end
    if on == Admin.isOnDuty(ply) then return true end
    ply:SetNW2Bool("sv_admin_duty", on)
    if on then
        ply:GodEnable()
        for _, w in ipairs(Admin.dutyTools) do
            ply.SVGivingWeapon = w
            ply:Give(w)
            ply.SVGivingWeapon = nil
        end
        if Admin.can(ply, "SiteVeil_MapConfig") then
            ply.SVGivingWeapon = "sv_mapper"
            ply:Give("sv_mapper")
            ply.SVGivingWeapon = nil
        end
    else
        ply:GodDisable()
        for _, w in ipairs(Admin.dutyTools) do ply:StripWeapon(w) end
        ply:StripWeapon("sv_mapper")
        if ply:GetMoveType() == MOVETYPE_NOCLIP then ply:SetMoveType(MOVETYPE_WALK) end
        if not ply.SVChar then SV.Chars.enterLobby(ply) end
    end
    if SV.Access then SV.Access.invalidate(ply) end
    SV.Audit.log("admin", on and "duty.on" or "duty.off", ply)
    for _, p in ipairs(player.GetAll()) do
        if p:IsAdmin() then DarkRP.notify(p, 0, 4, ply:SteamName() .. (on and " заступил на дежурство администратора." or " завершил дежурство администратора.")) end
    end
    return true
end

Bridge.chatCommand({command = "adminduty", description = "Режим дежурного администратора.", delay = 2}, function(ply)
    local ok, msg = Admin.setDuty(ply, not Admin.isOnDuty(ply))
    if msg then DarkRP.notify(ply, ok and 0 or 1, 4, msg) end
    return ""
end)

Net.handle("admin.duty", function(ply)
    return Admin.setDuty(ply, not Admin.isOnDuty(ply))
end)

function GM:PlayerNoClip(ply, desired)
    if not desired then return true end
    return Admin.isOnDuty(ply)
end

-- Admins on duty in the lobby are visible and can move.
hook.Add("PlayerSpawn", "SiteVeil.Admin.Duty", function(ply)
    if Admin.isOnDuty(ply) then
        timer.Simple(0, function()
            if not IsValid(ply) or not Admin.isOnDuty(ply) then return end
            if not ply.SVChar then SV.Chars.leaveLobby(ply) end
            ply:GodEnable()
            for _, w in ipairs(Admin.dutyTools) do
                ply.SVGivingWeapon = w
                ply:Give(w)
                ply.SVGivingWeapon = nil
            end
        end)
    end
end)

--- Server status for the admin panel.
function Admin.status()
    local perf = SV.Perf.report()
    return {
        version = SV.Version,
        loaderErrors = SV.Loader.errors,
        addons = SV.Addons.describe(),
        mapSource = SV.MapCfg.source,
        mapReport = SV.MapCfg.report,
        darkrpVerified = Bridge.verified,
        db = {ready = SV.DB.ready, failed = SV.DB.failed, queries = SV.DB.stats.queries, errors = SV.DB.stats.errors,
            slowestMs = math.Round(SV.DB.stats.slowest * 1000, 2)},
        perf = perf,
        recentLog = SV.Log.recent,
        shift = SV.Shift.id,
        state = SV.Facility and SV.Facility.state.id or "normal",
    }
end

Net.handle("admin.status", function(ply)
    if not Admin.can(ply, "SiteVeil_Admin") then return false, "Нет прав." end
    Net.send(ply, "admin.status", Admin.status())
end)

--[[---------------------------------------------------------------------------
Alarm lights (server): one tick for all lamps, the mode is networked on the
entity. Lamps without sector power stay dark.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Alarms = SV.Alarms
local Facility = SV.Facility
local K = SV.Config.Alarms

SV.MapCfg.editorProps.alarm = {sector = true}

Alarms.lamps = Alarms.lamps or {}
function Alarms.register(ent) Alarms.lamps[ent] = true end
function Alarms.unregister(ent) Alarms.lamps[ent] = nil end

--- Mode of a sector: decon > evac > breach > lockdown > alert > "".
function Alarms.modeFor(sector)
    if Facility.power(sector) < 0.3 then return "" end
    if SV.Decon and SV.Decon.active and SV.Decon.active.sector == sector then return "decon" end
    local st = Facility.stateId()
    if st == "evacuation" then return "evac" end
    if st == "breach" then return "breach" end
    if Facility.isLockedDown(sector) then return "lockdown" end
    if Facility.hasAlert(sector) then return "alert" end
    return ""
end

timer.Create("SiteVeil.Alarms", K.tick, 0, function()
    for ent in pairs(Alarms.lamps) do
        if IsValid(ent) then
            local p = ent.SVPoint
            local mode = Alarms.modeFor(p and p.props.sector or Facility.sectorAt(ent:GetPos()))
            if ent:GetMode() ~= mode then ent:SetMode(mode) end
        else
            Alarms.lamps[ent] = nil
        end
    end
end)

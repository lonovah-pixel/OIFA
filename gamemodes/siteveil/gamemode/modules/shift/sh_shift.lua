--[[---------------------------------------------------------------------------
Shift cycle (смена). A shift is a fixed length period used for quotas,
reward caps, budget allocation and task limits. The shift counter is
persistent so caps survive restarts within the same shift.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Shift = SV.Shift or {id = 0, startedAt = 0, endsAt = 0}
local Shift = SV.Shift

SV.Sync.define("shift", {scope = "global"})

if CLIENT then
    function Shift.remaining()
        local endsAt = SV.Sync.get("shift", "endsAt")
        return endsAt and math.max(endsAt - os.time(), 0) or 0
    end
end

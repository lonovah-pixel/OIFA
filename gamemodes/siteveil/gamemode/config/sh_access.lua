--[[---------------------------------------------------------------------------
Access control configuration (shared).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Access = {
    autoClose = 6,
    emergencyOpenTime = 10,
    emergencyCooldown = 30,
    crankTime = 6,
    crankOpenTime = 15,
    passMaxMinutes = 30,
    passMaxClearance = 3,
    logSize = 40,
    logTimePrecision = 5,      -- minutes; game logs are rounded, the audit log is exact
    useThrottle = 0.4,
}

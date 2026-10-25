--[[---------------------------------------------------------------------------
Medicine (shared): network schema and status helpers.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Medical = SV.Medical or {}
local Medical = SV.Medical

function Medical.isDown(ply)
    return ply:GetNW2Bool("sv_down", false)
end

Medical.bleedNames = {[0] = "нет", "слабое", "умеренное", "сильное", "массивное"}

function Medical.bleedLevel(bleed)
    if bleed <= 0 then return 0 end
    if bleed <= 1 then return 1 end
    if bleed <= 3 then return 2 end
    if bleed <= 6 then return 3 end
    return 4
end

SV.Net.define("med.examine", {args = {"ent"}, alive = true, rate = {burst = 3, refill = 0.5}})
SV.Net.define("med.treat", {args = {"ent", "str:24"}, alive = true, rate = {burst = 3, refill = 0.5}})
SV.Net.define("med.giveup", {args = {}, ignoreStates = true, rate = {burst = 1, refill = 0.1}})

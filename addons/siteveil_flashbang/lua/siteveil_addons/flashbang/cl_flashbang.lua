--[[---------------------------------------------------------------------------
Flashbang (client): ringing overlay while blinded.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local flashUntil = 0

SV.Net.on("flash.effect", function(data)
    flashUntil = CurTime() + (data.duration or 2)
end)

UI.hudElement("flashbang", 1, function()
    local left = flashUntil - CurTime()
    if left <= 0 then return end
    surface.SetDrawColor(255, 255, 255, math.Clamp(left * 60, 0, 230))
    surface.DrawRect(0, 0, ScrW(), ScrH())
end)

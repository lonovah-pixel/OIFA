--[[---------------------------------------------------------------------------
Communication (shared): radio channel lookup and network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Comms = SV.Comms or {}
local Comms = SV.Comms
local C = SV.Config

Comms.channels = {}
for i, ch in ipairs(C.Radio.channels) do
    ch.index = i
    ch.item = ch.item or "radio"
    Comms.channels[ch.id] = ch
end

--- Whether a role/division may use a channel (radio item checked separately).
function Comms.roleAllowed(ch, role, divisionId)
    if not role then return false end
    if ch.divisions and divisionId and SV.Util.contains(ch.divisions, divisionId) then return true end
    if ch.flags then
        for _, f in ipairs(ch.flags) do
            if role.flags[f] then return true end
        end
    end
    return ch.divisions == nil and ch.flags == nil
end

SV.Net.define("comms.channel", {args = {"str:16"}, rate = {burst = 4, refill = 1}})
SV.Net.define("comms.listen", {args = {"str:16", "bool"}, rate = {burst = 6, refill = 2}})
SV.Net.define("comms.ptt", {args = {"bool"}, rate = {burst = 10, refill = 4}, rateMessage = false})
SV.Net.define("comms.ticket", {args = {"str:300"}, allowNoChar = true, rate = {burst = 1, refill = 0.02}})

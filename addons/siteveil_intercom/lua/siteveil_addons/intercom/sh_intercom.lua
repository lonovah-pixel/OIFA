--[[---------------------------------------------------------------------------
Intercom (shared): configuration, terminal kind, network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Intercom = SV.Intercom or {}
local Net = SV.Net

SV.Config.Intercom = {
    voiceTime = 20,          -- seconds on air
    cooldown = 120,          -- facility-wide pause between two broadcasts
    personalCooldown = 300,  -- the same player
    stayRadius = 120,        -- the speaker must stay at the terminal
    textMax = 200,
    clearance = 2,           -- minimal card clearance (terminal requirement)
    tags = {"administration", "security", "science"},
}

SV.MapCfg.terminalKinds.intercom = "Интерком"
SV.Sync.define("intercom", {scope = "global"})

Net.define("intercom.voice", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("intercom.text", {args = {"ent", "str:200"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("intercom.stop", {args = {}, rate = {burst = 3, refill = 0.5}})

--[[---------------------------------------------------------------------------
Drills (shared): configuration and network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Drills = SV.Drills or {}

SV.Config.Drills = {
    kinds = {
        evac = {name = "Учебная эвакуация", time = 180, text = "Пройдите к шлюзу эвакуации."},
        muster = {name = "Учебный сбор", time = 120, radius = 260, text = "Соберитесь у указанного поста."},
    },
    cooldown = 3600,
    minOnline = 6,
    flags = {"declareAlert"},
    xp = 10,
    leaderXP = 15,             -- the organiser, if at least half made it
}

SV.Sync.define("drill", {scope = "global"})
SV.Net.define("drill.start", {args = {"str:8"}, alive = true, rate = {burst = 2, refill = 0.05}})
SV.Net.define("drill.cancel", {args = {}, rate = {burst = 2, refill = 0.2}})

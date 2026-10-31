--[[---------------------------------------------------------------------------
CCTV (shared): configuration, map kinds, network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Cctv = SV.Cctv or {}
local Net = SV.Net

SV.Config.Cctv = {
    stayRadius = 100,         -- the viewer must stay at the monitor
    fov = 0.6,                -- cos of half the camera's field of view
    range = 2500,
    tick = 0.25,
    tags = {"security", "administration", "science", "engineering"},
    clearance = 1,
}

SV.MapCfg.pointKinds.camera = {name = "Камера наблюдения", entity = "sv_cctv_camera"}
SV.MapCfg.terminalKinds.cctv = "Пост видеонаблюдения"

Net.define("cctv.view", {args = {"ent", "u8"}, alive = true, rate = {burst = 8, refill = 2}})
Net.define("cctv.stop", {args = {}, rate = {burst = 4, refill = 1}})

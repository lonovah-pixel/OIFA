--[[---------------------------------------------------------------------------
Notes and notice boards (shared): configuration, map kind, network schema.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Notes = SV.Notes or {}
local Net = SV.Net

SV.Config.Notes = {
    titleMax = 40,
    textMax = 300,
    perCharacter = 3,         -- notes in the world at once
    worldMax = 60,
    lifetime = 1800,
    writeCooldown = 30,
    boardPostMax = 200,
    boardPostsPerCharacter = 2,
    boardMax = 20,            -- posts per board
    boardLifetime = 7200,
}

SV.MapCfg.pointKinds.board = {name = "Доска объявлений", entity = "sv_notice_board"}

Net.define("notes.write", {args = {"str:40", "str:300"}, alive = true, rate = {burst = 2, refill = 0.05}})
Net.define("notes.read", {args = {"ent"}, rate = {burst = 4, refill = 1}})
Net.define("notes.take", {args = {"ent"}, alive = true, rate = {burst = 3, refill = 0.5}})
Net.define("board.view", {args = {"ent"}, rate = {burst = 4, refill = 1}})
Net.define("board.post", {args = {"ent", "str:200"}, alive = true, rate = {burst = 2, refill = 0.05}})
Net.define("board.remove", {args = {"ent", "u16"}, rate = {burst = 4, refill = 1}})

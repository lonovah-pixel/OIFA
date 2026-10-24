--[[---------------------------------------------------------------------------
Characters (shared part): network schema, public DarkRP vars, validation
helpers used by both the server and the character creation screen.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Net = SV.Net
local U = SV.Util

SV.Chars = SV.Chars or {}
local Chars = SV.Chars

--[[---------------------------------------------------------------------------
Public per-player data (visible to everyone) is carried by DarkRP vars:
  rpname   (DarkRP)  character name
  job      (DarkRP)  role name
  sv_num             service number
  sv_rank            rank index within the division
  sv_div             division id
---------------------------------------------------------------------------]]
DarkRP.registerDarkRPVar("sv_num", net.WriteString, net.ReadString)
DarkRP.registerDarkRPVar("sv_div", net.WriteString, net.ReadString)
DarkRP.registerDarkRPVar("sv_rank", function(v) net.WriteUInt(v, 8) end, function() return net.ReadUInt(8) end)

SV.Sync.define("self", {scope = "player"})

Net.define("char.create", {args = {"str:40", "str:24", "u8"}, allowNoChar = true, ignoreStates = true, rate = {burst = 2, refill = 0.1}})
Net.define("char.select", {args = {"u32"}, allowNoChar = true, ignoreStates = true, rate = {burst = 2, refill = 0.2}})
Net.define("char.delete", {args = {"u32", "str:40"}, allowNoChar = true, ignoreStates = true, rate = {burst = 2, refill = 0.05}})
Net.define("char.unload", {args = {}, rate = {burst = 1, refill = 0.05}})
Net.define("char.list", {args = {}, allowNoChar = true, ignoreStates = true, rate = {burst = 2, refill = 0.2}})
Net.define("char.takeRole", {args = {"str:32"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("char.promote", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("char.transfer", {args = {"str:24", "str:200"}, rate = {burst = 1, refill = 0.02}})
Net.define("char.roles", {args = {}, rate = {burst = 4, refill = 0.5}})
Net.define("char.transferDecide", {args = {"u32", "bool"}, rate = {burst = 3, refill = 0.2}})

--[[---------------------------------------------------------------------------
Name validation
---------------------------------------------------------------------------]]

-- Upper -> lower case for Cyrillic (SQLite's lower() is ASCII only).
local cyrUpper = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
local cyrLower = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
local lowerMap = {}
do
    local ups, lows = {}, {}
    for ch in string.gmatch(cyrUpper, "[\192-\255][\128-\191]*") do ups[#ups + 1] = ch end
    for ch in string.gmatch(cyrLower, "[\192-\255][\128-\191]*") do lows[#lows + 1] = ch end
    for i, ch in ipairs(ups) do lowerMap[ch] = lows[i] end
end

function U.lowerRu(s)
    s = string.lower(s)
    return (string.gsub(s, "[\192-\255][\128-\191]*", function(ch) return lowerMap[ch] or ch end))
end

local reservedNames = {
    ["администратор"] = true, ["admin"] = true, ["console"] = true, ["консоль"] = true,
    ["scp"] = true, ["фонд"] = true, ["o5"] = true,
}

--- Checks a character name. Returns cleaned name or nil, reason.
function Chars.validateName(name)
    local cfg = SV.Config.Characters
    name = U.cleanText(name or "")
    local len = U.utf8len(name)
    if len < cfg.nameMinLength then return nil, "Имя слишком короткое (минимум " .. cfg.nameMinLength .. " символа)." end
    if len > cfg.nameMaxLength then return nil, "Имя слишком длинное (максимум " .. cfg.nameMaxLength .. " символа)." end

    -- Letters (Latin, Cyrillic), spaces, hyphen and apostrophe only.
    local stripped = string.gsub(name, "[%a%s%-']", "")
    stripped = string.gsub(stripped, "\208[\128-\191]", "")  -- U+0400..U+043F
    stripped = string.gsub(stripped, "\209[\128-\159]", "")  -- U+0440..U+045F
    if stripped ~= "" then return nil, "Имя может содержать только буквы, пробел, дефис и апостроф." end

    local words = 0
    for _ in string.gmatch(name, "%S+") do words = words + 1 end
    if words < 2 or words > 3 then return nil, "Укажите имя и фамилию (2–3 слова)." end

    for word in string.gmatch(U.lowerRu(name), "%S+") do
        if reservedNames[word] then return nil, "Имя содержит зарезервированное слово." end
    end
    return name
end

--- Public description of a player for HUD/scoreboard ("Сержант Иван Петров").
function Chars.publicInfo(ply)
    local div = ply:getDarkRPVar("sv_div")
    return {
        name = ply:Nick(),
        number = ply:getDarkRPVar("sv_num") or "",
        division = div,
        rank = ply:getDarkRPVar("sv_rank") or 1,
        rankName = div and SV.Roles.rankName(div, ply:getDarkRPVar("sv_rank")) or "",
        role = SV.Roles.ofPlayer(ply),
    }
end

--- Display designation: D-class personnel are addressed by their number.
function Chars.displayName(ply)
    if ply:getDarkRPVar("sv_div") == "classd" then
        local num = ply:getDarkRPVar("sv_num")
        if num and num ~= "" then return "D-" .. string.gsub(num, "%D", "") end
    end
    return ply:Nick()
end

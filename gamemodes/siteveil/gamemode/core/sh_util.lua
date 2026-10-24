--[[---------------------------------------------------------------------------
Shared helpers used by every module.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Util = SV.Util or {}
local U = SV.Util

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.round(v, step)
    step = step or 1
    return math.floor(v / step + 0.5) * step
end

function U.count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

function U.copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = U.copy(val) end
    return out
end

function U.keys(tbl)
    local out = {}
    for k in pairs(tbl) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function U.contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function U.set(list)
    local out = {}
    for _, v in ipairs(list or {}) do out[v] = true end
    return out
end

--- Length of a UTF-8 string in characters (Cyrillic is two bytes per char).
function U.utf8len(s)
    local _, n = string.gsub(s, "[^\128-\191]", "")
    return n
end

--- Truncates a UTF-8 string to at most maxChars characters.
function U.utf8sub(s, maxChars)
    if U.utf8len(s) <= maxChars then return s end
    local out, n = {}, 0
    for ch in string.gmatch(s, "[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > maxChars then break end
        out[n] = ch
    end
    return table.concat(out)
end

--- Removes control characters and trims whitespace.
function U.cleanText(s, maxChars)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "[%c]", " ")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "%s%s+", " ")
    if maxChars then s = U.utf8sub(s, maxChars) end
    return s
end

--- Russian plural form: plural(5, "минута", "минуты", "минут").
function U.plural(n, one, few, many)
    n = math.abs(math.floor(n))
    local n10, n100 = n % 10, n % 100
    if n10 == 1 and n100 ~= 11 then return one end
    if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14) then return few end
    return many
end

function U.formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds < 60 then
        return seconds .. " " .. U.plural(seconds, "секунда", "секунды", "секунд")
    end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return minutes .. " " .. U.plural(minutes, "минута", "минуты", "минут")
    end
    local hours = math.floor(minutes / 60)
    minutes = minutes % 60
    local out = hours .. " " .. U.plural(hours, "час", "часа", "часов")
    if minutes > 0 then out = out .. " " .. minutes .. " мин" end
    return out
end

function U.formatClock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

--- Unix time (wall clock) used for persisted timestamps.
function U.now()
    return os.time()
end

--- In-game clock string "ЧЧ:ММ" for a unix timestamp, optionally rounded to
--- a number of minutes (used for intentionally imprecise game evidence).
function U.clockString(ts, roundMinutes)
    if roundMinutes and roundMinutes > 1 then
        local step = roundMinutes * 60
        ts = math.floor(ts / step) * step
    end
    return os.date("%H:%M", ts)
end

--- Stable 32-bit FNV-1a hash of a string.
function U.hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, string.byte(s, i))
        if h < 0 then h = h + 4294967296 end -- bit ops return signed 32-bit values
        -- h * 16777619 mod 2^32 without exceeding the 53-bit double mantissa:
        -- 16777619 = 2^24 + 403
        h = ((h % 256) * 16777216 + h * 403) % 4294967296
    end
    return h
end

function U.isPlayer(v)
    return IsValid(v) and v:IsPlayer()
end

--- Iterates human players that have an active character.
function U.activePlayers()
    local out = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply.SVChar then out[#out + 1] = ply end
    end
    return out
end

function U.onlineCount()
    local n = 0
    for _, ply in ipairs(player.GetAll()) do
        if not ply:IsBot() or SV.Config.Debug then n = n + 1 end
    end
    return n
end

function U.distSqr(a, b)
    return a:GetPos():DistToSqr(b:GetPos())
end

function U.within(a, b, dist)
    return IsValid(a) and IsValid(b) and a:GetPos():DistToSqr(b:GetPos()) <= dist * dist
end

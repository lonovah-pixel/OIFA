--[[---------------------------------------------------------------------------
Console logging. Persistent, exact administrative records go through
SiteVeil.Audit (core/sv_audit.lua); this file only prints and keeps the last
problems in memory for the admin panel.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Log = SV.Log or {}
local Log = SV.Log

Log.recent = Log.recent or {}
local MAX_RECENT = 200

local colors = {
    debug = Color(150, 150, 150),
    info = Color(120, 200, 255),
    warn = Color(255, 200, 80),
    error = Color(255, 90, 90),
}

local function push(level, msg)
    table.insert(Log.recent, {level = level, msg = msg, time = os.time()})
    if #Log.recent > MAX_RECENT then table.remove(Log.recent, 1) end
end

local function out(level, fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    if level == "debug" and not SV.Config.Debug then return end
    MsgC(colors[level], "[SITE-VEIL] ", color_white, msg, "\n")
    if level == "warn" or level == "error" then push(level, msg) end
end

function Log.debug(fmt, ...) out("debug", fmt, ...) end
function Log.info(fmt, ...) out("info", fmt, ...) end
function Log.warn(fmt, ...) out("warn", fmt, ...) end
function Log.error(fmt, ...)
    out("error", fmt, ...)
end

--- Runs fn in protected mode and logs the error with a context label.
function Log.guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        Log.error("%s: %s", label, tostring(err))
    end
    return ok, err
end

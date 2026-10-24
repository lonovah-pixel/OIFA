--[[---------------------------------------------------------------------------
Networking.

Client -> server: one net message "sv_rpc" carrying an action name and typed
arguments described by a schema shared by both realms:

    -- shared file
    SiteVeil.Net.define("inventory.drop", {
        args = {"u32", "u8"},          -- item uid, amount
        rate = {burst = 4, refill = 2},
        alive = true,
    })
    -- server file
    SiteVeil.Net.handle("inventory.drop", function(ply, uid, amount) ... end)
    -- client
    SiteVeil.Net.call("inventory.drop", uid, 1)

Before a handler runs the server checks: message size, action existence,
global and per-action rate limits, argument types and bounds, admin rights,
that the player has a loaded character (unless allowNoChar), alive state and
the generic "SiteVeil.CanUseAction" veto hook (restraints, incapacitation).
Handlers still validate entities, distances, ownership and state transitions
themselves; they return `ok, message` and the message is shown to the player.

Server -> client: "sv_push" carrying an event name and a table:
    SiteVeil.Net.send(plyOrListOrNil, "inventory.full", data)
    SiteVeil.Net.on("inventory.full", function(data) ... end)   -- client
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Net = SV.Net or {}
local Net = SV.Net

local RPC = "sv_rpc"
local PUSH = "sv_push"

Net.defs = Net.defs or {}
Net.handlers = Net.handlers or {}
Net.listeners = Net.listeners or {}

if SERVER then
    util.AddNetworkString(RPC)
    util.AddNetworkString(PUSH)
end

--[[---------------------------------------------------------------------------
Argument codecs
---------------------------------------------------------------------------]]
local function parseType(t)
    local base, param = string.match(t, "^(%a+%d*):?(%d*)$")
    return base, tonumber(param)
end

local writers = {
    u8 = function(v) net.WriteUInt(v, 8) end,
    u16 = function(v) net.WriteUInt(v, 16) end,
    u32 = function(v) net.WriteUInt(v, 32) end,
    i32 = function(v) net.WriteInt(v, 32) end,
    bool = function(v) net.WriteBool(v) end,
    float = function(v) net.WriteFloat(v) end,
    str = function(v) net.WriteString(v) end,
    json = function(v) net.WriteString(util.TableToJSON(v) or "{}") end,
    ent = function(v) net.WriteEntity(v) end,
    vec = function(v) net.WriteVector(v) end,
}

local checkers = {
    u8 = function(v) return isnumber(v) and v >= 0 and v <= 255 and v == math.floor(v) end,
    u16 = function(v) return isnumber(v) and v >= 0 and v <= 65535 and v == math.floor(v) end,
    u32 = function(v) return isnumber(v) and v >= 0 and v <= 4294967295 and v == math.floor(v) end,
    i32 = function(v) return isnumber(v) and v >= -2147483648 and v <= 2147483647 and v == math.floor(v) end,
    bool = isbool,
    float = function(v) return isnumber(v) and v == v and v ~= math.huge and v ~= -math.huge end,
    str = isstring,
    json = istable,
    ent = function(v) return isentity(v) end,
    vec = isvector,
}

--- Reads one argument; returns value or nil, error.
local function readArg(t)
    local base, limit = parseType(t)
    if base == "u8" then return net.ReadUInt(8) end
    if base == "u16" then return net.ReadUInt(16) end
    if base == "u32" then return net.ReadUInt(32) end
    if base == "i32" then return net.ReadInt(32) end
    if base == "bool" then return net.ReadBool() end
    if base == "float" then
        local v = net.ReadFloat()
        if v ~= v or v == math.huge or v == -math.huge then return nil, "non-finite float" end
        return v
    end
    if base == "str" then
        local s = net.ReadString()
        limit = limit or 128
        if #s > limit * 4 or SV.Util.utf8len(s) > limit then return nil, "string too long" end
        return s
    end
    if base == "json" then
        local s = net.ReadString()
        limit = limit or 2048
        if #s > limit then return nil, "json too long" end
        local tbl = util.JSONToTable(s)
        if not istable(tbl) then return nil, "invalid json" end
        return tbl
    end
    if base == "ent" then return net.ReadEntity() end
    if base == "vec" then
        local v = net.ReadVector()
        if v.x ~= v.x or v.y ~= v.y or v.z ~= v.z then return nil, "invalid vector" end
        return v
    end
    return nil, "unknown type " .. tostring(t)
end

--[[---------------------------------------------------------------------------
Definitions
---------------------------------------------------------------------------]]
function Net.define(name, def)
    def = def or {}
    def.name = name
    def.args = def.args or {}
    def.rate = def.rate or {burst = 5, refill = 2}
    for _, t in ipairs(def.args) do
        local base = parseType(t)
        assert(writers[base], "Net.define " .. name .. ": unknown arg type " .. t)
    end
    Net.defs[name] = def
end

--[[---------------------------------------------------------------------------
Client side
---------------------------------------------------------------------------]]
if CLIENT then
    function Net.call(name, ...)
        local def = Net.defs[name]
        if not def then
            SV.Log.error("Net.call: unknown action %s", name)
            return false
        end
        local args = {...}
        for i, t in ipairs(def.args) do
            local base = parseType(t)
            if not checkers[base](args[i]) then
                SV.Log.error("Net.call %s: argument %d is not %s", name, i, t)
                return false
            end
        end
        net.Start(RPC)
        net.WriteString(name)
        for i, t in ipairs(def.args) do
            writers[parseType(t)](args[i])
        end
        net.SendToServer()
        return true
    end

    function Net.on(event, fn)
        Net.listeners[event] = fn
    end

    net.Receive(PUSH, function()
        local event = net.ReadString()
        local data = net.ReadTable()
        local fn = Net.listeners[event]
        if fn then
            local ok, err = pcall(fn, data)
            if not ok then SV.Log.error("push handler %s: %s", event, tostring(err)) end
        end
        hook.Run("SiteVeil.Push", event, data)
    end)
end

--[[---------------------------------------------------------------------------
Server side
---------------------------------------------------------------------------]]
if SERVER then
    function Net.handle(name, fn)
        assert(Net.defs[name], "Net.handle: action not defined: " .. name)
        Net.handlers[name] = fn
    end

    --- Token bucket. Returns true when a token was available.
    local function take(ply, key, rate)
        local buckets = ply.SVBuckets
        if not buckets then
            buckets = {}
            ply.SVBuckets = buckets
        end
        local now = CurTime()
        local b = buckets[key]
        if not b then
            b = {tokens = rate.burst, at = now}
            buckets[key] = b
        end
        b.tokens = math.min(rate.burst, b.tokens + (now - b.at) * rate.refill)
        b.at = now
        if b.tokens < 1 then return false end
        b.tokens = b.tokens - 1
        return true
    end
    Net.takeToken = take

    function Net.violation(ply, reason)
        SV.Perf.count("net.violation")
        local now = CurTime()
        ply.SVViolations = ply.SVViolations or {}
        local list = ply.SVViolations
        table.insert(list, now)
        local window = SV.Config.Net.violationWindow
        while list[1] and list[1] < now - window do table.remove(list, 1) end

        -- Log the first violations of a burst exactly, then only every 10th.
        if #list <= 3 or #list % 10 == 0 then
            SV.Audit.log("net", "violation", ply, nil, {reason = reason, count = #list})
        end

        if #list >= SV.Config.Net.violationKick then
            SV.Audit.log("net", "kick", ply, nil, {reason = reason})
            ply:Kick("SITE-VEIL: слишком много недопустимых запросов")
        end
    end

    local function notifyResult(ply, ok, message)
        if not isstring(message) or message == "" then return end
        DarkRP.notify(ply, ok == false and 1 or 0, 5, message)
    end
    Net.notifyResult = notifyResult

    net.Receive(RPC, function(len, ply)
        if not IsValid(ply) then return end
        SV.Perf.count("net.rpc.in")

        if len > SV.Config.Net.maxRpcBytes * 8 then
            Net.violation(ply, "oversized rpc (" .. len .. " bits)")
            return
        end

        if not take(ply, "__global", SV.Config.Net.globalRate) then
            SV.Perf.count("net.rpc.ratelimited")
            return
        end

        local name = net.ReadString()
        if #name > 48 then
            Net.violation(ply, "action name too long")
            return
        end

        local def = Net.defs[name]
        local handler = Net.handlers[name]
        if not def or not handler then
            Net.violation(ply, "unknown action " .. string.sub(name, 1, 48))
            return
        end

        if def.maxBytes and len > def.maxBytes * 8 then
            Net.violation(ply, "oversized " .. name)
            return
        end

        if not take(ply, name, def.rate) then
            SV.Perf.count("net.rpc.ratelimited")
            if def.rateMessage ~= false then
                notifyResult(ply, false, "Слишком частые действия. Подождите.")
            end
            return
        end

        local args = {}
        for i, t in ipairs(def.args) do
            local v, err = readArg(t)
            if v == nil and err then
                Net.violation(ply, name .. ": " .. err)
                return
            end
            args[i] = v
        end

        if def.admin == "superadmin" and not ply:IsSuperAdmin() then
            Net.violation(ply, name .. ": superadmin action")
            return
        elseif def.admin and not ply:IsAdmin() then
            Net.violation(ply, name .. ": admin action")
            return
        end

        if not def.allowNoChar and not ply.SVChar then
            notifyResult(ply, false, "Сначала выберите персонажа.")
            return
        end

        if def.alive and not ply:Alive() then
            notifyResult(ply, false, "Действие недоступно: персонаж мёртв.")
            return
        end

        if not def.ignoreStates then
            local allowed, reason = hook.Run("SiteVeil.CanUseAction", ply, name, def)
            if allowed == false then
                notifyResult(ply, false, reason or "Действие сейчас недоступно.")
                return
            end
        end

        SV.Perf.count("net.rpc." .. name)
        local started = SysTime()
        local ok, result, message = pcall(handler, ply, unpack(args, 1, #def.args))
        SV.Perf.record("rpc." .. name, SysTime() - started)

        if not ok then
            SV.Log.error("rpc %s from %s failed: %s", name, ply:SteamID64() or "?", tostring(result))
            notifyResult(ply, false, "Внутренняя ошибка сервера. Действие отменено.")
            return
        end
        notifyResult(ply, result, message)
    end)

    --- Sends an event to one player, a list of players or everyone (nil).
    function Net.send(target, event, data)
        if istable(target) and next(target) == nil then return end
        net.Start(PUSH)
        net.WriteString(event)
        net.WriteTable(data or {})
        local bytes = net.BytesWritten and net.BytesWritten() or 0
        if target == nil then
            net.Broadcast()
        else
            net.Send(target)
        end
        SV.Perf.count("net.push." .. event)
        SV.Perf.count("net.push.bytes", bytes)
    end
end

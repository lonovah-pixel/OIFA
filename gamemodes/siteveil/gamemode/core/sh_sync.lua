--[[---------------------------------------------------------------------------
State replication.

Channels are key/value stores replicated from the server. Changes are
batched and sent as deltas every SiteVeil.Config.Sync.flushInterval seconds;
a full snapshot is sent once when a client reports that it is ready.

    global channel:  everyone receives it  (facility state, sectors, ...)
    player channel:  only the owning player (own character, own inventory)

Never put information into a channel that some receivers must not know:
restricted data (dossiers, evidence details) is sent on request after a
server-side permission check instead.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Sync = SV.Sync or {}
local Sync = SV.Sync
local Net = SV.Net

Sync.channels = Sync.channels or {}
Sync.data = Sync.data or {}           -- client: channel -> key -> value

Net.define("sync.ready", {args = {}, allowNoChar = true, ignoreStates = true, rate = {burst = 2, refill = 0.1}})

function Sync.define(name, opts)
    opts = opts or {}
    Sync.channels[name] = {
        name = name,
        scope = opts.scope or "global",
        values = (Sync.channels[name] and Sync.channels[name].values) or {},
        dirty = {},
    }
end

if SERVER then
    local playerDirty = {}  -- ply -> channel -> key -> true
    local playerValues = {} -- ply -> channel -> key -> value

    function Sync.set(name, key, value)
        local ch = Sync.channels[name]
        assert(ch and ch.scope == "global", "Sync.set on non-global channel " .. tostring(name))
        if ch.values[key] == value and not istable(value) then return end
        ch.values[key] = value
        ch.dirty[key] = true
    end

    function Sync.get(name, key)
        local ch = Sync.channels[name]
        return ch and ch.values[key]
    end

    function Sync.setFor(ply, name, key, value)
        local ch = Sync.channels[name]
        assert(ch and ch.scope == "player", "Sync.setFor on non-player channel " .. tostring(name))
        playerValues[ply] = playerValues[ply] or {}
        playerValues[ply][name] = playerValues[ply][name] or {}
        local store = playerValues[ply][name]
        if store[key] == value and not istable(value) then return end
        store[key] = value
        playerDirty[ply] = playerDirty[ply] or {}
        playerDirty[ply][name] = playerDirty[ply][name] or {}
        playerDirty[ply][name][key] = true
    end

    function Sync.getFor(ply, name, key)
        local p = playerValues[ply]
        return p and p[name] and p[name][key]
    end

    function Sync.clearFor(ply, name)
        local p = playerValues[ply]
        if not p or not p[name] then return end
        for key in pairs(p[name]) do
            Sync.setFor(ply, name, key, nil)
        end
    end

    local function readyPlayers()
        local out = {}
        for _, ply in ipairs(player.GetHumans()) do
            if ply.SVSyncReady then out[#out + 1] = ply end
        end
        return out
    end

    local function buildDelta(values, dirty)
        local set, del = {}, {}
        local any = false
        for key in pairs(dirty) do
            any = true
            local v = values[key]
            if v == nil then del[#del + 1] = key else set[key] = v end
        end
        return any, set, del
    end

    function Sync.flush()
        local targets
        for name, ch in pairs(Sync.channels) do
            if ch.scope == "global" and next(ch.dirty) then
                local _, set, del = buildDelta(ch.values, ch.dirty)
                ch.dirty = {}
                targets = targets or readyPlayers()
                Net.send(targets, "sync", {c = name, s = set, d = del})
            end
        end

        for ply, channels in pairs(playerDirty) do
            if IsValid(ply) and ply.SVSyncReady then
                for name, dirty in pairs(channels) do
                    local any, set, del = buildDelta(playerValues[ply][name], dirty)
                    if any then Net.send(ply, "sync", {c = name, s = set, d = del}) end
                end
                playerDirty[ply] = nil
            elseif not IsValid(ply) then
                playerDirty[ply] = nil
            end
        end
    end

    function Sync.sendSnapshot(ply)
        for name, ch in pairs(Sync.channels) do
            if ch.scope == "global" then
                Net.send(ply, "sync", {c = name, s = ch.values, d = {}, full = true})
            elseif playerValues[ply] and playerValues[ply][name] then
                Net.send(ply, "sync", {c = name, s = playerValues[ply][name], d = {}, full = true})
            end
        end
        playerDirty[ply] = nil
    end

    Net.handle("sync.ready", function(ply)
        if ply.SVSyncReady then return end
        ply.SVSyncReady = true
        Sync.sendSnapshot(ply)
        hook.Run("SiteVeil.ClientReady", ply)
    end)

    hook.Add("PlayerDisconnected", "SiteVeil.Sync", function(ply)
        playerDirty[ply] = nil
        playerValues[ply] = nil
    end)

    timer.Create("SiteVeil.Sync.Flush", SV.Config.Sync.flushInterval, 0, function()
        SV.Perf.time("sync.flush", Sync.flush)
    end)

    SV.Perf.registry("sync.players", function() return SV.Util.count(playerValues) end)
end

if CLIENT then
    function Sync.get(name, key)
        local ch = Sync.data[name]
        return ch and ch[key]
    end

    function Sync.all(name)
        Sync.data[name] = Sync.data[name] or {}
        return Sync.data[name]
    end

    Net.on("sync", function(msg)
        local name = msg.c
        if msg.full then Sync.data[name] = {} end
        local ch = Sync.all(name)
        for key, value in pairs(msg.s or {}) do
            ch[key] = value
            hook.Run("SiteVeil.Sync", name, key, value)
        end
        for _, key in ipairs(msg.d or {}) do
            ch[key] = nil
            hook.Run("SiteVeil.Sync", name, key, nil)
        end
        hook.Run("SiteVeil.SyncChannel", name)
    end)

    hook.Add("InitPostEntity", "SiteVeil.Sync.Ready", function()
        Net.call("sync.ready")
    end)
end

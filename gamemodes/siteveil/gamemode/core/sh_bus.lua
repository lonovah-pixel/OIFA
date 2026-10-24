--[[---------------------------------------------------------------------------
Internal event bus.

Modules publish domain events ("node.repaired", "experiment.finished", ...)
and other modules subscribe without a load-time dependency in either
direction. This keeps the manifest dependency graph acyclic: tasks, evidence
and the director listen to events emitted by lower level systems.

Handlers run synchronously in subscription order; an error in one handler is
logged and does not stop the others.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Bus = SV.Bus or {}
local Bus = SV.Bus

Bus.handlers = Bus.handlers or {}

function Bus.on(event, id, fn)
    Bus.handlers[event] = Bus.handlers[event] or {}
    local list = Bus.handlers[event]
    for i, h in ipairs(list) do
        if h.id == id then
            list[i].fn = fn
            return
        end
    end
    table.insert(list, {id = id, fn = fn})
end

function Bus.off(event, id)
    local list = Bus.handlers[event]
    if not list then return end
    for i, h in ipairs(list) do
        if h.id == id then
            table.remove(list, i)
            return
        end
    end
end

function Bus.emit(event, data)
    local list = Bus.handlers[event]
    if SV.Perf then SV.Perf.count("bus." .. event) end
    if not list then return end
    for _, h in ipairs(list) do
        local ok, err = pcall(h.fn, data)
        if not ok then
            SV.Log.error("bus handler %s/%s: %s", event, h.id, tostring(err))
        end
    end
end

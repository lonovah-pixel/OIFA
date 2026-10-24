--[[---------------------------------------------------------------------------
Timed actions (repairs, treatment, restraining, evidence collection, ...).

The server owns the timer and re-validates the action every tick:
distance to the target, movement, death, damage and an optional
`canContinue` callback. Only one action per player. The client only draws a
progress bar from the "self" sync channel and may request cancellation.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Actions = SV.Actions or {}
local Actions = SV.Actions
local Net = SV.Net

Net.define("action.cancel", {args = {}, ignoreStates = true, rate = {burst = 3, refill = 1}})

if SERVER then
    Actions.active = Actions.active or {} -- ply -> action

    local TICK = 0.2

    function Actions.get(ply)
        return Actions.active[ply]
    end

    function Actions.isBusy(ply)
        return Actions.active[ply] ~= nil
    end

    local function publish(ply, a)
        SV.Sync.setFor(ply, "self", "action", a and {
            label = a.label,
            started = a.startedAt,
            duration = a.duration,
            target = IsValid(a.target) and a.target:EntIndex() or nil,
        } or nil)
    end

    local function finish(ply, a, completed, reason)
        Actions.active[ply] = nil
        if IsValid(ply) then publish(ply, nil) end
        if completed then
            if a.onComplete then SV.Log.guard("action " .. a.id .. " complete", a.onComplete, ply, a) end
        else
            if a.onCancel then SV.Log.guard("action " .. a.id .. " cancel", a.onCancel, ply, reason, a) end
            if IsValid(ply) and reason and not a.silent then
                DarkRP.notify(ply, 1, 4, "Действие прервано: " .. reason)
            end
        end
    end

    --- Starts an action. Returns true or false, reason.
    function Actions.start(ply, def)
        if not IsValid(ply) or not ply:Alive() then return false, "персонаж мёртв" end
        if Actions.active[ply] then return false, "вы уже выполняете другое действие" end

        local a = {
            id = def.id or "action",
            label = def.label or "Выполнение",
            duration = math.max(def.duration or 1, 0.1),
            target = def.target,
            maxDist = def.maxDist or 120,
            allowMove = def.allowMove or false,
            cancelOnDamage = def.cancelOnDamage ~= false,
            canContinue = def.canContinue,
            onComplete = def.onComplete,
            onCancel = def.onCancel,
            silent = def.silent,
            data = def.data,
            startedAt = CurTime(),
            startPos = ply:GetPos(),
        }
        a.endsAt = a.startedAt + a.duration

        if a.target ~= nil and not IsValid(a.target) then return false, "цель недоступна" end
        if IsValid(a.target) and not SV.Util.within(ply, a.target, a.maxDist) then
            return false, "цель слишком далеко"
        end

        Actions.active[ply] = a
        publish(ply, a)
        return true
    end

    function Actions.cancel(ply, reason)
        local a = Actions.active[ply]
        if a then finish(ply, a, false, reason) end
    end

    --- Cancels every action whose target is ent (target died, was removed...).
    function Actions.cancelTargeting(ent, reason)
        for ply, a in pairs(Actions.active) do
            if a.target == ent then finish(ply, a, false, reason) end
        end
    end

    local function tick()
        local now = CurTime()
        for ply, a in pairs(Actions.active) do
            local reason
            if not IsValid(ply) then
                Actions.active[ply] = nil
                if a.onCancel then SV.Log.guard("action cancel", a.onCancel, ply, "отключение", a) end
            else
                if not ply:Alive() then
                    reason = "персонаж погиб"
                elseif a.target ~= nil and not IsValid(a.target) then
                    reason = "цель недоступна"
                elseif IsValid(a.target) and not SV.Util.within(ply, a.target, a.maxDist + 24) then
                    reason = "вы отошли слишком далеко"
                elseif not a.allowMove and ply:GetPos():DistToSqr(a.startPos) > 48 * 48 then
                    reason = "вы сдвинулись с места"
                elseif a.canContinue then
                    local ok, why = a.canContinue(ply, a)
                    if not ok then reason = why or "условия изменились" end
                end

                if reason then
                    finish(ply, a, false, reason)
                elseif now >= a.endsAt then
                    finish(ply, a, true)
                end
            end
        end
    end
    timer.Create("SiteVeil.Actions", TICK, 0, function() SV.Perf.time("actions.tick", tick) end)

    hook.Add("EntityTakeDamage", "SiteVeil.Actions", function(ent, dmg)
        if not ent:IsPlayer() then return end
        local a = Actions.active[ent]
        if a and a.cancelOnDamage and dmg:GetDamage() >= 1 then
            finish(ent, a, false, "получен урон")
        end
    end)

    hook.Add("PlayerDisconnected", "SiteVeil.Actions", function(ply)
        local a = Actions.active[ply]
        if a then
            Actions.active[ply] = nil
            if a.onCancel then SV.Log.guard("action cancel", a.onCancel, ply, "отключение", a) end
        end
        Actions.cancelTargeting(ply, "цель отключилась")
    end)

    hook.Add("PlayerDeath", "SiteVeil.Actions", function(ply)
        Actions.cancel(ply, "персонаж погиб")
        Actions.cancelTargeting(ply, "цель погибла")
    end)

    Net.handle("action.cancel", function(ply)
        Actions.cancel(ply, "отменено")
    end)

    SV.Perf.registry("actions.active", function() return SV.Util.count(Actions.active) end)
end

--[[---------------------------------------------------------------------------
Crafting (server).

Workbenches (map point kind "workbench", prop bench = general | engineering
| medical) turn inventory items into others by recipe, as a timed action at
the bench; inputs are taken only on completion (rechecked). Finished labor
jobs sometimes give scrap. A lockpick opens a door of clearance <= 1 after a
noisy 12 s action with a 60% chance; it may break; the attempt is audited
and leaves a trace.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Crafting = SV.Crafting
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Crafting
local Inv = SV.Inv
local Items = SV.Config.Items

SV.MapCfg.editorProps.workbench = {bench = true, name = true}

Crafting.byId = {}
for _, r in ipairs(K.recipes) do Crafting.byId[r.id] = r end

local function benchOf(ent)
    return IsValid(ent) and ent:GetClass() == "sv_workbench" and ent.SVPoint and K.benches[ent.SVPoint.props.bench] and ent.SVPoint.props.bench or nil
end

function Crafting.blockedReason(ply, ent, r)
    local bench = benchOf(ent)
    if not bench then return "верстак не настроен" end
    if r.bench ~= bench then return "нужен " .. string.lower(K.benches[r.bench]) end
    if not U.within(ply, ent, 110) then return "подойдите к верстаку" end
    local okDiv = false
    for _, d in ipairs(r.divisions) do if ply.SVChar.division == d then okDiv = true end end
    if not okDiv and not SV.Admin.isOnDuty(ply) then return "не ваша специальность" end
    for item, n in pairs(r.inputs) do
        if not Inv.has(ply, item, n) then return "нужно: " .. Items[item].name .. " ×" .. n end
    end
    if not Inv.fits(ply, r.output[1], r.output[2]) then return "нет места в инвентаре" end
    return nil
end

Net.handle("craft.open", function(ply, ent)
    local bench = benchOf(ent)
    if not bench or not U.within(ply, ent, 110) then return false end
    local list = {}
    for _, r in ipairs(K.recipes) do
        if r.bench == bench then
            local inputs = {}
            for item, n in SortedPairs(r.inputs) do inputs[#inputs + 1] = Items[item].name .. " ×" .. n end
            list[#list + 1] = {id = r.id, name = Items[r.output[1]].name .. (r.output[2] > 1 and (" ×" .. r.output[2]) or ""),
                inputs = table.concat(inputs, ", "), time = r.time, blocked = Crafting.blockedReason(ply, ent, r)}
        end
    end
    Net.send(ply, "craft.open", {ent = ent:EntIndex(), title = K.benches[bench], recipes = list})
end)

Net.handle("craft.make", function(ply, ent, id)
    local r = Crafting.byId[id]
    if not r then return false end
    local why = Crafting.blockedReason(ply, ent, r)
    if why then return false, "Нельзя изготовить: " .. why .. "." end
    return SV.Actions.start(ply, {
        id = "craft", label = "Изготовление: " .. Items[r.output[1]].name, duration = r.time, target = ent, maxDist = 130,
        onComplete = function(p)
            local again = Crafting.blockedReason(p, ent, r)
            if again then
                DarkRP.notify(p, 1, 4, "Не получилось: " .. again .. ".")
                return
            end
            for item, n in pairs(r.inputs) do Inv.take(p, item, n) end
            Inv.add(p, r.output[1], r.output[2])
            SV.Audit.log("crafting", "make", p, nil, {recipe = r.id})
            SV.Bus.emit("crafting.made", {ply = p, recipe = r.id, item = r.output[1]})
            DarkRP.notify(p, 0, 4, "Изготовлено: " .. Items[r.output[1]].name .. ".")
        end,
    })
end)

-- Scrap from class-D labor.
SV.Bus.on("labor.done", "crafting.scrap", function(data)
    local p = data.ply
    if not IsValid(p) or not p.SVChar then return end
    Crafting.scrapRolls = (Crafting.scrapRolls or 0) + 1
    local rng = SV.RNG.new(SV.RNG.seedFor("crafting.scrap", p.SVChar.id * 1000 + Crafting.scrapRolls))
    if rng:chance(K.scrapChance) and Inv.fits(p, "scrap", 1) then
        Inv.add(p, "scrap", 1)
        DarkRP.notify(p, 0, 4, "Вы припрятали немного металлолома.")
    end
end)

--[[---------------------------------------------------------------------------
Lockpick
---------------------------------------------------------------------------]]
local function isDoor(ent)
    local c = IsValid(ent) and ent:GetClass() or ""
    return c == "prop_door_rotating" or c == "func_door" or c == "func_door_rotating"
end

Crafting.picks = Crafting.picks or 0

Inv.registerUse("lockpick", function(ply, item)
    local L = K.lockpick
    local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * L.range, filter = ply})
    local door = tr.Entity
    if not isDoor(door) then return false, "Посмотрите на дверь." end
    local cfg = SV.MapCfg.doorConfig(door)
    if cfg and (cfg.policy == "locked" or (tonumber(cfg.clearance) or 0) > L.maxClearance) then return false, "Этот замок отмычкой не открыть." end
    local nextNoise = 0
    return SV.Actions.start(ply, {
        id = "lockpick", label = "Вскрытие замка", duration = L.time, target = door, maxDist = L.range + 30,
        canContinue = function(p)
            if CurTime() >= nextNoise then
                nextNoise = CurTime() + 2
                door:EmitSound("doors/door_locked2.wav", 70)
            end
            return Inv.getItem(p, item.uid) ~= nil, "отмычка потеряна"
        end,
        onComplete = function(p)
            Crafting.picks = Crafting.picks + 1
            local rng = SV.RNG.new(SV.RNG.seedFor("lockpick", p.SVChar.id * 1000 + Crafting.picks))
            local ok = rng:chance(L.success)
            if SV.Evidence then
                SV.Evidence.addTrace("damage", door:GetPos(), {attacker = {char = p.SVChar.id, name = p.SVChar.name, division = p.SVChar.division}, door = true})
            end
            SV.Audit.log("crafting", "lockpick", p, nil, {door = door:MapCreationID(), ok = ok})
            SV.Bus.emit("access.forced", {ply = p, door = door, ok = ok})
            if ok then
                door:Fire("Unlock", "", 0)
                door:Fire("Open", "", 0)
                if SV.Access then SV.Access.openDoors[door] = CurTime() + L.openFor end
                if rng:chance(L.breakOnSuccess) then Inv.removeUid(p, item.uid, 1) end
                DarkRP.notify(p, 0, 4, "Замок поддался.")
            else
                Inv.removeUid(p, item.uid, 1)
                DarkRP.notify(p, 1, 4, "Отмычка сломалась.")
            end
        end,
    })
end)

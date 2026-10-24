--[[---------------------------------------------------------------------------
"Живой комплекс": infrastructure simulation (server).

Model (deliberately simple, see ARCHITECTURE.md):
  * Sectors (map zones of kind "sector") demand power and have a priority
    (1 = high ... 3 = low, 0 = shed by engineers).
  * The main generator (nodes of subsystem "generator") provides capacity;
    the distribution gives power to sectors in priority order.
  * Each sector has nodes per subsystem (power, comms, ventilation,
    surveillance, security). Node health 0..100 and an optional fault.
  * Effective sector power = allocated ratio x power-panel factor, raised to
    the backup level while backup fuel lasts.
  * Devices depend on it: doors (power + security), terminals, cameras
    (power + surveillance), containment equipment.
Missing configuration degrades gracefully: a subsystem without nodes in a
sector counts as healthy, a map without generator nodes has full capacity.

Infrastructure state is temporary (resets on restart / map change).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local F = C.Facility
local Roles = SV.Roles
local Inv = SV.Inv

Facility.nodes = Facility.nodes or {}      -- id -> node
Facility.sectors = Facility.sectors or {}  -- id -> sector state
Facility.capacity = Facility.capacity or F.generatorCapacity
Facility.sabotageLog = Facility.sabotageLog or {} -- sid -> {times}

local rng

--[[---------------------------------------------------------------------------
Building the model from the map configuration
---------------------------------------------------------------------------]]
function Facility.build()
    local oldNodes = Facility.nodes
    Facility.nodes, Facility.sectors = {}, {}
    for _, zone in ipairs(SV.MapCfg.zones("sector")) do
        local old = Facility.sectors[zone.id]
        Facility.sectors[zone.id] = old or {
            id = zone.id, name = zone.name or zone.id,
            priority = tonumber(zone.props.priority) or 2,
            demand = tonumber(zone.props.demand) or F.defaultSectorDemand,
            fuel = F.backupStartFuel, power = 1, backup = false, alloc = 1,
            contaminated = false,
        }
    end
    for _, p in ipairs(SV.MapCfg.points("node")) do
        local sub = p.props.subsystem
        if Facility.subsystems[sub] then
            local sectorId = p.props.sector
            if not sectorId or not Facility.sectors[sectorId] then
                local z = SV.MapCfg.sectorAt(SV.MapCfg.toVec(p.pos))
                sectorId = z and z.id
            end
            local prev = oldNodes[p.id]
            Facility.nodes[p.id] = {
                id = p.id, subsystem = sub, sector = sectorId,
                name = p.props.name or Facility.subsystems[sub].node,
                health = prev and prev.health or 100, fault = prev and prev.fault or nil,
                bypassUntil = prev and prev.bypassUntil or nil, diagnosedBy = {},
                pos = SV.MapCfg.toVec(p.pos),
            }
        end
    end
    rng = SV.RNG.forSource("infra", game.GetMap())
    Facility.recompute()
    SV.Log.info("инфраструктура: секторов %d, узлов %d", U.count(Facility.sectors), U.count(Facility.nodes))
end

hook.Add("SiteVeil.MapConfigLoaded", "SiteVeil.Facility", function() Facility.build() end)

function Facility.nodeForEntity(ent)
    local p = IsValid(ent) and ent.SVPoint
    return p and Facility.nodes[p.id] or nil
end

function Facility.nodesIn(sectorId, subsystem)
    local out = {}
    for _, n in pairs(Facility.nodes) do
        if (sectorId == nil or n.sector == sectorId) and (subsystem == nil or n.subsystem == subsystem) then out[#out + 1] = n end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--[[---------------------------------------------------------------------------
Queries used by other modules
---------------------------------------------------------------------------]]
function Facility.sectorOf(ply)
    if ply.SVSector ~= nil then return ply.SVSector or nil end
    local z = SV.MapCfg.sectorAt(ply:GetPos())
    return z and z.id or nil
end

function Facility.sectorAt(pos)
    local z = SV.MapCfg.sectorAt(pos)
    return z and z.id or nil
end

local function avgHealth(nodes)
    if #nodes == 0 then return nil end
    local sum = 0
    for _, n in ipairs(nodes) do sum = sum + n.health end
    return sum / #nodes
end

--- Effective power of a sector in [0, 1] (1 for unknown sectors).
function Facility.power(sectorId)
    local s = sectorId and Facility.sectors[sectorId]
    return s and s.power or 1
end

--- Health of a subsystem in a sector in [0, 1] including the power supply.
function Facility.subsystemHealth(sectorId, subsystem)
    local s = sectorId and Facility.sectors[sectorId]
    if not s then return 1 end
    local h = avgHealth(Facility.nodesIn(sectorId, subsystem))
    local base = h and h / 100 or 1
    if subsystem == "power" then return s.power end
    local p = s.power
    local factor = p >= 0.6 and 1 or (p >= 0.3 and 0.7 or 0.15)
    return base * factor
end

function Facility.subsystemOk(sectorId, subsystem)
    return Facility.subsystemHealth(sectorId, subsystem) >= F.healthDegraded / 100
end

--- Whether a device class works in a sector.
function Facility.devicePowered(sectorId, kind)
    local p = Facility.power(sectorId)
    if kind == "doors" then
        return p >= 0.3 and Facility.subsystemHealth(sectorId, "security") >= F.healthDamaged / 100
    elseif kind == "terminals" then
        return p >= 0.5
    elseif kind == "cameras" then
        return p >= 0.5 and Facility.subsystemOk(sectorId, "surveillance")
    elseif kind == "containment" then
        return p >= 0.6
    end
    return p >= 0.3
end

function Facility.averageHealth()
    local sum, n = 0, 0
    for _, node in pairs(Facility.nodes) do sum = sum + node.health n = n + 1 end
    return n > 0 and sum / n or 100
end

--[[---------------------------------------------------------------------------
Simulation
---------------------------------------------------------------------------]]
local faultsBySubsystem = {
    power = {"overheat", "short"}, comms = {"short", "overheat"}, ventilation = {"contamination", "wear"},
    surveillance = {"short", "wear"}, security = {"short", "wear"}, generator = {"overheat", "wear"},
}

local function panelFactor(h)
    if h == nil then return 1 end
    if h >= F.healthDegraded then return 1 end
    if h >= F.healthDamaged then return 0.6 end
    return 0
end

function Facility.recompute()
    local gens = Facility.nodesIn(nil, "generator")
    local genHealth = avgHealth(gens)
    local cap = F.generatorCapacity
    if genHealth then
        cap = F.generatorCapacity * math.Clamp((genHealth - 10) / (F.healthOk - 10), 0, 1)
    end
    Facility.capacity = cap

    local order = {}
    for _, s in pairs(Facility.sectors) do order[#order + 1] = s end
    table.sort(order, function(a, b)
        if a.priority ~= b.priority then return (a.priority == 0 and 99 or a.priority) < (b.priority == 0 and 99 or b.priority) end
        return a.id < b.id
    end)

    local remaining = cap
    for _, s in ipairs(order) do
        local before = s.power
        if s.priority == 0 then
            s.alloc = 0
        else
            local give = math.min(s.demand, remaining)
            remaining = remaining - give
            s.alloc = s.demand > 0 and give / s.demand or 1
        end
        local panelH = avgHealth(Facility.nodesIn(s.id, "power"))
        local f = panelFactor(panelH)
        local eff = s.alloc * f
        s.backup = false
        if eff < 0.5 and s.fuel > 0 and f > 0 and s.priority ~= 0 then
            eff = math.max(eff, F.backupLevel)
            s.backup = true
        end
        s.power = math.Clamp(eff, 0, 1)
        if Facility.bucket(before) ~= Facility.bucket(s.power) then
            SV.Bus.emit("facility.powerChanged", {sector = s.id, from = before, to = s.power})
            if s.power < before and s.power < 0.5 then
                for _, ply in ipairs(player.GetAll()) do
                    if ply.SVSector == s.id then ply:EmitSound(C.Sounds.powerDown, 50) end
                end
            end
        end
    end
end

local function publish()
    for id, s in pairs(Facility.sectors) do
        local subs = {}
        for sub, def in pairs(Facility.subsystems) do
            if not def.global then subs[sub] = Facility.bucket(Facility.subsystemHealth(id, sub)) end
        end
        SV.Sync.set("sectors", id, {
            name = s.name, power = math.Round(s.power, 1), backup = s.backup, fuel = math.Round(s.fuel / F.backupFuelMax * 100),
            priority = s.priority, subs = subs, contaminated = s.contaminated,
        })
    end
    SV.Sync.set("facility", "capacity", math.Round(Facility.capacity))
end
Facility.publish = publish

local function tickNodes(dt)
    local now = CurTime()
    for _, n in pairs(Facility.nodes) do
        n.health = n.health - F.wearPerMinute * dt / 60
        local fault = n.fault and F.faults[n.fault]
        if fault then n.health = n.health - fault.rate end
        if n.bypassUntil and now >= n.bypassUntil then
            n.bypassUntil = nil
            n.health = math.min(n.health, 10)
            n.fault = "short"
            SV.Bus.emit("node.failed", {node = n, reason = "bypass expired"})
        end
        if not n.fault and n.health < 50 then
            local chance = F.faultChancePerMinute * dt / 60 * (1 + (50 - n.health) / 25)
            if rng:chance(chance) then
                local list = faultsBySubsystem[n.subsystem] or {"wear"}
                n.fault = list[rng:int(1, #list)]
                SV.Bus.emit("node.fault", {node = n, fault = n.fault})
            end
        end
        local before = n.health
        n.health = math.Clamp(n.health, 0, 100)
        if before > F.healthDamaged and n.health <= F.healthDamaged then
            SV.Bus.emit("node.failed", {node = n, reason = "health"})
        end
        -- Symptom: sparks and noise from badly damaged nodes.
        if n.health < F.healthDegraded and rng:chance(0.15) then
            local ent = SV.MapCfg.spawned[n.id]
            if IsValid(ent) then
                ent:EmitSound(C.Sounds.sparks, 65, math.random(90, 110))
                local ed = EffectData()
                ed:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
                ed:SetMagnitude(1)
                util.Effect("Sparks", ed)
            end
        end
    end
end

local function tickSectors(dt)
    for id, s in pairs(Facility.sectors) do
        if s.backup then s.fuel = math.max(s.fuel - dt, 0) end
        local vent = Facility.nodesIn(id, "ventilation")
        local contaminated = false
        for _, n in ipairs(vent) do
            if n.fault == "contamination" and n.health < F.healthOk then contaminated = true end
        end
        if contaminated ~= s.contaminated then
            s.contaminated = contaminated
            SV.Bus.emit("facility.contamination", {sector = id, on = contaminated})
        end
    end
end

local contaminationTick = 0
timer.Create("SiteVeil.Facility.Tick", F.tick, 0, function()
    if not rng then return end
    SV.Perf.time("facility.tick", function()
        tickNodes(F.tick)
        tickSectors(F.tick)
        Facility.recompute()
        publish()
    end)
    contaminationTick = contaminationTick + F.tick
    if contaminationTick >= 4 then
        contaminationTick = 0
        for _, ply in ipairs(player.GetAll()) do
            local s = ply.SVSector and Facility.sectors[ply.SVSector]
            if s and s.contaminated and ply:Alive() and ply.SVChar and not Roles.isSCP(ply)
                and not Inv.isWearing(ply, "gas_mask") and not Inv.isWearing(ply, "hazmat") then
                local d = DamageInfo()
                d:SetDamage(F.contaminationDamage)
                d:SetDamageType(DMG_NERVEGAS)
                d:SetAttacker(game.GetWorld())
                ply:TakeDamageInfo(d)
                SV.Bus.emit("facility.exposed", {ply = ply, sector = s.id})
            end
        end
    end
end)

-- Player sector tracking (one cheap box test per player per second).
timer.Create("SiteVeil.Facility.Sectors", F.sectorCheckInterval, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if ply.SVChar then
            local z = SV.MapCfg.sectorAt(ply:GetPos())
            local id = z and z.id or false
            if ply.SVSector ~= id then
                local old = ply.SVSector
                ply.SVSector = id
                SV.Sync.setFor(ply, "self", "sector", id or nil)
                SV.Bus.emit("sector.entered", {ply = ply, sector = id, from = old})
            end
        end
    end
end)

--[[---------------------------------------------------------------------------
Node interactions
---------------------------------------------------------------------------]]
local function isEngineer(ply)
    return Roles.hasFlag(ply, "engineer") or (SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply))
end

local function hasTool(ply)
    return ply:HasWeapon("sv_toolkit")
end

local function indicator(n)
    if n.health >= F.healthOk then return "зелёный индикатор, ровный гул" end
    if n.health >= F.healthDegraded then return "жёлтый индикатор, неравномерный гул" end
    if n.health >= F.healthDamaged then return "красный индикатор, запах гари, искры" end
    return "индикатор не горит, узел обесточен"
end

local function nodeView(ply, n)
    local sector = n.sector and Facility.sectors[n.sector]
    local view = {
        name = n.name, subsystem = Facility.subsystems[n.subsystem].name, sector = sector and sector.name or "—",
        indicator = indicator(n), engineer = isEngineer(ply), tool = hasTool(ply),
        sabotageReady = n.prepared ~= nil,
    }
    local diag = n.diagnosedBy[ply]
    if diag and CurTime() - diag < 600 then
        view.health = math.Round(n.health)
        view.fault = n.fault and F.faults[n.fault].name or nil
        view.hint = n.fault and F.faults[n.fault].hint or (n.health < F.healthOk and "Плановое обслуживание" or nil)
        view.parts = Facility.repairCost(n)
        view.bypass = n.bypassUntil and math.ceil(n.bypassUntil - CurTime()) or nil
    end
    if n.subsystem == "power" and sector then
        view.fuel = math.Round(sector.fuel / F.backupFuelMax * 100)
    end
    return view
end

function Facility.repairCost(n)
    local fault = n.fault and F.faults[n.fault]
    local severity = fault and fault.severity or 1
    return {parts = severity * F.partsPerSeverity, item = fault and fault.item or nil, time = F.repairBase + severity * F.repairPerSeverity}
end

local function sabotageAllowed(ply, n)
    local sid = ply:SteamID64()
    local now = CurTime()
    local log = Facility.sabotageLog[sid] or {}
    Facility.sabotageLog[sid] = log
    while log[1] and log[1] < now - F.sabotage.window do table.remove(log, 1) end
    if log[#log] and now - log[#log] < F.sabotage.cooldown then
        return false, "вы недавно уже вмешивались в оборудование"
    end
    if #log >= F.sabotage.windowLimit then return false, "слишком много вмешательств за короткое время" end
    if n.health < F.healthDamaged then return false, "узел уже выведен из строя" end
    return true
end

local function notifySecurity(n, text)
    local sector = n.sector and Facility.sectors[n.sector]
    if n.sector and not Facility.subsystemOk(n.sector, "security") then return end
    timer.Simple(math.random(5, 15), function()
        for _, p in ipairs(player.GetAll()) do
            if Roles.hasFlag(p, "canDetain") and not Roles.hasFlag(p, "sabotage") then
                DarkRP.notify(p, 3, 8, text .. ": " .. n.name .. (sector and (" (" .. sector.name .. ")") or ""))
            end
        end
    end)
end

local actions = {}

actions.diagnose = function(ply, n, ent)
    if not isEngineer(ply) or not hasTool(ply) then return false, "Диагностика требует инструмента техника." end
    return SV.Actions.start(ply, {
        id = "diagnose", label = "Диагностика: " .. n.name, duration = F.diagnoseTime, target = ent, maxDist = 120,
        onComplete = function(p)
            local fresh = not n.diagnosedBy[p] or CurTime() - n.diagnosedBy[p] > 300
            n.diagnosedBy[p] = CurTime()
            Net.send(p, "infra.node", {ent = ent:EntIndex(), view = nodeView(p, n)})
            if fresh then SV.Bus.emit("node.diagnosed", {ply = p, node = n}) end
        end,
    })
end

actions.repair = function(ply, n, ent)
    if not isEngineer(ply) or not hasTool(ply) then return false, "Ремонт требует инструмента техника." end
    if n.health >= F.healthOk and not n.fault then return false, "Узел исправен, ремонт не нужен." end
    local cost = Facility.repairCost(n)
    if not Inv.has(ply, "spare_parts", cost.parts) then return false, "Нужно запчастей: " .. cost.parts .. "." end
    if cost.item and not Inv.has(ply, cost.item) then return false, "Нужно: " .. C.Items[cost.item].name .. "." end
    ent:EmitSound(C.Sounds.repair, 60)
    return SV.Actions.start(ply, {
        id = "repair", label = "Ремонт: " .. n.name, duration = cost.time, target = ent, maxDist = 120,
        canContinue = function(p) return Inv.has(p, "spare_parts", cost.parts), "закончились запчасти" end,
        onComplete = function(p)
            if not Inv.take(p, "spare_parts", cost.parts) then return end
            if cost.item then Inv.take(p, cost.item, 1) end
            local hadFault = n.fault
            n.health = 100
            n.fault = nil
            n.bypassUntil = nil
            n.prepared = nil
            Facility.recompute()
            publish()
            DarkRP.notify(p, 0, 5, n.name .. ": ремонт выполнен.")
            SV.Chars.addXP(p, 15, "engineering")
            SV.Audit.log("infra", "repair", p, nil, {node = n.id, fault = hadFault})
            SV.Bus.emit("node.repaired", {ply = p, node = n, fault = hadFault})
        end,
    })
end

actions.bypass = function(ply, n, ent)
    if not isEngineer(ply) or not hasTool(ply) then return false, "Нужен инструмент техника." end
    if n.health >= F.healthDegraded then return false, "Обходное решение нужно только для неисправного узла." end
    if n.bypassUntil then return false, "Обход уже установлен." end
    return SV.Actions.start(ply, {
        id = "bypass", label = "Временный обход: " .. n.name, duration = F.bypassTime, target = ent, maxDist = 120,
        onComplete = function(p)
            n.health = math.max(n.health, F.bypassHealth)
            n.bypassUntil = CurTime() + F.bypassDuration
            Facility.recompute()
            publish()
            DarkRP.notify(p, 3, 6, n.name .. ": временный обход установлен на " .. U.formatDuration(F.bypassDuration) .. ". Затем узел откажет — нужен полноценный ремонт.")
            SV.Audit.log("infra", "bypass", p, nil, {node = n.id})
            SV.Bus.emit("node.bypassed", {ply = p, node = n})
        end,
    })
end

actions.refuel = function(ply, n, ent)
    if n.subsystem ~= "power" then return false, "Заправка выполняется у распределительного щита сектора." end
    local sector = Facility.sectors[n.sector or ""]
    if not sector then return false, "Узел не привязан к сектору." end
    if not Inv.has(ply, "fuel") then return false, "Нужна канистра топлива." end
    if sector.fuel >= F.backupFuelMax - 1 then return false, "Бак резервного генератора полон." end
    return SV.Actions.start(ply, {
        id = "refuel", label = "Заправка резервного генератора", duration = F.refuelTime, target = ent, maxDist = 120,
        onComplete = function(p)
            if not Inv.take(p, "fuel", 1) then return end
            sector.fuel = math.min(sector.fuel + F.refuelAmount, F.backupFuelMax)
            publish()
            DarkRP.notify(p, 0, 4, "Резервный генератор заправлен.")
            SV.Bus.emit("node.refueled", {ply = p, node = n, sector = sector.id})
        end,
    })
end

actions.sabotage = function(ply, n, ent)
    if Roles.isSCP(ply) then return false, "Недоступно." end
    local tool = hasTool(ply) or ply:HasWeapon("weapon_crowbar")
    if not tool then return false, "Нужен инструмент (набор техника или монтировка)." end
    local ok, why = sabotageAllowed(ply, n)
    if not ok then return false, "Нельзя: " .. why .. "." end
    local isGen = n.subsystem == "generator"
    return SV.Actions.start(ply, {
        id = "sabotage", label = isGen and not n.prepared and "Вскрытие кожуха генератора" or "Вмешательство в оборудование",
        duration = F.sabotage.time, target = ent, maxDist = 100,
        onComplete = function(p)
            local log = Facility.sabotageLog[p:SteamID64()]
            table.insert(log, CurTime())
            if isGen and F.sabotage.generatorPrep then
                local prep = n.prepared
                local elapsed = prep and CurTime() - prep.at or nil
                if not prep or prep.by ~= p or elapsed > F.sabotage.prepWindow[2] then
                    n.prepared = {by = p, at = CurTime()}
                    n.health = n.health - 10
                    notifySecurity(n, "Датчик вскрытия генератора")
                    SV.Bus.emit("node.sabotaged", {ply = p, node = n, stage = "prep"})
                    SV.Audit.log("infra", "sabotage.prep", p, nil, {node = n.id})
                    DarkRP.notify(p, 3, 6, "Кожух вскрыт. Повторное вмешательство возможно через " .. F.sabotage.prepWindow[1] .. " с.")
                    return
                elseif elapsed < F.sabotage.prepWindow[1] then
                    DarkRP.notify(p, 1, 5, "Слишком рано: схема ещё под защитой.")
                    return
                end
                n.prepared = nil
                n.health = math.max(n.health - F.sabotage.damage, F.sabotage.generatorFloor)
            else
                n.health = n.health - F.sabotage.damage
            end
            n.fault = "tamper"
            n.tamperedAt = os.time()
            Facility.recompute()
            publish()
            notifySecurity(n, "Срабатывание датчика вскрытия")
            SV.Audit.log("infra", "sabotage", p, nil, {node = n.id, health = n.health})
            SV.Bus.emit("node.sabotaged", {ply = p, node = n, stage = "done"})
        end,
    })
end

Net.handle("infra.node", function(ply, ent)
    local n = Facility.nodeForEntity(ent)
    if not n then return false, "Это не инфраструктурный узел." end
    if not U.within(ply, ent, 160) then return false, "Подойдите к узлу." end
    Net.send(ply, "infra.node", {ent = ent:EntIndex(), view = nodeView(ply, n)})
end)

Net.handle("infra.action", function(ply, ent, action)
    local n = Facility.nodeForEntity(ent)
    if not n then return false, "Это не инфраструктурный узел." end
    if not U.within(ply, ent, 120) then return false, "Подойдите к узлу." end
    local fn = actions[action]
    if not fn then
        Net.violation(ply, "unknown infra action")
        return false
    end
    return fn(ply, n, ent)
end)

--[[---------------------------------------------------------------------------
Infrastructure terminal: overview and power priorities
---------------------------------------------------------------------------]]
function Facility.overview(ply)
    local out = {capacity = math.Round(Facility.capacity), max = F.generatorCapacity, sectors = {}, canControl = Roles.hasFlag(ply, "powerControl")
        or (SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply))}
    local gen = avgHealth(Facility.nodesIn(nil, "generator"))
    out.generator = gen and Facility.bucket(gen / 100) or "unknown"
    for id, s in pairs(Facility.sectors) do
        local suspected = {}
        for _, n in ipairs(Facility.nodesIn(id)) do
            if n.health < F.healthOk or n.fault then
                local diag = n.diagnosedBy[ply]
                local known = diag and CurTime() - diag < 600
                suspected[#suspected + 1] = known and (n.name .. ": " .. math.Round(n.health) .. "%" .. (n.fault and (", " .. F.faults[n.fault].name) or ""))
                    or ("Возможна неисправность: " .. Facility.subsystems[n.subsystem].name)
            end
        end
        local subs = {}
        for sub, def in pairs(Facility.subsystems) do
            if not def.global then subs[sub] = Facility.bucket(Facility.subsystemHealth(id, sub)) end
        end
        out.sectors[#out.sectors + 1] = {id = id, name = s.name, power = math.Round(s.power * 100), alloc = math.Round(s.alloc * 100),
            demand = s.demand, priority = s.priority, backup = s.backup, fuel = math.Round(s.fuel / F.backupFuelMax * 100),
            subs = subs, suspected = suspected, contaminated = s.contaminated}
    end
    table.sort(out.sectors, function(a, b) return a.id < b.id end)
    return out
end

Facility.registerTerminal("infrastructure", {
    name = "Терминал инфраструктуры", req = {clearance = 1, tags = {"engineering", "power", "administration", "security"}}, power = 0.3,
    open = function(ply, ent) Net.send(ply, "infra.overview", {ent = ent:EntIndex(), data = Facility.overview(ply)}) end,
})

Net.handle("infra.overview", function(ply, ent)
    if not SV.Terminals.canUse(ply, ent, "infrastructure") then return false end
    Net.send(ply, "infra.overview", {ent = ent:EntIndex(), data = Facility.overview(ply)})
end)

Net.handle("infra.priority", function(ply, ent, sectorId, priority)
    if not SV.Terminals.canUse(ply, ent, "infrastructure") then return false end
    if not (Roles.hasFlag(ply, "powerControl") or (SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply))) then
        return false, "Распределение мощности доступно инженерам."
    end
    local s = Facility.sectors[sectorId]
    if not s then return false, "Сектор не найден." end
    if priority > 3 then return false, "Приоритет 0–3." end
    s.priority = priority
    Facility.recompute()
    publish()
    SV.Audit.log("infra", "priority", ply, nil, {sector = sectorId, priority = priority})
    SV.Bus.emit("infra.priority", {ply = ply, sector = sectorId, priority = priority})
    Net.send(ply, "infra.overview", {ent = ent:EntIndex(), data = Facility.overview(ply)})
    return true, priority == 0 and ("Сектор «" .. s.name .. "» обесточен.") or ("Приоритет сектора «" .. s.name .. "»: " .. priority)
end)

--- Damages a node (events, SCP-106 corrosion, explosions).
function Facility.damageNode(n, amount, fault, cause)
    n.health = math.Clamp(n.health - amount, 0, 100)
    if fault and not n.fault then n.fault = fault end
    SV.Bus.emit("node.damaged", {node = n, amount = amount, cause = cause})
end

-- Bullets and explosions damage node entities.
hook.Add("EntityTakeDamage", "SiteVeil.Facility.NodeDamage", function(ent, dmg)
    if not IsValid(ent) or ent:GetClass() ~= "sv_infra_node" then return end
    local n = Facility.nodeForEntity(ent)
    if not n then return end
    local amount = dmg:GetDamage() * 0.4
    if amount < 1 then return end
    Facility.damageNode(n, amount, amount > 20 and "short" or nil, "damage")
    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() then
        SV.Audit.log("infra", "shot", attacker, nil, {node = n.id, amount = amount})
        SV.Bus.emit("node.shot", {ply = attacker, node = n, amount = amount})
    end
end)

SV.Perf.registry("facility.nodes", function() return U.count(Facility.nodes) end)
SV.Perf.registry("facility.sectors", function() return U.count(Facility.sectors) end)

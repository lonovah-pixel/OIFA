--[[---------------------------------------------------------------------------
Per-map configuration (server): loading, saving, validation, automatic
fallback layout, queries and spawning of configured entities.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local MapCfg = SV.MapCfg
local Log = SV.Log
local U = SV.Util

MapCfg.cfg = MapCfg.cfg or nil
MapCfg.source = MapCfg.source or "none"   -- "data", "shipped", "auto"
MapCfg.spawned = MapCfg.spawned or {}     -- point id -> entity
MapCfg.report = MapCfg.report or {errors = {}, warnings = {}}

local DATA_DIR = "siteveil/maps"

local function dataPath(map)
    return DATA_DIR .. "/" .. (map or game.GetMap()) .. ".json"
end

local function emptyConfig()
    return {version = MapCfg.FORMAT_VERSION, map = game.GetMap(), zones = {}, points = {}, doors = {}}
end

local function normalize(cfg)
    cfg.version = cfg.version or MapCfg.FORMAT_VERSION
    cfg.zones = cfg.zones or {}
    cfg.points = cfg.points or {}
    cfg.doors = cfg.doors or {}
    -- JSON turns numeric keys into strings; door keys are MapCreationIDs.
    local doors = {}
    for k, v in pairs(cfg.doors) do doors[tostring(k)] = v end
    cfg.doors = doors
    for _, z in ipairs(cfg.zones) do z.props = z.props or {} end
    for _, p in ipairs(cfg.points) do p.props = p.props or {} end
    return cfg
end

--[[---------------------------------------------------------------------------
Automatic layout ("Автоматический макет")

Used when the map has no configuration. Only positions derived from the
map's own spawn entities are used; every candidate is checked with traces
(floor below, free player hull, line of sight from the spawn), so no
coordinates are invented. The layout is intentionally minimal and is
reported as a validation warning.
---------------------------------------------------------------------------]]
local spawnClasses = {
    "info_player_start", "info_player_deathmatch", "info_player_combine", "info_player_rebel",
    "info_player_counterterrorist", "info_player_terrorist", "gmod_player_start",
}

local HULL_MIN, HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 72)

function MapCfg.floorBelow(pos)
    local tr = util.TraceLine({start = pos + Vector(0, 0, 40), endpos = pos - Vector(0, 0, 300), mask = MASK_SOLID_BRUSHONLY})
    if tr.Hit and not tr.StartSolid and tr.HitNormal.z > 0.7 then return tr.HitPos end
    return nil
end

function MapCfg.hullFree(pos)
    local tr = util.TraceHull({start = pos + Vector(0, 0, 4), endpos = pos + Vector(0, 0, 4), mins = HULL_MIN, maxs = HULL_MAX, mask = MASK_PLAYERSOLID})
    return not tr.Hit and not tr.StartSolid
end

function MapCfg.lineOfSight(a, b)
    local tr = util.TraceLine({start = a + Vector(0, 0, 48), endpos = b + Vector(0, 0, 48), mask = MASK_SOLID_BRUSHONLY})
    return not tr.Hit
end

local function collectSpawnPositions()
    local out = {}
    for _, class in ipairs(spawnClasses) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            local pos = ent:GetPos()
            local dup = false
            for _, o in ipairs(out) do
                if o.pos:DistToSqr(pos) < 32 * 32 then dup = true break end
            end
            if not dup then out[#out + 1] = {pos = pos, ang = ent:GetAngles()} end
        end
    end
    return out
end

local function candidatesAround(origin)
    local list = {}
    for _, radius in ipairs({180, 280, 380, 480}) do
        for i = 0, 7 do
            local yaw = math.rad(i * 45 + radius % 45)
            local probe = origin + Vector(math.cos(yaw) * radius, math.sin(yaw) * radius, 0)
            local floor = MapCfg.floorBelow(probe)
            if floor and math.abs(floor.z - origin.z) < 96 and MapCfg.hullFree(floor) and MapCfg.lineOfSight(origin, floor) then
                list[#list + 1] = floor
            end
        end
    end
    return list
end

function MapCfg.buildAutoLayout()
    local cfg = emptyConfig()
    cfg.auto = true
    cfg.zones[1] = {
        id = "facility", kind = "sector", name = "Комплекс (автоматический макет)",
        boxes = {{min = {-65536, -65536, -65536}, max = {65536, 65536, 65536}}},
        props = {type = "ez", auto = true},
    }

    local spawns = collectSpawnPositions()
    for i, s in ipairs(spawns) do
        cfg.points[#cfg.points + 1] = {id = "auto_spawn_" .. i, kind = "spawn", pos = MapCfg.fromVec(s.pos), ang = MapCfg.fromAng(s.ang), props = {group = "any", auto = true}}
    end

    -- Collect verified candidate spots around all spawns, keep them >= 220u apart.
    local spots = {}
    for _, s in ipairs(spawns) do
        for _, c in ipairs(candidatesAround(s.pos)) do
            local ok = true
            for _, o in ipairs(spots) do
                if o:DistToSqr(c) < 220 * 220 then ok = false break end
            end
            for _, sp in ipairs(spawns) do
                if sp.pos:DistToSqr(c) < 120 * 120 then ok = false break end
            end
            if ok then spots[#spots + 1] = c end
        end
    end

    local plan = {
        {kind = "checkpoint", props = {name = "Пост А"}},
        {kind = "node", props = {subsystem = "power", name = "Распределительный щит"}},
        {kind = "terminal", props = {terminal = "infrastructure"}},
        {kind = "checkpoint", props = {name = "Пост Б"}},
        {kind = "node", props = {subsystem = "comms", name = "Ретранслятор связи"}},
        {kind = "terminal", props = {terminal = "research"}},
        {kind = "locker", props = {locker = "general"}},
        {kind = "node", props = {subsystem = "ventilation", name = "Вентиляционный узел"}},
        {kind = "terminal", props = {terminal = "security"}},
        {kind = "checkpoint", props = {name = "Пост В"}},
        {kind = "node", props = {subsystem = "surveillance", name = "Узел наблюдения"}},
        {kind = "terminal", props = {terminal = "logistics"}},
        {kind = "node", props = {subsystem = "security", name = "Контроллер дверей"}},
        {kind = "locker", props = {locker = "medical"}},
        {kind = "locker", props = {locker = "armory"}},
        {kind = "locker", props = {locker = "engineering"}},
        {kind = "logistics", props = {name = "Площадка поставок"}},
        {kind = "terminal", props = {terminal = "records"}},
        {kind = "terminal", props = {terminal = "medical"}},
        {kind = "locker", props = {locker = "science"}},
    }

    for i, spot in ipairs(spots) do
        local entry = plan[i]
        if not entry then break end
        local props = U.copy(entry.props)
        props.auto = true
        props.sector = "facility"
        cfg.points[#cfg.points + 1] = {
            id = "auto_" .. entry.kind .. "_" .. i, kind = entry.kind,
            pos = MapCfg.fromVec(spot), ang = {0, (i * 47) % 360, 0}, props = props,
        }
    end

    cfg.autoSpots = #spots
    cfg.autoPlanned = math.min(#spots, #plan)
    return cfg
end

--[[---------------------------------------------------------------------------
Validation
---------------------------------------------------------------------------]]
function MapCfg.validate(cfg)
    local errors, warnings = {}, {}
    local function err(fmt, ...) errors[#errors + 1] = string.format(fmt, ...) end
    local function warn(fmt, ...) warnings[#warnings + 1] = string.format(fmt, ...) end

    if not istable(cfg) then
        err("конфигурация отсутствует")
        return {errors = errors, warnings = warnings}
    end
    if cfg.version ~= MapCfg.FORMAT_VERSION then warn("версия формата %s, ожидается %d", tostring(cfg.version), MapCfg.FORMAT_VERSION) end
    if cfg.auto then warn("используется автоматический макет: настройте карту инструментом администратора (см. ADMIN_GUIDE.md)") end

    local zoneIds, sectors = {}, 0
    for i, z in ipairs(cfg.zones) do
        if not isstring(z.id) or z.id == "" then err("зона #%d без идентификатора", i)
        elseif zoneIds[z.id] then err("повторяющийся идентификатор зоны %s", z.id)
        else zoneIds[z.id] = z end
        local kind = MapCfg.zoneKinds[z.kind]
        if not kind then err("зона %s: неизвестный тип %s", tostring(z.id), tostring(z.kind)) end
        if kind and kind.needsProp and not z.props[kind.needsProp] then err("зона %s: не указан параметр %s", tostring(z.id), kind.needsProp) end
        if z.kind == "sector" then sectors = sectors + 1 end
        if not istable(z.boxes) or #z.boxes == 0 then err("зона %s: нет ни одного объёма", tostring(z.id)) end
        for j, b in ipairs(z.boxes or {}) do
            if not (istable(b.min) and istable(b.max)) then
                err("зона %s, объём %d: неверный формат", tostring(z.id), j)
            elseif b.min[1] >= b.max[1] or b.min[2] >= b.max[2] or b.min[3] >= b.max[3] then
                err("зона %s, объём %d: минимум не меньше максимума", tostring(z.id), j)
            end
        end
    end
    if sectors == 0 then err("не настроено ни одного сектора") end

    local pointIds = {}
    local spawnGroups = U.set(MapCfg.spawnGroups())
    local hasSpawn = false
    for i, p in ipairs(cfg.points) do
        if not isstring(p.id) or p.id == "" then err("точка #%d без идентификатора", i)
        elseif pointIds[p.id] then err("повторяющийся идентификатор точки %s", p.id)
        else pointIds[p.id] = p end
        local kind = MapCfg.pointKinds[p.kind]
        if not kind then
            err("точка %s: неизвестный тип %s", tostring(p.id), tostring(p.kind))
        else
            if kind.needsProp and not p.props[kind.needsProp] then err("точка %s: не указан параметр %s", tostring(p.id), kind.needsProp) end
            if kind.entity and not scripted_ents.GetStored(kind.entity) then
                warn("точка %s: класс %s не загружен", tostring(p.id), kind.entity)
            end
        end
        if not istable(p.pos) or #p.pos ~= 3 then
            err("точка %s: неверная позиция", tostring(p.id))
        else
            local pos = MapCfg.toVec(p.pos)
            if not util.IsInWorld(pos) then err("точка %s находится вне мира карты", tostring(p.id)) end
            if p.kind == "spawn" then
                hasSpawn = true
                if not MapCfg.hullFree(pos) then warn("точка появления %s: игрок может застрять", tostring(p.id)) end
                if p.props.group and not spawnGroups[p.props.group] then err("точка появления %s: неизвестная группа %s", tostring(p.id), tostring(p.props.group)) end
            end
        end
        if p.props.sector and not zoneIds[p.props.sector] then err("точка %s: неизвестный сектор %s", tostring(p.id), tostring(p.props.sector)) end
        if p.kind == "node" and p.props.subsystem and SV.Facility and not SV.Facility.subsystems[p.props.subsystem] then
            err("точка %s: неизвестная подсистема %s", tostring(p.id), tostring(p.props.subsystem))
        end
        if p.kind == "terminal" and p.props.terminal and not MapCfg.terminalKinds[p.props.terminal] then
            err("точка %s: неизвестный тип терминала %s", tostring(p.id), tostring(p.props.terminal))
        end
    end
    if not hasSpawn then warn("нет точек появления: используются точки карты") end

    for key, d in pairs(cfg.doors) do
        local id = tonumber(key)
        local ent = id and ents.GetMapCreatedEntity(id)
        if not IsValid(ent) then
            err("дверь %s: сущность карты не найдена", tostring(key))
        elseif ent.isDoor and not ent:isDoor() then
            warn("дверь %s: сущность %s не является дверью", tostring(key), ent:GetClass())
        end
        if d.sector and not zoneIds[d.sector] then err("дверь %s: неизвестный сектор %s", tostring(key), tostring(d.sector)) end
        if d.clearance and (d.clearance < 0 or d.clearance > 5) then err("дверь %s: допуск вне диапазона 0–5", tostring(key)) end
    end

    for _, role in ipairs(SV.Roles.list) do
        if role.scp and not role.hidden then
            local cell
            for _, z in ipairs(cfg.zones) do
                if z.kind == "cell" and z.props.scp == role.scp then cell = z break end
            end
            if not cell then warn("%s: камера содержания не настроена, используется запасной сценарий", role.name) end
        end
    end

    return {errors = errors, warnings = warnings}
end

--[[---------------------------------------------------------------------------
Loading and saving
---------------------------------------------------------------------------]]
local function loadFromData()
    local path = dataPath()
    if not file.Exists(path, "DATA") then return nil end
    local raw = file.Read(path, "DATA")
    local cfg = raw and util.JSONToTable(raw)
    if not istable(cfg) then
        Log.error("mapcfg: файл %s повреждён, используется запасной вариант", path)
        return nil
    end
    return normalize(cfg)
end

local function loadShipped()
    local path = SV.Root .. "mapcfg/" .. game.GetMap() .. ".lua"
    if not file.Exists(path, "LUA") then return nil end
    local ok, cfg = pcall(include, path)
    if not ok or not istable(cfg) then
        Log.error("mapcfg: %s не вернул таблицу конфигурации", path)
        return nil
    end
    return normalize(U.copy(cfg))
end

function MapCfg.load()
    local cfg, source = loadFromData(), "data"
    if not cfg then cfg, source = loadShipped(), "shipped" end
    if not cfg then cfg, source = MapCfg.buildAutoLayout(), "auto" end

    MapCfg.cfg = cfg
    MapCfg.source = source
    MapCfg.reindex()
    MapCfg.report = MapCfg.validate(cfg)

    Log.info("mapcfg: %s (%s), зон %d, точек %d, дверей %d", game.GetMap(), source, #cfg.zones, #cfg.points, U.count(cfg.doors))
    for _, e in ipairs(MapCfg.report.errors) do Log.error("mapcfg: %s", e) end
    for _, w in ipairs(MapCfg.report.warnings) do Log.warn("mapcfg: %s", w) end
    hook.Run("SiteVeil.MapConfigLoaded", cfg, source)
end

function MapCfg.save(actor)
    local cfg = MapCfg.cfg
    if not cfg then return false, "нет конфигурации" end
    cfg.auto = nil
    cfg.map = game.GetMap()
    cfg.savedAt = os.time()
    file.CreateDir(DATA_DIR)
    local path = dataPath()
    if file.Exists(path, "DATA") then
        file.Write(DATA_DIR .. "/" .. game.GetMap() .. ".bak.json", file.Read(path, "DATA") or "")
    end
    file.Write(path, util.TableToJSON(cfg, true))
    MapCfg.source = "data"
    MapCfg.report = MapCfg.validate(cfg)
    SV.Audit.log("admin", "mapcfg.save", actor, nil, {zones = #cfg.zones, points = #cfg.points})
    return true
end

--[[---------------------------------------------------------------------------
Indexes and queries
---------------------------------------------------------------------------]]
MapCfg.zonesByKind = MapCfg.zonesByKind or {}
MapCfg.zoneById = MapCfg.zoneById or {}
MapCfg.pointsByKind = MapCfg.pointsByKind or {}
MapCfg.pointById = MapCfg.pointById or {}

function MapCfg.reindex()
    local cfg = MapCfg.cfg
    MapCfg.zonesByKind, MapCfg.zoneById, MapCfg.pointsByKind, MapCfg.pointById = {}, {}, {}, {}
    for _, z in ipairs(cfg.zones) do
        MapCfg.zoneById[z.id] = z
        MapCfg.zonesByKind[z.kind] = MapCfg.zonesByKind[z.kind] or {}
        table.insert(MapCfg.zonesByKind[z.kind], z)
    end
    for _, p in ipairs(cfg.points) do
        MapCfg.pointById[p.id] = p
        MapCfg.pointsByKind[p.kind] = MapCfg.pointsByKind[p.kind] or {}
        table.insert(MapCfg.pointsByKind[p.kind], p)
    end
end

function MapCfg.zones(kind)
    return MapCfg.zonesByKind[kind] or {}
end

function MapCfg.points(kind)
    return MapCfg.pointsByKind[kind] or {}
end

function MapCfg.zone(id)
    return MapCfg.zoneById[id]
end

function MapCfg.point(id)
    return MapCfg.pointById[id]
end

--- First zone of `kind` containing pos (sectors: smallest box wins so nested
--- sectors work).
function MapCfg.zoneAt(pos, kind)
    local best, bestVol
    for _, z in ipairs(MapCfg.zones(kind)) do
        for _, b in ipairs(z.boxes) do
            if MapCfg.boxContains(b, pos) then
                local vol = (b.max[1] - b.min[1]) * (b.max[2] - b.min[2]) * (b.max[3] - b.min[3])
                if not bestVol or vol < bestVol then best, bestVol = z, vol end
            end
        end
    end
    return best
end

function MapCfg.zonesAt(pos, kind)
    local out = {}
    for _, z in ipairs(MapCfg.zones(kind)) do
        if MapCfg.zoneContains(z, pos) then out[#out + 1] = z end
    end
    return out
end

function MapCfg.sectorAt(pos)
    return MapCfg.zoneAt(pos, "sector")
end

function MapCfg.doorConfig(ent)
    if not IsValid(ent) or not MapCfg.cfg then return nil end
    local id = ent:MapCreationID()
    if not id or id < 0 then return nil end
    return MapCfg.cfg.doors[tostring(id)]
end

--- Picks a spawn position for a role: role id group, then division, then "any",
--- then the map's own spawn points. Returns pos, ang or nil.
function MapCfg.pickSpawn(ply, role)
    local groups = {role.id, role.division or "", "any"}
    local override = hook.Run("SiteVeil.SpawnGroup", ply, role)
    if override then table.insert(groups, 1, override) end

    for _, group in ipairs(groups) do
        local list = {}
        for _, p in ipairs(MapCfg.points("spawn")) do
            if p.props.group == group then list[#list + 1] = p end
        end
        if #list > 0 then
            local p = list[math.random(#list)]
            local pos = DarkRP.findEmptyPos(MapCfg.toVec(p.pos), {ply}, 400, 30, Vector(16, 16, 64))
            return pos, MapCfg.toAng(p.ang)
        end
    end
    return nil
end

--- Random point of kind with optional props filter.
function MapCfg.findPoints(kind, filter)
    local out = {}
    for _, p in ipairs(MapCfg.points(kind)) do
        local ok = true
        for k, v in pairs(filter or {}) do
            if p.props[k] ~= v then ok = false break end
        end
        if ok then out[#out + 1] = p end
    end
    return out
end

--[[---------------------------------------------------------------------------
Entities from points
---------------------------------------------------------------------------]]
function MapCfg.spawnPointEntity(p)
    local kind = MapCfg.pointKinds[p.kind]
    if not kind or not kind.entity then return nil end
    local old = MapCfg.spawned[p.id]
    if IsValid(old) then old:Remove() end
    if not scripted_ents.GetStored(kind.entity) then return nil end

    local ent = ents.Create(kind.entity)
    if not IsValid(ent) then
        Log.error("mapcfg: не удалось создать %s для точки %s", kind.entity, p.id)
        return nil
    end
    ent.SVPoint = p
    ent:SetPos(MapCfg.toVec(p.pos))
    ent:SetAngles(MapCfg.toAng(p.ang))
    ent:Spawn()
    ent:Activate()
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    MapCfg.spawned[p.id] = ent
    return ent
end

function MapCfg.spawnEntities()
    for id, ent in pairs(MapCfg.spawned) do
        if IsValid(ent) then ent:Remove() end
        MapCfg.spawned[id] = nil
    end
    local n = 0
    for _, p in ipairs(MapCfg.cfg.points) do
        if MapCfg.spawnPointEntity(p) then n = n + 1 end
    end
    hook.Run("SiteVeil.MapEntitiesSpawned")
    return n
end

hook.Add("InitPostEntity", "SiteVeil.MapCfg", function()
    MapCfg.load()
    -- Entities are created one tick later so that scripted entities are registered.
    timer.Simple(0, function() MapCfg.spawnEntities() end)
end)

hook.Add("PostCleanupMap", "SiteVeil.MapCfg", function()
    timer.Simple(0, function()
        if MapCfg.cfg then MapCfg.spawnEntities() end
    end)
end)

SV.Perf.registry("mapcfg.entities", function()
    local n = 0
    for _, e in pairs(MapCfg.spawned) do if IsValid(e) then n = n + 1 end end
    return n
end)

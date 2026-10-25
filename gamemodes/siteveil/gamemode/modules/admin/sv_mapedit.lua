--[[---------------------------------------------------------------------------
Map configuration editor (server side of the admin tool).

Only superadmins on duty (privilege SiteVeil_MapConfig). Positions are
always taken on the server from the admin's own position or eye trace, never
from coordinates sent by the client. Properties are filtered by a whitelist
per kind. Changes apply immediately (reindex, infrastructure rebuild,
entity respawn) and are written to data/siteveil/maps/<map>.json on "save".
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Admin = SV.Admin
local MapCfg = SV.MapCfg
local Net = SV.Net
local U = SV.Util

local allowedProps = {
    sector = {type = true, priority = true, demand = true},
    cell = {scp = true}, evac = {}, detention = {}, pocket = {}, lure = {}, testchamber = {}, safe = {},
    spawn = {group = true}, checkpoint = {name = true}, terminal = {terminal = true, clearance = true, tags = true, name = true},
    node = {subsystem = true, name = true, sector = true}, locker = {locker = true}, panel = {scp = true},
    logistics = {name = true}, reinforcement = {group = true}, pocket_exit = {safe = true}, emergence = {}, stash = {},
}

local doorProps = {name = true, clearance = true, tags = true, tagMode = true, sector = true, policy = true,
    failMode = true, autoClose = true, lockdownExempt = true}

local function cleanProps(kind, raw)
    local allow = allowedProps[kind] or {}
    local out = {}
    for k, v in pairs(raw or {}) do
        if allow[k] then
            if isstring(v) then out[k] = U.cleanText(v, 64)
            elseif isnumber(v) then out[k] = math.Clamp(v, -100000, 100000)
            elseif istable(v) then
                local list = {}
                for _, x in ipairs(v) do if isstring(x) and #list < 16 then list[#list + 1] = U.cleanText(x, 32) end end
                out[k] = list
            elseif isbool(v) then out[k] = v end
        end
    end
    return out
end

--- Serialises plain data (tables, strings, numbers, booleans) as Lua source.
function Admin.toLua(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then return tostring(math.Round(v, 3)) end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local inner = indent .. "    "
    local parts = {}
    if #v > 0 then
        for _, x in ipairs(v) do parts[#parts + 1] = inner .. Admin.toLua(x, inner) end
    else
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local key = (isstring(k) and string.match(k, "^[%a_][%w_]*$")) and k or ("[" .. Admin.toLua(k) .. "]")
            parts[#parts + 1] = inner .. key .. " = " .. Admin.toLua(v[k], inner)
        end
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

local function guard(ply)
    if not Admin.isOnDuty(ply) or not Admin.can(ply, "SiteVeil_MapConfig") then
        return false, "Нужны права настройки карты и режим дежурства (/adminduty)."
    end
    return true
end

local function newId(kind)
    local base = kind .. "_" .. os.time() % 100000
    local id, n = base, 1
    while MapCfg.point(id) or MapCfg.zone(id) do
        n = n + 1
        id = base .. "_" .. n
    end
    return id
end

local function applied(changedPointId)
    MapCfg.reindex()
    MapCfg.report = MapCfg.validate(MapCfg.cfg)
    if SV.Facility and SV.Facility.build then SV.Facility.build() end
    if changedPointId then
        local p = MapCfg.point(changedPointId)
        if p then MapCfg.spawnPointEntity(p) end
    end
    if SV.Access then SV.Access.applyDoorStates() end
end

function Admin.sendMapConfig(ply)
    local doors = {}
    for _, ent in ipairs(ents.GetAll()) do
        local c = ent:GetClass()
        if (c == "prop_door_rotating" or c == "func_door" or c == "func_door_rotating" or c == "func_button") and ent:MapCreationID() >= 0 then
            local key = tostring(ent:MapCreationID())
            doors[#doors + 1] = {id = key, class = c, pos = MapCfg.fromVec(ent:GetPos()), cfg = MapCfg.cfg.doors[key], ent = ent:EntIndex()}
        end
    end
    Net.send(ply, "mapcfg.data", {cfg = MapCfg.cfg, source = MapCfg.source, report = MapCfg.report, doors = doors,
        corners = ply.SVMapCorners, map = game.GetMap()})
end

Net.handle("mapcfg.get", function(ply)
    local ok, why = guard(ply)
    if not ok then return false, why end
    Admin.sendMapConfig(ply)
end)

Net.handle("mapcfg.corner", function(ply, which)
    local ok, why = guard(ply)
    if not ok then return false, why end
    if which ~= 1 and which ~= 2 then return false end
    local tr = ply:GetEyeTrace()
    ply.SVMapCorners = ply.SVMapCorners or {}
    ply.SVMapCorners[which] = MapCfg.fromVec(tr.HitPos)
    Admin.sendMapConfig(ply)
    return true, "Угол " .. which .. ": " .. table.concat(ply.SVMapCorners[which], " ")
end)

local function boxFromCorners(ply)
    local c = ply.SVMapCorners
    if not c or not c[1] or not c[2] then return nil, "Отметьте оба угла объёма (ЛКМ и ПКМ инструментом настройки)." end
    local a, b = c[1], c[2]
    local box = {min = {math.min(a[1], b[1]), math.min(a[2], b[2]), math.min(a[3], b[3])},
                 max = {math.max(a[1], b[1]), math.max(a[2], b[2]), math.max(a[3], b[3])}}
    -- Boxes picked on the floor get a usable height.
    if box.max[3] - box.min[3] < 64 then box.max[3] = box.min[3] + 160 end
    if box.max[1] - box.min[1] < 16 or box.max[2] - box.min[2] < 16 then return nil, "Объём слишком мал." end
    return box
end

Net.handle("mapcfg.addPoint", function(ply, kind, props, atEye)
    local ok, why = guard(ply)
    if not ok then return false, why end
    if not MapCfg.pointKinds[kind] then return false, "Неизвестный тип точки." end
    local pos, ang
    if atEye then
        local tr = ply:GetEyeTrace()
        pos = tr.HitPos + tr.HitNormal * 2
        ang = Angle(0, ply:EyeAngles().y + 180, 0)
    else
        pos = ply:GetPos()
        ang = Angle(0, ply:EyeAngles().y, 0)
    end
    local id = newId(kind)
    local p = {id = id, kind = kind, pos = MapCfg.fromVec(pos), ang = MapCfg.fromAng(ang), props = cleanProps(kind, props)}
    table.insert(MapCfg.cfg.points, p)
    applied(id)
    SV.Audit.log("admin", "mapcfg.point", ply, nil, {id = id, kind = kind})
    Admin.sendMapConfig(ply)
    return true, "Точка добавлена: " .. id
end)

Net.handle("mapcfg.removePoint", function(ply, id)
    local ok, why = guard(ply)
    if not ok then return false, why end
    for i, p in ipairs(MapCfg.cfg.points) do
        if p.id == id then
            table.remove(MapCfg.cfg.points, i)
            local ent = MapCfg.spawned[id]
            if IsValid(ent) then ent:Remove() end
            MapCfg.spawned[id] = nil
            applied()
            SV.Audit.log("admin", "mapcfg.removePoint", ply, nil, {id = id})
            Admin.sendMapConfig(ply)
            return true, "Точка удалена."
        end
    end
    return false, "Точка не найдена."
end)

Net.handle("mapcfg.addZone", function(ply, kind, id, name, props)
    local ok, why = guard(ply)
    if not ok then return false, why end
    if not MapCfg.zoneKinds[kind] then return false, "Неизвестный тип зоны." end
    id = string.lower(U.cleanText(id, 32))
    if not string.match(id, "^[%w_]+$") then return false, "Идентификатор: латиница, цифры и подчёркивание." end
    if MapCfg.zone(id) then return false, "Зона с таким идентификатором уже есть. Добавьте объём кнопкой «+ объём»." end
    local box, err = boxFromCorners(ply)
    if not box then return false, err end
    table.insert(MapCfg.cfg.zones, {id = id, kind = kind, name = U.cleanText(name, 64), boxes = {box}, props = cleanProps(kind, props)})
    -- Leaving the automatic layout: its catch-all sector would swallow the new one.
    if MapCfg.cfg.auto and kind == "sector" then
        for i = #MapCfg.cfg.zones, 1, -1 do
            if MapCfg.cfg.zones[i].props.auto then table.remove(MapCfg.cfg.zones, i) end
        end
        for _, p in ipairs(MapCfg.cfg.points) do
            if p.props.sector == "facility" then p.props.sector = nil end
        end
        MapCfg.cfg.auto = nil
    end
    ply.SVMapCorners = nil
    applied()
    SV.Audit.log("admin", "mapcfg.zone", ply, nil, {id = id, kind = kind})
    Admin.sendMapConfig(ply)
    return true, "Зона «" .. id .. "» создана."
end)

Net.handle("mapcfg.addBox", function(ply, id)
    local ok, why = guard(ply)
    if not ok then return false, why end
    local zone = MapCfg.zone(id)
    if not zone then return false, "Зона не найдена." end
    local box, err = boxFromCorners(ply)
    if not box then return false, err end
    table.insert(zone.boxes, box)
    ply.SVMapCorners = nil
    applied()
    Admin.sendMapConfig(ply)
    return true, "Объём добавлен в зону " .. id .. "."
end)

Net.handle("mapcfg.removeZone", function(ply, id)
    local ok, why = guard(ply)
    if not ok then return false, why end
    for i, z in ipairs(MapCfg.cfg.zones) do
        if z.id == id then
            table.remove(MapCfg.cfg.zones, i)
            applied()
            SV.Audit.log("admin", "mapcfg.removeZone", ply, nil, {id = id})
            Admin.sendMapConfig(ply)
            return true, "Зона удалена."
        end
    end
    return false, "Зона не найдена."
end)

local function isDoorEntity(ent)
    if not IsValid(ent) then return false end
    local c = ent:GetClass()
    return (c == "prop_door_rotating" or c == "func_door" or c == "func_door_rotating" or c == "func_button" or c == "func_rot_button")
        and ent:MapCreationID() >= 0
end

Net.handle("mapcfg.setDoor", function(ply, ent, raw)
    local ok, why = guard(ply)
    if not ok then return false, why end
    if not isDoorEntity(ent) then return false, "Это не дверь или кнопка карты." end
    local cfg = {}
    for k, v in pairs(raw) do
        if doorProps[k] then cfg[k] = v end
    end
    cfg.clearance = math.Clamp(math.floor(tonumber(cfg.clearance) or 0), 0, 5)
    if cfg.name then cfg.name = U.cleanText(tostring(cfg.name), 48) end
    if cfg.policy ~= "open" and cfg.policy ~= "locked" then cfg.policy = "card" end
    if cfg.failMode ~= "safe" then cfg.failMode = "secure" end
    if cfg.tagMode ~= "all" then cfg.tagMode = "any" end
    if istable(cfg.tags) then
        local tags = {}
        for _, t in ipairs(cfg.tags) do if SV.Access.TAG_NAMES[t] then tags[#tags + 1] = t end end
        cfg.tags = tags
    else
        cfg.tags = nil
    end
    cfg.autoClose = cfg.autoClose and math.Clamp(tonumber(cfg.autoClose) or 6, 2, 60) or nil
    if cfg.sector and not MapCfg.zone(cfg.sector) then cfg.sector = nil end
    MapCfg.cfg.doors[tostring(ent:MapCreationID())] = cfg
    applied()
    SV.Audit.log("admin", "mapcfg.door", ply, nil, {id = ent:MapCreationID(), cfg = cfg})
    Admin.sendMapConfig(ply)
    return true, "Дверь настроена: допуск " .. cfg.clearance .. "."
end)

Net.handle("mapcfg.removeDoor", function(ply, ent)
    local ok, why = guard(ply)
    if not ok then return false, why end
    if not isDoorEntity(ent) then return false, "Это не дверь карты." end
    MapCfg.cfg.doors[tostring(ent:MapCreationID())] = nil
    ent:Fire("Unlock", "", 0)
    applied()
    Admin.sendMapConfig(ply)
    return true, "Требования двери сняты."
end)

Net.handle("mapcfg.command", function(ply, cmd)
    local ok, why = guard(ply)
    if not ok then return false, why end
    if cmd == "save" then
        local saved, err = MapCfg.save(ply)
        Admin.sendMapConfig(ply)
        if not saved then return false, err end
        local r = MapCfg.report
        return true, string.format("Сохранено. Ошибок: %d, предупреждений: %d.", #r.errors, #r.warnings)
    elseif cmd == "reload" then
        MapCfg.load()
        MapCfg.spawnEntities()
        Admin.sendMapConfig(ply)
        return true, "Конфигурация перечитана (" .. MapCfg.source .. ")."
    elseif cmd == "validate" then
        MapCfg.report = MapCfg.validate(MapCfg.cfg)
        Admin.sendMapConfig(ply)
        return true, string.format("Проверка: ошибок %d, предупреждений %d.", #MapCfg.report.errors, #MapCfg.report.warnings)
    elseif cmd == "respawn" then
        local n = MapCfg.spawnEntities()
        return true, "Пересоздано сущностей: " .. n
    elseif cmd == "auto" then
        MapCfg.cfg = MapCfg.buildAutoLayout()
        applied()
        MapCfg.spawnEntities()
        Admin.sendMapConfig(ply)
        return true, "Построен автоматический макет (не сохранён)."
    elseif cmd == "export" then
        -- A Lua file that can be shipped as gamemode/mapcfg/<map>.lua.
        local text = "-- SITE-VEIL map configuration for " .. game.GetMap() .. ", exported " .. os.date("%Y-%m-%d %H:%M") .. "\nreturn " .. Admin.toLua(MapCfg.cfg) .. "\n"
        file.CreateDir("siteveil/export")
        file.Write("siteveil/export/" .. game.GetMap() .. ".lua.txt", text)
        return true, "Экспортировано в data/siteveil/export/" .. game.GetMap() .. ".lua.txt"
    end
    Net.violation(ply, "unknown mapcfg command")
    return false
end)

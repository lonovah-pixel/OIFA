--[[---------------------------------------------------------------------------
Per-map configuration (shared definitions).

A map configuration consists of
  zones   axis-aligned boxes with a kind (sector, evac, detention, cell, ...)
  points  positions with a kind (spawn, checkpoint, terminal, node, ...)
  doors   access requirements keyed by the door's MapCreationID

Files: garrysmod/data/siteveil/maps/<map>.json (written by the in-game tool).
Shipped defaults: gamemodes/siteveil/gamemode/mapcfg/<map>.lua (server only).
Without either, an automatic layout is generated from the map's spawn points
(see sv_mapcfg.lua, "Автоматический макет").
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.MapCfg = SV.MapCfg or {}
local MapCfg = SV.MapCfg

MapCfg.FORMAT_VERSION = 1

-- Zone kinds. `required` ones produce validation errors when missing.
MapCfg.zoneKinds = {
    sector = {name = "Сектор", required = true},
    evac = {name = "Зона эвакуации"},
    detention = {name = "Камера задержания"},
    cell = {name = "Камера содержания SCP", needsProp = "scp"},
    pocket = {name = "Карманное измерение SCP-106"},
    lure = {name = "Камера приманки SCP-106"},
    testchamber = {name = "Испытательная камера"},
    safe = {name = "Безопасная зона (запрет способностей SCP)"},
}

-- Point kinds. `entity` points spawn an entity of that class.
MapCfg.pointKinds = {
    spawn = {name = "Точка появления", needsProp = "group"},
    checkpoint = {name = "Пост патрулирования"},
    terminal = {name = "Терминал", entity = "sv_terminal", needsProp = "terminal"},
    node = {name = "Инфраструктурный узел", entity = "sv_infra_node", needsProp = "subsystem"},
    locker = {name = "Шкаф снаряжения", entity = "sv_locker", needsProp = "locker"},
    panel = {name = "Панель содержания SCP", entity = "sv_containment_panel", needsProp = "scp"},
    logistics = {name = "Точка поставок"},
    reinforcement = {name = "Точка прибытия подкрепления", needsProp = "group"},
    pocket_exit = {name = "Выход из карманного измерения"},
    emergence = {name = "Точка выхода SCP-106"},
    stash = {name = "Точка тайника"},
}

MapCfg.terminalKinds = {
    research = "Исследовательский терминал",
    infrastructure = "Терминал инфраструктуры",
    security = "Терминал службы безопасности",
    logistics = "Терминал снабжения",
    records = "Архивный терминал",
    medical = "Медицинский терминал",
}

MapCfg.lockerKinds = {
    armory = "Оружейная",
    medical = "Медицинский шкаф",
    engineering = "Инженерный склад",
    science = "Научный склад",
    general = "Хозяйственный склад",
}

-- Spawn groups: role id, division id or "any".
function MapCfg.spawnGroups()
    local out = {"any"}
    for _, div in ipairs(SV.Roles.divisions) do out[#out + 1] = div.id end
    for _, role in ipairs(SV.Roles.list) do
        if role.division then out[#out + 1] = role.id end
    end
    return out
end

--- Box containment test. Boxes are stored as {min = {x,y,z}, max = {x,y,z}}.
function MapCfg.boxContains(box, pos)
    local mn, mx = box.min, box.max
    return pos.x >= mn[1] and pos.x <= mx[1] and pos.y >= mn[2] and pos.y <= mx[2] and pos.z >= mn[3] and pos.z <= mx[3]
end

function MapCfg.zoneContains(zone, pos)
    for _, box in ipairs(zone.boxes or {}) do
        if MapCfg.boxContains(box, pos) then return true end
    end
    return false
end

function MapCfg.toVec(t)
    return Vector(t[1] or 0, t[2] or 0, t[3] or 0)
end

function MapCfg.toAng(t)
    return Angle(t and t[1] or 0, t and t[2] or 0, t and t[3] or 0)
end

function MapCfg.fromVec(v)
    return {math.Round(v.x, 1), math.Round(v.y, 1), math.Round(v.z, 1)}
end

function MapCfg.fromAng(a)
    return {math.Round(a.p, 1), math.Round(a.y, 1), math.Round(a.r, 1)}
end

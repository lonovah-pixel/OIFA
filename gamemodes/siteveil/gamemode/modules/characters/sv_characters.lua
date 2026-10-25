--[[---------------------------------------------------------------------------
Characters (server).

Owns: character records, whitelist, role assignment (the only code path that
changes the DarkRP team), lobby state, spawning, respawn timing, playtime and
experience. Other modules attach their per-character state through the hooks

    SiteVeil.CharacterLoaded(ply, char)       after selection, before spawn
    SiteVeil.CharacterUnloading(ply, char, reason)  before the record is saved
    SiteVeil.RoleAssigned(ply, role, oldRole)
    SiteVeil.RoleSpawn(ply, role)             every spawn with a character
---------------------------------------------------------------------------]]

local SV = SiteVeil
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local Roles = SV.Roles
local Bridge = SV.DarkRP
local Chars = SV.Chars
local C = SV.Config
local BaseClass = SV.BaseClass

Chars.active = Chars.active or {}  -- char id -> ply

DB.registerMigrations("characters", {
    {1, "characters, whitelist, player meta", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_characters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            steamid TEXT NOT NULL,
            name TEXT NOT NULL,
            name_key TEXT NOT NULL,
            number TEXT NOT NULL UNIQUE,
            division TEXT NOT NULL,
            role TEXT NOT NULL,
            rank INTEGER NOT NULL DEFAULT 1,
            xp INTEGER NOT NULL DEFAULT 0,
            playtime INTEGER NOT NULL DEFAULT 0,
            model TEXT,
            data TEXT NOT NULL DEFAULT '{}',
            is_scp INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            last_played INTEGER,
            deleted_at INTEGER
        )]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_characters_owner ON sv_characters (steamid, deleted_at)")
        DB.query("CREATE INDEX IF NOT EXISTS sv_characters_name ON sv_characters (name_key, deleted_at)")
        DB.query([[CREATE TABLE IF NOT EXISTS sv_whitelist (
            steamid TEXT NOT NULL,
            scope TEXT NOT NULL,
            value TEXT NOT NULL,
            granted_by TEXT,
            granted_at INTEGER NOT NULL,
            note TEXT,
            PRIMARY KEY (steamid, scope, value)
        )]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_player_meta (
            steamid TEXT PRIMARY KEY,
            extra_slots INTEGER NOT NULL DEFAULT 0,
            first_seen INTEGER,
            last_seen INTEGER
        )]])
    end},
    {2, "role transfer requests", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_transfers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            char_id INTEGER NOT NULL,
            from_division TEXT NOT NULL,
            to_division TEXT NOT NULL,
            reason TEXT NOT NULL,
            status TEXT NOT NULL,
            decided_by INTEGER,
            created_at INTEGER NOT NULL,
            decided_at INTEGER
        )]])
    end},
})

--[[---------------------------------------------------------------------------
Records
---------------------------------------------------------------------------]]
local function rowToChar(row)
    return {
        id = tonumber(row.id),
        steamid = row.steamid,
        name = row.name,
        number = row.number,
        division = row.division,
        role = row.role,
        rank = tonumber(row.rank) or 1,
        xp = tonumber(row.xp) or 0,
        playtime = tonumber(row.playtime) or 0,
        model = row.model ~= "NULL" and row.model or nil,
        data = DB.decode(row.data),
        isSCP = tonumber(row.is_scp) == 1,
        createdAt = tonumber(row.created_at),
        lastPlayed = tonumber(row.last_played),
    }
end
Chars.rowToChar = rowToChar

function Chars.listFor(steamid)
    local rows = DB.query("SELECT * FROM sv_characters WHERE steamid = ? AND deleted_at IS NULL ORDER BY id", steamid) or {}
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = rowToChar(row) end
    return out
end

function Chars.loadById(id)
    local row = DB.queryRow("SELECT * FROM sv_characters WHERE id = ? AND deleted_at IS NULL", id)
    return row and rowToChar(row) or nil
end

function Chars.save(char)
    if not char or not char.id then return end
    DB.defer("char:" .. char.id, function()
        DB.query([[UPDATE sv_characters SET name = ?, division = ?, role = ?, rank = ?, xp = ?, playtime = ?,
            model = ?, data = ?, last_played = ? WHERE id = ?]],
            char.name, char.division, char.role, char.rank, char.xp, char.playtime,
            char.model, DB.encode(char.data), os.time(), char.id)
    end)
end

function Chars.saveNow(char)
    Chars.save(char)
    DB.flushKey("char:" .. char.id)
end

function Chars.slotsFor(steamid)
    local extra = tonumber(DB.queryValue("SELECT extra_slots FROM sv_player_meta WHERE steamid = ?", steamid)) or 0
    return math.min(C.Characters.slots + extra, C.Characters.maxSlots)
end

local function generateNumber()
    for _ = 1, 100 do
        local num = string.format("%05d", math.random(10000, 99999))
        if not DB.queryValue("SELECT 1 FROM sv_characters WHERE number = ?", num) then return num end
    end
    return nil
end

--[[---------------------------------------------------------------------------
Whitelist
---------------------------------------------------------------------------]]
function Chars.hasWhitelist(steamid, scope, value)
    return DB.queryValue("SELECT 1 FROM sv_whitelist WHERE steamid = ? AND scope = ? AND value = ?", steamid, scope, value) ~= nil
end

function Chars.grantWhitelist(steamid, scope, value, admin, note)
    local ok = DB.exec("INSERT OR REPLACE INTO sv_whitelist (steamid, scope, value, granted_by, granted_at, note) VALUES (?, ?, ?, ?, ?, ?)",
        steamid, scope, value, IsValid(admin) and admin:SteamID64() or "console", os.time(), note or "")
    SV.Audit.log("admin", "whitelist.grant", admin, nil, {steamid = steamid, scope = scope, value = value, note = note})
    return ok
end

function Chars.revokeWhitelist(steamid, scope, value, admin)
    local ok = DB.exec("DELETE FROM sv_whitelist WHERE steamid = ? AND scope = ? AND value = ?", steamid, scope, value)
    SV.Audit.log("admin", "whitelist.revoke", admin, nil, {steamid = steamid, scope = scope, value = value})
    return ok
end

function Chars.whitelistFor(steamid)
    return DB.query("SELECT scope, value, granted_at, note FROM sv_whitelist WHERE steamid = ? ORDER BY scope, value", steamid) or {}
end

local function divisionWhitelisted(steamid, divId)
    return Chars.hasWhitelist(steamid, "division", divId)
end

local function roleWhitelisted(steamid, role)
    return Chars.hasWhitelist(steamid, "role", role.id) or (role.division and divisionWhitelisted(steamid, role.division))
end

--[[---------------------------------------------------------------------------
Client list
---------------------------------------------------------------------------]]
function Chars.sendList(ply)
    local steamid = ply:SteamID64()
    local list = {}
    for _, char in ipairs(Chars.listFor(steamid)) do
        local div = Roles.getDivision(char.division)
        local role = Roles.get(char.role)
        list[#list + 1] = {
            id = char.id, name = char.name, number = char.number,
            division = char.division, divisionName = div and div.name or char.division,
            role = char.role, roleName = role and role.name or char.role,
            rank = char.rank, rankName = Roles.rankName(char.division, char.rank),
            playtime = char.playtime, lastPlayed = char.lastPlayed, isSCP = char.isSCP,
            active = Chars.active[char.id] ~= nil,
        }
    end

    local startDivs = {}
    for _, divId in ipairs(C.Characters.startDivisions) do
        local div = Roles.getDivision(divId)
        if div then startDivs[#startDivs + 1] = {id = div.id, name = div.name} end
    end
    -- Whitelisted divisions can also be chosen at creation.
    for _, div in ipairs(Roles.divisions) do
        if div.whitelist and div.id ~= "scp" and divisionWhitelisted(steamid, div.id) then
            startDivs[#startDivs + 1] = {id = div.id, name = div.name, whitelisted = true}
        end
    end

    local scpRoles = {}
    for _, role in ipairs(Roles.list) do
        if role.scp and not role.hidden then
            local ok, reason = Chars.canTakeRole(ply, role, {asSCP = true})
            scpRoles[#scpRoles + 1] = {id = role.id, name = role.name, ok = ok, reason = reason}
        end
    end

    Net.send(ply, "char.list", {
        chars = list,
        slots = Chars.slotsFor(steamid),
        divisions = startDivs,
        scp = scpRoles,
        current = ply.SVChar and ply.SVChar.id or nil,
    })
end

--[[---------------------------------------------------------------------------
Creation and deletion
---------------------------------------------------------------------------]]
function Chars.create(ply, rawName, divisionId, modelIndex)
    if not DB.ready then return false, "База данных недоступна, создание персонажей временно отключено." end
    local steamid = ply:SteamID64()

    local name, why = Chars.validateName(rawName)
    if not name then return false, why end

    local div = Roles.getDivision(divisionId)
    if not div or div.id == "scp" then return false, "Неизвестное подразделение." end
    if not div.selectable and not divisionWhitelisted(steamid, div.id) then
        return false, "Подразделение «" .. div.name .. "» доступно только по допуску (whitelist)."
    end

    local existing = Chars.listFor(steamid)
    local regular = 0
    for _, c in ipairs(existing) do if not c.isSCP then regular = regular + 1 end end
    if regular >= Chars.slotsFor(steamid) then return false, "Все слоты персонажей заняты." end

    local key = U.lowerRu(name)
    if DB.queryValue("SELECT 1 FROM sv_characters WHERE name_key = ? AND deleted_at IS NULL", key) then
        return false, "Персонаж с таким именем уже существует."
    end

    local role = Roles.get(div.defaultRole)
    local models = role and role.models or {C.FallbackModel}
    local model = models[math.Clamp(modelIndex or 1, 1, #models)]

    local number = generateNumber()
    if not number then return false, "Не удалось выдать служебный номер, попробуйте ещё раз." end

    local ok, idOrErr = DB.transaction(function()
        DB.query([[INSERT INTO sv_characters (steamid, name, name_key, number, division, role, rank, xp, playtime, model, data, is_scp, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 1, 0, 0, ?, '{}', 0, ?)]], steamid, name, key, number, div.id, div.defaultRole, model, os.time())
        return DB.lastInsertId()
    end)
    if not ok then return false, "Ошибка базы данных при создании персонажа." end

    SV.Audit.log("character", "create", ply, nil, {id = idOrErr, name = name, division = div.id})
    hook.Run("SiteVeil.CharacterCreated", ply, idOrErr, div.id)
    return true, "Персонаж «" .. name .. "» создан. Служебный номер: " .. number .. "."
end

--- SCP characters are created on demand, one per SCP role per player.
local function ensureSCPCharacter(ply, role)
    local steamid = ply:SteamID64()
    local row = DB.queryRow("SELECT * FROM sv_characters WHERE steamid = ? AND role = ? AND is_scp = 1 AND deleted_at IS NULL", steamid, role.id)
    if row then return rowToChar(row) end
    local number = generateNumber()
    if not number then return nil end
    DB.query([[INSERT INTO sv_characters (steamid, name, name_key, number, division, role, rank, xp, playtime, model, data, is_scp, created_at)
        VALUES (?, ?, ?, ?, 'scp', ?, 1, 0, 0, ?, '{}', 1, ?)]], steamid, role.name, "scp:" .. role.id .. ":" .. steamid, number, role.id, role.models[1], os.time())
    return Chars.loadById(DB.lastInsertId())
end

function Chars.delete(ply, id, confirm)
    local char = Chars.loadById(id)
    if not char or char.steamid ~= ply:SteamID64() then return false, "Персонаж не найден." end
    if Chars.active[id] then return false, "Нельзя удалить активного персонажа. Сначала вернитесь к выбору персонажа." end
    if char.isSCP then return false, "Профиль SCP не удаляется." end
    if U.lowerRu(U.cleanText(confirm or "")) ~= U.lowerRu(char.name) then
        return false, "Для удаления введите имя персонажа полностью."
    end

    local ok = DB.transaction(function()
        DB.query("UPDATE sv_characters SET deleted_at = ? WHERE id = ?", os.time(), id)
        hook.Run("SiteVeil.CharacterDeleted", id)
    end)
    if not ok then return false, "Ошибка базы данных." end
    SV.Audit.log("character", "delete", ply, nil, {id = id, name = char.name})
    return true, "Персонаж «" .. char.name .. "» удалён."
end

--[[---------------------------------------------------------------------------
Role assignment
---------------------------------------------------------------------------]]
function Chars.countInRole(role, except)
    local n = 0
    for _, p in ipairs(player.GetAll()) do
        if p ~= except and p:Team() == role.team then n = n + 1 end
    end
    return n
end

--- Checks whether ply may take role now. Returns ok, reason.
--  opts.asSCP: SCP selection from the character screen
--  opts.reinforcement: called by the reinforcement wave system
--  opts.restore: returning to the saved role of a character on selection
function Chars.canTakeRole(ply, role, opts)
    opts = opts or {}
    if not role then return false, "Неизвестная роль." end
    if role.hidden and not opts.system then return false, "Роль назначается только игровыми системами." end

    local steamid = ply:SteamID64()

    if role.scp then
        if not opts.asSCP and not opts.system then return false, "Роль SCP выбирается на экране персонажей." end
        if role.whitelist and not opts.system and not roleWhitelisted(steamid, role) then
            return false, "Нет допуска к игре за " .. role.name .. "."
        end
    else
        local char = ply.SVChar
        if not char then return false, "Персонаж не выбран." end
        if role.division ~= char.division then return false, "Роль относится к другому подразделению. Требуется перевод." end
        if char.rank < role.minRank then
            return false, "Требуется звание «" .. Roles.rankName(role.division, role.minRank) .. "» или выше."
        end
        if role.whitelist and not roleWhitelisted(steamid, role) then
            return false, "Роль доступна только по допуску (whitelist)."
        end
        if role.reinforcement and not opts.reinforcement then
            return false, "Роль доступна только при развёртывании подкрепления."
        end
    end

    local slots = Roles.quotaFor(role, U.onlineCount())
    if slots ~= nil and not opts.ignoreQuota then
        if slots <= 0 then
            local q = role.quota
            if q.minOnline then
                return false, "Роль открывается при онлайне от " .. q.minOnline .. " игроков."
            end
            return false, "Сейчас нет свободных мест для этой роли."
        end
        if Chars.countInRole(role, ply) >= slots then
            return false, "Все места заняты (" .. slots .. ")."
        end
    end

    local veto, reason = hook.Run("SiteVeil.CanTakeRole", ply, role, opts)
    if veto == false then return false, reason or "Смена роли сейчас невозможна." end
    return true
end

--- Assigns a role (must have passed canTakeRole). Returns ok, message.
function Chars.assignRole(ply, role, opts)
    opts = opts or {}
    local oldRole = Roles.ofPlayer(ply)
    hook.Run("SiteVeil.BeforeRoleChange", ply, role, oldRole)
    if not Bridge.setTeam(ply, role.team) then
        return false, "DarkRP отклонил смену роли."
    end

    local char = ply.SVChar
    if char and not role.scp and not role.flags.temporary and not role.reinforcement then
        char.role = role.id
        Chars.save(char)
    end

    ply.SVRoleSince = CurTime()
    ply:setDarkRPVar("job", role.name)
    hook.Run("SiteVeil.RoleAssigned", ply, role, oldRole, opts)
    SV.Audit.log("character", "role", ply, nil, {role = role.id, from = oldRole and oldRole.id or nil, reason = opts.reason})

    -- Dead players keep their respawn timer; living ones are re-equipped now.
    if opts.respawn ~= false and ply:Alive() then
        ply:Spawn()
    end
    return true
end

function Chars.takeRole(ply, roleId)
    local role = Roles.get(roleId)
    if role and Roles.ofPlayer(ply) == role then return false, "Вы уже занимаете эту должность." end
    local ok, reason = Chars.canTakeRole(ply, role)
    if not ok then return false, reason end

    local last = ply.SVLastRoleChange or 0
    if CurTime() - last < 60 then
        return false, "Сменить должность можно через " .. U.formatDuration(60 - (CurTime() - last)) .. "."
    end
    if CurTime() - (ply.SVLastCombat or -1000) < C.Characters.combatLock then
        return false, "Нельзя менять должность во время боя."
    end

    ply.SVLastRoleChange = CurTime()
    return Chars.assignRole(ply, role, {reason = "self"})
end

--[[---------------------------------------------------------------------------
Selection, lobby and unloading
---------------------------------------------------------------------------]]
local function applyPublicVars(ply, char)
    ply:setDarkRPVar("rpname", char.name)
    ply:setDarkRPVar("sv_num", char.number)
    ply:setDarkRPVar("sv_div", char.division)
    ply:setDarkRPVar("sv_rank", char.rank)
end

local function publishSelf(ply)
    local char = ply.SVChar
    if not char then
        SV.Sync.setFor(ply, "self", "char", nil)
        return
    end
    SV.Sync.setFor(ply, "self", "char", {
        id = char.id, name = char.name, number = char.number, division = char.division,
        role = char.role, rank = char.rank, xp = char.xp, playtime = char.playtime, isSCP = char.isSCP,
    })
end
Chars.publishSelf = publishSelf

function Chars.enterLobby(ply)
    ply:StripWeapons()
    ply:SetNoDraw(true)
    ply:SetNotSolid(true)
    ply:SetNoTarget(true)
    ply:GodEnable()
    ply:Freeze(true)
    ply:DrawShadow(false)
end

function Chars.leaveLobby(ply)
    ply:SetNoDraw(false)
    ply:SetNotSolid(false)
    ply:SetNoTarget(false)
    ply:GodDisable()
    ply:Freeze(false)
    ply:DrawShadow(true)
end

function Chars.unload(ply, reason)
    local char = ply.SVChar
    if not char then return end
    hook.Run("SiteVeil.CharacterUnloading", ply, char, reason)
    char.lastPlayed = os.time()
    Chars.saveNow(char)
    Chars.active[char.id] = nil
    ply.SVChar = nil
    SV.Audit.log("character", "unload", ply, nil, {id = char.id, reason = reason})

    if reason ~= "disconnect" and IsValid(ply) then
        Bridge.setTeam(ply, Bridge.lobbyTeam)
        ply:setDarkRPVar("rpname", ply:SteamName())
        ply:setDarkRPVar("sv_num", nil)
        ply:setDarkRPVar("sv_div", nil)
        ply:setDarkRPVar("sv_rank", nil)
        publishSelf(ply)
        ply:Spawn()
        Chars.sendList(ply)
    end
end

--- Selects a character. opts.role (role table) with opts.reinforcement is
--- used by reinforcement waves to deploy a character directly in a wave role.
function Chars.select(ply, id, opts)
    opts = opts or {}
    if not DB.ready then return false, "База данных недоступна." end
    local char = Chars.loadById(id)
    if not char or char.steamid ~= ply:SteamID64() then return false, "Персонаж не найден." end
    if ply.SVChar and ply.SVChar.id == id then return false, "Этот персонаж уже выбран." end
    if Chars.active[id] then return false, "Персонаж уже используется." end

    if ply.SVChar then
        local ok, reason = Chars.canSwitch(ply)
        if not ok then return false, reason end
        Chars.unload(ply, "switch")
    end

    -- Resolve the role to return to.
    local role = Roles.get(char.role)
    if opts.role then
        role = opts.role
        ply.SVChar = char
        local ok, reason = Chars.canTakeRole(ply, role, {reinforcement = opts.reinforcement, restore = true})
        if not ok then
            ply.SVChar = nil
            return false, reason
        end
    elseif char.isSCP then
        local ok, reason = Chars.canTakeRole(ply, role, {asSCP = true})
        if not ok then return false, reason end
    else
        local div = Roles.getDivision(char.division)
        ply.SVChar = char -- canTakeRole needs the character
        local ok = role and not role.hidden and not role.reinforcement and Chars.canTakeRole(ply, role, {restore = true})
        if not ok then
            role = div and Roles.get(div.defaultRole)
            if not role then
                ply.SVChar = nil
                return false, "У подразделения нет базовой роли. Обратитесь к администратору."
            end
            local okDefault, reasonDefault = Chars.canTakeRole(ply, role, {restore = true})
            if not okDefault then
                ply.SVChar = nil
                return false, reasonDefault
            end
        end
    end

    ply.SVChar = char
    Chars.active[char.id] = ply
    char.sessionStart = CurTime()
    applyPublicVars(ply, char)
    publishSelf(ply)
    Chars.leaveLobby(ply)

    hook.Run("SiteVeil.CharacterLoaded", ply, char)
    SV.Audit.log("character", "select", ply, nil, {id = char.id})

    ply.SVLastSwitch = CurTime()
    local ok, msg = Chars.assignRole(ply, role, {reason = opts.reinforcement and "reinforcement" or "select", reinforcement = opts.reinforcement})
    if not ok then
        Chars.unload(ply, "error")
        return false, msg
    end
    Net.send(ply, "char.selected", {id = char.id})
    return true, "Вы на смене: " .. role.name .. "."
end

function Chars.canSwitch(ply)
    if CurTime() - (ply.SVLastSwitch or -10000) < C.Characters.switchCooldown then
        return false, "Сменить персонажа можно через " .. U.formatDuration(C.Characters.switchCooldown - (CurTime() - ply.SVLastSwitch)) .. "."
    end
    if CurTime() - (ply.SVLastCombat or -10000) < C.Characters.combatLock then
        return false, "Нельзя сменить персонажа во время боя."
    end
    local veto, reason = hook.Run("SiteVeil.CanSwitchCharacter", ply)
    if veto == false then return false, reason end
    return true
end

--[[---------------------------------------------------------------------------
Progression: experience and ranks
---------------------------------------------------------------------------]]

--- Adds experience. Sources are capped per shift (SiteVeil.Config.XPCaps).
function Chars.addXP(ply, amount, source)
    local char = ply.SVChar
    if not char or char.isSCP or amount <= 0 then return 0 end
    local caps = C.XPCaps or {}
    local cap = caps[source] or caps.default
    if cap then
        char.data.xpShift = char.data.xpShift or {}
        local shiftId = SV.Shift and SV.Shift.id or 0
        if char.data.xpShiftId ~= shiftId then
            char.data.xpShift = {}
            char.data.xpShiftId = shiftId
        end
        local used = char.data.xpShift[source] or 0
        amount = math.min(amount, math.max(cap - used, 0))
        char.data.xpShift[source] = used + amount
    end
    if amount <= 0 then return 0 end
    char.xp = char.xp + amount
    Chars.save(char)
    publishSelf(ply)
    hook.Run("SiteVeil.XPGained", ply, amount, source)
    return amount
end

--- Conditions for promoting a character to the next rank.
--  Returns {rank, conditions = {{text, met}}, needsApproval, possible}
function Chars.promotionStatus(char)
    local div = Roles.getDivision(char.division)
    if not div then return {possible = false, conditions = {}} end
    local nextRank = char.rank + 1
    if nextRank > #div.ranks then
        return {rank = char.rank, possible = false, max = true, conditions = {{text = "Достигнуто высшее звание подразделения", met = true}}}
    end
    local needXP = div.rankXP[nextRank] or 0
    local needHours = div.rankHours[nextRank] or 0
    local conditions = {
        {text = string.format("Опыт: %d / %d", char.xp, needXP), met = char.xp >= needXP},
        {text = string.format("Время на службе: %.1f / %d ч", char.playtime / 3600, needHours), met = char.playtime >= needHours * 3600},
    }
    local needsApproval = nextRank >= div.approvalFromRank
    if needsApproval then
        table.insert(conditions, {text = "Требуется приказ старшего по званию (звание выше «" .. div.ranks[nextRank] .. "») или администрации", met = false, approval = true})
    end
    local possible = true
    for _, c in ipairs(conditions) do
        if not c.met and not c.approval then possible = false end
    end
    return {rank = nextRank, rankName = div.ranks[nextRank], conditions = conditions, needsApproval = needsApproval, possible = possible}
end

--- Promotes `target` (self-promotion when no approval is needed).
function Chars.promote(actor, target)
    local char = IsValid(target) and target.SVChar
    if not char or char.isSCP then return false, "Нет персонажа для повышения." end
    local status = Chars.promotionStatus(char)
    if not status.possible then return false, "Условия повышения не выполнены." end

    if status.needsApproval then
        if actor == target then return false, "Для этого звания нужен приказ старшего по званию." end
        local actorChar = IsValid(actor) and actor.SVChar
        local adminOk = IsValid(actor) and actor:IsAdmin() and SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(actor)
        local seniorOk = actorChar and actorChar.division == char.division and actorChar.rank > status.rank
            and (Roles.hasFlag(actor, "promote") or Roles.hasFlag(actor, "divisionHead"))
        local directorOk = Roles.hasFlag(actor, "approveTransfers")
        if not (adminOk or seniorOk or directorOk) then
            return false, "Недостаточно полномочий для присвоения звания «" .. status.rankName .. "»."
        end
        if not U.within(actor, target, 300) then return false, "Подойдите к сотруднику." end
    elseif actor ~= target then
        return false, "Это звание присваивается автоматически при выполнении условий."
    end

    char.rank = status.rank
    Chars.saveNow(char)
    target:setDarkRPVar("sv_rank", char.rank)
    publishSelf(target)
    SV.Audit.log("character", "promote", actor, target, {rank = char.rank, division = char.division})
    hook.Run("SiteVeil.Promoted", target, char.rank, actor)
    DarkRP.notify(target, 0, 6, "Вам присвоено звание «" .. status.rankName .. "».")
    return true, actor ~= target and ("Звание присвоено: " .. target:Nick()) or nil
end

--[[---------------------------------------------------------------------------
Division transfers (смена подразделения)
---------------------------------------------------------------------------]]
function Chars.requestTransfer(ply, divId, reason)
    local char = ply.SVChar
    if not char or char.isSCP then return false, "Нет персонажа." end
    local div = Roles.getDivision(divId)
    if not div or div.id == "scp" or div.id == char.division then return false, "Некорректное подразделение." end
    if not div.selectable and not divisionWhitelisted(ply:SteamID64(), div.id) then
        return false, "Перевод в «" .. div.name .. "» требует допуска (whitelist)."
    end
    reason = U.cleanText(reason, 200)
    if U.utf8len(reason) < 10 then return false, "Опишите причину перевода (не короче 10 символов)." end
    if DB.queryValue("SELECT 1 FROM sv_transfers WHERE char_id = ? AND status = 'pending'", char.id) then
        return false, "У вас уже есть рассматриваемый запрос на перевод."
    end
    DB.query("INSERT INTO sv_transfers (char_id, from_division, to_division, reason, status, created_at) VALUES (?, ?, ?, ?, 'pending', ?)",
        char.id, char.division, div.id, reason, os.time())
    SV.Audit.log("character", "transfer.request", ply, nil, {to = div.id})
    for _, p in ipairs(player.GetAll()) do
        if Roles.hasFlag(p, "approveTransfers") or (p:IsAdmin() and SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(p)) then
            DarkRP.notify(p, 0, 6, "Новый запрос на перевод: " .. char.name .. " → " .. div.name)
        end
    end
    return true, "Запрос на перевод отправлен в администрацию."
end

function Chars.pendingTransfers()
    local rows = DB.query([[SELECT t.*, c.name AS char_name FROM sv_transfers t JOIN sv_characters c ON c.id = t.char_id
        WHERE t.status = 'pending' ORDER BY t.id]]) or {}
    return rows
end

function Chars.decideTransfer(actor, id, approve)
    local isAdmin = actor:IsAdmin() and SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(actor)
    if not (Roles.hasFlag(actor, "approveTransfers") or isAdmin) then return false, "Нет полномочий." end
    local row = DB.queryRow("SELECT * FROM sv_transfers WHERE id = ? AND status = 'pending'", id)
    if not row then return false, "Запрос не найден." end
    local charId = tonumber(row.char_id)
    if actor.SVChar and actor.SVChar.id == charId then return false, "Нельзя рассматривать собственный запрос." end

    DB.query("UPDATE sv_transfers SET status = ?, decided_by = ?, decided_at = ? WHERE id = ?",
        approve and "approved" or "rejected", actor.SVChar and actor.SVChar.id or 0, os.time(), id)
    SV.Audit.log("character", "transfer." .. (approve and "approve" or "reject"), actor, nil, {transfer = id, char = charId})

    local target = Chars.active[charId]
    if approve then
        local div = Roles.getDivision(row.to_division)
        if IsValid(target) then
            target.SVChar.division = div.id
            target.SVChar.rank = 1
            target.SVChar.role = div.defaultRole
            Chars.saveNow(target.SVChar)
            applyPublicVars(target, target.SVChar)
            publishSelf(target)
            Chars.assignRole(target, Roles.get(div.defaultRole), {reason = "transfer", system = true})
            DarkRP.notify(target, 0, 8, "Перевод одобрен: вы зачислены в «" .. div.name .. "».")
        else
            DB.query("UPDATE sv_characters SET division = ?, rank = 1, role = ? WHERE id = ?", div.id, div.defaultRole, charId)
        end
    elseif IsValid(target) then
        DarkRP.notify(target, 1, 8, "Запрос на перевод отклонён.")
    end
    return true, approve and "Перевод одобрен." or "Перевод отклонён."
end

--[[---------------------------------------------------------------------------
Network handlers
---------------------------------------------------------------------------]]
Net.handle("char.list", function(ply) Chars.sendList(ply) end)

Net.handle("char.create", function(ply, name, division, model)
    local ok, msg = Chars.create(ply, name, division, model)
    Chars.sendList(ply)
    return ok, msg
end)

Net.handle("char.select", function(ply, id)
    local ok, msg = Chars.select(ply, id)
    if not ok then Chars.sendList(ply) end
    return ok, msg
end)

Net.handle("char.delete", function(ply, id, confirm)
    local ok, msg = Chars.delete(ply, id, confirm)
    Chars.sendList(ply)
    return ok, msg
end)

Net.handle("char.unload", function(ply)
    local ok, reason = Chars.canSwitch(ply)
    if not ok then return false, reason end
    Chars.unload(ply, "switch")
    return true
end)

Net.handle("char.takeRole", function(ply, roleId)
    return Chars.takeRole(ply, roleId)
end)

Net.handle("char.promote", function(ply, target)
    if not IsValid(target) or not target:IsPlayer() then target = ply end
    return Chars.promote(ply, target)
end)

Net.handle("char.transfer", function(ply, divId, reason)
    return Chars.requestTransfer(ply, divId, reason)
end)

Net.handle("char.transferDecide", function(ply, id, approve)
    return Chars.decideTransfer(ply, id, approve)
end)

--- Role availability for the division tab and the promotion checklist.
Net.handle("char.roles", function(ply)
    local char = ply.SVChar
    local current = Roles.ofPlayer(ply)
    local roles = {}
    local div = Roles.getDivision(char.division)
    if div and not char.isSCP then
        for _, role in ipairs(div.roles) do
            if not role.hidden and not role.reinforcement then
                local ok, reason = Chars.canTakeRole(ply, role)
                roles[#roles + 1] = {
                    id = role.id, ok = ok and current ~= role, reason = reason, current = current == role,
                    count = Chars.countInRole(role), slots = Roles.quotaFor(role, U.onlineCount()),
                }
            end
        end
    end

    local targets = {}
    for _, d in ipairs(Roles.divisions) do
        if d.id ~= char.division and d.id ~= "scp" and (d.selectable or divisionWhitelisted(ply:SteamID64(), d.id)) then
            targets[#targets + 1] = {id = d.id, name = d.name}
        end
    end

    local canDecide = Roles.hasFlag(ply, "approveTransfers") or (ply:IsAdmin() and SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply))
    Net.send(ply, "char.roles", {
        roles = roles,
        online = U.onlineCount(),
        promotion = Chars.promotionStatus(char),
        transferTargets = targets,
        pendingTransfer = DB.queryValue("SELECT 1 FROM sv_transfers WHERE char_id = ? AND status = 'pending'", char.id) ~= nil,
        transfers = canDecide and Chars.pendingTransfers() or nil,
    })
end)

--- Selecting an SCP from the character screen.
Net.define("char.selectSCP", {args = {"str:32"}, allowNoChar = true, ignoreStates = true, rate = {burst = 2, refill = 0.1}})
Net.handle("char.selectSCP", function(ply, roleId)
    local role = Roles.get(roleId)
    if not role or not role.scp or role.hidden then return false, "Неизвестный объект." end
    local ok, reason = Chars.canTakeRole(ply, role, {asSCP = true})
    if not ok then return false, reason end
    local char = ensureSCPCharacter(ply, role)
    if not char then return false, "Ошибка базы данных." end
    return Chars.select(ply, char.id)
end)

--[[---------------------------------------------------------------------------
Gamemode integration
---------------------------------------------------------------------------]]
hook.Add("PlayerInitialSpawn", "SiteVeil.Chars", function(ply)
    if ply:IsBot() then return end
    local sid = ply:SteamID64()
    -- INSERT OR IGNORE + UPDATE instead of an UPSERT: works on every SQLite
    -- version shipped with Garry's Mod.
    DB.query("INSERT OR IGNORE INTO sv_player_meta (steamid, extra_slots, first_seen, last_seen) VALUES (?, 0, ?, ?)", sid, os.time(), os.time())
    DB.query("UPDATE sv_player_meta SET last_seen = ? WHERE steamid = ?", os.time(), sid)
end)

hook.Add("SiteVeil.ClientReady", "SiteVeil.Chars", function(ply)
    Chars.sendList(ply)
end)

hook.Add("PlayerDisconnected", "SiteVeil.Chars", function(ply)
    if ply.SVChar then Chars.unload(ply, "disconnect") end
end)

hook.Add("ShutDown", "SiteVeil.Chars", function()
    for _, ply in ipairs(player.GetAll()) do
        if ply.SVChar then
            hook.Run("SiteVeil.CharacterUnloading", ply, ply.SVChar, "shutdown")
            Chars.save(ply.SVChar)
        end
    end
    DB.flush()
end)

-- Combat marker used by switching rules.
hook.Add("EntityTakeDamage", "SiteVeil.Chars.Combat", function(ent, dmg)
    if not ent:IsPlayer() or dmg:GetDamage() < 1 then return end
    ent.SVLastCombat = CurTime()
    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() then attacker.SVLastCombat = CurTime() end
end)

-- Lobby players cannot be damaged.
hook.Add("EntityTakeDamage", "SiteVeil.Chars.Lobby", function(ent)
    if ent:IsPlayer() and not ent.SVChar then return true end
end)

-- Playtime: once per minute for active characters.
timer.Create("SiteVeil.Chars.Playtime", 60, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local char = ply.SVChar
        if char and ply:Alive() then
            char.playtime = char.playtime + 60
            Chars.save(char)
            publishSelf(ply)
        end
    end
end)

local function pickModel(ply, role)
    local char = ply.SVChar
    local models = role.models or {}
    if char and char.model then
        for _, m in ipairs(models) do
            if m == char.model and util.IsValidModel(m) then return m end
        end
    end
    -- Stable choice per character so the model does not change every spawn.
    if #models > 0 then
        local idx = char and (char.id % #models) + 1 or 1
        if util.IsValidModel(models[idx]) then return models[idx] end
        for _, m in ipairs(models) do
            if util.IsValidModel(m) then return m end
        end
    end
    return C.FallbackModel
end
Chars.pickModel = pickModel

function GM:PlayerSetModel(ply)
    local role = Roles.ofPlayer(ply)
    if not ply.SVChar or not role then
        ply:SetModel(C.FallbackModel)
        return
    end
    ply:SetModel(pickModel(ply, role))
    ply:SetupHands()
end

function GM:PlayerLoadout(ply)
    if not ply.SVChar then
        ply:StripWeapons()
        return true
    end
    BaseClass.PlayerLoadout(self, ply)
    return true
end

function GM:PlayerSpawn(ply)
    BaseClass.PlayerSpawn(self, ply)

    if not ply.SVChar then
        Chars.enterLobby(ply)
        return
    end

    Chars.leaveLobby(ply)
    local role = Roles.ofPlayer(ply)
    if role then
        ply:SetMaxHealth(role.health or 100)
        ply:SetHealth(role.health or 100)
        ply:SetArmor(role.armor or 0)
        ply:SetWalkSpeed(role.walkSpeed or GAMEMODE.Config.walkspeed)
        ply:SetRunSpeed(role.runSpeed or GAMEMODE.Config.runspeed)
        hook.Run("SiteVeil.RoleSpawn", ply, role)
    end
end

function GM:PlayerSelectSpawn(ply)
    local role = Roles.ofPlayer(ply)
    if ply.SVChar and role and SV.MapCfg and SV.MapCfg.pickSpawn then
        local pos, ang = SV.MapCfg.pickSpawn(ply, role)
        if pos then
            ply.SVSpawnAngles = ang
            -- DarkRP's PlayerSpawn uses the second return value as position.
            return BaseClass.PlayerSelectSpawn(self, ply), pos
        end
    end
    return BaseClass.PlayerSelectSpawn(self, ply)
end

hook.Add("PlayerSpawn", "SiteVeil.SpawnAngles", function(ply)
    if ply.SVSpawnAngles then
        local ang = ply.SVSpawnAngles
        ply.SVSpawnAngles = nil
        timer.Simple(0, function() if IsValid(ply) then ply:SetEyeAngles(ang) end end)
    end
end)

--[[---------------------------------------------------------------------------
Death and respawn
---------------------------------------------------------------------------]]
function Chars.respawnDelay()
    local r = C.Respawn
    return math.min(r.base + U.onlineCount() * r.perPlayers, r.max)
end

hook.Add("PlayerDeath", "SiteVeil.Chars.Respawn", function(ply)
    local delay = hook.Run("SiteVeil.RespawnDelay", ply) or Chars.respawnDelay()
    ply.SVRespawnAt = CurTime() + delay
    SV.Sync.setFor(ply, "self", "respawnAt", ply.SVRespawnAt)
end)

function GM:PlayerDeathThink(ply)
    if ply.SVRespawnAt and CurTime() < ply.SVRespawnAt then return false end
    return BaseClass.PlayerDeathThink(self, ply)
end

function GM:CanPlayerSuicide(ply)
    if not ply.SVChar then return false end
    local veto = hook.Run("SiteVeil.CanSuicide", ply)
    if veto == false then return false end
    return BaseClass.CanPlayerSuicide(self, ply)
end

SV.Perf.registry("characters.active", function() return U.count(Chars.active) end)

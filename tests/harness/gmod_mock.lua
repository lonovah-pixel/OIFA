--[[---------------------------------------------------------------------------
Minimal Garry's Mod + DarkRP server API mock for headless tests.

This is NOT an emulator of the game. It provides just enough of the server
realm API (hook, timer, net, sql via SQLite, players, entities, vectors and a
DarkRP subset) to execute SITE-VEIL server logic and check its behaviour.
Anything that depends on the engine (physics, rendering, real traces,
networking to clients, the real DarkRP) must be verified in game; see
TESTING.md.

Host functions provided by runner.py (prefixed with __host_):
  __host_sql(query)            -> ok, rows|error
  __host_json_encode(table)    -> string
  __host_json_decode(string)   -> table|nil
  __host_read(path)            -> source|nil  (path relative to gamemodes/)
  __host_exists(path)          -> bool
  __host_data_read/write/exists(path)
---------------------------------------------------------------------------]]

SERVER = true
CLIENT = false
MOCK = {}

local clock = 0
function CurTime() return clock end
function RealTime() return clock end
function SysTime() return os.clock() end
function FrameTime() return 0.015 end
function MOCK.setTime(t) clock = t end

-- Lua 5.1 / GMod compatibility --------------------------------------------
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function istable(v) return type(v) == "table" and not v.__isVector and not v.__isAngle and not v.__isEntity end
function isbool(v) return type(v) == "boolean" end
function isfunction(v) return type(v) == "function" end
function isentity(v) return type(v) == "table" and v.__isEntity == true end
function isvector(v) return type(v) == "table" and v.__isVector == true end
function isangle(v) return type(v) == "table" and v.__isAngle == true end
function IsColor(v) return type(v) == "table" and v.r ~= nil and v.g ~= nil and v.b ~= nil end
function tobool(v) return v ~= nil and v ~= false and v ~= 0 and v ~= "0" and v ~= "false" end

MOCK.output = {}
function Msg(...) table.insert(MOCK.output, table.concat({...})) end
function MsgN(...) table.insert(MOCK.output, table.concat({...})) end
function MsgC(...)
    local parts = {}
    for _, v in ipairs({...}) do if type(v) == "string" then parts[#parts + 1] = v end end
    table.insert(MOCK.output, table.concat(parts))
end
MOCK.errors = {}
function ErrorNoHalt(...)
    local msg = table.concat({...})
    table.insert(MOCK.errors, msg)
    table.insert(MOCK.output, "ERROR: " .. msg)
end
function ServerLog() end
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    table.insert(MOCK.output, table.concat(parts, "\t"))
end

function Color(r, g, b, a) return {r = r, g = g, b = b, a = a or 255} end
color_white = Color(255, 255, 255)
color_black = Color(0, 0, 0)
function ColorAlpha(c, a) return Color(c.r, c.g, c.b, a) end

-- math / string / table extensions ----------------------------------------
function math.Clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
function math.Round(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
math.Min, math.Max = math.min, math.max
function math.Rand(a, b) return a + math.random() * (b - a) end
function math.Approach(cur, target, inc)
    if cur < target then return math.min(cur + inc, target) end
    return math.max(cur - inc, target)
end
function math.Remap(v, a, b, c, d) return c + (d - c) * (v - a) / (b - a) end

function string.Explode(sep, str)
    local out, start = {}, 1
    if sep == "" then for i = 1, #str do out[#out + 1] = str:sub(i, i) end return out end
    while true do
        local s, e = string.find(str, sep, start, true)
        if not s then out[#out + 1] = str:sub(start) break end
        out[#out + 1] = str:sub(start, s - 1)
        start = e + 1
    end
    return out
end
function string.Trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
function string.StartWith(s, p) return s:sub(1, #p) == p end
string.StartsWith = string.StartWith
function string.EndsWith(s, p) return p == "" or s:sub(-#p) == p end
function string.GetFileFromFilename(p) return p:match("([^/]+)$") or p end
function string.Left(s, n) return s:sub(1, n) end
function string.Split(s, sep) return string.Explode(sep, s) end

function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.HasValue(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and table.Copy(v) or v end
    return setmetatable(o, getmetatable(t))
end
function table.IsEmpty(t) return next(t) == nil end
function table.GetKeys(t) local o = {} for k in pairs(t) do o[#o + 1] = k end return o end
function table.Merge(a, b) for k, v in pairs(b) do a[k] = v end return a end
function table.KeyFromValue(t, v) for k, x in pairs(t) do if x == v then return k end end end
function table.RemoveByValue(t, v) for i, x in ipairs(t) do if x == v then table.remove(t, i) return i end end end
function table.ClearKeys(t) local o = {} for _, v in pairs(t) do o[#o + 1] = v end return o end
function SortedPairs(t, desc)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) if desc then return tostring(a) > tostring(b) end return tostring(a) < tostring(b) end)
    local i = 0
    return function() i = i + 1 local k = keys[i] if k ~= nil then return k, t[k] end end
end

-- bit: LuaJIT provides it ---------------------------------------------------
bit = bit or require("bit")

-- Vector / Angle -------------------------------------------------------------
local VEC = {}
VEC.__index = VEC
function Vector(x, y, z)
    if type(x) == "table" and x.__isVector then return Vector(x.x, x.y, x.z) end
    return setmetatable({x = x or 0, y = y or 0, z = z or 0, __isVector = true}, VEC)
end
VEC.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VEC.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VEC.__mul = function(a, b)
    if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
VEC.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
VEC.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
VEC.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
VEC.__tostring = function(a) return string.format("%g %g %g", a.x, a.y, a.z) end
function VEC:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VEC:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function VEC:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function VEC:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function VEC:Distance(o) return math.sqrt(self:DistToSqr(o)) end
function VEC:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function VEC:GetNormalized() local l = self:Length() if l == 0 then return Vector() end return self / l end
function VEC:Normalize() local n = self:GetNormalized() self.x, self.y, self.z = n.x, n.y, n.z end
function VEC:IsZero() return self.x == 0 and self.y == 0 and self.z == 0 end
function VEC:Angle() return Angle(0, math.deg(math.atan2(self.y, self.x)), 0) end
function VEC:WithinAABox(mn, mx)
    return self.x >= mn.x and self.x <= mx.x and self.y >= mn.y and self.y <= mx.y and self.z >= mn.z and self.z <= mx.z
end

local ANG = {}
ANG.__index = ANG
function Angle(p, y, r) return setmetatable({p = p or 0, y = y or 0, r = r or 0, __isAngle = true}, ANG) end
function ANG:Forward()
    local p, y = math.rad(self.p), math.rad(self.y)
    return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end

-- hook ---------------------------------------------------------------------
hook = {}
local hooks = {}
function hook.Add(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end
function hook.Remove(name, id) if hooks[name] then hooks[name][id] = nil end end
function hook.GetTable() return hooks end
function hook.Call(name, gm, ...)
    local list = hooks[name]
    if list then
        -- deterministic order for tests
        local ids = {}
        for id in pairs(list) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, id in ipairs(ids) do
            local a, b, c, d = list[id](...)
            if a ~= nil then return a, b, c, d end
        end
    end
    if gm and gm[name] then return gm[name](gm, ...) end
end
function hook.Run(name, ...) return hook.Call(name, GAMEMODE, ...) end

-- timer ----------------------------------------------------------------------
timer = {}
local timers = {}
local simple = {}
function timer.Create(id, delay, reps, fn) timers[id] = {delay = delay, reps = reps, fn = fn, next = clock + delay, count = 0} end
function timer.Remove(id) timers[id] = nil end
function timer.Exists(id) return timers[id] ~= nil end
function timer.Simple(delay, fn) table.insert(simple, {at = clock + delay, fn = fn}) end
function timer.Adjust(id, delay) if timers[id] then timers[id].delay = delay end end
function timer.TimeLeft(id) return timers[id] and timers[id].next - clock or nil end

--- Advances the mock clock, running due timers in time order.
function MOCK.advance(seconds, step)
    step = step or 0.1
    local target = clock + seconds
    while clock < target - 1e-9 do
        clock = math.min(clock + step, target)
        for i = #simple, 1, -1 do
            local s = simple[i]
            if s.at <= clock then
                table.remove(simple, i)
                s.fn()
            end
        end
        local ids = {}
        for id in pairs(timers) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, id in ipairs(ids) do
            local t = timers[id]
            if t and t.next <= clock then
                t.next = clock + t.delay
                t.count = t.count + 1
                t.fn()
                if t.reps > 0 and t.count >= t.reps then timers[id] = nil end
            end
        end
    end
end

function MOCK.runTimer(id) if timers[id] then timers[id].fn() end end

-- concommand / convars -----------------------------------------------------------
concommand = {}
MOCK.concommands = {}
function concommand.Add(name, fn) MOCK.concommands[name] = fn end
function concommand.Remove(name) MOCK.concommands[name] = nil end
local convars = {}
local CV = {}
CV.__index = CV
function CV:GetString() return self.value end
function CV:GetFloat() return tonumber(self.value) or 0 end
function CV:GetInt() return math.floor(tonumber(self.value) or 0) end
function CV:GetBool() return tobool(self.value) end
function CreateConVar(name, default) convars[name] = convars[name] or setmetatable({value = tostring(default)}, CV) return convars[name] end
function GetConVar(name) return convars[name] end
function RunConsoleCommand(name, value) if convars[name] then convars[name].value = tostring(value) end end
cvars = {AddChangeCallback = function() end}
FCVAR_ARCHIVE, FCVAR_PROTECTED, FCVAR_NOTIFY, FCVAR_REPLICATED = 128, 32, 256, 8192

-- game / misc --------------------------------------------------------------------
MOCK.map = "gm_test"
game = {GetMap = function() return MOCK.map end, IsDedicated = function() return true end, ConsoleCommand = function() end, GetWorld = function() return MOCK.world end}

util = {}
function util.TableToJSON(t, pretty) return __host_json_encode(t) end
function util.JSONToTable(s) return __host_json_decode(s) end
function util.AddNetworkString(name) MOCK.netStrings = MOCK.netStrings or {} MOCK.netStrings[name] = true end
function util.PrecacheModel() end
MOCK.invalidModels = {}
function util.IsValidModel(m) return type(m) == "string" and m:sub(-4) == ".mdl" and not MOCK.invalidModels[m] end
function util.IsInWorld(pos) return math.abs(pos.x) < 16384 and math.abs(pos.y) < 16384 and math.abs(pos.z) < 16384 end
MOCK.traceHit = false
function util.TraceLine(tr)
    if MOCK.traceFn then return MOCK.traceFn(tr) end
    local hit = MOCK.traceHit
    return {Hit = hit, HitWorld = hit, HitPos = tr.endpos, StartPos = tr.start, Entity = MOCK.world, HitNormal = Vector(0, 0, 1), Fraction = hit and 0.5 or 1, StartSolid = false}
end
util.TraceHull = function(tr)
    if MOCK.hullFn then return MOCK.hullFn(tr) end
    return {Hit = false, StartSolid = false, HitPos = tr.endpos, Entity = MOCK.world, Fraction = 1}
end
function util.Decal() end
function util.Effect() end
function util.ScreenShake() end
function util.Compress(s) return s end
function util.Decompress(s) return s end
function util.SHA256(s) return tostring(#s) end
function util.CRC(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end return tostring(h) end
MASK_SOLID_BRUSHONLY, MASK_PLAYERSOLID, MASK_SHOT, MASK_VISIBLE, MASK_OPAQUE, MASK_SOLID = 1, 2, 3, 4, 5, 6
COLLISION_GROUP_WORLD, COLLISION_GROUP_DEBRIS, COLLISION_GROUP_WEAPON, COLLISION_GROUP_PLAYER = 1, 2, 3, 4
HUD_PRINTCONSOLE, HUD_PRINTCENTER, HUD_PRINTTALK = 2, 4, 3
DMG_BULLET, DMG_SLASH, DMG_BURN, DMG_BLAST, DMG_CLUB, DMG_FALL, DMG_GENERIC, DMG_CRUSH, DMG_POISON, DMG_ACID, DMG_NERVEGAS, DMG_SHOCK, DMG_RADIATION, DMG_DIRECT =
    2, 4, 8, 64, 128, 32, 0, 1, 131072, 1048576, 65536, 256, 262144, 268435456
IN_ATTACK, IN_ATTACK2, IN_USE, IN_JUMP, IN_DUCK, IN_SPEED, IN_RELOAD, IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT, IN_WALK =
    1, 2048, 32, 2, 4, 131072, 8192, 8, 16, 512, 1024, 262144
DMG_DISSOLVE, DMG_SONIC = 67108864, 1024
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH, HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG = 0, 1, 2, 3, 4, 5, 6, 7
SCREENFADE = {IN = 1, OUT = 2, MODULATE = 4, STAYOUT = 8, PURGE = 16}
MASK_SHOT_HULL, MASK_NPCWORLDSTATIC, CONTENTS_SOLID = 7, 8, 1
PLAYER_ATTACK1, ACT_VM_HITCENTER, ACT_VM_MISSCENTER, ACT_VM_PRIMARYATTACK = 5, 180, 181, 182
function CreateSound() return {Play = function() end, Stop = function() end, ChangeVolume = function() end, IsPlaying = function() return false end, SetSoundLevel = function() end} end
MOVETYPE_NONE, MOVETYPE_WALK, MOVETYPE_NOCLIP, MOVETYPE_OBSERVER = 0, 2, 8, 10
SOLID_NONE, SOLID_VPHYSICS, SOLID_BBOX = 0, 6, 2
SIMPLE_USE, USE_TOGGLE, CONTINUOUS_USE = 3, 3, 0
RENDERMODE_NORMAL, RENDERMODE_TRANSALPHA = 0, 4
NULL = {__isEntity = true, IsValid = function() return false end}
setmetatable(NULL, {__index = function() return function() return nil end end})
function IsValid(v) return v ~= nil and v ~= NULL and type(v) == "table" and v.IsValid ~= nil and v:IsValid() end
function IsFirstTimePredicted() return true end
function SafeRemoveEntity(e) if IsValid(e) then e:Remove() end end
function DamageInfo() return MOCK.makeDamage({}) end
function EffectData() return setmetatable({}, {__index = function() return function() end end}) end
function DEFINE_BASECLASS() end
function AddCSLuaFile() end
function FindMetaTable(name) MOCK.meta = MOCK.meta or {} MOCK.meta[name] = MOCK.meta[name] or {} return MOCK.meta[name] end
function Material() return {} end
function ents_dummy() end
function RecipientFilter() local r = {list = {}} function r:AddPlayer(p) table.insert(self.list, p) end function r:AddAllPlayers() self.list = player.GetAll() end function r:GetPlayers() return self.list end return r end
sound = {Play = function() end, Add = function() end}
resource = {AddFile = function() end, AddWorkshop = function() end}
physenv = {GetPerformanceSettings = function() return {} end, SetPerformanceSettings = function() end}
engine = {ActiveGamemode = function() return "siteveil" end}
umsg = {Start = function() end, String = function() end, Short = function() end, Long = function() end, End = function() end, Bool = function() end}
gamemode = {Call = function(name, ...) return hook.Call(name, GAMEMODE, ...) end}
scripted_ents = {stored = {}}
function scripted_ents.GetStored(class) return scripted_ents.stored[class] end
function scripted_ents.Register(t, class) scripted_ents.stored[class] = {t = t} end
weapons = {stored = {}}
function weapons.GetStored(class) return weapons.stored[class] end
player_manager = {SetPlayerClass = function() end, RunClass = function() end}
navmesh = {GetNavArea = function() return nil end}

-- file ---------------------------------------------------------------------------
file = {}
function file.Exists(path, where)
    if where == "LUA" then return __host_exists(path) end
    if where == "DATA" then return __host_data_exists(path) end
    return false
end
function file.Read(path, where)
    if where == "DATA" then return __host_data_read(path) end
    return __host_read(path)
end
function file.Write(path, content) __host_data_write(path, content) end
function file.Append(path, content) __host_data_write(path, (__host_data_read(path) or "") .. content) end
function file.CreateDir() end
function file.Delete(path) __host_data_write(path, nil) end
function file.Find() return {}, {} end

function include(path)
    local src = __host_read(path)
    if not src then error("include: file not found " .. tostring(path), 2) end
    local fn, err = loadstring(src, "@" .. path)
    if not fn then error(err, 0) end
    return fn()
end
function CompileString(src, name) return loadstring(src, name) end

-- sql (SQLite through the host) ----------------------------------------------------
sql = {}
function sql.Query(q)
    local ok, result = __host_sql(q)
    if not ok then
        sql.m_strError = result
        return false
    end
    sql.m_strError = nil
    if result == nil or #result == 0 then return nil end
    return result
end
function sql.QueryValue(q)
    local rows = sql.Query(q)
    if not rows then return rows end
    local _, v = next(rows[1])
    return v
end
function sql.QueryRow(q) local rows = sql.Query(q) return rows and rows[1] end
function sql.LastError() return sql.m_strError end
function sql.SQLStr(s, noQuotes)
    s = string.gsub(tostring(s), "'", "''")
    if noQuotes then return s end
    return "'" .. s .. "'"
end
function sql.Begin() sql.Query("BEGIN") end
function sql.Commit() sql.Query("COMMIT") end
function sql.TableExists(name) return sql.QueryValue("SELECT name FROM sqlite_master WHERE name = " .. sql.SQLStr(name)) ~= nil end

-- net ------------------------------------------------------------------------------
net = {Receivers = {}}
local wbuf, rbuf, rpos
local current
function net.Receive(name, fn) net.Receivers[string.lower(name)] = fn end
function net.Start(name) current = name wbuf = {} end
local function writeValue(v) table.insert(wbuf, v) end
local function r() rpos = rpos + 1 return rbuf[rpos] end
net.WriteString, net.WriteUInt, net.WriteInt, net.WriteBool, net.WriteFloat, net.WriteEntity, net.WriteVector, net.WriteTable, net.WriteDouble, net.WriteAngle, net.WriteType =
    writeValue, writeValue, writeValue, writeValue, writeValue, writeValue, writeValue, writeValue, writeValue, writeValue, writeValue
net.ReadString = function() local v = r() return v == nil and "" or v end
net.ReadUInt = function() return r() or 0 end
net.ReadInt = function() return r() or 0 end
net.ReadBool = function() return r() == true end
net.ReadFloat = function() return r() or 0 end
net.ReadDouble = function() return r() or 0 end
net.ReadEntity = function() local v = r() if v == nil then return NULL end return v end
net.ReadVector = function() return r() or Vector() end
net.ReadTable = function() return r() or {} end
net.ReadAngle = function() return r() or Angle() end
function net.BytesWritten() return #wbuf * 4 end
MOCK.sent = {}
local function deliver(targets)
    local msg = {name = current, data = wbuf, targets = targets}
    table.insert(MOCK.sent, msg)
end
function net.Send(target) deliver(type(target) == "table" and target.__isEntity and {target} or target) end
function net.Broadcast() deliver(player.GetAll()) end
function net.SendOmit(omit) deliver(player.GetAll()) end
function net.SendPVS() deliver(player.GetAll()) end

--- Simulates a client sending a net message.
function MOCK.clientSend(ply, name, values, bits)
    rbuf, rpos = values, 0
    local fn = net.Receivers[string.lower(name)]
    if not fn then error("no receiver for " .. name) end
    fn(bits or (#values * 32), ply)
end

--- Returns pushes (sv_push) sent to a player, optionally filtered by event.
function MOCK.pushes(ply, event)
    local out = {}
    for _, m in ipairs(MOCK.sent) do
        if m.name == "sv_push" and (m.data[1] == event or event == nil) then
            local targets = m.targets
            local hit = false
            if targets == nil then hit = true else
                for _, t in ipairs(targets) do if t == ply then hit = true end end
            end
            if hit then out[#out + 1] = {event = m.data[1], data = m.data[2]} end
        end
    end
    return out
end

function MOCK.clearSent() MOCK.sent = {} end

-- entities ---------------------------------------------------------------------------
local entities = {}
local nextIndex = 1
MOCK.entities = entities

local ENT = {}
ENT.__index = function(self, k)
    local v = rawget(ENT, k)
    if v ~= nil then return v end
    local meta = MOCK.meta and MOCK.meta.Entity
    if meta and meta[k] then return meta[k] end
    return nil
end

local function newEntity(class)
    local e = setmetatable({__isEntity = true, class = class, pos = Vector(), ang = Angle(), valid = true,
        index = nextIndex, nw = {}, health = 100, maxHealth = 100, model = "", mapId = -1, color = Color(255, 255, 255)}, ENT)
    nextIndex = nextIndex + 1
    entities[#entities + 1] = e
    return e
end
MOCK.newEntity = newEntity

function ENT:IsValid() return self.valid end
function ENT:GetClass() return self.class end
function ENT:GetPos() return Vector(self.pos) end
function ENT:SetPos(p) self.pos = Vector(p) end
function ENT:GetAngles() return self.ang end
function ENT:SetAngles(a) self.ang = a end
function ENT:EntIndex() return self.index end
function ENT:IsPlayer() return false end
function ENT:IsNPC() return false end
function ENT:IsWeapon() return false end
function ENT:IsVehicle() return false end
function ENT:IsWorld() return self.class == "worldspawn" end
function ENT:Remove()
    if not self.valid then return end
    if self.OnRemove then self:OnRemove() end
    hook.Run("EntityRemoved", self)
    self.valid = false
end
function ENT:Spawn() if self.Initialize then self:Initialize() end end
function ENT:Activate() end
function ENT:SetModel(m) self.model = m end
function ENT:GetModel() return self.model end
function ENT:Health() return self.health end
function ENT:SetHealth(h) self.health = h end
function ENT:GetMaxHealth() return self.maxHealth end
function ENT:SetMaxHealth(h) self.maxHealth = h end
function ENT:MapCreationID() return self.mapId end
function ENT:GetPhysicsObject() return NULL end
function ENT:EmitSound() end
function ENT:StopSound() end
function ENT:Fire(input, param) self.fired = self.fired or {} table.insert(self.fired, input) end
function ENT:GetSaveTable() return self.saveTable or {} end
function ENT:SetNW2Bool(k, v) self.nw[k] = v end
function ENT:SetNW2Int(k, v) self.nw[k] = v end
function ENT:SetNW2Float(k, v) self.nw[k] = v end
function ENT:SetNW2String(k, v) self.nw[k] = v end
function ENT:SetNW2Entity(k, v) self.nw[k] = v end
function ENT:GetNW2Bool(k, d) local v = self.nw[k] if v == nil then return d or false end return v end
function ENT:GetNW2Int(k, d) return self.nw[k] or d or 0 end
function ENT:GetNW2Float(k, d) return self.nw[k] or d or 0 end
function ENT:GetNW2String(k, d) return self.nw[k] or d or "" end
function ENT:GetNW2Entity(k) return self.nw[k] or NULL end
ENT.SetNWBool, ENT.SetNWInt, ENT.SetNWFloat, ENT.SetNWString, ENT.SetNWEntity = ENT.SetNW2Bool, ENT.SetNW2Int, ENT.SetNW2Float, ENT.SetNW2String, ENT.SetNW2Entity
ENT.GetNWBool, ENT.GetNWInt, ENT.GetNWFloat, ENT.GetNWString, ENT.GetNWEntity = ENT.GetNW2Bool, ENT.GetNW2Int, ENT.GetNW2Float, ENT.GetNW2String, ENT.GetNW2Entity
function ENT:SetColor(c) self.color = c end
function ENT:GetColor() return self.color end
function ENT:SetRenderMode() end
function ENT:SetMaterial() end
function ENT:DrawShadow() end
function ENT:SetNoDraw(v) self.noDraw = v end
function ENT:GetNoDraw() return self.noDraw end
function ENT:SetNotSolid(v) self.notSolid = v end
function ENT:SetCollisionGroup() end
function ENT:SetMoveType(m) self.moveType = m end
function ENT:GetMoveType() return self.moveType or 0 end
function ENT:SetSolid() end
function ENT:PhysicsInit() end
function ENT:SetUseType() end
function ENT:SetTrigger() end
function ENT:SetParent(p) self.parent = p end
function ENT:GetParent() return self.parent or NULL end
function ENT:OBBCenter() return Vector() end
function ENT:WorldSpaceCenter() return self:GetPos() end
function ENT:LocalToWorld(v) return self:GetPos() + v end
function ENT:GetForward() return self.ang:Forward() end
function ENT:GetVelocity() return self.velocity or Vector() end
function ENT:SetVelocity(v) self.velocity = v end
function ENT:TakeDamageInfo(d)
    if hook.Run("EntityTakeDamage", self, d) == true then return end
    if not self.IsPlayer or not self:IsPlayer() or not self.alive or self.god then return end
    -- Engine behaviour: damage lowers health; zero health kills.
    self.health = self.health - math.floor(d:GetDamage())
    if self.health <= 0 then
        self.health = 0
        self.alive = false
        hook.Run("DoPlayerDeath", self, d:GetAttacker(), d)
        hook.Run("PlayerDeath", self, d:GetInflictor(), d:GetAttacker())
    end
end
function ENT:TakeDamage(amount, attacker) self:TakeDamageInfo(MOCK.makeDamage({damage = amount, attacker = attacker})) end
function ENT:IsOnFire() return false end
function ENT:Extinguish() end
function ENT:CPPIGetOwner() return self.owner end
function ENT:CPPISetOwner(o) self.owner = o end
function ENT:isDoor() return self.class == "prop_door_rotating" or self.class == "func_door" or self.class == "func_door_rotating" end
function ENT:GetTable() return self end
function ENT:SetSubMaterial() end
function ENT:GetBoneMatrix() return nil end
function ENT:LookupBone() return nil end
function ENT:EyePos() return self:GetPos() + Vector(0, 0, 64) end
function ENT:SetKeyValue() end
function ENT:IsSolid() return true end
function ENT:SetCustomCollisionCheck() end
function ENT:GetCollisionGroup() return 0 end

ents = {}
function ENT:NetworkVar(_, _, name)
    self.nwvars = self.nwvars or {}
    self["Set" .. name] = function(s, v) s.nwvars[name] = v end
    self["Get" .. name] = function(s) local v = s.nwvars[name] if v == nil then return "" end return v end
end

function ents.Create(class)
    local e = newEntity(class)
    local stored = scripted_ents.stored[class]
    if stored then
        for k, v in pairs(stored.t) do e[k] = v end
        if e.SetupDataTables then e:SetupDataTables() end
    end
    return e
end
function ents.GetAll() local o = {} for _, e in ipairs(entities) do if e.valid then o[#o + 1] = e end end return o end
function ents.FindByClass(class)
    local o = {}
    local prefix = class:match("^(.-)%*$")
    for _, e in ipairs(entities) do
        if e.valid and (e.class == class or (prefix and e.class:sub(1, #prefix) == prefix)) then o[#o + 1] = e end
    end
    return o
end
function ents.FindInSphere(pos, radius)
    local o = {}
    for _, e in ipairs(entities) do if e.valid and e.pos:DistToSqr(pos) <= radius * radius then o[#o + 1] = e end end
    return o
end
function ents.FindInBox(mn, mx)
    local o = {}
    for _, e in ipairs(entities) do if e.valid and e.pos:WithinAABox(mn, mx) then o[#o + 1] = e end end
    return o
end
function ents.GetMapCreatedEntity(id)
    for _, e in ipairs(entities) do if e.valid and e.mapId == id then return e end end
    return NULL
end
function ents.GetByIndex(i) for _, e in ipairs(entities) do if e.index == i then return e end end return NULL end
function Entity(i) if i == 0 then return MOCK.world end return ents.GetByIndex(i) end

MOCK.world = newEntity("worldspawn")

-- damage info --------------------------------------------------------------------------
function MOCK.makeDamage(t)
    local d = {damage = t.damage or 0, type = t.type or DMG_GENERIC, attacker = t.attacker or MOCK.world, inflictor = t.inflictor or t.attacker or MOCK.world, pos = t.pos or Vector()}
    return setmetatable(d, {__index = {
        GetDamage = function(s) return s.damage end, SetDamage = function(s, v) s.damage = v end,
        ScaleDamage = function(s, f) s.damage = s.damage * f end,
        GetDamageType = function(s) return s.type end, SetDamageType = function(s, v) s.type = v end,
        IsDamageType = function(s, ty) return bit.band(s.type, ty) ~= 0 end,
        IsBulletDamage = function(s) return bit.band(s.type, DMG_BULLET) ~= 0 end,
        IsFallDamage = function(s) return bit.band(s.type, DMG_FALL) ~= 0 end,
        IsExplosionDamage = function(s) return bit.band(s.type, DMG_BLAST) ~= 0 end,
        GetAttacker = function(s) return s.attacker end, SetAttacker = function(s, v) s.attacker = v end,
        GetInflictor = function(s) return s.inflictor end, SetInflictor = function(s, v) s.inflictor = v end,
        GetDamagePosition = function(s) return s.pos end, SetDamagePosition = function(s, v) s.pos = v end,
        SetDamageForce = function() end, GetDamageForce = function() return Vector() end,
    }})
end

-- players ---------------------------------------------------------------------------------
local players = {}
MOCK.players = players
player = {}
function player.GetAll() local o = {} for _, p in ipairs(players) do if p.valid then o[#o + 1] = p end end return o end
function player.GetHumans() local o = {} for _, p in ipairs(players) do if p.valid and not p.bot then o[#o + 1] = p end end return o end
function player.GetCount() return #player.GetAll() end
function player.GetBySteamID64(sid) for _, p in ipairs(players) do if p.valid and p.sid == sid then return p end end return false end
function Player(uid) for _, p in ipairs(players) do if p.userId == uid then return p end end return NULL end

local PLY = {}
for k, v in pairs(ENT) do if k ~= "__index" then PLY[k] = v end end
PLY.__index = function(self, k)
    local v = rawget(PLY, k)
    if v ~= nil then return v end
    local meta = MOCK.meta and MOCK.meta.Player
    if meta and meta[k] then return meta[k] end
    meta = MOCK.meta and MOCK.meta.Entity
    if meta and meta[k] then return meta[k] end
    return nil
end

function MOCK.addPlayer(opts)
    opts = opts or {}
    local p = newEntity("player")
    setmetatable(p, PLY)
    p.sid = opts.steamid or ("7656119800000" .. string.format("%04d", #players + 1))
    p.name = opts.name or ("Player" .. (#players + 1))
    p.userId = #players + 1
    p.teamId = 0
    p.alive = true
    p.weapons = {}
    p.ammo = {}
    p.admin = opts.admin or false
    p.superadmin = opts.superadmin or false
    p.bot = opts.bot or false
    p.armor = 0
    p.walk, p.run = 160, 235
    p.kicked = nil
    p.darkrpVars = {rpname = p.name, money = 0}
    p.eyeAng = Angle()
    players[#players + 1] = p
    return p
end

function PLY:IsPlayer() return true end
function PLY:SteamID64() return self.sid end
function PLY:SteamID() return "STEAM_0:0:" .. self.sid:sub(-6) end
function PLY:UserID() return self.userId end
function PLY:Nick() return self.darkrpVars.rpname or self.name end
PLY.Name = PLY.Nick
PLY.GetName = PLY.Nick
function PLY:SteamName() return self.name end
function PLY:Team() return self.teamId end
function PLY:SetTeam(t) self.teamId = t end
function PLY:Alive() return self.alive end
function PLY:IsBot() return self.bot end
function PLY:IsAdmin() return self.admin or self.superadmin end
function PLY:IsSuperAdmin() return self.superadmin end
function PLY:IsUserGroup(g) return (g == "superadmin" and self.superadmin) or (g == "admin" and self:IsAdmin()) end
function PLY:GetUserGroup() return self.superadmin and "superadmin" or (self.admin and "admin" or "user") end
function PLY:Kick(reason) self.kicked = reason self.valid = false end
function PLY:Kill()
    if not self.alive then return end
    self.alive = false
    hook.Run("DoPlayerDeath", self, self, MOCK.makeDamage({}))
    hook.Run("PlayerDeath", self, self, self)
end
function PLY:KillSilent()
    if not self.alive then return end
    self.alive = false
    hook.Run("PlayerSilentDeath", self)
end
function PLY:Spawn()
    self.alive = true
    self.health = self.maxHealth or 100
    hook.Run("PlayerSpawn", self)
end
function PLY:Armor() return self.armor end
function PLY:SetArmor(a) self.armor = a end
function PLY:Give(class)
    local w = newEntity(class)
    w.owner = self
    function w:IsWeapon() return true end
    function w:GetOwner() return self.owner end
    function w:Clip1() return self.clip or 0 end
    function w:SetClip1(v) self.clip = v end
    function w:GetPrimaryAmmoType() return 1 end
    self.weapons[class] = w
    return w
end
function PLY:HasWeapon(class) return self.weapons[class] ~= nil and self.weapons[class].valid end
function PLY:GetWeapon(class) return self.weapons[class] or NULL end
function PLY:GetWeapons() local o = {} for _, w in pairs(self.weapons) do if w.valid then o[#o + 1] = w end end return o end
function PLY:StripWeapon(class) if self.weapons[class] then self.weapons[class].valid = false self.weapons[class] = nil end end
function PLY:StripWeapons() for c in pairs(self.weapons) do self:StripWeapon(c) end end
function PLY:GetActiveWeapon() return self.active or NULL end
function PLY:SelectWeapon(class) self.active = self.weapons[class] end
function PLY:SwitchToDefaultWeapon() end
function PLY:GiveAmmo(n, t) self.ammo[t] = (self.ammo[t] or 0) + n end
function PLY:GetAmmoCount(t) return self.ammo[t] or 0 end
function PLY:SetAmmo(n, t) self.ammo[t] = n end
function PLY:RemoveAllAmmo() self.ammo = {} end
function PLY:RemoveAmmo(n, t) self.ammo[t] = math.max((self.ammo[t] or 0) - n, 0) end
function PLY:SetWalkSpeed(v) self.walk = v end
function PLY:SetRunSpeed(v) self.run = v end
function PLY:GetWalkSpeed() return self.walk end
function PLY:GetRunSpeed() return self.run end
function PLY:SetJumpPower(v) self.jump = v end
function PLY:GetJumpPower() return self.jump or 200 end
function PLY:SetCrouchedWalkSpeed() end
function PLY:Freeze(v) self.frozen = v end
function PLY:IsFrozen() return self.frozen end
function PLY:GodEnable() self.god = true end
function PLY:GodDisable() self.god = false end
function PLY:HasGodMode() return self.god end
function PLY:SetNoTarget(v) self.notarget = v end
function PLY:SetupHands() end
function PLY:PrintMessage(_, msg) self.printed = self.printed or {} table.insert(self.printed, msg) end
function PLY:ChatPrint(msg) self:PrintMessage(HUD_PRINTTALK, msg) end
function PLY:SendLua() end
function PLY:ConCommand() end
function PLY:GetInfo() return "" end
function PLY:GetInfoNum(_, d) return d end
function PLY:EyePos() return self:GetPos() + Vector(0, 0, 64) end
function PLY:GetShootPos() return self:EyePos() end
function PLY:EyeAngles() return self.eyeAng end
function PLY:SetEyeAngles(a) self.eyeAng = a end
function PLY:GetAimVector() return self.eyeAng:Forward() end
function PLY:GetEyeTrace() return {Entity = self.lookAt or NULL, HitPos = self:EyePos(), StartPos = self:EyePos()} end
function PLY:GetEyeTraceNoCursor() return self:GetEyeTrace() end
function PLY:InVehicle() return false end
function PLY:ExitVehicle() end
function PLY:Crouching() return false end
function PLY:IsSpeaking() return self.speaking or false end
function PLY:Ping() return 30 end
function PLY:SetViewEntity() end
function PLY:ScreenFade() end
function PLY:SetDSP() end
function PLY:Spectate() end
function PLY:UnSpectate() end
function PLY:SetObserverMode() end
function PLY:GetObserverMode() return 0 end
function PLY:IsOnGround() return true end
function PLY:KeyDown() return false end
function PLY:SetHull() end
function PLY:GetHull() return Vector(-16, -16, 0), Vector(16, 16, 72) end
function PLY:LagCompensation() end
function PLY:SetAvoidPlayers() end
function PLY:SetNoCollideWithTeammates() end
function PLY:AllowFlashlight() end
function PLY:Flashlight() end
function PLY:FlashlightIsOn() return false end
function PLY:DrawViewModel() end
function PLY:SetDuckSpeed() end
function PLY:SetUnDuckSpeed() end
function PLY:SetModelScale() end
function PLY:GetModelScale() return 1 end
function PLY:SetPlayerColor() end
function PLY:AddFrags() end
function PLY:AddDeaths() end
function PLY:CrosshairEnable() end
function PLY:CrosshairDisable() end

-- DarkRP vars and DarkRP subset (the real DarkRP is not loaded in tests) ---------------------
function PLY:getDarkRPVar(k, fallback) local v = self.darkrpVars[k] if v == nil then return fallback end return v end
function PLY:setDarkRPVar(k, v) self.darkrpVars[k] = v end
function PLY:setSelfDarkRPVar(k, v) self.darkrpVars[k] = v end
function PLY:getJobTable() return RPExtraTeams[self.teamId] end

MOCK.notifications = {}
DarkRP = {disabledDefaults = {modules = {}, jobs = {}, shipments = {}, entities = {}, ammo = {}, agendas = {}, doorgroups = {}, demotegroups = {}, groupchat = {}, food = {}, hitmen = {}, vehicles = {}, workarounds = {}}}
MOCK.languages = {}
function DarkRP.addLanguage(name, tbl) MOCK.languages[name] = tbl end
function DarkRP.notify(ply, kind, len, msg)
    local list = type(ply) == "table" and ply.__isEntity and {ply} or ply
    for _, p in ipairs(list or {}) do
        table.insert(MOCK.notifications, {ply = p, kind = kind, msg = msg})
    end
end
function DarkRP.notifyAll(kind, len, msg) DarkRP.notify(player.GetAll(), kind, len, msg) end
function DarkRP.talkToRange(ply, prefix, text, dist)
    MOCK.chat = MOCK.chat or {}
    table.insert(MOCK.chat, {from = ply, prefix = prefix, text = text, dist = dist})
end
function DarkRP.talkToPerson(receiver, col1, prefix, col2, text, sender)
    MOCK.chat = MOCK.chat or {}
    table.insert(MOCK.chat, {to = receiver, prefix = prefix, text = text, from = sender})
end
function DarkRP.log() end
function DarkRP.error(msg) error(msg, 2) end
function DarkRP.errorNoHalt(msg) ErrorNoHalt(msg) end
function DarkRP.getPhrase(name) return name end
function DarkRP.findEmptyPos(pos) return pos end
function DarkRP.registerDarkRPVar() end
function DarkRP.formatMoney(n) return tostring(n) end
DarkRP.chatCommands = {}
function DarkRP.declareChatCommand(t) DarkRP.chatCommands[string.lower(t.command)] = t end
function DarkRP.defineChatCommand(cmd, fn) DarkRP.chatCommands[string.lower(cmd)] = DarkRP.chatCommands[string.lower(cmd)] or {command = cmd} DarkRP.chatCommands[string.lower(cmd)].callback = fn end
function DarkRP.removeChatCommand(cmd) DarkRP.chatCommands[string.lower(cmd)] = nil end
function DarkRP.getChatCommands() return DarkRP.chatCommands end
function DarkRP.getChatCommand(cmd) return DarkRP.chatCommands[string.lower(cmd)] end

RPExtraTeams = {}
DarkRPEntities = {}
CustomShipments = {}
local categories = {}
function DarkRP.createCategory(t) categories[t.name] = t end
function DarkRP.createJob(name, t)
    t.name = name
    local i = #RPExtraTeams + 1
    t.team = i
    RPExtraTeams[i] = t
    return i
end
team = {GetName = function(i) return RPExtraTeams[i] and RPExtraTeams[i].name or "" end, GetColor = function() return Color(255, 255, 255) end, NumPlayers = function(t) local n = 0 for _, p in ipairs(player.GetAll()) do if p.teamId == t then n = n + 1 end end return n end, SetUp = function() end}

--- Mimics DarkRP's changeTeam: asks playerCanChangeTeam, then sets the team.
function PLY:changeTeam(t, force)
    if self.teamId == t then return false end
    local ok, reason = hook.Call("playerCanChangeTeam", nil, self, t, force)
    if ok == false then
        MOCK.lastTeamRefusal = reason
        return false
    end
    local prev = self.teamId
    self.teamId = t
    self.darkrpVars.job = RPExtraTeams[t] and RPExtraTeams[t].name
    hook.Run("OnPlayerChangedTeam", self, prev, t)
    if self.alive then
        hook.Run("PlayerLoadout", self)
    end
    return true
end

-- Base class used by GM methods (DarkRP + sandbox stand-in).
MOCK.BaseClass = {
    PlayerSpawn = function() end,
    PlayerLoadout = function(gm, ply)
        local job = RPExtraTeams[ply:Team()]
        for _, w in ipairs(job and job.weapons or {}) do ply:Give(w) end
    end,
    PlayerSelectSpawn = function() return MOCK.world end,
    PlayerDeathThink = function() return true end,
    CanPlayerSuicide = function() return true end,
    canChatCommand = function() return true end,
    PlayerSpawnSENT = function() return true end,
    PlayerSpawnSWEP = function() return true end,
    PlayerGiveSWEP = function() return true end,
    PlayerCanPickupWeapon = function() return true end,
    PlayerUse = function() return true end,
    PlayerCanHearPlayersVoice = function() return true, true end,
    PlayerSay = function(_, _, text) return text end,
    EntityTakeDamage = function() end,
    PlayerDeath = function() end,
    DoPlayerDeath = function() end,
    PlayerInitialSpawn = function() end,
    PlayerDisconnected = function() end,
    KeyPress = function() end,
    PlayerShouldTakeDamage = function() return true end,
    ScalePlayerDamage = function() end,
    PlayerCanJoinTeam = function() return true end,
    PlayerSwitchFlashlight = function() return true end,
    CanPlayerEnterVehicle = function() return true end,
    PlayerSpray = function() return true end,
    GetFallDamage = function() return 10 end,
    PostPlayerDeath = function() end,
    PlayerSilentDeath = function() end,
    SetupMove = function() end,
    Move = function() end,
    StartCommand = function() end,
    PlayerTick = function() end,
}
GM = setmetatable({FolderName = "siteveil", Config = {}, Sandbox = MOCK.BaseClass}, {__index = MOCK.BaseClass})
GAMEMODE = GM

--- Simulates a full join of a player: initial spawn, client ready, spawn.
function MOCK.join(opts)
    local p = MOCK.addPlayer(opts)
    p.teamId = GAMEMODE.DefaultTeam or 1
    hook.Run("PlayerInitialSpawn", p)
    p:Spawn()
    MOCK.clientSend(p, "sv_rpc", {"sync.ready"})
    return p
end

function MOCK.disconnect(p)
    hook.Run("PlayerDisconnected", p)
    p.valid = false
end

--- Calls an RPC as the given player.
function MOCK.rpc(ply, name, ...)
    local values = {name}
    local def = SiteVeil and SiteVeil.Net.defs[name]
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        -- Encode like the client writer does (json arguments travel as strings).
        if def and def.args[i] and string.sub(def.args[i], 1, 4) == "json" and type(v) == "table" then
            v = util.TableToJSON(v)
        end
        values[#values + 1] = v
    end
    MOCK.clientSend(ply, "sv_rpc", values)
end

function MOCK.lastNotify(ply)
    for i = #MOCK.notifications, 1, -1 do
        if MOCK.notifications[i].ply == ply then return MOCK.notifications[i].msg, MOCK.notifications[i].kind end
    end
end

--- Simulates chat input going through PlayerSay hooks and DarkRP command routing.
function MOCK.say(ply, text, teamOnly)
    local ret = hook.Call("PlayerSay", GAMEMODE, ply, text, teamOnly or false)
    if ret == "" then return "" end
    if text:sub(1, 1) == "/" then
        local cmd, args = text:match("^/(%S+)%s*(.*)$")
        local def = cmd and DarkRP.getChatCommand(cmd)
        if def and def.callback then
            local allowed = hook.Call("canChatCommand", GAMEMODE, ply, cmd, args)
            if allowed == false then return "" end
            return def.callback(ply, args)
        end
    end
    return ret
end

-- CAMI (bundled with DarkRP) ------------------------------------------------------------
CAMI = {privileges = {}}
function CAMI.RegisterPrivilege(p) CAMI.privileges[p.Name] = p end
function CAMI.UsergroupInherits(group, ancestor)
    if group == ancestor then return true end
    return group == "superadmin" and ancestor == "admin"
end
function CAMI.PlayerHasAccess(ply, priv, cb)
    local p = CAMI.privileges[priv]
    local ok = p == nil or (p.MinAccess == "admin" and ply:IsAdmin()) or (p.MinAccess == "superadmin" and ply:IsSuperAdmin()) or p.MinAccess == "user"
    if cb then cb(ok) end
    return ok
end

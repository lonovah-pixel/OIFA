--[[---------------------------------------------------------------------------
SCP framework (server).

Every SCP definition (SCP.register) provides:
  conditions   list of {id, name, eval = function(st) -> status, rate, text}
               status "ok" | "warn" | "bad"; rate = integrity per minute
  regen        integrity per minute when every condition is ok
  procedures   containment procedures started at the containment panel
  recapture    function(actor, scpPly) for breached SCPs (optional)
  setup / think / onSpawn / onBreach / onRecontain hooks

Containment integrity 0..100 maps to stages (config C.SCP.stages). At
"escape" a played SCP may break out; an unplayed SCP causes a containment
incident instead of a real breach (low population adaptation). A played SCP
outside its cell without authorisation is breached; recapture brings it back.

State is temporary and resets on restart (integrity back to 100).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SCP = SV.SCP
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local SC = C.SCP
local Roles = SV.Roles
local Facility = SV.Facility

SCP.state = SCP.state or {}       -- id -> state
SCP.unlocks = SCP.unlocks or {}   -- id -> {unlockId = true} (persistent)

function SCP.register(id, def)
    def.id = id
    def.conditions = def.conditions or {}
    def.procedures = def.procedures or {}
    SCP.defs[id] = def
    SCP.state[id] = SCP.state[id] or {id = id, integrity = 100, stage = "stable", breached = false, procCooldown = {}, data = {}}
    if def.setup then def.setup(SCP.state[id]) end
end

function SCP.get(id)
    return SCP.state[id]
end

function SCP.playerOf(id)
    local st = SCP.state[id]
    local p = st and st.player
    if IsValid(p) and SCP.of(p) == id then return p end
    return nil
end

--- Breached objects. Objects registered with minor = true (harmless ones)
--- are counted only when includeMinor is set.
function SCP.breachedCount(includeMinor)
    local n = 0
    for id, st in pairs(SCP.state) do
        local def = SCP.defs[id]
        if st.breached and (includeMinor or not (def and def.minor)) then n = n + 1 end
    end
    return n
end

function SCP.anyBreached()
    return SCP.breachedCount() > 0
end

function SCP.popFactor()
    return math.Clamp(U.onlineCount() / C.Population.target, SC.popFloor, 1)
end

function SCP.lowPop()
    return U.onlineCount() < C.Population.low
end

function SCP.hasUnlock(id, unlock)
    return SCP.unlocks[id] ~= nil and SCP.unlocks[id][unlock] == true
end

function SCP.unlock(id, unlock)
    SCP.unlocks[id] = SCP.unlocks[id] or {}
    if SCP.unlocks[id][unlock] then return false end
    SCP.unlocks[id][unlock] = true
    SV.Settings.set("scp.unlocks", SCP.unlocks)
    SV.Bus.emit("scp.unlocked", {scp = id, unlock = unlock})
    return true
end

hook.Add("SiteVeil.DatabaseReady", "SiteVeil.SCP", function()
    local saved = SV.Settings.get("scp.unlocks", {})
    if istable(saved) then SCP.unlocks = saved end
end)

--[[---------------------------------------------------------------------------
Cells
---------------------------------------------------------------------------]]
function SCP.cellZone(id)
    for _, z in ipairs(SV.MapCfg.zones("cell")) do
        if z.props.scp == id then return z end
    end
    return nil
end

--- Spawn / reference point of the SCP's cell.
function SCP.cellCenter(id)
    local def = SCP.defs[id]
    local role = def and Roles.get(def.role)
    if role then
        for _, p in ipairs(SV.MapCfg.points("spawn")) do
            if p.props.group == role.id then return SV.MapCfg.toVec(p.pos) end
        end
    end
    local z = SCP.cellZone(id)
    if z then
        local b = z.boxes[1]
        return Vector((b.min[1] + b.max[1]) / 2, (b.min[2] + b.max[2]) / 2, b.min[3] + 8)
    end
    local st = SCP.state[id]
    return st and st.virtualCenter or nil
end

function SCP.inCell(id, pos)
    local z = SCP.cellZone(id)
    if z then return SV.MapCfg.zoneContains(z, pos) end
    local center = SCP.cellCenter(id)
    if not center then return true end
    return pos:DistToSqr(center) <= SC.virtualCellRadius * SC.virtualCellRadius
end

function SCP.cellSector(id)
    local center = SCP.cellCenter(id)
    return center and Facility.sectorAt(center) or nil
end

--- Players (non-SCP, alive, with a character) inside the cell, by category.
function SCP.peopleInCell(id)
    local out = {all = {}, classd = {}, staff = {}, science = {}, security = {}}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p.SVChar and not Roles.isSCP(p) and SCP.inCell(id, p:GetPos()) then
            table.insert(out.all, p)
            local div = p.SVChar.division
            if div == "classd" then table.insert(out.classd, p) else table.insert(out.staff, p) end
            if div == "science" then table.insert(out.science, p) end
            if div == "security" or div == "mtf" then table.insert(out.security, p) end
        end
    end
    return out
end

--[[---------------------------------------------------------------------------
Helpers shared by SCP implementations
---------------------------------------------------------------------------]]
--- Safe zones (map config) forbid offensive SCP abilities.
function SCP.inSafeZone(pos)
    return SV.MapCfg.zoneAt(pos, "safe") ~= nil
end

--- Whether a position can hold a player: inside the world, not in solid.
function SCP.validDestination(pos)
    return pos ~= nil and util.IsInWorld(pos) and SV.MapCfg.hullFree(pos)
end

--- Teleports ply to pos after validation; falls back to the role spawn.
--- Returns true when ply was moved to pos (or a free position near it).
function SCP.teleport(ply, pos)
    local dest = pos and DarkRP.findEmptyPos(pos, {ply}, 200, 30, Vector(16, 16, 64))
    if SCP.validDestination(dest) then
        ply:SetPos(dest)
        return true
    end
    local role = Roles.ofPlayer(ply)
    local spawn = role and SV.MapCfg.pickSpawn(ply, role)
    if spawn then ply:SetPos(spawn) end
    SV.Log.warn("SCP teleport rejected for %s at %s, used spawn", tostring(ply), tostring(pos))
    return false
end

--- Entity in front of ply within range (hull trace).
function SCP.frontTarget(ply, range)
    local tr = util.TraceHull({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * range, filter = ply,
        mins = Vector(-12, -12, -12), maxs = Vector(12, 12, 12), mask = MASK_SHOT_HULL})
    return tr.Entity
end

--- Valid human victim for an SCP attack.
function SCP.validVictim(target)
    return IsValid(target) and target:IsPlayer() and target:Alive() and target.SVChar ~= nil and not Roles.isSCP(target)
        and not SV.Admin.isOnDuty(target) and not SCP.inSafeZone(target:GetPos())
end

--- Lethal SCP attack; on small servers it incapacitates instead.
function SCP.harm(scpPly, target, id, lowPopRule)
    if lowPopRule ~= false and SCP.lowPop() and C.Medical.lowPopInjury and not SV.Medical.isIncapacitated(target) then
        SV.Medical.incapacitate(target, SCP.defs[id].name, scpPly)
    else
        SV.Medical.markLethal(target)
        local d = DamageInfo()
        d:SetDamage(math.max(target:Health(), 1) + 500)
        d:SetDamageType(DMG_SLASH)
        d:SetAttacker(scpPly)
        d:SetInflictor(scpPly)
        target:TakeDamageInfo(d)
    end
    SV.Audit.log("scp", "attack", scpPly, target, {scp = id})
    SV.Bus.emit("scp.attack", {scp = id, ply = scpPly, target = target})
end

--[[---------------------------------------------------------------------------
Integrity
---------------------------------------------------------------------------]]
local function publish(id)
    local st = SCP.state[id]
    local def = SCP.defs[id]
    SV.Sync.set("scp", id, {name = def.name, stage = st.stage, breached = st.breached, played = SCP.playerOf(id) ~= nil})
    local ply = SCP.playerOf(id)
    if ply then
        SV.Sync.setFor(ply, "self", "scp", {id = id, integrity = math.Round(st.integrity), stage = st.stage, breached = st.breached,
            conditions = st.lastConditions, data = def.publicData and def.publicData(st) or nil})
    end
end
SCP.publish = publish

local function stageMin(stageId)
    for _, s in ipairs(SC.stages) do
        if s.id == stageId then return s.min end
    end
    return 0
end

function SCP.adjustIntegrity(id, delta, reason)
    local st = SCP.state[id]
    if not st then return end
    local before = st.stage
    st.integrity = math.Clamp(st.integrity + delta, 0, 100)
    local stage = SCP.stageOf(st.integrity).id
    if stage ~= before then
        st.stage = stage
        SV.Bus.emit("scp.stageChanged", {scp = id, from = before, to = stage, reason = reason})
        local worse = SCP.stageOf(st.integrity).min < stageMin(before)
        if worse and stage ~= "signs" then
            local def = SCP.defs[id]
            for _, p in ipairs(player.GetAll()) do
                local r = Roles.ofPlayer(p)
                if r and (r.division == "science" or r.division == "security" or r.division == "mtf" or r.flags.recontain) then
                    DarkRP.notify(p, 3, 6, def.name .. ": " .. SCP.stageName(stage) .. ".")
                end
            end
        end
        if stage == "escape" then st.escapeSince = CurTime() else st.escapeSince = nil end
    end
    publish(id)
end

local function evaluate(id)
    local def = SCP.defs[id]
    local st = SCP.state[id]
    local total, allOk = 0, true
    local list = {}
    for _, cond in ipairs(def.conditions) do
        local status, rate, text = cond.eval(st)
        rate = rate or 0
        if status ~= "ok" then allOk = false end
        if rate < 0 then rate = rate * SCP.popFactor() end
        total = total + rate
        list[#list + 1] = {id = cond.id, name = cond.name, status = status, text = text}
    end
    if allOk and not st.breached then total = total + (def.regen or 1) end
    st.lastConditions = list
    return total, list
end
SCP.evaluate = evaluate

local function containmentTick()
    for id, def in pairs(SCP.defs) do
        local st = SCP.state[id]
        if not st.breached then
            local rate = evaluate(id)
            SCP.adjustIntegrity(id, rate * SC.tick / 60, "conditions")
            if def.tick then def.tick(st, SC.tick) end
            -- Unplayed SCP at "escape": incident, not a breach.
            if st.stage == "escape" and not SCP.playerOf(id) and st.escapeSince and CurTime() - st.escapeSince >= SC.unplayedIncidentDelay and not st.incident then
                st.incident = true
                local sector = SCP.cellSector(id)
                if sector then Facility.setAlert(sector, nil, true, "Сбой условий содержания " .. def.name) end
                SV.Bus.emit("scp.incident", {scp = id})
            elseif st.stage ~= "escape" then
                st.incident = nil
            end
        else
            st.lastConditions = st.lastConditions or {}
            publish(id)
        end
    end
end
timer.Create("SiteVeil.SCP.Containment", SC.tick, 0, function() SV.Perf.time("scp.containment", containmentTick) end)

--[[---------------------------------------------------------------------------
Breach and recontainment
---------------------------------------------------------------------------]]
--- Allows the SCP to be outside its cell (escorted experiments) for seconds.
function SCP.authorize(id, seconds)
    local st = SCP.state[id]
    if st then st.authorizedUntil = CurTime() + seconds end
end

function SCP.breach(id, how)
    local st = SCP.state[id]
    if not st or st.breached then return end
    st.breached = true
    st.breachedAt = CurTime()
    local def = SCP.defs[id]
    local ply = SCP.playerOf(id)
    if ply then ply:SetNW2Bool("sv_scp_breached", true) end
    SV.Audit.log("scp", "breach", ply, nil, {scp = id, how = how})
    if def.onBreach then def.onBreach(st, ply) end
    publish(id)
    SV.Bus.emit("scp.breached", {scp = id, name = def.name, how = how, minor = def.minor or nil})
end

function SCP.recontain(id, by, how)
    local st = SCP.state[id]
    if not st or not st.breached then return false end
    st.breached = false
    st.authorizedUntil = nil
    st.integrity = SC.recontainIntegrity
    st.stage = SCP.stageOf(st.integrity).id
    local def = SCP.defs[id]
    local ply = SCP.playerOf(id)
    if ply then
        ply:SetNW2Bool("sv_scp_breached", false)
        if not SCP.inCell(id, ply:GetPos()) then
            local center = SCP.cellCenter(id)
            if center then ply:SetPos(DarkRP.findEmptyPos(center, {ply}, 300, 30, Vector(16, 16, 64))) end
        end
    end
    if def.onRecontain then def.onRecontain(st, ply, by) end
    SV.Audit.log("scp", "recontain", by, ply, {scp = id, how = how})
    publish(id)
    for _, p in ipairs(player.GetAll()) do
        if IsValid(by) and (p == by or (p.SVChar and U.within(p, by, 600) and Roles.hasFlag(p, "canDetain"))) then
            SV.Chars.addXP(p, SC.recaptureXP, "security")
        end
    end
    DarkRP.notifyAll(0, 8, def.name .. " возвращён в камеру содержания.")
    SV.Bus.emit("scp.recontained", {scp = id, name = def.name, by = by, how = how})
    return true
end

local function breachCheck()
    for id in pairs(SCP.defs) do
        local st = SCP.state[id]
        local ply = SCP.playerOf(id)
        if ply and ply:Alive() and not st.breached then
            local authorized = st.authorizedUntil and CurTime() < st.authorizedUntil
            if not authorized and not SCP.inCell(id, ply:GetPos()) then SCP.breach(id, "left cell") end
        end
    end
end
timer.Create("SiteVeil.SCP.Breach", SC.breachCheck, 0, breachCheck)

--[[---------------------------------------------------------------------------
SCP players
---------------------------------------------------------------------------]]
hook.Add("SiteVeil.RoleSpawn", "SiteVeil.SCP", function(ply, role)
    if not role.scp then return end
    local id = role.scp
    local st = SCP.state[id]
    local def = SCP.defs[id]
    if not st or not def then return end
    st.player = ply
    if not st.virtualCenter then st.virtualCenter = ply:GetPos() end
    -- Breached SCPs respawn in the cell only after recontainment.
    if not st.breached then
        local center = SCP.cellCenter(id)
        if center and not SCP.inCell(id, ply:GetPos()) then
            ply:SetPos(DarkRP.findEmptyPos(center, {ply}, 300, 30, Vector(16, 16, 64)))
        end
    end
    ply:SetNW2Bool("sv_scp_breached", st.breached)
    if def.onSpawn then def.onSpawn(st, ply) end
    publish(id)
end)

hook.Add("SiteVeil.RoleAssigned", "SiteVeil.SCP", function(ply, role, oldRole)
    if oldRole and oldRole.scp and (not role or role.scp ~= oldRole.scp) then
        local st = SCP.state[oldRole.scp]
        local def = SCP.defs[oldRole.scp]
        if st and st.player == ply then
            if def and def.onLeave then def.onLeave(st, ply) end
            st.player = nil
            publish(oldRole.scp)
        end
    end
end)

hook.Add("PlayerDisconnected", "SiteVeil.SCP", function(ply)
    for id, st in pairs(SCP.state) do
        if st.player == ply then
            local def = SCP.defs[id]
            if def.onLeave then def.onLeave(st, ply) end
            st.player = nil
            -- Nobody plays it any more: a breached SCP counts as recontained
            -- by the facility's automated systems so the breach can end.
            if st.breached then SCP.recontain(id, nil, "unplayed") end
            publish(id)
        end
    end
end)

-- A neutralised breached SCP is secured by the facility; it respawns in its
-- cell after the normal respawn delay.
hook.Add("PlayerDeath", "SiteVeil.SCP", function(ply, _, attacker)
    local id = SCP.of(ply)
    local st = id and SCP.state[id]
    local def = id and SCP.defs[id]
    if not st or st.player ~= ply then return end
    if def.onDeath then def.onDeath(st, ply, attacker) end
    if st.breached then SCP.recontain(id, IsValid(attacker) and attacker:IsPlayer() and attacker or nil, "neutralized") end
end)

-- SCPs cannot carry items or use terminals and lockers.
hook.Add("SiteVeil.CanPickupItem", "SiteVeil.SCP", function(ply)
    if Roles.isSCP(ply) then return false, "Объект не может подбирать предметы." end
end)

hook.Add("SiteVeil.CanSwitchCharacter", "SiteVeil.SCP", function(ply)
    local id = SCP.of(ply)
    if id and SCP.state[id] and SCP.state[id].breached then return false, "Нельзя покинуть роль во время нарушения содержания." end
end)

-- Damage to SCP players is decided by their definition.
hook.Add("EntityTakeDamage", "SiteVeil.SCP.Damage", function(ent, dmg)
    if not ent:IsPlayer() then return end
    local id = SCP.of(ent)
    local def = id and SCP.defs[id]
    if def and def.onDamage then return def.onDamage(SCP.state[id], ent, dmg) end
end)

--[[---------------------------------------------------------------------------
Containment panel and procedures
---------------------------------------------------------------------------]]
local function staffCanRead(ply)
    local r = Roles.ofPlayer(ply)
    return r and (r.division == "science" or r.division == "security" or r.division == "mtf" or r.division == "engineering"
        or r.division == "administration" or r.flags.recontain) or SV.Admin.isOnDuty(ply)
end

local function procedureStatus(ply, id, proc)
    local st = SCP.state[id]
    local now = CurTime()
    if st.breached and not proc.duringBreach then return false, "объект вне камеры" end
    local cd = st.procCooldown[proc.id]
    if cd and cd > now then return false, "повтор через " .. U.formatDuration(cd - now) end
    if proc.roles then
        local r = Roles.ofPlayer(ply)
        local ok = false
        for _, f in ipairs(proc.roles) do
            if r and (r.division == f or r.flags[f]) then ok = true break end
        end
        if not ok then return false, proc.rolesText or "не ваша процедура" end
    end
    if proc.items then
        for itemId, n in pairs(proc.items) do
            if not SV.Inv.has(ply, itemId, n) then return false, "нужно: " .. C.Items[itemId].name end
        end
    end
    if proc.requires then
        local ok, why = proc.requires(st, ply)
        if not ok then return false, why end
    end
    return true
end

function SCP.panelView(ply, id)
    local def = SCP.defs[id]
    local st = SCP.state[id]
    local view = {id = id, name = def.name, stage = st.stage, stageName = SCP.stageName(st.stage), breached = st.breached,
        played = SCP.playerOf(id) ~= nil, procedures = {}}
    if staffCanRead(ply) then
        evaluate(id)
        view.conditions = st.lastConditions
        local exact = Roles.hasFlag(ply, "approveExperiments") or Roles.hasFlag(ply, "recontain") or SV.Admin.isOnDuty(ply)
        view.integrity = exact and math.Round(st.integrity) or nil
    end
    for _, proc in ipairs(def.procedures) do
        local ok, why = procedureStatus(ply, id, proc)
        view.procedures[#view.procedures + 1] = {id = proc.id, name = proc.name, desc = proc.desc, ok = ok, reason = why, duration = proc.duration}
    end
    return view
end

local function panelScp(ent)
    if not IsValid(ent) or ent:GetClass() ~= "sv_containment_panel" then return nil end
    local id = ent:GetScpId()
    return SCP.defs[id] and id or nil
end

Net.handle("scp.panel", function(ply, ent)
    local id = panelScp(ent)
    if not id then return false, "Панель не настроена." end
    if not U.within(ply, ent, 150) then return false, "Подойдите к панели." end
    if Facility.power(Facility.sectorAt(ent:GetPos())) < 0.3 then return false, "Панель обесточена." end
    Net.send(ply, "scp.panel", {ent = ent:EntIndex(), view = SCP.panelView(ply, id)})
    if staffCanRead(ply) then
        ply.SVInspected = ply.SVInspected or {}
        if not ply.SVInspected[id] or CurTime() - ply.SVInspected[id] > 300 then
            ply.SVInspected[id] = CurTime()
            SV.Bus.emit("containment.inspected", {ply = ply, scp = id})
        end
    end
end)

Net.handle("scp.procedure", function(ply, ent, procId)
    local id = panelScp(ent)
    if not id then return false, "Панель не настроена." end
    if not U.within(ply, ent, 150) then return false, "Подойдите к панели." end
    local def = SCP.defs[id]
    local proc
    for _, p in ipairs(def.procedures) do if p.id == procId then proc = p end end
    if not proc then return false, "Неизвестная процедура." end
    local ok, why = procedureStatus(ply, id, proc)
    if not ok then return false, "Процедура недоступна: " .. why .. "." end
    local st = SCP.state[id]
    return SV.Actions.start(ply, {
        id = "procedure", label = proc.name, duration = proc.duration, target = ent, maxDist = proc.anywhere and 99999 or 400, allowMove = true,
        cancelOnDamage = true,
        canContinue = function(p)
            local ok2, why2 = procedureStatus(p, id, proc)
            if not ok2 then return false, why2 end
            if proc.during then return proc.during(st, p) end
            return true
        end,
        onComplete = function(p)
            st.procCooldown[proc.id] = CurTime() + (proc.cooldown or 120)
            if proc.items then
                for itemId, n in pairs(proc.items) do SV.Inv.take(p, itemId, n) end
            end
            local msg = proc.effect(st, p)
            SV.Audit.log("scp", "procedure", p, nil, {scp = id, procedure = proc.id})
            SV.Bus.emit("containment.procedure", {ply = p, scp = id, procedure = proc.id})
            SV.Chars.addXP(p, proc.xp or 10, "research")
            DarkRP.notify(p, 0, 6, proc.name .. ": выполнено." .. (msg and (" " .. msg) or ""))
            publish(id)
        end,
    })
end)

Net.handle("scp.recapture", function(ply, target)
    if not IsValid(target) or not target:IsPlayer() then return false, "Нет цели." end
    local id = SCP.of(target)
    local def = id and SCP.defs[id]
    if not def or not def.recapture then return false, "Этот объект так не захватывается." end
    if not SCP.state[id].breached then return false, "Объект не покидал камеру." end
    return def.recapture(ply, target, SCP.state[id])
end)

Net.handle("scp.ability", function(ply, ability, ent)
    local id = SCP.of(ply)
    local def = id and SCP.defs[id]
    if not def or not def.abilities or not def.abilities[ability] then
        Net.violation(ply, "invalid scp ability")
        return false
    end
    if not ply:Alive() then return false end
    return def.abilities[ability](ply, SCP.state[id], ent)
end)

SV.Perf.registry("scp.breached", SCP.breachedCount)

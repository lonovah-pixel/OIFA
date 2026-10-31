--[[---------------------------------------------------------------------------
Jammer and RF tracker (server).

Placing a jammer (inventory use) creates an entity at the player's feet; for
lifetime seconds radio links that start or end in its sector lose most of
their quality (hook SiteVeil.RadioQuality) - messages are garbled or lost.
At most maxActive jammers on the map; a placement cooldown per player; the
placement leaves a trace. A tracker shows the bearing and rough distance to
the nearest jammer. Anybody can disarm one (5 s action) or shoot it.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Jammer = SV.Jammer
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Jammer
local Inv = SV.Inv
local Facility = SV.Facility

Jammer.active = Jammer.active or {}   -- ent -> {sector, untilTime, by}

local function prune()
    for ent, j in pairs(Jammer.active) do
        if not IsValid(ent) or CurTime() >= j.untilTime then
            Jammer.active[ent] = nil
            if IsValid(ent) then ent:Remove() end
        end
    end
end

function Jammer.jammedSector(sector)
    if not sector then return false end
    for ent, j in pairs(Jammer.active) do
        if IsValid(ent) and j.sector == sector and CurTime() < j.untilTime then return true end
    end
    return false
end

hook.Add("SiteVeil.RadioQuality", "SiteVeil.Jammer", function(from, to, q)
    if next(Jammer.active) == nil then return end
    if Jammer.jammedSector(Facility.sectorAt(from:GetPos())) or Jammer.jammedSector(Facility.sectorAt(to:GetPos())) then
        return q * K.quality
    end
end)

Inv.registerUse("jammer", function(ply, item)
    prune()
    if U.count(Jammer.active) >= K.maxActive then return false, "Слишком много помех в эфире: глушилка бесполезна." end
    if (ply.SVJammerAt or -1e9) + K.placeCooldown > CurTime() then return false, "Не сейчас." end
    local sector = Facility.sectorAt(ply:GetPos())
    if not sector then return false, "Здесь нечего глушить." end
    local ent = ents.Create("sv_jammer")
    if not IsValid(ent) then return false end
    ent:SetPos(ply:GetPos() + Vector(0, 0, 4))
    ent:Spawn()
    Inv.removeUid(ply, item.uid, 1)
    ply.SVJammerAt = CurTime()
    Jammer.active[ent] = {sector = sector, untilTime = CurTime() + K.lifetime, by = ply}
    if SV.Evidence then
        SV.Evidence.addTrace("damage", ent:GetPos(), {attacker = {char = ply.SVChar.id, name = ply.SVChar.name, division = ply.SVChar.division}})
    end
    SV.Audit.log("jammer", "place", ply, nil, {sector = sector})
    SV.Bus.emit("jammer.placed", {ply = ply, sector = sector})
    return true, "Глушилка включена."
end)

local bearings = {"восток", "северо-восток", "север", "северо-запад", "запад", "юго-запад", "юг", "юго-восток"}

Inv.registerUse("rftrack", function(ply)
    if (ply.SVTrackAt or -1e9) + K.trackCooldown > CurTime() then return false end
    ply.SVTrackAt = CurTime()
    prune()
    local best, bestD
    for ent in pairs(Jammer.active) do
        local d = ent:GetPos():Distance(ply:GetPos())
        if d <= K.trackRange and (not bestD or d < bestD) then best, bestD = ent, d end
    end
    if not best then return true, "Пеленгатор: источников помех не обнаружено." end
    local dir = best:GetPos() - ply:GetPos()
    local angle = (math.deg(math.atan2(dir.y, dir.x)) + 360 + 22.5) % 360
    local bearing = bearings[math.floor(angle / 45) + 1]
    local meters = math.max(math.Round(bestD / 52.5 / 5) * 5, 5)
    return true, "Пеленгатор: помехи — " .. bearing .. ", около " .. meters .. " м."
end)

function Jammer.destroy(ent, by, reason)
    if not Jammer.active[ent] then return end
    Jammer.active[ent] = nil
    if IsValid(ent) then ent:Remove() end
    SV.Audit.log("jammer", reason or "destroy", by)
    SV.Bus.emit("jammer.destroyed", {ply = by, reason = reason})
end

Net.handle("jammer.disarm", function(ply, ent)
    if not IsValid(ent) or not Jammer.active[ent] then return false end
    if not U.within(ply, ent, 90) then return false, "Подойдите ближе." end
    return SV.Actions.start(ply, {
        id = "disarm", label = "Отключение глушилки", duration = K.disarmTime, target = ent, maxDist = 110,
        onComplete = function(p)
            Jammer.destroy(ent, p, "disarm")
            if SV.Roles.hasFlag(p, "engineer") then SV.Chars.addXP(p, K.disarmXP, "engineering") end
            DarkRP.notify(p, 0, 4, "Глушилка отключена.")
        end,
    })
end)

hook.Add("EntityTakeDamage", "SiteVeil.Jammer", function(ent, dmg)
    local j = Jammer.active[ent]
    if not j then return end
    j.health = (j.health or K.health) - dmg:GetDamage()
    if j.health <= 0 then
        local attacker = dmg:GetAttacker()
        Jammer.destroy(ent, IsValid(attacker) and attacker:IsPlayer() and attacker or nil, "shot")
    end
end)

timer.Create("SiteVeil.Jammer", 2, 0, prune)
SV.Perf.registry("jammer.active", function() return U.count(Jammer.active) end)

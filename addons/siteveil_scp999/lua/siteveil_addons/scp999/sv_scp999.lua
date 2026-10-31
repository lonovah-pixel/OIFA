--[[---------------------------------------------------------------------------
SCP-999 (server). A harmless object (minor = true: leaving the cell raises
a local alert, not a facility breach).

Abilities: "hug" heals a person in front (no effect on incapacitated people:
that stays medical work) and relieves pain; "calm" sends a raging SCP-096
nearby into calming, otherwise lowers the director's tension.
Recapture: anybody with sweets lures it back (5 s action).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local SCP = SV.SCP
local U = SV.Util
local K = SV.Config.SCP.scp999
local Roles = SV.Roles
local Medical = SV.Medical
local Facility = SV.Facility

local ID = "scp999"
local S999 = {}
SCP.S999 = S999

local abilities = {}

abilities.hug = function(ply, st)
    local now = CurTime()
    if (st.nextHug or 0) > now then return false end
    local target = SCP.frontTarget(ply, K.hugRange)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or not target.SVChar or Roles.isSCP(target) then return false end
    if Medical.isIncapacitated(target) then
        DarkRP.notify(ply, 1, 3, "Человеку нужен врач.")
        return false
    end
    st.nextHug = now + K.hugCooldown
    target:SetHealth(math.min(target:Health() + K.heal, target:GetMaxHealth()))
    local m = Medical.get(target)
    m.pain = math.max((m.pain or 0) - K.painRelief, 0)
    Medical.publish(target)
    target:EmitSound("ambient/creatures/teddy.wav", 60, 130)
    DarkRP.notify(target, 0, 4, "SCP-999 обнимает вас. Становится легче.")
    SV.Audit.log("scp", "999.hug", ply, target)
    SV.Bus.emit("scp999.hug", {ply = ply, target = target})
    return true
end

abilities.calm = function(ply, st)
    local now = CurTime()
    if (st.nextCalm or 0) > now then
        DarkRP.notify(ply, 1, 3, "Успокоение будет доступно через " .. math.ceil(st.nextCalm - now) .. " с.")
        return false
    end
    local cooldown = SCP.hasUnlock(ID, "calm_boost") and K.calmCooldownBoost or K.calmCooldown
    local p096 = SCP.playerOf("scp096")
    local st096 = SCP.get("scp096")
    if p096 and st096 and SCP.S096 and (st096.data.mode == "rage" or st096.data.mode == "triggered") and U.within(ply, p096, K.calmRange) then
        st.nextCalm = now + cooldown
        SCP.S096.setMode(st096, "calming", "scp999")
        DarkRP.notify(p096, 0, 6, "Что-то тёплое и мягкое успокаивает вас.")
        SV.Bus.emit("scp999.calm", {ply = ply, scp = "scp096"})
        return true
    end
    if SV.Director then
        st.nextCalm = now + cooldown
        SV.Director.tension = math.max((SV.Director.tension or 0) - K.calmTension, 0)
        ply:EmitSound("ambient/creatures/teddy.wav", 70, 110)
        SV.Bus.emit("scp999.calm", {ply = ply})
        return true
    end
    return false
end

local function recapture(ply, target, st)
    if not SV.Inv.has(ply, "sweets") then return false, "Нужны конфеты — SCP-999 пойдёт за ними." end
    if not U.within(ply, target, 150) then return false, "Подойдите к объекту." end
    return SV.Actions.start(ply, {
        id = "recapture999", label = "Подманить SCP-999 конфетами", duration = K.recaptureTime, target = target, maxDist = 170,
        canContinue = function(p) return SV.Inv.has(p, "sweets"), "конфеты закончились" end,
        onComplete = function(p)
            SV.Inv.take(p, "sweets", 1)
            st.data.fedAt = CurTime()
            SCP.recontain(ID, p, "sweets")
        end,
    })
end

SCP.register(ID, {
    name = "SCP-999", role = "scp999", regen = 2, minor = true,
    setup = function(st)
        st.data.lastVisit = st.data.lastVisit or CurTime()
        st.data.fedAt = st.data.fedAt or CurTime()
    end,
    tick = function(st)
        if #SCP.peopleInCell(ID).all > 0 then st.data.lastVisit = CurTime() end
    end,
    conditions = {
        {id = "company", name = "Общение", eval = function(st)
            local since = CurTime() - (st.data.lastVisit or 0)
            if since < K.visitOk then return "ok", 0, "навещают" end
            return "warn", -1, "объекту одиноко"
        end},
        {id = "food", name = "Питание", eval = function(st)
            local since = CurTime() - (st.data.fedAt or 0)
            if since < K.fedOk then return "ok", 0, "сыт" end
            return "warn", -2, "голоден"
        end},
        {id = "power", name = "Питание замка", eval = function()
            if Facility.devicePowered(SCP.cellSector(ID), "containment") then return "ok", 0, "норма" end
            return "bad", -3, "замок обесточен"
        end},
    },
    procedures = {
        {
            id = "feed", name = "Покормить объект", desc = "Объекту дают конфеты. Он становится спокойнее и охотнее участвует в исследованиях.",
            duration = 8, cooldown = 300, xp = 5, items = {sweets = 1},
            effect = function(st)
                st.data.fedAt = CurTime()
                SCP.adjustIntegrity(ID, 8, "feed")
            end,
        },
        {
            id = "inspection", name = "Осмотр камеры", desc = "Проверка замка и состояния объекта.",
            duration = 10, cooldown = 120, xp = 5,
            effect = function() SCP.adjustIntegrity(ID, 2, "inspection") end,
        },
    },
    abilities = abilities,
    recapture = recapture,
    onSpawn = function(_, ply)
        ply:SetRunSpeed(170)
        ply:SetWalkSpeed(110)
        ply:SetModelScale(K.scale, 0)
        ply:SetColor(Color(255, 140, 30))
    end,
    onLeave = function(_, ply)
        if IsValid(ply) then
            ply:SetModelScale(1, 0)
            ply:SetColor(Color(255, 255, 255))
        end
    end,
    onDamage = function(_, _, dmg)
        dmg:ScaleDamage(K.damageFactor)
    end,
    publicData = function(st)
        return {fedMinutes = math.floor((CurTime() - (st.data.fedAt or 0)) / 60)}
    end,
})

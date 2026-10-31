--[[---------------------------------------------------------------------------
Tesla gates (server).

Each gate entity (map point kind "tesla") watches a cylinder. When someone
without a bypass card (clearance 3 with the "security" zone) or any SCP
enters, it charges audibly for C.charge seconds and then discharges into
everybody inside (admins on duty excepted). A gate works only with sector
power and a functional security subsystem. Staff with the lockdown or
recontain flag can switch off all gates of a sector for a limited time.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Tesla = SV.Tesla
local Net = SV.Net
local K = SV.Config.Tesla
local Facility = SV.Facility
local Roles = SV.Roles

SV.MapCfg.editorProps.tesla = {name = true, sector = true, radius = true}

Tesla.gates = Tesla.gates or {}          -- ent -> state
Tesla.disabledUntil = Tesla.disabledUntil or {}  -- sector -> CurTime
Tesla.lastDisable = Tesla.lastDisable or {}      -- sector -> CurTime

function Tesla.register(ent)
    Tesla.gates[ent] = {phase = "idle", chargeAt = 0, readyAt = 0}
end

function Tesla.unregister(ent)
    Tesla.gates[ent] = nil
end

local function sectorOf(ent)
    local p = ent.SVPoint
    return p and p.props.sector or Facility.sectorAt(ent:GetPos())
end

function Tesla.isActive(ent)
    local sector = sectorOf(ent)
    if (Tesla.disabledUntil[sector] or 0) > CurTime() then return false, "отключены охраной" end
    if Facility.power(sector) < 0.5 then return false, "нет питания" end
    if not Facility.subsystemOk(sector, "security") then return false, "неисправна система безопасности" end
    return true
end

local function bypasses(p)
    if Roles.isSCP(p) then return false end
    return SV.Access.check(p, K.bypass) == true
end

local function occupants(ent)
    local p = ent.SVPoint
    local radius = tonumber(p and p.props.radius) or K.radius
    local pos = ent:GetPos()
    local out = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and ply.SVChar and not SV.Admin.isOnDuty(ply) then
            local d = ply:GetPos() - pos
            if d.x * d.x + d.y * d.y <= radius * radius and math.abs(d.z) <= K.height then out[#out + 1] = ply end
        end
    end
    return out
end

local function discharge(ent)
    local victims = occupants(ent)
    ent:EmitSound("ambient/energy/zap" .. math.random(1, 9) .. ".wav", 90)
    local names = {}
    for _, p in ipairs(victims) do
        local d = DamageInfo()
        d:SetDamage(K.damage)
        d:SetDamageType(DMG_SHOCK)
        d:SetAttacker(ent)
        d:SetInflictor(ent)
        p:TakeDamageInfo(d)
        names[#names + 1] = p.SVChar and p.SVChar.name or p:Nick()
    end
    if #victims > 0 then
        SV.Audit.log("tesla", "discharge", nil, nil, {gate = ent.SVPoint and ent.SVPoint.id, victims = names})
        SV.Bus.emit("tesla.discharge", {gate = ent, victims = victims})
    end
end

local function tick()
    local now = CurTime()
    for ent, st in pairs(Tesla.gates) do
        if not IsValid(ent) then
            Tesla.gates[ent] = nil
        elseif st.phase == "charging" then
            if not Tesla.isActive(ent) then
                -- Switched off or lost power while charging: no discharge.
                st.phase = "idle"
            elseif now >= st.chargeAt then
                discharge(ent)
                st.phase = "idle"
                st.readyAt = now + K.cooldown
            end
        elseif now >= st.readyAt and Tesla.isActive(ent) then
            for _, p in ipairs(occupants(ent)) do
                if not bypasses(p) then
                    st.phase = "charging"
                    st.chargeAt = now + K.charge
                    ent:EmitSound("ambient/machines/electric_machine.wav", 80, 120)
                    break
                end
            end
        end
        if IsValid(ent) and ent.SetCharging then ent:SetCharging(st.phase == "charging") end
    end
end
timer.Create("SiteVeil.Tesla", K.tick, 0, function() SV.Perf.time("tesla.tick", tick) end)

local function publish()
    local out = {}
    for sector, t in pairs(Tesla.disabledUntil) do
        if t > CurTime() then out[sector] = t end
    end
    SV.Sync.set("tesla", "disabled", out)
end

--- Switches the gates of a sector off for seconds (clamped). Returns ok, msg.
function Tesla.disable(sector, seconds, by)
    if not Facility.sectors[sector] then return false, "Сектор не найден." end
    local now = CurTime()
    local last = Tesla.lastDisable[sector]
    if last and now - last < K.disableCooldown and not SV.Admin.isOnDuty(by) then
        return false, "Повторное отключение через " .. math.ceil(K.disableCooldown - (now - last)) .. " с."
    end
    seconds = math.Clamp(math.floor(seconds), 10, K.disableMax)
    Tesla.disabledUntil[sector] = now + seconds
    Tesla.lastDisable[sector] = now
    SV.Audit.log("tesla", "disable", by, nil, {sector = sector, seconds = seconds})
    publish()
    timer.Create("SiteVeil.Tesla.Enable." .. sector, seconds, 1, publish)
    return true, "Тесла-ворота сектора отключены на " .. seconds .. " с."
end

Net.handle("tesla.disable", function(ply, sector, seconds)
    local allowed = SV.Admin.isOnDuty(ply)
    for _, f in ipairs(K.disableFlags) do if Roles.hasFlag(ply, f) then allowed = true end end
    if not allowed then return false, "Отключать тесла-ворота могут командиры охраны и МОГ." end
    return Tesla.disable(sector, seconds, ply)
end)

SV.Perf.registry("tesla.gates", function() return SV.Util.count(Tesla.gates) end)

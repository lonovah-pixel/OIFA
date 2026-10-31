--[[---------------------------------------------------------------------------
Surgery (server).

A doctor at an operating table (map point kind "medbed") operates a patient
lying at it. A conscious patient must consent; an incapacitated one cannot.
The server reveals one step at a time (which tool is needed now); the
doctor answers each step. Too fast or too slow, or the wrong tool, is a
complication (extra bleeding); more complications than allowed fail the
operation. Items are spent at the start. Success applies the effect:
  trauma     bleeding stopped, an incapacitated patient stabilised
  fracture   fracture healed, pain gone
  infection  infection removed even at stage 2 (otherwise incurable)
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Surgery = SV.Surgery
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Surgery
local Medical = SV.Medical
local M = SV.Config.Medical
local Inv = SV.Inv
local Roles = SV.Roles

SV.MapCfg.editorProps.medbed = {name = true}

Surgery.active = Surgery.active or {}    -- doctor -> operation
Surgery.consents = Surgery.consents or {} -- patient -> pending request
Surgery.nextId = Surgery.nextId or 1

local function indicated(op, patient)
    local s = Medical.get(patient)
    if op == "trauma" then return (s.bleed or 0) >= M.bleedHeavy or (s.down ~= nil and not s.down.stabilised) end
    if op == "fracture" then return s.fracture == true end
    if op == "infection" then return s.infected ~= nil and s.infected.stage >= 2 end
    return false
end
Surgery.indicated = indicated

function Surgery.blockedReason(doctor, bed, patient, op)
    local def = K.operations[op]
    if not def then return "неизвестная операция" end
    if not Roles.hasFlag(doctor, "doctor") and not SV.Admin.isOnDuty(doctor) then return "операции проводит врач" end
    if not IsValid(bed) or bed:GetClass() ~= "sv_medbed" then return "нужен операционный стол" end
    if not U.within(doctor, bed, K.doctorRadius) then return "подойдите к столу" end
    if not IsValid(patient) or not patient:IsPlayer() or not patient:Alive() or not patient.SVChar or Roles.isSCP(patient) then return "нет пациента" end
    if patient == doctor then return "нельзя оперировать себя" end
    if not U.within(patient, bed, K.patientRadius) then return "пациент должен лежать на столе" end
    if Surgery.active[doctor] then return "операция уже идёт" end
    for _, o in pairs(Surgery.active) do
        if o.patient == patient or o.bed == bed then return "стол или пациент заняты" end
    end
    if not indicated(op, patient) then return "нет показаний: " .. def.needs end
    for item, n in pairs(def.items) do
        if not Inv.has(doctor, item, n) then return "нужно: " .. SV.Config.Items[item].name .. " ×" .. n end
    end
    return nil
end

local function sendStep(o)
    o.stepAt = CurTime()
    o.need = o.rng:int(1, #K.tools)
    Net.send(o.doctor, "surgery.step", {id = o.id, step = o.step, steps = o.steps, tool = o.need, tools = K.tools,
        complications = o.complications, allowed = o.allowed, name = K.operations[o.op].name})
end

local function finish(o, ok, reason)
    Surgery.active[o.doctor] = nil
    local patient, doctor = o.patient, o.doctor
    if IsValid(doctor) then Net.send(doctor, "surgery.done", {ok = ok, reason = reason}) end
    if not IsValid(patient) then return end
    local s = Medical.get(patient)
    if ok then
        if o.op == "trauma" then
            s.bleed = 0
            if s.down then
                s.down.stabilised = true
                s.down.wakeAt = CurTime() + M.stabilisedMax
            end
        elseif o.op == "fracture" then
            s.fracture = false
            s.pain = 0
            SV.Move.clear(patient, "fracture")
        elseif o.op == "infection" then
            s.infected = nil
            SV.Bus.emit("medical.cured", {ply = patient})
        end
        if IsValid(doctor) then SV.Chars.addXP(doctor, K.xp, "medical") end
        DarkRP.notify(patient, 0, 6, K.operations[o.op].name .. ": операция прошла успешно.")
    else
        s.bleed = math.min((s.bleed or 0) + M.bleedHeavy, M.bleedMax)
        DarkRP.notify(patient, 1, 6, K.operations[o.op].name .. ": операция не удалась.")
    end
    Medical.publish(patient)
    SV.Audit.log("surgery", ok and "success" or "fail", doctor, patient, {op = o.op, reason = reason})
    SV.Bus.emit("surgery.finished", {ply = doctor, target = patient, op = o.op, ok = ok})
end

local function begin(doctor, bed, patient, op)
    local why = Surgery.blockedReason(doctor, bed, patient, op)
    if why then return false, "Операция невозможна: " .. why .. "." end
    local def = K.operations[op]
    for item, n in pairs(def.items) do Inv.take(doctor, item, n) end
    local assist = false
    for _, p in ipairs(player.GetAll()) do
        if p ~= doctor and p ~= patient and Roles.hasFlag(p, "medic") and U.within(p, bed, K.assistRadius) then assist = true end
    end
    local id = Surgery.nextId
    Surgery.nextId = id + 1
    local o = {id = id, doctor = doctor, patient = patient, bed = bed, op = op, step = 1, steps = def.steps, complications = 0,
        allowed = K.complications + (assist and 1 or 0), rng = SV.RNG.new(SV.RNG.seedFor("surgery", id))}
    Surgery.active[doctor] = o
    SV.Audit.log("surgery", "start", doctor, patient, {op = op, assist = assist})
    sendStep(o)
    return true, def.name .. ": операция начата" .. (assist and " (ассистирует медик)" or "") .. "."
end

Net.handle("surgery.start", function(doctor, bed, patient, op)
    local why = Surgery.blockedReason(doctor, bed, patient, op)
    if why then return false, "Операция невозможна: " .. why .. "." end
    if Medical.isIncapacitated(patient) or (SV.Security and SV.Security.restrained[patient]) then
        return begin(doctor, bed, patient, op)
    end
    Surgery.consents[patient] = {doctor = doctor, bed = bed, op = op, expires = CurTime() + 20}
    Net.send(patient, "surgery.consent", {doctor = SV.Chars.displayName(doctor), name = K.operations[op].name})
    return true, "Запрошено согласие пациента."
end)

Net.handle("surgery.consent", function(patient, yes)
    local c = Surgery.consents[patient]
    Surgery.consents[patient] = nil
    if not c or c.expires < CurTime() or not IsValid(c.doctor) then return false, "Запрос больше не действует." end
    if not yes then
        DarkRP.notify(c.doctor, 3, 4, SV.Chars.displayName(patient) .. " отказывается от операции.")
        return true
    end
    local ok, msg = begin(c.doctor, c.bed, patient, c.op)
    DarkRP.notify(c.doctor, ok and 0 or 1, 5, msg)
    return ok
end)

Net.handle("surgery.step", function(doctor, id, tool)
    local o = Surgery.active[doctor]
    if not o or o.id ~= id then return false end
    local dt = CurTime() - o.stepAt
    local good = tool == o.need and dt >= K.stepMin and dt <= K.stepMax
    if good then
        o.step = o.step + 1
        if o.step > o.steps then
            finish(o, true)
            return true, "Операция завершена успешно."
        end
    else
        o.complications = o.complications + 1
        if IsValid(o.patient) then
            local s = Medical.get(o.patient)
            s.bleed = math.min((s.bleed or 0) + M.bleedLight, M.bleedMax)
        end
        if o.complications > o.allowed then
            finish(o, false, "слишком много осложнений")
            return false, "Операция не удалась."
        end
    end
    sendStep(o)
    return true
end)

Net.handle("surgery.open", function(doctor, bed)
    if not IsValid(bed) or bed:GetClass() ~= "sv_medbed" or not U.within(doctor, bed, K.doctorRadius) then return false end
    local patients = {}
    for _, p in ipairs(player.GetAll()) do
        if p ~= doctor and p:Alive() and p.SVChar and not Roles.isSCP(p) and U.within(p, bed, K.patientRadius) then
            local ops = {}
            for op, def in pairs(K.operations) do
                ops[#ops + 1] = {id = op, name = def.name, needs = def.needs, blocked = Surgery.blockedReason(doctor, bed, p, op)}
            end
            table.sort(ops, function(a, b) return a.id < b.id end)
            patients[#patients + 1] = {ent = p:EntIndex(), name = SV.Chars.displayName(p), ops = ops}
        end
    end
    Net.send(doctor, "surgery.open", {bed = bed:EntIndex(), patients = patients})
end)

-- Leaving the table or the patient: the operation fails.
timer.Create("SiteVeil.Surgery", 0.5, 0, function()
    for doctor, o in pairs(Surgery.active) do
        if not IsValid(doctor) or not doctor:Alive() or not IsValid(o.patient) or not o.patient:Alive() then
            finish(o, false, "операция прервана")
        elseif not U.within(doctor, o.bed, K.doctorRadius) or not U.within(o.patient, o.bed, K.patientRadius) then
            finish(o, false, "врач или пациент отошли от стола")
        elseif CurTime() - o.stepAt > K.stepMax + 2 then
            o.complications = o.complications + 1
            if o.complications > o.allowed then finish(o, false, "операция затянулась") else sendStep(o) end
        end
    end
end)

hook.Add("PlayerDisconnected", "SiteVeil.Surgery", function(ply) Surgery.consents[ply] = nil end)

--[[---------------------------------------------------------------------------
Class-D labor (server).

A workstation (map point kind "workstation", prop job = sorting | assembly
| cleaning) hands out a small interactive job. The server generates the
challenge and keeps the solution; the client returns the answer. The
answer is accepted only if it is correct, took at least minStepTime per
step (no scripts) and arrived within the time limit while the worker stayed
at the station. One worker per station; cooldowns; a per-shift limit.
Rewards: experience (capped by the gamemode), budget or stock.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Labor = SV.Labor
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Labor

SV.MapCfg.editorProps.workstation = {job = true, name = true}

Labor.active = Labor.active or {}     -- ply -> challenge
Labor.done = Labor.done or {}         -- "char:shift" -> count
Labor.nextId = Labor.nextId or 1

local function jobOf(ent)
    local p = ent.SVPoint
    return p and K.jobs[p.props.job] and p.props.job or nil
end

local function allowed(ply, job)
    for _, d in ipairs(K.jobs[job].divisions) do
        if ply.SVChar.division == d then return true end
    end
    return false
end

local function doneKey(ply) return ply.SVChar.id .. ":" .. SV.Shift.id end

local generators = {}

generators.sorting = function(def, rng)
    local seq = {}
    for i = 1, def.steps do seq[i] = rng:int(1, #def.symbols) end
    return {symbols = def.symbols, items = seq}, seq
end

generators.assembly = function(def, rng)
    local numbers, used = {}, {}
    while #numbers < def.steps do
        local n = rng:int(10, 99)
        if not used[n] then used[n] = true numbers[#numbers + 1] = n end
    end
    local order = {}
    for i = 1, #numbers do order[i] = i end
    table.sort(order, function(a, b) return numbers[a] < numbers[b] end)
    return {numbers = numbers}, order
end

generators.cleaning = function(def, rng)
    local dirty, list = {}, {}
    while #list < def.steps do
        local c = rng:int(1, def.grid)
        if not dirty[c] then dirty[c] = true list[#list + 1] = c end
    end
    table.sort(list)
    return {grid = def.grid, dirty = list}, list
end

local function sameList(a, b, unordered)
    if not istable(a) or #a ~= #b then return false end
    local x, y = {}, {}
    for i = 1, #a do x[i] = tonumber(a[i]) y[i] = b[i] end
    if unordered then
        table.sort(x)
        table.sort(y)
    end
    for i = 1, #x do
        if x[i] ~= y[i] then return false end
    end
    return true
end

function Labor.blockedReason(ply, ent)
    local job = jobOf(ent)
    if not job then return "рабочее место не настроено" end
    if not allowed(ply, job) then return "это работа для другого подразделения" end
    if not U.within(ply, ent, 100) then return "подойдите к рабочему месту" end
    if Labor.active[ply] then return "вы уже работаете" end
    for _, c in pairs(Labor.active) do
        if c.station == ent then return "место занято" end
    end
    if (ply.SVLaborNext or -1e9) > CurTime() then return "перерыв ещё " .. math.ceil(ply.SVLaborNext - CurTime()) .. " с" end
    if (Labor.done[doneKey(ply)] or 0) >= K.perShift then return "норма смены выполнена" end
    return nil
end

function Labor.start(ply, ent)
    local why = Labor.blockedReason(ply, ent)
    if why then return false, "Работа недоступна: " .. why .. "." end
    local job = jobOf(ent)
    local def = K.jobs[job]
    local id = Labor.nextId
    Labor.nextId = id + 1
    local rng = SV.RNG.new(SV.RNG.seedFor("labor", ply.SVChar.id * 100000 + id))
    local view, solution = generators[job](def, rng)
    Labor.active[ply] = {id = id, job = job, station = ent, solution = solution, started = CurTime()}
    view.id, view.job, view.name, view.hint, view.timeLimit = id, job, def.name, def.hint, K.timeLimit
    Net.send(ply, "labor.challenge", view)
    return true
end

local function reward(ply, def)
    local r = def.reward
    if r.xp then SV.Chars.addXP(ply, r.xp, "task") end
    if r.budget then SV.Supply.adjustBudget(r.budget.division, r.budget.amount, "Работы класса D") end
    if r.stock then SV.Supply.addStock(r.stock.division, r.stock.item, r.stock.count) end
end

function Labor.answer(ply, id, answer)
    local c = Labor.active[ply]
    if not c or c.id ~= id then return false, "Задание не найдено." end
    Labor.active[ply] = nil
    local def = K.jobs[c.job]
    local elapsed = CurTime() - c.started
    local ok, why = true, nil
    if elapsed > K.timeLimit then ok, why = false, "время вышло"
    elseif elapsed < def.steps * K.minStepTime then ok, why = false, "слишком быстро"
    elseif not IsValid(c.station) or not U.within(ply, c.station, 120) then ok, why = false, "вы отошли от рабочего места"
    elseif not sameList(answer, c.solution, c.job == "cleaning") then ok, why = false, "ошибка в работе" end
    if not ok then
        ply.SVLaborNext = CurTime() + K.failCooldown
        SV.Bus.emit("labor.failed", {ply = ply, job = c.job, reason = why})
        return false, "Работа не принята: " .. why .. "."
    end
    ply.SVLaborNext = CurTime() + K.cooldown
    local key = doneKey(ply)
    Labor.done[key] = (Labor.done[key] or 0) + 1
    reward(ply, def)
    SV.Audit.log("labor", "done", ply, nil, {job = c.job, seconds = math.Round(elapsed, 1)})
    SV.Bus.emit("labor.done", {ply = ply, job = c.job})
    return true, def.name .. ": работа принята (" .. Labor.done[key] .. "/" .. K.perShift .. " за смену)."
end

Net.handle("labor.start", function(ply, ent) return Labor.start(ply, ent) end)
Net.handle("labor.answer", function(ply, id, answer) return Labor.answer(ply, id, answer) end)

hook.Add("PlayerDisconnected", "SiteVeil.Labor", function(ply) Labor.active[ply] = nil end)
hook.Add("PlayerDeath", "SiteVeil.Labor", function(ply) Labor.active[ply] = nil end)
timer.Create("SiteVeil.Labor.Timeout", 5, 0, function()
    for ply, c in pairs(Labor.active) do
        if not IsValid(ply) or CurTime() - c.started > K.timeLimit + 5 then Labor.active[ply] = nil end
    end
end)

--[[---------------------------------------------------------------------------
Director event: an urgent warehouse order for class D (custom kind).
---------------------------------------------------------------------------]]
local RUSH = 3

local function stations()
    local list = {}
    for _, ent in ipairs(ents.FindByClass("sv_workstation")) do
        if IsValid(ent) then list[#list + 1] = ent end
    end
    return list
end

if SV.Director and SV.Director.registerEvent then
    SV.Director.registerEvent({
        id = "labor_rush", name = "Срочный заказ склада", kind = "custom", weight = 5, minOnline = 4, cooldown = 1800,
        duration = 360, warn = 0,
        text = "Выполните " .. RUSH .. " работы на рабочих местах до конца срока.",
        solvers = {{division = "classd", min = 1}},
        condition = function() return #stations() > 0 end,
        reward = {xp = 10, budget = 20, division = "administration"},
        custom = {
            prepare = function(run)
                local list = stations()
                if #list == 0 then return false end
                run.pos = list[1]:GetPos()
                run.sector = SV.Facility.sectorAt(run.pos)
                run.count = 0
                run.percent = 0
                return true
            end,
            check = function(run) return run.count >= RUSH end,
        },
    })

    SV.Bus.on("labor.done", "labor.rush", function(data)
        for _, run in pairs(SV.Director.active) do
            if run.def.id == "labor_rush" and run.phase == "active" then
                run.count = run.count + 1
                run.percent = math.floor(math.min(run.count / RUSH, 1) * 100)
                run.helpers[data.ply] = true
            end
        end
    end)
end

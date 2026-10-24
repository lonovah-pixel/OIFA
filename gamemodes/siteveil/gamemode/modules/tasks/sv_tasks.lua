--[[---------------------------------------------------------------------------
Duty tasks (server).

Per-character state lives in char.data.tasks:
    active = {[taskId] = {progress = n, visited = {[pointId] = true}, shift = id}}
    done   = {[taskId] = {shift = id, count = n}}
Completed tasks are additionally written to sv_task_log (permanent history).
Progress comes from two sources only: the visit checker below and bus events
emitted by other modules, so the client never reports progress itself.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Tasks = SV.Tasks
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config

DB.registerMigrations("tasks", {
    {1, "task log", function()
        DB.query([[CREATE TABLE IF NOT EXISTS sv_task_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            char_id INTEGER NOT NULL,
            task_id TEXT NOT NULL,
            shift INTEGER NOT NULL,
            xp INTEGER NOT NULL,
            completed_at INTEGER NOT NULL
        )]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_task_log_char ON sv_task_log (char_id, shift)")
    end},
})

local function state(char)
    char.data.tasks = char.data.tasks or {}
    local st = char.data.tasks
    st.active = st.active or {}
    st.done = st.done or {}
    -- Drop progress of tasks from earlier shifts.
    for id, a in pairs(st.active) do
        if a.shift ~= SV.Shift.id or not Tasks.defs[id] then st.active[id] = nil end
    end
    return st
end

local function doneThisShift(st, id)
    local d = st.done[id]
    if not d or d.shift ~= SV.Shift.id then return 0 end
    return d.count
end

local function objectiveText(def, a)
    local o = def.objective
    local progress = a and a.progress or 0
    if o.type == "visit" then
        return string.format("Посещено постов: %d / %d", progress, o.count)
    end
    return string.format("Выполнено: %d / %d", progress, o.count)
end

function Tasks.publish(ply)
    local char = ply.SVChar
    if not char then
        SV.Sync.setFor(ply, "self", "tasks", nil)
        return
    end
    local st = state(char)
    local list = {}
    for id, a in pairs(st.active) do
        local def = Tasks.defs[id]
        local visited = {}
        for pid in pairs(a.visited or {}) do visited[#visited + 1] = pid end
        list[#list + 1] = {id = id, name = def.name, text = objectiveText(def, a), progress = a.progress, count = def.objective.count, visited = visited, point = def.objective.point}
    end
    table.sort(list, function(x, y) return x.id < y.id end)
    SV.Sync.setFor(ply, "self", "tasks", list)
end

--- Whether ply may take task def. Returns ok, reason.
function Tasks.canTake(ply, def)
    local char = ply.SVChar
    if not char then return false, "Нет персонажа." end
    if char.isSCP then return false, "SCP не выполняют служебные задачи." end
    if def.divisions and not U.contains(def.divisions, char.division) then return false, "Задача другого подразделения." end
    if def.roles and not U.contains(def.roles, char.role) then return false, "Задача для другой должности." end
    if def.minOnline and U.onlineCount() < def.minOnline then return false, "Недоступно при текущем онлайне." end
    local st = state(char)
    if st.active[def.id] then return false, "Задача уже выполняется." end
    if U.count(st.active) >= C.Tasks.maxActive then return false, "Одновременно можно выполнять не более " .. C.Tasks.maxActive .. " задач." end
    if doneThisShift(st, def.id) >= (def.perShift or 1) then return false, "Лимит этой задачи на смену исчерпан." end
    if def.objective.type == "visit" then
        local pts = SV.MapCfg.points(def.objective.point)
        if #pts < def.objective.count then
            return false, "На карте настроено недостаточно постов (" .. #pts .. " из " .. def.objective.count .. ")."
        end
    end
    return true
end

function Tasks.listFor(ply)
    local out = {}
    for _, def in ipairs(C.TaskList) do
        local ok, reason = Tasks.canTake(ply, def)
        local visible = ok or (reason ~= "Задача другого подразделения." and reason ~= "Задача для другой должности." and reason ~= "Нет персонажа.")
        if visible then
            out[#out + 1] = {id = def.id, name = def.name, description = def.description, ok = ok, reason = reason,
                xp = def.reward.xp, objective = objectiveText(def, nil)}
        end
    end
    return out
end

function Tasks.accept(ply, id)
    local def = Tasks.defs[id]
    if not def then return false, "Неизвестная задача." end
    local ok, reason = Tasks.canTake(ply, def)
    if not ok then return false, reason end
    local st = state(ply.SVChar)
    st.active[id] = {progress = 0, visited = {}, shift = SV.Shift.id}
    SV.Chars.save(ply.SVChar)
    Tasks.publish(ply)
    return true, "Задача принята: " .. def.name
end

function Tasks.abandon(ply, id)
    local st = state(ply.SVChar)
    if not st.active[id] then return false, "Задача не выполняется." end
    st.active[id] = nil
    SV.Chars.save(ply.SVChar)
    Tasks.publish(ply)
    return true, "Задача отменена."
end

function Tasks.complete(ply, id)
    local char = ply.SVChar
    local def = Tasks.defs[id]
    local st = state(char)
    if not st.active[id] then return end
    st.active[id] = nil

    local d = st.done[id]
    if not d or d.shift ~= SV.Shift.id then d = {shift = SV.Shift.id, count = 0} end
    d.count = d.count + 1
    st.done[id] = d

    local gained = SV.Chars.addXP(ply, def.reward.xp or 0, def.reward.source or "task")
    if def.reward.budget and SV.Supply and SV.Supply.adjustBudget then
        SV.Supply.adjustBudget(char.division, def.reward.budget, "Задача: " .. def.name, ply)
    end

    DB.query("INSERT INTO sv_task_log (char_id, task_id, shift, xp, completed_at) VALUES (?, ?, ?, ?, ?)",
        char.id, id, SV.Shift.id, gained, os.time())
    SV.Chars.save(char)
    Tasks.publish(ply)

    local msg = "Задача выполнена: " .. def.name
    if gained > 0 then msg = msg .. " (+" .. gained .. " опыта)" else msg = msg .. " (лимит опыта за смену исчерпан)" end
    DarkRP.notify(ply, 0, 6, msg)
    ply:EmitSound(C.Sounds.taskDone, 60)
    SV.Audit.log("task", "complete", ply, nil, {task = id, xp = gained})
    SV.Bus.emit("task.completed", {ply = ply, task = id})
end

local function advance(ply, id, amount)
    local char = ply.SVChar
    local st = state(char)
    local a = st.active[id]
    if not a then return end
    a.progress = math.min(a.progress + amount, Tasks.defs[id].objective.count)
    if a.progress >= Tasks.defs[id].objective.count then
        Tasks.complete(ply, id)
    else
        SV.Chars.save(char)
        Tasks.publish(ply)
    end
end

--[[---------------------------------------------------------------------------
Visit objectives
---------------------------------------------------------------------------]]
local function checkVisits()
    local radiusSqr = C.Tasks.visitRadius * C.Tasks.visitRadius
    for _, ply in ipairs(player.GetAll()) do
        local char = ply.SVChar
        if char and ply:Alive() and char.data.tasks and char.data.tasks.active then
            local pos = ply:GetPos()
            for id, a in pairs(char.data.tasks.active) do
                local def = Tasks.defs[id]
                if def and def.objective.type == "visit" then
                    for _, p in ipairs(SV.MapCfg.points(def.objective.point)) do
                        if not a.visited[p.id] and pos:DistToSqr(SV.MapCfg.toVec(p.pos)) <= radiusSqr then
                            a.visited[p.id] = true
                            DarkRP.notify(ply, 0, 3, "Пост отмечен: " .. (p.props.name or p.id))
                            advance(ply, id, 1)
                            break
                        end
                    end
                end
            end
        end
    end
end
timer.Create("SiteVeil.Tasks.Visits", C.Tasks.visitCheckInterval, 0, function()
    SV.Perf.time("tasks.visits", checkVisits)
end)

--[[---------------------------------------------------------------------------
Event objectives: subscribe once per distinct event name.
---------------------------------------------------------------------------]]
local subscribed = {}
for _, def in ipairs(C.TaskList) do
    local o = def.objective
    if o.type == "event" and not subscribed[o.event] then
        subscribed[o.event] = true
        SV.Bus.on(o.event, "tasks", function(data)
            local ply = data and data.ply
            if not IsValid(ply) or not ply.SVChar or not ply.SVChar.data.tasks then return end
            for id in pairs(ply.SVChar.data.tasks.active or {}) do
                local d = Tasks.defs[id]
                if d and d.objective.type == "event" and d.objective.event == o.event then
                    local match = true
                    for k, v in pairs(d.objective.match or {}) do
                        if data[k] ~= v then match = false break end
                    end
                    if match then advance(ply, id, 1) end
                end
            end
        end)
    end
end

--[[---------------------------------------------------------------------------
Network and lifecycle
---------------------------------------------------------------------------]]
Net.handle("tasks.list", function(ply)
    Net.send(ply, "tasks.list", {tasks = Tasks.listFor(ply)})
end)

Net.handle("tasks.accept", function(ply, id)
    local ok, msg = Tasks.accept(ply, id)
    Net.send(ply, "tasks.list", {tasks = Tasks.listFor(ply)})
    return ok, msg
end)

Net.handle("tasks.abandon", function(ply, id)
    local ok, msg = Tasks.abandon(ply, id)
    Net.send(ply, "tasks.list", {tasks = Tasks.listFor(ply)})
    return ok, msg
end)

hook.Add("SiteVeil.CharacterLoaded", "SiteVeil.Tasks", function(ply)
    Tasks.publish(ply)
end)

hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.Tasks", function(ply, _, reason)
    if reason ~= "disconnect" then SV.Sync.setFor(ply, "self", "tasks", nil) end
end)

SV.Bus.on("shift.started", "tasks", function()
    for _, ply in ipairs(player.GetAll()) do
        if ply.SVChar then Tasks.publish(ply) end
    end
end)

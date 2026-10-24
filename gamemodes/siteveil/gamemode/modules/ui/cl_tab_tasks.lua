--[[---------------------------------------------------------------------------
Tab "Задачи": active and available duty tasks.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local Net = SV.Net

UI.taskList = UI.taskList or nil

UI.registerTab{
    id = "tasks", name = "Задачи", order = 18,
    visible = function() local c = UI.myChar() return c and not c.isSCP end,
    build = function(panel)
        local scroll = UI.scroll(panel)
        local active = SV.Sync.get("self", "tasks") or {}
        local act = UI.card(scroll, "Выполняются (" .. #active .. " / " .. SV.Config.Tasks.maxActive .. ")")
        if #active == 0 then UI.text(act, "Нет активных задач.", "SV.Small", C.dim) end
        for _, t in ipairs(active) do
            UI.text(act, t.name .. " — " .. t.text, "SV.Body")
            local b = UI.button(act, "Отказаться", function() Net.call("tasks.abandon", t.id) end, "ghost")
            b:Dock(TOP)
        end

        local avail = UI.card(scroll, "Доступные задачи")
        if not UI.taskList then
            UI.text(avail, "Загрузка…", "SV.Small", C.dim)
            Net.call("tasks.list")
            return
        end
        for _, t in ipairs(UI.taskList) do
            UI.text(avail, t.name .. "  (+" .. (t.xp or 0) .. " опыта)", "SV.Sub")
            UI.text(avail, t.description, "SV.Small", C.dim)
            local b = UI.button(avail, "Принять", function() Net.call("tasks.accept", t.id) end, "primary")
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, UI.S(10))
            if not t.ok then b:SetBlocked(t.reason) end
        end
    end,
}

Net.on("tasks.list", function(data)
    UI.taskList = data.tasks
    UI.refreshTab("tasks")
end)

hook.Add("SiteVeil.Sync", "SiteVeil.UI.Tasks", function(channel, key)
    if channel == "self" and key == "tasks" then UI.refreshTab("tasks") end
end)

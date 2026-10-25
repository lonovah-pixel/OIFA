--[[---------------------------------------------------------------------------
Client smoke test: every client module loads, every HUD painter and every
tab builder runs without Lua errors - with empty state and with a typical
state of a character on shift. Rendering is stubbed (client_stubs.lua).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI

TEST("client modules load without errors", function()
    for _, e in ipairs(SV.Loader.errors) do error("loader: " .. e) end
    for _, name in ipairs({"ui_base", "ui", "scp", "research", "evidence", "director", "hidden", "reinforcements", "admin"}) do
        expect(SV.Loaded[name], "module not loaded: " .. name)
    end
    expect(#UI.hudElements >= 15, "few HUD elements registered: " .. #UI.hudElements)
    expect(#UI.tabs >= 8, "few tabs registered: " .. #UI.tabs)
end)

local function runAll(label)
    local ply = LocalPlayer()
    local errors = {}
    for _, e in ipairs(UI.hudElements) do
        local ok, err = pcall(e.fn, ply)
        if not ok then errors[#errors + 1] = label .. " HUD " .. e.id .. ": " .. tostring(err) end
    end
    for _, t in ipairs(UI.tabs) do
        local visible = true
        if t.visible then
            local ok, v = pcall(t.visible, ply)
            if not ok then errors[#errors + 1] = label .. " tab visible " .. t.id .. ": " .. tostring(v) end
            visible = ok and v
        end
        if visible then
            local ok, err = pcall(t.build, MOCK.makePanel("DPanel"))
            if not ok then errors[#errors + 1] = label .. " tab " .. t.id .. ": " .. tostring(err) end
        end
    end
    if #errors > 0 then error(table.concat(errors, "\n")) end
end

TEST("HUD and tabs with empty state", function()
    runAll("empty")
end)

TEST("HUD and tabs with a character on shift and active systems", function()
    local now = CurTime()
    SV.Sync.data.self = {
        char = {id = 1, name = "Тест Тестов", number = "D-0001", division = "security", role = "sec_guard", rank = 2, isSCP = false, xp = 10, playtime = 3600},
        med = {bleed = 1, fracture = true, pain = 40, down = {since = now, deathAt = now + 60, stabilised = false}},
        blink = {nextAt = now + 3, duration = 0.3},
        pocket = {untilTime = now + 30, fallback = false},
        target096 = true,
        instance = {untilTime = now + 100},
        hidden = {name = "Задание", text = "Текст", endsAt = now + 200, progress = 50, target = "Цель"},
        tasks = {{id = "orientation", name = "Обход", text = "Посетите посты"}},
        respawnAt = now + 10, sector = "lcz",
        scp = {id = "scp096", integrity = 60, stage = "signs", breached = false, conditions = {{name = "Шум", status = "warn", text = "шумно"}},
            data = {mode = "rage", modeName = "ярость", targets = 1, bagged = false, rageLeft = 20}},
    }
    SV.Sync.data.facility = {state = {id = "breach", since = now}, alerts = {lcz = {untilTime = now + 60}}, lockdowns = {lcz = {untilTime = now + 60}},
        recovery = {repairs = 1, needed = 3}}
    SV.Sync.data.director = {events = {{id = 1, name = "Событие", text = "Сделайте", solvers = {"security"}, pos = {0, 0, 0}, endsAt = now + 100, progress = 10}}}
    SV.Sync.data.reinforcements = {waves = {mtf = {queued = 1, pending = now + 30, active = 0, name = "МОГ"}, chaos = {queued = 0, active = 0, name = "ПХ"}}}
    SV.Research.current = {id = 1, status = "running", step = 1, steps = {{name = "Шаг", by = "lead", time = 5, critical = true}}}
    SV.Evidence.scanned = {{id = 1, kind = "blood", name = "Кровь", count = 2, age = "недавно", pos = {0, 0, 0}}}
    SV.Evidence.scannedAt = now
    runAll("state")
end)

TEST("every push handler accepts the payloads recorded by the server tests", function()
    local raw = __host_fixtures()
    if not raw then
        io.write("       (no recorded pushes: run the full suite to replay them)\n")
        return
    end
    local samples = util.JSONToTable(raw)
    local errors, handled, events = {}, 0, 0
    for event, list in pairs(samples) do
        local fn = SV.Net.listeners[event]
        if fn then
            events = events + 1
            for _, payload in ipairs(list) do
                local ok, err = pcall(fn, payload)
                handled = handled + 1
                if not ok then errors[#errors + 1] = event .. ": " .. tostring(err) end
            end
        end
    end
    io.write(string.format("       replayed %d payloads of %d events\n", handled, events))
    if #errors > 0 then error(table.concat(errors, "\n")) end
end)

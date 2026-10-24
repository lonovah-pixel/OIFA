--[[---------------------------------------------------------------------------
Stage 1: boot, DarkRP integration, database, characters, roles, one task.
---------------------------------------------------------------------------]]

local SV = SiteVeil

TEST("loader has no errors and all modules loaded", function()
    eq(#SV.Loader.errors, 0, table.concat(SV.Loader.errors, "; "))
    for _, m in ipairs(SV.Loader.describe()) do
        expect(m.loaded, "module not loaded: " .. m.name)
    end
end)

TEST("database migrated", function()
    expect(SV.DB.ready, "DB not ready")
    expect(SV.DB.queryValue("SELECT COUNT(*) FROM sv_migrations") ~= nil)
    expect(SV.DB.queryValue("SELECT 1 FROM sqlite_master WHERE name = 'sv_characters'") ~= nil)
end)

TEST("DarkRP city modules disabled and jobs generated from roles", function()
    local dd = DarkRP.disabledDefaults
    for _, m in ipairs({"money", "police", "hitmenu", "hungermod", "f4menu", "hud", "sleep", "tipjar", "events"}) do
        expect(dd.modules[m], "module not disabled: " .. m)
    end
    expect(dd.jobs.citizen and dd.jobs.cp and dd.jobs.mayor, "default jobs not disabled")
    expect(dd.entities["Money printer"], "money printer not disabled")
    eq(#RPExtraTeams, #SV.Config.Roles)
    for _, role in ipairs(SV.Roles.list) do
        expect(role.team and RPExtraTeams[role.team].siteVeilRole == role.id, "job mismatch for " .. role.id)
        eq(RPExtraTeams[role.team].salary, 0)
    end
    eq(GM.DefaultTeam, SV.Roles.get("lobby").team)
    eq(GM.Config.disallowClientsideScripts, true)
    eq(GM.Config.voiceradius, false)
end)

TEST("verify() reports no integration problems", function()
    local problems = SV.DarkRP.verify()
    eq(#problems, 0, table.concat(problems, "; "))
end)

TEST("disabled DarkRP commands are pruned, own commands kept", function()
    DarkRP.declareChatCommand{command = "buydoor", description = "x", delay = 1}
    DarkRP.declareChatCommand{command = "dropmoney", description = "x", delay = 1}
    SV.DarkRP.pruneCommands()
    expect(DarkRP.getChatCommand("buydoor") == nil, "buydoor survived")
    expect(DarkRP.getChatCommand("dropmoney") == nil, "dropmoney survived")
    expect(DarkRP.getChatCommand("cancel") ~= nil, "own command removed")
end)

TEST("money shims keep wallets at zero", function()
    local p = MOCK.join({name = "Wallet"})
    eq(p:addMoney(1000), false)
    eq(p:canAfford(1), false)
    eq(p:canAfford(0), true)
    eq(GM:playerWalletChanged(p, 500, 0), 0)
    eq(p:isArrested(), false)
end)

TEST("team change outside the character system is refused", function()
    local p = MOCK.join({name = "Hacker"})
    local sec = SV.Roles.get("sec_guard")
    eq(p:changeTeam(sec.team, true), false)
    contains(MOCK.lastTeamRefusal, "служебную систему")
end)

TEST("name validation", function()
    expect(SV.Chars.validateName("Анна Левченко"))
    expect(SV.Chars.validateName("John Smith"))
    expect(not SV.Chars.validateName("Анна"), "one word accepted")
    expect(not SV.Chars.validateName("Анна1 Левченко"), "digits accepted")
    expect(not SV.Chars.validateName("Admin Петров"), "reserved accepted")
    expect(not SV.Chars.validateName(string.rep("Длинное ", 10)), "too long accepted")
    eq(SV.Util.lowerRu("АННА Левченко"), "анна левченко")
end)

TEST("first join: lobby state, then character creation and selection", function()
    local p = MOCK.join({name = "Newbie"})
    expect(p.SVChar == nil)
    expect(p.frozen and p.noDraw and p.god, "not in lobby state")
    eq(#MOCK.pushes(p, "char.list") > 0, true, "char list not pushed")

    MOCK.rpc(p, "char.create", "Пётр Иванов", "security", 1)
    local list = SV.Chars.listFor(p:SteamID64())
    eq(#list, 1)
    eq(list[1].division, "security")
    eq(list[1].role, "sec_guard")
    eq(#list[1].number, 5)

    MOCK.rpc(p, "char.select", list[1].id)
    expect(p.SVChar ~= nil, "not selected: " .. tostring(MOCK.lastNotify(p)))
    eq(p:Team(), SV.Roles.get("sec_guard").team)
    eq(p:Nick(), "Пётр Иванов")
    expect(not p.frozen and not p.noDraw, "still in lobby state")
    expect(p:HasWeapon("sv_restraints"), "role tools not given")
end)

TEST("duplicate names and slot limit", function()
    local a = MOCK.join({name = "A"})
    MOCK.rpc(a, "char.create", "Мария Соколова", "science", 1)
    local b = MOCK.join({name = "B"})
    MOCK.rpc(b, "char.create", "мария соколова", "science", 1)
    eq(#SV.Chars.listFor(b:SteamID64()), 0, "duplicate name accepted")
    contains(MOCK.lastNotify(b), "уже существует")

    for i, n in ipairs({"Олег Первый", "Олег Второй", "Олег Третий", "Олег Четвёртый"}) do
        MOCK.rpc(a, "char.create", n, "classd", 1)
        MOCK.advance(11)
    end
    eq(#SV.Chars.listFor(a:SteamID64()), SV.Config.Characters.slots)
end)

TEST("whitelisted division needs whitelist", function()
    local p = MOCK.join({name = "WL"})
    MOCK.rpc(p, "char.create", "Игорь Директоров", "administration", 1)
    eq(#SV.Chars.listFor(p:SteamID64()), 0)
    SV.Chars.grantWhitelist(p:SteamID64(), "division", "administration", nil, "test")
    MOCK.advance(11)
    MOCK.rpc(p, "char.create", "Игорь Директоров", "administration", 1)
    eq(#SV.Chars.listFor(p:SteamID64()), 1)
end)

TEST("role requirements: rank and quota", function()
    local p = makeStaff({steam = "Rank", name = "Семён Рядовой", division = "security"})
    local ok, reason = SV.Chars.canTakeRole(p, SV.Roles.get("sec_officer"))
    expect(not ok, "low rank accepted")
    contains(reason, "звание")
    p.SVChar.rank = 3
    ok = SV.Chars.canTakeRole(p, SV.Roles.get("sec_officer"))
    expect(ok, "rank 3 refused")
    ok, reason = SV.Chars.canTakeRole(p, SV.Roles.get("sec_chief"))
    expect(not ok)
    ok, reason = SV.Chars.canTakeRole(p, SV.Roles.get("sci_junior"))
    expect(not ok)
    contains(reason, "перевод")
end)

TEST("quota scales with online", function()
    local role = SV.Roles.get("mtf_garrison")
    eq(SV.Roles.quotaFor(role, 10), 0)
    eq(SV.Roles.quotaFor(role, 16), 1)
    eq(SV.Roles.quotaFor(role, 64), 2)
    eq(SV.Roles.quotaFor(SV.Roles.get("classd_worker"), 64), nil)
end)

TEST("character persists across reconnect", function()
    local p = makeStaff({steam = "Persist", name = "Анна Сохранова", division = "medical"})
    local id = p.SVChar.id
    p.SVChar.xp = 77
    SV.Chars.save(p.SVChar)
    local sid = p:SteamID64()
    MOCK.disconnect(p)
    eq(SV.Chars.active[id], nil, "still active after disconnect")
    local row = SV.Chars.loadById(id)
    eq(row.xp, 77)
    local p2 = MOCK.join({name = "Persist", steamid = sid})
    MOCK.rpc(p2, "char.select", id)
    eq(p2.SVChar.xp, 77)
end)

TEST("deletion requires typed name and inactive character", function()
    local p = makeStaff({steam = "Del", name = "Борис Удалов", division = "classd"})
    local id = p.SVChar.id
    local ok, msg = SV.Chars.delete(p, id, "Борис Удалов")
    expect(not ok)
    contains(msg, "активного")
    p.SVLastSwitch = -1000
    MOCK.rpc(p, "char.unload")
    expect(p.SVChar == nil, "not unloaded: " .. tostring(MOCK.lastNotify(p)))
    ok = SV.Chars.delete(p, id, "Борис")
    expect(not ok)
    ok = SV.Chars.delete(p, id, "борис удалов")
    expect(ok)
    eq(SV.Chars.loadById(id), nil)
end)

TEST("orientation task: visit checkpoints, xp saved once per shift", function()
    -- Three checkpoints configured for the test map.
    local cfg = SV.MapCfg.cfg
    for i = 1, 3 do
        table.insert(cfg.points, {id = "cp" .. i, kind = "checkpoint", pos = {i * 500, 0, 0}, ang = {0, 0, 0}, props = {name = "Пост " .. i}})
    end
    SV.MapCfg.reindex()

    local p = makeStaff({steam = "Walker", name = "Глеб Ходоков", division = "engineering"})
    MOCK.rpc(p, "tasks.accept", "orientation")
    expect(p.SVChar.data.tasks.active.orientation, "task not accepted: " .. tostring(MOCK.lastNotify(p)))

    for i = 1, 3 do
        p:SetPos(Vector(i * 500 + 20, 0, 0))
        MOCK.advance(1.1)
    end
    eq(p.SVChar.data.tasks.active.orientation, nil, "task still active")
    eq(p.SVChar.xp, 25)
    eq(tonumber(SV.DB.queryValue("SELECT COUNT(*) FROM sv_task_log WHERE char_id = ?", p.SVChar.id)), 1)

    local ok, reason = SV.Tasks.accept(p, "orientation")
    expect(not ok, "orientation accepted twice in a shift")
    contains(reason, "Лимит")
    SV.DB.flush()
    eq(tonumber(SV.DB.queryValue("SELECT xp FROM sv_characters WHERE id = ?", p.SVChar.id)), 25)
end)

TEST("invalid RPCs are rejected and counted", function()
    local p = MOCK.join({name = "Evil"})
    MOCK.clientSend(p, "sv_rpc", {"no.such.action"})
    expect(#p.SVViolations >= 1, "unknown action not counted")
    -- oversized message
    MOCK.clientSend(p, "sv_rpc", {"char.list"}, 999999)
    expect(#p.SVViolations >= 2)
    -- string too long for schema
    MOCK.rpc(p, "char.create", string.rep("я", 200), "security", 1)
    expect(#p.SVViolations >= 3, "oversized string accepted")
    eq(#SV.Chars.listFor(p:SteamID64()), 0)
    -- action requiring a character
    MOCK.rpc(p, "tasks.accept", "orientation")
    contains(MOCK.lastNotify(p), "персонажа")
end)

TEST("rate limiting", function()
    local p = MOCK.join({name = "Spam"})
    local before = SV.Perf.counters["net.rpc.ratelimited"] and SV.Perf.counters["net.rpc.ratelimited"].total or 0
    for _ = 1, 10 do MOCK.rpc(p, "char.list") end
    local after = SV.Perf.counters["net.rpc.ratelimited"].total
    expect(after > before, "no rate limiting")
end)

TEST("transaction rollback", function()
    local DB = SV.DB
    DB.query("CREATE TABLE IF NOT EXISTS t_tx (v INTEGER)")
    local ok = DB.transaction(function()
        DB.query("INSERT INTO t_tx (v) VALUES (?)", 1)
        error("boom")
    end)
    expect(not ok)
    eq(tonumber(DB.queryValue("SELECT COUNT(*) FROM t_tx")), 0)
    ok = DB.transaction(function()
        DB.query("INSERT INTO t_tx (v) VALUES (?)", 2)
        DB.transaction(function()
            DB.query("INSERT INTO t_tx (v) VALUES (?)", 3)
            error("inner")
        end)
    end)
    expect(ok)
    eq(tonumber(DB.queryValue("SELECT COUNT(*) FROM t_tx")), 1)
end)

TEST("escaping prevents injection", function()
    local DB = SV.DB
    DB.query("CREATE TABLE IF NOT EXISTS t_esc (v TEXT)")
    DB.query("INSERT INTO t_esc (v) VALUES (?)", "x'); DROP TABLE t_esc; --")
    eq(DB.queryValue("SELECT v FROM t_esc"), "x'); DROP TABLE t_esc; --")
    local ok = pcall(DB.format, "SELECT ?, ?", 1)
    expect(not ok, "missing parameter accepted")
end)

TEST("deterministic RNG", function()
    local a = SV.RNG.new(12345)
    local b = SV.RNG.new(12345)
    for _ = 1, 50 do eq(a:nextU32(), b:nextU32()) end
    local c = SV.RNG.new(54321)
    expect(c:nextU32() ~= SV.RNG.new(12345):nextU32())
    local g = SV.RNG.new(7)
    for _ = 1, 200 do
        local v = g:float()
        expect(v >= 0 and v < 1, "float out of range")
        local i = g:int(3, 5)
        expect(i >= 3 and i <= 5)
    end
    eq(SV.Util.hash("abc"), SV.Util.hash("abc"))
    eq(SV.Util.hash("abc"), 440920331) -- FNV-1a reference value
end)

TEST("automatic map layout exists", function()
    expect(SV.MapCfg.cfg ~= nil)
    eq(SV.MapCfg.source, "auto")
    expect(SV.MapCfg.sectorAt(Vector(0, 0, 0)) ~= nil, "no fallback sector")
    local report = SV.MapCfg.validate(SV.MapCfg.cfg)
    eq(#report.errors, 0, table.concat(report.errors, "; "))
end)

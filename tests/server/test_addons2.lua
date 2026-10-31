--[[---------------------------------------------------------------------------
Second batch of addons: emotes, notes and boards, class-D labor, alarm
lights, flashbang, service record.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Facility = SV.Facility
local MapCfg = SV.MapCfg
local SCP = SV.SCP

local function box(x1, x2)
    return {min = {x1, -1000, -100}, max = {x2, 1000, 500}}
end

local function point(id, kind, x, props)
    return {id = id, kind = kind, pos = {x, 0, 0}, ang = {0, 0, 0}, props = props or {}}
end

local function setupMap()
    for _, p in ipairs(player.GetAll()) do MOCK.disconnect(p) end
    MOCK.hullFn, MOCK.traceHit = nil, false
    MOCK.advance(0.3)
    MapCfg.cfg = {version = 1, map = "gm_test", zones = {
        {id = "lcz", kind = "sector", name = "Лёгкая зона", boxes = {box(0, 2000)}, props = {priority = 2, demand = 30}},
        {id = "hcz", kind = "sector", name = "Тяжёлая зона", boxes = {box(2000, 6000)}, props = {priority = 3, demand = 30}},
        {id = "cell173", kind = "cell", name = "Камера SCP-173", boxes = {box(4000, 4500)}, props = {scp = "scp173"}},
    }, points = {
        point("gen", "node", 100, {subsystem = "generator", sector = "lcz"}),
        point("lcz_pow", "node", 200, {subsystem = "power", sector = "lcz"}),
        point("hcz_pow", "node", 2100, {subsystem = "power", sector = "hcz"}),
        point("board_any", "board", 600, {name = "Общая доска"}),
        point("board_sci", "board", 650, {division = "science"}),
        point("ws_sort", "workstation", 800, {job = "sorting"}),
        point("ws_asm", "workstation", 900, {job = "assembly"}),
        point("alarm_h", "alarm", 3000, {}),
        point("spawn173", "spawn", 4200, {group = "scp173"}),
    }, doors = {}}
    MapCfg.reindex()
    Facility.sectors, Facility.nodes, Facility.sabotageLog = {}, {}, {}
    Facility.build()
    MapCfg.spawnEntities()
    for _, st in pairs(SCP.state) do st.integrity, st.stage, st.breached = 100, "stable", false end
    if Facility.stateId() ~= "normal" then Facility.setState("normal", nil, "test", {force = true}) end
    for sector in pairs(Facility.flags) do Facility.flags[sector] = nil end
    SV.Notes.world = {}
    SV.Labor.active, SV.Labor.done = {}, {}
    SCP.blinded = {}
    MOCK.chat = {}
    return MapCfg.spawned
end

local function staff(division, role, rank, whitelist)
    local r = SV.Roles.get(role)
    local q = r.quota
    r.quota = nil
    local p = makeStaff({steam = role, name = uniqueName("Тест Тестов"), division = division, role = role, rank = rank or 1, whitelist = whitelist})
    r.quota = q
    return p
end

local function chatHas(text)
    for _, m in ipairs(MOCK.chat or {}) do
        if string.find((m.prefix or "") .. " " .. (m.text or ""), text, 1, true) then return true end
    end
    return false
end

TEST("second batch of addons is loaded", function()
    for _, id in ipairs({"emotes", "notes", "labor", "alarms", "flashbang", "servicerecord"}) do
        expect(SV.Addons.isLoaded(id), "addon not loaded: " .. id)
    end
    expect(SV.Config.Items.flashbang and SV.Config.TraceKinds.flash, "flashbang config stage missing")
end)

--[[---------------------------------------------------------------------------
Emotes
---------------------------------------------------------------------------]]
TEST("emotes: gestures for people nearby, blocked when cuffed; handshake needs consent; server dice", function()
    setupMap()
    local a = staff("science", "sci_junior")
    local b = staff("classd", "classd_worker")
    a:SetPos(Vector(100, 0, 0))
    b:SetPos(Vector(150, 0, 0))
    MOCK.clearSent()
    MOCK.rpc(a, "emote.play", "wave")
    local pushes = MOCK.pushes(b, "emote.anim")
    eq(#pushes, 1, "gesture not shown to the person nearby")
    eq(pushes[1].data.act, "ACT_GMOD_GESTURE_WAVE")
    expect(chatHas("машет рукой"), "no narration")
    -- Cooldown.
    MOCK.clearSent()
    MOCK.rpc(a, "emote.play", "salute")
    eq(#MOCK.pushes(b, "emote.anim"), 0, "cooldown ignored")
    -- Cuffed people do not gesture.
    SV.Security.restrain(b, a)
    MOCK.advance(3)
    MOCK.clearSent()
    MOCK.rpc(b, "emote.play", "wave")
    eq(#MOCK.pushes(a, "emote.anim"), 0, "cuffed person gestured")
    SV.Security.unrestrain(b, a, "manual")
    -- Handshake.
    MOCK.rpc(a, "emote.offer", b)
    expect(#MOCK.pushes(b, "emote.offer") == 1, "offer not delivered")
    MOCK.chat = {}
    MOCK.rpc(b, "emote.answer", true)
    expect(chatHas("пожимают руки"), "handshake not narrated")
    MOCK.rpc(b, "emote.answer", true)
    contains(tostring(MOCK.lastNotify(b)), "не действует")
    -- Dice.
    MOCK.chat = {}
    MOCK.say(a, "/roll 6")
    expect(chatHas("бросает кубик d6"), "roll not narrated")
    MOCK.say(a, "/try открыть ящик")
    expect(chatHas("пытается открыть ящик"), "try not narrated")
end)

--[[---------------------------------------------------------------------------
Notes and boards
---------------------------------------------------------------------------]]
TEST("notes: anonymous for players, author for admins, limits, removal; boards per division", function()
    local S = setupMap()
    local a = staff("classd", "classd_worker")
    a:SetPos(Vector(300, 0, 0))
    MOCK.rpc(a, "notes.write", "Не входить", "В ящике у шлюза спрятан ключ")
    local note = next(SV.Notes.world)
    expect(IsValid(note), "note not created")
    eq(note:GetNoteTitle(), "Не входить")
    local reader = staff("science", "sci_junior")
    reader:SetPos(note:GetPos())
    MOCK.clearSent()
    MOCK.rpc(reader, "notes.read", note)
    local msg = MOCK.pushes(reader, "notes.text")[1]
    expect(msg, "note not readable")
    contains(msg.data.text, "спрятан ключ")
    expect(msg.data.author == nil, "author shown to a player")
    expect(not msg.data.canTake, "a scientist may take the note")
    local admin = makeStaff({steam = "NoteAdmin", name = uniqueName("Админ Админов"), division = "classd", role = "classd_worker", admin = true})
    SV.Admin.setDuty(admin, true)
    admin:SetPos(note:GetPos())
    MOCK.clearSent()
    MOCK.rpc(admin, "notes.read", note)
    contains(MOCK.pushes(admin, "notes.text")[1].data.author or "", a.SVChar.name)
    -- Limit per character.
    for i = 1, 3 do
        MOCK.advance(31, 5)
        MOCK.rpc(a, "notes.write", "N" .. i, "Текст записки " .. i)
    end
    local mine = 0
    for _, r in pairs(SV.Notes.world) do if r.char == a.SVChar.id then mine = mine + 1 end end
    eq(mine, SV.Config.Notes.perCharacter, "note limit not enforced")
    -- A guard confiscates.
    local g = staff("security", "sec_guard")
    g:SetPos(note:GetPos())
    MOCK.rpc(g, "notes.take", note)
    expect(not IsValid(note), "guard could not take the note")
    -- Expiry.
    MOCK.advance(SV.Config.Notes.lifetime + 40, 10)
    eq(SV.Util.count(SV.Notes.world), 0, "notes did not expire")

    -- Boards.
    local board, sciBoard = S.board_any, S.board_sci
    a:SetPos(board:GetPos())
    MOCK.rpc(a, "board.post", board, "Ищу напарника для уборки")
    eq(#SV.Notes.boards[board].posts, 1, "post not added")
    MOCK.advance(25, 5)
    MOCK.rpc(a, "board.post", board, "Второе объявление")
    MOCK.advance(25, 5)
    MOCK.rpc(a, "board.post", board, "Третье объявление")
    eq(#SV.Notes.boards[board].posts, SV.Config.Notes.boardPostsPerCharacter, "post limit not enforced")
    a:SetPos(sciBoard:GetPos())
    MOCK.advance(25, 5)
    MOCK.rpc(a, "board.post", sciBoard, "Чужая доска")
    eq(#SV.Notes.boards[sciBoard].posts, 0, "posted on another division's board")
    reader:SetPos(board:GetPos())
    local id = SV.Notes.boards[board].posts[1].id
    MOCK.rpc(reader, "board.remove", board, id)
    eq(#SV.Notes.boards[board].posts, 2, "a stranger removed a post")
    MOCK.rpc(a, "board.remove", board, id)
end)

--[[---------------------------------------------------------------------------
Labor
---------------------------------------------------------------------------]]
TEST("labor: server-checked mini-games, anti-script timing, division, busy station, rewards", function()
    local S = setupMap()
    local d = staff("classd", "classd_worker")
    local station = S.ws_sort
    d:SetPos(station:GetPos())
    local sci = staff("science", "sci_junior")
    sci:SetPos(station:GetPos())
    MOCK.clearSent()
    MOCK.rpc(sci, "labor.start", station)
    expect(not SV.Labor.active[sci], "a scientist got a class-D job")
    MOCK.rpc(d, "labor.start", station)
    local c = SV.Labor.active[d]
    expect(c, "job not started: " .. tostring(MOCK.lastNotify(d)))
    expect(#MOCK.pushes(d, "labor.challenge") == 1, "challenge not sent")
    -- Station busy for others.
    local d2 = staff("classd", "classd_worker")
    d2:SetPos(station:GetPos())
    expect(SV.Labor.blockedReason(d2, station), "busy station accepted a second worker")
    -- Instant answer: rejected as a script.
    MOCK.rpc(d, "labor.answer", c.id, c.solution)
    contains(tostring(MOCK.lastNotify(d)), "слишком быстро")
    MOCK.advance(SV.Config.Labor.failCooldown + 1, 1)
    -- Correct answer after a human delay: rewarded.
    local budget = SV.Supply.budget("administration")
    MOCK.rpc(d, "labor.start", station)
    c = SV.Labor.active[d]
    MOCK.advance(3, 0.5)
    MOCK.rpc(d, "labor.answer", c.id, c.solution)
    contains(tostring(MOCK.lastNotify(d)), "работа принята")
    expect(SV.Supply.budget("administration") > budget, "no budget reward")
    -- Wrong answer.
    MOCK.advance(SV.Config.Labor.cooldown + 1, 1)
    MOCK.rpc(d, "labor.start", station)
    c = SV.Labor.active[d]
    MOCK.advance(3, 0.5)
    local wrong = {}
    for i, v in ipairs(c.solution) do wrong[i] = v % #SV.Config.Labor.jobs.sorting.symbols + 1 end
    MOCK.rpc(d, "labor.answer", c.id, wrong)
    contains(tostring(MOCK.lastNotify(d)), "ошибка")
    -- Assembly adds engineering stock.
    local asm = S.ws_asm
    d2:SetPos(asm:GetPos())
    local stock = SV.Supply.stock("engineering", "spare_parts")
    MOCK.rpc(d2, "labor.start", asm)
    c = SV.Labor.active[d2]
    MOCK.advance(3, 0.5)
    MOCK.rpc(d2, "labor.answer", c.id, c.solution)
    eq(SV.Supply.stock("engineering", "spare_parts"), stock + 1, "assembly did not add stock")
end)

--[[---------------------------------------------------------------------------
Alarm lights
---------------------------------------------------------------------------]]
TEST("alarms: lamp mode follows alert, lockdown, breach, decontamination and power", function()
    local S = setupMap()
    local lamp = S.alarm_h
    expect(IsValid(lamp) and SV.Alarms.lamps[lamp], "lamp not registered")
    MOCK.advance(1.5)
    eq(lamp:GetMode(), "")
    Facility.setAlert("hcz", nil, true, "test")
    MOCK.advance(1.5)
    eq(lamp:GetMode(), "alert")
    Facility.setLockdown("hcz", nil, true, "test")
    MOCK.advance(1.5)
    eq(lamp:GetMode(), "lockdown")
    Facility.setState("breach", nil, "test", {force = true})
    MOCK.advance(1.5)
    eq(lamp:GetMode(), "breach")
    if SV.Decon then
        SV.Decon.active = {sector = "hcz", phase = "gas", at = CurTime() + 60}
        MOCK.advance(1.5)
        eq(lamp:GetMode(), "decon")
        SV.Decon.active = nil
    end
    Facility.nodes.hcz_pow.health = 0
    Facility.recompute()
    MOCK.advance(1.5)
    eq(lamp:GetMode(), "", "unpowered lamp lit")
end)

--[[---------------------------------------------------------------------------
Flashbang
---------------------------------------------------------------------------]]
TEST("flashbang: thrown from the inventory, blinds people in sight, frees SCP-173, leaves a trace", function()
    setupMap()
    local g = staff("security", "sec_guard")
    g:SetPos(Vector(4000, 0, 0))
    SV.Inv.add(g, "flashbang", 2, {force = true})
    local item = SV.Inv.find(g, function(it) return it.id == "flashbang" end)[1]
    local ok, why = SV.Inv.equip(g, item)
    expect(ok, "not equipped: " .. tostring(why))
    -- SCP-173 held by an observer.
    local p = MOCK.join({name = "SCP_173"})
    SV.Chars.grantWhitelist(p:SteamID64(), "role", "scp173", nil, "test")
    local role = SV.Roles.get("scp173")
    local q = role.quota
    role.quota = nil
    MOCK.rpc(p, "char.selectSCP", "scp173")
    role.quota = q
    MOCK.advance(0.3)
    local obs = staff("security", "sec_guard")
    obs:SetPos(Vector(4100, 0, 0))
    obs:SetEyeAngles(((p:GetPos() + Vector(0, 0, 36)) - obs:EyePos()):Angle())
    SV.SCP.S173.forceBlink(obs, 0)
    MOCK.advance(0.3)
    expect(SV.Move.has(p, "173"), "SCP-173 not held before the flash")
    g:SetEyeAngles((obs:EyePos() - g:EyePos()):Angle())
    expect(SV.Flash.throw(g), "throw refused")
    eq(SV.Inv.count(g, "flashbang"), 1, "grenade not spent")
    MOCK.advance(SV.Config.Flashbang.fuse + 0.2, 0.1)
    expect(SV.SCP.isBlinded(obs), "observer not blinded")
    expect(not SV.SCP.isBlinded(p), "SCP-173 blinded")
    local trace = false
    for _, t in pairs(SV.Evidence.traces) do if t.kind == "flash" then trace = true end end
    expect(trace, "no flash trace")
    SV.SCP.S173.forceBlink(obs, 0)
    MOCK.advance(0.5)
    expect(not SV.Move.has(p, "173"), "blinded observer still holds SCP-173")
    MOCK.advance(SV.Config.Flashbang.blindMax + 0.5, 0.5)
    expect(not SV.SCP.isBlinded(obs), "blindness did not end")
end)

--[[---------------------------------------------------------------------------
Service record
---------------------------------------------------------------------------]]
TEST("service record: superiors only, reason and limits, reprimands block promotion, revocation", function()
    setupMap()
    local chief = staff("security", "sec_chief", 5, true)
    local guard = staff("security", "sec_guard", 1)
    guard:SetPos(chief:GetPos())
    MOCK.rpc(guard, "srec.issue", chief, "reprimand", "Неуважение к начальству при исполнении")
    eq(SV.ServiceRecord.activeReprimands(chief.SVChar.id), 0, "a subordinate reprimanded the chief")
    MOCK.rpc(chief, "srec.issue", guard, "commendation", "коротко")
    eq(tonumber(SV.DB.queryValue("SELECT COUNT(*) FROM sv_service_records")), 0, "record without a proper reason")
    local xp = guard.SVChar.xp
    MOCK.rpc(chief, "srec.issue", guard, "commendation", "Образцовое несение службы на посту")
    expect(guard.SVChar.xp > xp, "commendation gave no experience")
    MOCK.advance(12, 2)
    MOCK.rpc(chief, "srec.issue", guard, "commendation", "Повторная благодарность в ту же смену")
    eq(tonumber(SV.DB.queryValue("SELECT COUNT(*) FROM sv_service_records WHERE kind = 'commendation'")), 1, "duplicate in one shift")
    -- Two reprimands from two superiors block promotion.
    MOCK.advance(12, 2)
    MOCK.rpc(chief, "srec.issue", guard, "reprimand", "Сон на посту во время тревоги")
    local ia = staff("administration", "adm_ia", 2, true)
    ia:SetPos(guard:GetPos())
    MOCK.rpc(ia, "srec.issue", guard, "commendation", "Внутренняя безопасность хвалит охрану")
    eq(tonumber(SV.DB.queryValue("SELECT COUNT(*) FROM sv_service_records WHERE kind = 'commendation'")), 1, "IA issued a commendation")
    MOCK.rpc(ia, "srec.issue", guard, "reprimand", "Нарушение порядка доступа к оружейной")
    eq(SV.ServiceRecord.activeReprimands(guard.SVChar.id), 2)
    local status = SV.Chars.promotionStatus(guard.SVChar)
    local blocked = false
    for _, c in ipairs(status.conditions) do
        if string.find(c.text, "взысканий", 1, true) and not c.met then blocked = true end
    end
    expect(blocked and not status.possible, "reprimands do not block promotion")
    -- Revocation by the issuer.
    local id = tonumber(SV.DB.queryValue("SELECT id FROM sv_service_records WHERE kind = 'reprimand' AND by_name = ?", SV.Chars.displayName(chief)))
    MOCK.advance(5)
    MOCK.rpc(guard, "srec.revoke", id, "Прошу отменить своё взыскание")
    eq(SV.ServiceRecord.activeReprimands(guard.SVChar.id), 2, "the target revoked a reprimand")
    MOCK.rpc(chief, "srec.revoke", id, "Обстоятельства выяснены, взыскание снято")
    eq(SV.ServiceRecord.activeReprimands(guard.SVChar.id), 1)
    -- The file is visible to the person and superiors, not to strangers.
    local d = staff("classd", "classd_worker")
    MOCK.clearSent()
    MOCK.rpc(d, "srec.view", guard)
    eq(#MOCK.pushes(d, "srec.view"), 0, "a stranger opened the file")
    MOCK.rpc(guard, "srec.view", guard)
    expect(#MOCK.pushes(guard, "srec.view") == 1, "own file not visible")
end)

TEST("labor registers a director event solved by finishing jobs", function()
    local S = setupMap()
    expect(SV.Director.defs.labor_rush, "event not registered")
    for _, run in pairs(SV.Director.active) do SV.Director.finish(run, "withdrawn") end
    for i = 1, 4 do MOCK.join({name = "Filler" .. i}) end
    local d = staff("classd", "classd_worker")
    d:SetPos(S.ws_sort:GetPos())
    SV.Director.lastStart = {}
    local ok, why = SV.Director.start("labor_rush", true)
    expect(ok, "not started: " .. tostring(why))
    local run
    for _, r in pairs(SV.Director.active) do if r.def.id == "labor_rush" then run = r end end
    for _ = 1, 3 do
        MOCK.rpc(d, "labor.start", S.ws_sort)
        local c = SV.Labor.active[d]
        MOCK.advance(3, 0.5)
        MOCK.rpc(d, "labor.answer", c.id, c.solution)
        MOCK.advance(SV.Config.Labor.cooldown + 1, 1)
    end
    expect(not SV.Director.active[run.id], "event not solved")
    eq(SV.DB.queryValue("SELECT outcome FROM sv_director_log WHERE id = ?", run.logId), "success")
end)

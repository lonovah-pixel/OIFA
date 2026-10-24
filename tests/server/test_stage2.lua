--[[---------------------------------------------------------------------------
Stage 2: inventory, access, communication, supply.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Inv = SV.Inv

local function itemsOf(ply, id)
    return Inv.find(ply, function(it) return it.id == id end)
end

local function dbCount(where, ...)
    return tonumber(SV.DB.queryValue("SELECT COUNT(*) FROM sv_items WHERE " .. where, ...))
end

-- Inventory -------------------------------------------------------------------
TEST("kit issued once; respawn does not duplicate durable items", function()
    local p = makeStaff({steam = "Guard", name = "Олег Охранов", division = "security"})
    eq(#itemsOf(p, "pistol"), 1)
    eq(#itemsOf(p, "id_card"), 1)
    eq(Inv.count(p, "ammo_pistol"), 2)
    for _ = 1, 5 do
        p:Kill()
        MOCK.advance(1)
        p:Spawn()
    end
    eq(#itemsOf(p, "pistol"), 1, "pistol duplicated by respawns")
    eq(#itemsOf(p, "id_card"), 1)
    eq(dbCount("issued_to = ? AND item_id = 'pistol'", p.SVChar.id), 1)
end)

TEST("consumable kit refills are limited per shift", function()
    local p = makeStaff({steam = "Medic", name = "Вера Бинтова", division = "medical"})
    local refills = SV.Config.Inventory.kitRefillsPerShift
    for i = 1, refills + 3 do
        Inv.take(p, "bandage", 4)
        p:Kill()
        p:Spawn()
        if i <= refills then eq(Inv.count(p, "bandage"), 4, "refill " .. i) end
    end
    eq(Inv.count(p, "bandage"), 0, "refills beyond the limit")
end)

TEST("drop and double pickup in the same tick", function()
    local p = makeStaff({steam = "Dropper", name = "Пётр Ронялов", division = "engineering"})
    local q = makeStaff({steam = "Picker", name = "Роман Подбиралов", division = "engineering"})
    Inv.add(p, "flashlight", 1)
    local item = itemsOf(p, "flashlight")[1]
    local ok = Inv.drop(p, item.uid, 1)
    expect(ok, "drop failed")
    local ent
    for e in pairs(Inv.world) do ent = e end
    expect(ent, "no world entity")
    p:SetPos(ent:GetPos()) q:SetPos(ent:GetPos())
    local a = Inv.pickup(p, ent)
    local b = Inv.pickup(q, ent)
    expect(a ~= b, "both or none picked up")
    eq(#itemsOf(p, "flashlight") + #itemsOf(q, "flashlight"), 1)
    eq(dbCount("item_id = 'flashlight'"), 1)
end)

TEST("noDrop items cannot be dropped or offered", function()
    local p = makeStaff({steam = "NoDrop", name = "Карина Картова", division = "science"})
    local card = itemsOf(p, "id_card")[1]
    local ok = Inv.drop(p, card.uid, 1)
    expect(not ok)
    local q = makeStaff({steam = "Other", name = "Иван Чужов", division = "science"})
    ok = Inv.offer(p, q, card.uid, 1)
    expect(not ok)
end)

TEST("concurrent handover: offered item locked against drop/second offer", function()
    local a = makeStaff({steam = "Giver", name = "Дмитрий Даров", division = "engineering"})
    local b = makeStaff({steam = "Taker", name = "Борис Берёшин", division = "engineering"})
    local c = makeStaff({steam = "Third", name = "Сергей Третьяков", division = "engineering"})
    a:SetPos(Vector(0, 0, 0)) b:SetPos(Vector(50, 0, 0)) c:SetPos(Vector(0, 50, 0))
    Inv.add(a, "crowbar", 1)
    local item = itemsOf(a, "crowbar")[1]
    expect(Inv.offer(a, b, item.uid, 1))
    local ok = Inv.offer(a, c, item.uid, 1)
    expect(not ok, "second offer of the same item accepted")
    ok = Inv.drop(a, item.uid, 1)
    expect(not ok, "drop of offered item accepted")
    local offerId
    for id in pairs(Inv.offers) do offerId = id end
    expect(Inv.answer(b, offerId, true))
    eq(#itemsOf(a, "crowbar"), 0)
    eq(#itemsOf(b, "crowbar"), 1)
    ok = Inv.answer(b, offerId, true)
    expect(not ok, "offer accepted twice")
    eq(#itemsOf(b, "crowbar"), 1)
    eq(dbCount("item_id = 'crowbar'"), 1)
end)

TEST("offer cancelled when the giver disconnects", function()
    local a = makeStaff({steam = "Leaver", name = "Лев Уходов", division = "engineering"})
    local b = makeStaff({steam = "Stayer", name = "Степан Остаётся", division = "engineering"})
    a:SetPos(Vector(0, 0, 0)) b:SetPos(Vector(50, 0, 0))
    Inv.add(a, "spare_parts", 1, {data = {tag = "x"}})
    local item = itemsOf(a, "spare_parts")[2] or itemsOf(a, "spare_parts")[1]
    expect(Inv.offer(a, b, item.uid, 1))
    local offerId
    for id in pairs(Inv.offers) do offerId = id end
    MOCK.disconnect(a)
    local ok = Inv.answer(b, offerId, true)
    expect(not ok, "accepted after giver left")
    eq(tonumber(SV.DB.queryValue("SELECT char_id FROM sv_items WHERE uid = ?", item.uid)) ~= b.SVChar.id, true)
end)

TEST("death drops non-kit items into a bag, kit stays", function()
    local p = makeStaff({steam = "Victim", name = "Виктор Жертвов", division = "security"})
    Inv.add(p, "medkit", 1)
    Inv.add(p, "contraband", 2)
    p:Kill()
    eq(#itemsOf(p, "medkit"), 0)
    eq(#itemsOf(p, "contraband"), 0)
    eq(#itemsOf(p, "pistol"), 1, "kit pistol dropped")
    local bag
    for e, entry in pairs(Inv.world) do if entry.bag then bag = e end end
    expect(bag, "no bag")
    eq(#Inv.world[bag].items, 2)
    local q = makeStaff({steam = "Looter", name = "Лука Мародёров", division = "security"})
    q:SetPos(bag:GetPos())
    MOCK.rpc(q, "inv.bagTake", bag, Inv.world[bag].items[1].uid)
    eq(#Inv.world[bag].items, 1)
end)

TEST("inventory persists across reconnect; capacity enforced", function()
    local p = makeStaff({steam = "Hoarder", name = "Хома Запасов", division = "engineering"})
    local sid, id = p:SteamID64(), p.SVChar.id
    Inv.add(p, "fuel", 2)
    MOCK.disconnect(p)
    local p2 = MOCK.join({name = "Hoarder", steamid = sid})
    MOCK.rpc(p2, "char.select", id)
    eq(Inv.count(p2, "fuel"), 2)
    local ok, reason = Inv.add(p2, "fuel", 30)
    expect(not ok, "overweight accepted")
    contains(reason, "тяжело")
end)

TEST("weapons only come from the inventory", function()
    local p = makeStaff({steam = "Gunner", name = "Глеб Стрелков", division = "security"})
    local wep = MOCK.newEntity("weapon_ar2")
    eq(GM:PlayerCanPickupWeapon(p, wep), false)
    local pistol = itemsOf(p, "pistol")[1]
    expect(Inv.equip(p, pistol))
    expect(p:HasWeapon("weapon_pistol"))
    expect(Inv.holster(p, pistol))
    expect(not p:HasWeapon("weapon_pistol"))
end)

-- Access ---------------------------------------------------------------------
local function makeDoor(id, cfg)
    local door = MOCK.newEntity("func_door")
    door.mapId = id
    door:SetPos(Vector(1000 + id, 0, 0))
    SV.MapCfg.cfg.doors[tostring(id)] = cfg
    return door
end

TEST("door access by clearance and tags, logged", function()
    local door = makeDoor(501, {name = "Оружейная", clearance = 2, tags = {"armory"}})
    local guard = makeStaff({steam = "DoorGuard", name = "Глеб Дверев", division = "security"})
    local officer = makeStaff({steam = "DoorOfficer", name = "Олег Офицеров", division = "security", rank = 3, role = "sec_officer"})
    guard:SetPos(door:GetPos()) officer:SetPos(door:GetPos())
    eq(hook.Run("PlayerUse", guard, door), false)
    contains(MOCK.lastNotify(guard), "доступ запрещён")
    expect(not SV.Access.openDoors[door])
    MOCK.advance(1)
    eq(hook.Run("PlayerUse", officer, door), false)
    expect(SV.Access.openDoors[door], "officer could not open")
    local log = SV.Access.gameLog(SV.Access.doorKey(door))
    eq(#log, 2)
    eq(log[1].ok, true)
    MOCK.advance(8)
    expect(not SV.Access.openDoors[door], "door did not close")
end)

TEST("card revocation and role change invalidate the old serial", function()
    local door = makeDoor(502, {name = "Пост", clearance = 1, tags = {"security"}})
    local g = makeStaff({steam = "Revoked", name = "Роман Отозванов", division = "security"})
    g:SetPos(door:GetPos())
    local card = itemsOf(g, "id_card")[1]
    local serial = card.data.serial
    expect(SV.Access.check(g, {clearance = 1, tags = {"security"}}))
    expect(SV.Access.revokeCard(serial, nil, "тест"))
    local ok = SV.Access.check(g, {clearance = 1, tags = {"security"}})
    expect(not ok, "revoked card still works")
    -- respawn re-syncs the card with a new serial
    g:Kill() g:Spawn()
    MOCK.advance(0.2)
    card = itemsOf(g, "id_card")[1]
    expect(card.data.serial ~= serial, "serial not reissued")
    expect(SV.Access.check(g, {clearance = 1, tags = {"security"}}))
end)

TEST("stolen card works for the thief until revoked", function()
    local victim = makeStaff({steam = "Robbed", name = "Анна Обокрадова", division = "science", rank = 3, role = "sci_researcher"})
    local thief = makeStaff({steam = "Thief", name = "Тимур Воров", division = "classd"})
    local card = itemsOf(victim, "id_card")[1]
    expect(Inv.transfer(victim, thief, card.uid, 1, {force = true, reason = "test confiscation"}))
    SV.Access.invalidate(thief)
    local ok = SV.Access.check(thief, {clearance = 2, tags = {"labs"}})
    expect(ok, "stolen card rejected")
    SV.Access.revokeCard(card.data.serial, nil, "кража")
    ok = SV.Access.check(thief, {clearance = 2, tags = {"labs"}})
    expect(not ok)
    -- the victim does not get a new card while the old one exists
    victim:Kill() victim:Spawn()
    eq(#itemsOf(victim, "id_card"), 0)
end)

TEST("temporary pass: limits and expiry", function()
    local officer = makeStaff({steam = "Issuer", name = "Игорь Выдаев", division = "security", rank = 3, role = "sec_officer"})
    local d = makeStaff({steam = "Visitor", name = "Виктор Гостев", division = "classd"})
    officer:SetPos(Vector(0, 0, 0)) d:SetPos(Vector(40, 0, 0))
    MOCK.rpc(officer, "access.issuePass", d, 3, "", 10)
    eq(Inv.count(d, "temp_pass"), 0, "clearance above issuer accepted")
    MOCK.advance(11)
    MOCK.rpc(officer, "access.issuePass", d, 1, "science", 10)
    eq(Inv.count(d, "temp_pass"), 0, "foreign tag accepted")
    MOCK.advance(11)
    MOCK.rpc(officer, "access.issuePass", d, 1, "security", 1)
    eq(Inv.count(d, "temp_pass"), 1)
    SV.Access.invalidate(d)
    expect(SV.Access.check(d, {clearance = 1, tags = {"security"}}))
    local pass = itemsOf(d, "temp_pass")[1]
    SV.DB.query("UPDATE sv_cards SET expires_at = ? WHERE serial = ?", os.time() - 1, pass.data.serial)
    SV.Access.cards = {}
    SV.Access.invalidate(d)
    expect(not SV.Access.check(d, {clearance = 1, tags = {"security"}}), "expired pass works")
end)

TEST("emergency open requires authority and has a cooldown", function()
    local door = makeDoor(503, {name = "Шлюз", clearance = 5})
    local guard = makeStaff({steam = "NoAuth", name = "Никита Безправов", division = "security"})
    guard:SetPos(door:GetPos())
    local before = #(guard.SVViolations or {})
    MOCK.rpc(guard, "access.emergency", door)
    expect(#guard.SVViolations > before, "unauthorised emergency not flagged")
    expect(not SV.Access.openDoors[door])
    local officer = makeStaff({steam = "Auth", name = "Аркадий Аварийный", division = "security", rank = 3, role = "sec_officer"})
    officer:SetPos(door:GetPos())
    MOCK.rpc(officer, "access.emergency", door)
    expect(SV.Access.openDoors[door], "emergency open failed")
    MOCK.advance(12)
    MOCK.rpc(officer, "access.emergency", door)
    contains(MOCK.lastNotify(officer), "Повторное")
end)

TEST("SCP and lobby players cannot use controlled doors", function()
    local door = makeDoor(504, {name = "Камера", clearance = 0})
    local p = MOCK.join({name = "LobbyDoor"})
    eq(hook.Run("PlayerUse", p, door), false)
end)

-- Communication ------------------------------------------------------------------
TEST("local chat range and radio requirements", function()
    MOCK.chat = {}
    local a = makeStaff({steam = "Talker", name = "Тарас Говорунов", division = "security"})
    local near = makeStaff({steam = "Near", name = "Нина Ближняя", division = "security"})
    local far = makeStaff({steam = "Far", name = "Фёдор Дальний", division = "security"})
    local d = makeStaff({steam = "NoRadio", name = "Денис Безрации", division = "classd"})
    a:SetPos(Vector(0, 0, 0)) near:SetPos(Vector(100, 0, 0)) far:SetPos(Vector(5000, 0, 0)) d:SetPos(Vector(9000, 0, 0))
    MOCK.say(a, "Всем стоять")
    local got = {}
    for _, m in ipairs(MOCK.chat) do if m.to then got[m.to] = true end end
    expect(got[near] and not got[far], "local chat range wrong")
    MOCK.chat = {}
    MOCK.say(a, "/r Пост чист")
    got = {}
    for _, m in ipairs(MOCK.chat) do if m.to then got[m.to] = m end end
    expect(got[far], "radio not received far away")
    expect(not got[d], "player without radio received radio")
end)

TEST("radio garbling follows comms health and is deterministic", function()
    eq(SV.Comms.garble("один два три", 1, "s"), "один два три")
    eq(SV.Comms.garble("один два три", 0.1, "s"), "*помехи*")
    local g1 = SV.Comms.garble("раз два три четыре пять шесть", 0.4, "seed")
    local g2 = SV.Comms.garble("раз два три четыре пять шесть", 0.4, "seed")
    eq(g1, g2)
    expect(string.find(g1, "…", 1, true), "nothing garbled at 0.4")
end)

TEST("chat rate limit", function()
    MOCK.chat = {}
    local a = makeStaff({steam = "Spammer", name = "Семён Спамов", division = "classd"})
    for i = 1, 10 do MOCK.say(a, "сообщение " .. i) end
    local n = 0
    for _, m in ipairs(MOCK.chat) do if m.to == a then n = n + 1 end end
    expect(n <= SV.Config.Chat.icRate.burst + 1, "rate limit not applied (" .. n .. ")")
end)

TEST("voice: local proximity and radio push-to-talk", function()
    local a = makeStaff({steam = "VoiceA", name = "Антон Голосов", division = "security"})
    local b = makeStaff({steam = "VoiceB", name = "Богдан Слухов", division = "security"})
    a:SetPos(Vector(0, 0, 0)) b:SetPos(Vector(3000, 0, 0))
    SV.Comms.rebuildVoice()
    eq(GM:PlayerCanHearPlayersVoice(b, a), false)
    MOCK.rpc(a, "comms.ptt", true)
    eq(GM:PlayerCanHearPlayersVoice(b, a), true)
    MOCK.rpc(a, "comms.ptt", false)
    b:SetPos(Vector(100, 0, 0))
    SV.Comms.rebuildVoice()
    eq(GM:PlayerCanHearPlayersVoice(b, a), true)
end)

TEST("admin ticket without admins online is kept", function()
    local p = makeStaff({steam = "Asker", name = "Алла Спрашивает", division = "classd"})
    MOCK.say(p, "@ меня застряло в стене")
    contains(MOCK.lastNotify(p), "сохранено")
end)

-- Supply ---------------------------------------------------------------------------
TEST("supply request: server prices, own approval forbidden, budget deducted, delivery", function()
    local Supply = SV.Supply
    local eng = makeStaff({steam = "EngReq", name = "Евгений Заявкин", division = "engineering", rank = 2})
    local chief = makeStaff({steam = "EngChief", name = "Георгий Главный", division = "engineering", rank = 4, whitelist = true})
    SV.Chars.grantWhitelist(chief:SteamID64(), "role", "eng_chief", nil, "test")
    expect(SV.Chars.assignRole(chief, SV.Roles.get("eng_chief"), {reason = "test"}))
    local budget0 = Supply.budget("engineering")
    -- forged: unknown item, other division item, huge count
    local ok = Supply.createRequest(eng, {rifle = 1}, "нужно оружие")
    expect(not ok, "non-orderable item accepted")
    ok = Supply.createRequest(eng, {pistol = 1}, "охрана не даёт")
    expect(not ok, "foreign division item accepted")
    ok = Supply.createRequest(eng, {spare_parts = 999}, "много")
    expect(not ok, "huge count accepted")
    ok = Supply.createRequest(eng, {spare_parts = 3, fuel = 1}, "ремонт генератора")
    expect(ok, "valid request refused")
    local req = SV.DB.queryRow("SELECT * FROM sv_supply_requests ORDER BY id DESC LIMIT 1")
    eq(tonumber(req.cost), 3 * 8 + 12, "cost not from catalogue")
    local own = Supply.createRequest(chief, {filter = 1}, "фильтры для вентиляции")
    expect(own)
    local ownId = tonumber(SV.DB.queryValue("SELECT id FROM sv_supply_requests ORDER BY id DESC LIMIT 1"))
    ok = Supply.decide(chief, ownId, true, "")
    expect(not ok, "own request approved")
    local stock0 = Supply.stock("engineering", "spare_parts")
    ok = Supply.decide(chief, tonumber(req.id), true, "согласовано")
    expect(ok, "approval failed")
    eq(Supply.budget("engineering"), budget0 - 36)
    ok = Supply.decide(chief, tonumber(req.id), true, "")
    expect(not ok, "approved twice")
    MOCK.advance(SV.Config.Supply.deliveryDelay + 3, 1)
    eq(Supply.stock("engineering", "spare_parts"), stock0 + 3, "delivery not booked")
end)

TEST("insufficient budget blocks approval atomically", function()
    local Supply = SV.Supply
    local med = makeStaff({steam = "MedReq", name = "Мира Заявкина", division = "medical", rank = 2})
    local adm = makeStaff({steam = "Clerk", name = "Клара Канцелярова", division = "administration", whitelist = true})
    Supply.adjustBudget("medical", -Supply.budget("medical"), "test")
    expect(Supply.createRequest(med, {stimulant = 2}, "запас адреналина"))
    local id = tonumber(SV.DB.queryValue("SELECT id FROM sv_supply_requests ORDER BY id DESC LIMIT 1"))
    local ok = Supply.decide(adm, id, true, "")
    expect(not ok)
    eq(SV.DB.queryValue("SELECT status FROM sv_supply_requests WHERE id = ?", id), "pending")
    eq(Supply.budget("medical"), 0)
end)

TEST("locker quotas and stock", function()
    local locker = ents.Create("sv_locker")
    locker:SetLockerKind("medical")
    locker:SetPos(Vector(0, 0, 0))
    local m = makeStaff({steam = "Locker", name = "Лидия Шкафова", division = "medical"})
    m:SetPos(Vector(10, 0, 0))
    local quota = SV.Config.Lockers.medical.items.stimulant
    for _ = 1, quota + 2 do MOCK.rpc(m, "supply.lockerTake", locker, "stimulant") MOCK.advance(1) end
    eq(Inv.count(m, "stimulant"), quota, "quota not enforced")
end)

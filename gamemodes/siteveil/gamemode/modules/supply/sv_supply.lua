--[[---------------------------------------------------------------------------
Supply (server): division budgets, stock, supply requests, deliveries and
equipment lockers.

Budgets replace personal money (DarkRP wallets stay at 0). Every budget
change is a ledger entry; ledgers are visible to the division and to the
administration (audits). Prices come only from the item catalogue.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Supply = SV.Supply
local DB = SV.DB
local Net = SV.Net
local U = SV.Util
local C = SV.Config
local Roles = SV.Roles
local Inv = SV.Inv

Supply.deliveries = Supply.deliveries or {}  -- request id -> deliver time
Supply.crates = Supply.crates or {}          -- ent -> request id
Supply.delayMultiplier = Supply.delayMultiplier or 1
Supply.blocked = Supply.blocked or false     -- logistics disruption

DB.registerMigrations("supply", {
    {1, "budgets, stock, requests", function()
        DB.query("CREATE TABLE IF NOT EXISTS sv_budgets (division TEXT PRIMARY KEY, balance INTEGER NOT NULL)")
        DB.query([[CREATE TABLE IF NOT EXISTS sv_budget_ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT, division TEXT NOT NULL, delta INTEGER NOT NULL,
            balance INTEGER NOT NULL, reason TEXT NOT NULL, actor_char INTEGER, actor_name TEXT, time INTEGER NOT NULL)]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_ledger_div ON sv_budget_ledger (division, id)")
        DB.query([[CREATE TABLE IF NOT EXISTS sv_stock (division TEXT NOT NULL, item_id TEXT NOT NULL, count INTEGER NOT NULL,
            PRIMARY KEY (division, item_id))]])
        DB.query([[CREATE TABLE IF NOT EXISTS sv_supply_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT, division TEXT NOT NULL, requester_char INTEGER NOT NULL,
            requester_name TEXT NOT NULL, lines TEXT NOT NULL, cost INTEGER NOT NULL, reason TEXT NOT NULL,
            status TEXT NOT NULL, decided_char INTEGER, decided_name TEXT, note TEXT,
            created_at INTEGER NOT NULL, decided_at INTEGER, delivered_at INTEGER)]])
        DB.query("CREATE INDEX IF NOT EXISTS sv_requests_status ON sv_supply_requests (status, division)")
        DB.query([[CREATE TABLE IF NOT EXISTS sv_locker_usage (char_id INTEGER NOT NULL, shift INTEGER NOT NULL,
            locker TEXT NOT NULL, item_id TEXT NOT NULL, count INTEGER NOT NULL,
            PRIMARY KEY (char_id, shift, locker, item_id))]])
    end},
})

--[[---------------------------------------------------------------------------
Budgets
---------------------------------------------------------------------------]]
function Supply.budget(div)
    return tonumber(DB.queryValue("SELECT balance FROM sv_budgets WHERE division = ?", div)) or 0
end

local function publishBudgets()
    for _, d in ipairs(Roles.divisions) do
        SV.Sync.set("budgets", d.id, Supply.budget(d.id))
    end
end
Supply.publishBudgets = publishBudgets

--- Changes a budget. Fails (without change) if the result would be negative
--- unless allowNegative. Returns ok, newBalance.
function Supply.adjustBudget(div, delta, reason, actor, allowNegative)
    delta = math.floor(delta)
    if delta == 0 then return true, Supply.budget(div) end
    local ok, result = DB.transaction(function()
        local bal = Supply.budget(div)
        local new = bal + delta
        if new < 0 and not allowNegative then error("insufficient", 0) end
        new = math.Clamp(new, 0, C.Supply.maxBudget)
        DB.query("INSERT OR REPLACE INTO sv_budgets (division, balance) VALUES (?, ?)", div, new)
        DB.query("INSERT INTO sv_budget_ledger (division, delta, balance, reason, actor_char, actor_name, time) VALUES (?, ?, ?, ?, ?, ?, ?)",
            div, new - bal, new, reason or "", IsValid(actor) and actor.SVChar and actor.SVChar.id or nil,
            IsValid(actor) and actor.SVChar and actor.SVChar.name or "Система", os.time())
        return new
    end)
    if not ok then return false, Supply.budget(div) end
    SV.Sync.set("budgets", div, result)
    SV.Bus.emit("supply.budgetChanged", {division = div, delta = delta, reason = reason})
    return true, result
end

--[[---------------------------------------------------------------------------
Stock
---------------------------------------------------------------------------]]
function Supply.stock(div, itemId)
    return tonumber(DB.queryValue("SELECT count FROM sv_stock WHERE division = ? AND item_id = ?", div, itemId)) or 0
end

function Supply.stockList(div)
    local out = {}
    for _, row in ipairs(DB.query("SELECT item_id, count FROM sv_stock WHERE division = ? AND count > 0 ORDER BY item_id", div) or {}) do
        out[row.item_id] = tonumber(row.count)
    end
    return out
end

function Supply.addStock(div, itemId, n)
    DB.query("INSERT OR IGNORE INTO sv_stock (division, item_id, count) VALUES (?, ?, 0)", div, itemId)
    DB.query("UPDATE sv_stock SET count = count + ? WHERE division = ? AND item_id = ?", n, div, itemId)
end

--- Removes stock if available. Returns ok.
function Supply.takeStock(div, itemId, n)
    local have = Supply.stock(div, itemId)
    if have < n then return false end
    DB.query("UPDATE sv_stock SET count = count - ? WHERE division = ? AND item_id = ? AND count >= ?", n, div, itemId, n)
    return DB.changes() > 0
end

local function applyStartState()
    if SV.Settings.get("supply.initialized", false) then return end
    DB.transaction(function()
        for _, d in ipairs(Roles.divisions) do
            DB.query("INSERT OR IGNORE INTO sv_budgets (division, balance) VALUES (?, ?)", d.id, (C.Supply.allocation[d.id] or 0) > 0 and C.Supply.startBudget or 0)
        end
        for div, items in pairs(C.Supply.startStock) do
            for itemId, n in pairs(items) do Supply.addStock(div, itemId, n) end
        end
    end)
    SV.Settings.set("supply.initialized", true)
    SV.Log.info("снабжение: начальные бюджеты и запасы созданы")
end

--[[---------------------------------------------------------------------------
Permissions
---------------------------------------------------------------------------]]
local function isAdminDuty(ply)
    return SV.Admin and SV.Admin.isOnDuty and SV.Admin.isOnDuty(ply)
end

--- Whether ply can decide requests of a division.
function Supply.canDecide(ply, div)
    if isAdminDuty(ply) then return true end
    if not Roles.hasFlag(ply, "approveSupply") then return false end
    local char = ply.SVChar
    if not char then return false end
    if Roles.hasFlag(ply, "logistics") or char.division == "administration" then return true end
    return char.division == div
end

local function canRequest(ply)
    local char = ply.SVChar
    if not char or char.isSCP then return false, "нет персонажа" end
    if char.division == "classd" or char.division == "chaos" then return false, "подразделение не ведёт закупки" end
    if char.rank < C.Supply.requesterMinRank and not Roles.hasFlag(ply, "approveSupply") then
        return false, "заявки подают сотрудники со звания «" .. Roles.rankName(char.division, C.Supply.requesterMinRank) .. "»"
    end
    return true
end

--[[---------------------------------------------------------------------------
Requests
---------------------------------------------------------------------------]]
--- Validates request lines from the client. Returns lines, cost or nil, reason.
function Supply.parseLines(div, raw)
    if not istable(raw) then return nil, "неверный формат заявки" end
    local lines, total, cost, n = {}, 0, 0, 0
    for k, v in pairs(raw) do
        n = n + 1
        if n > C.Supply.requestMaxLines then return nil, "слишком много позиций (максимум " .. C.Supply.requestMaxLines .. ")" end
        local itemId, count = tostring(k), tonumber(v)
        local def = C.Items[itemId]
        if not def or not def.price then return nil, "позиция недоступна для заказа: " .. itemId end
        if def.division and not U.contains(def.division, div) then return nil, def.name .. ": не заказывается вашим подразделением" end
        if not count or count < 1 or count ~= math.floor(count) or count > 20 then return nil, def.name .. ": неверное количество" end
        lines[itemId] = count
        total = total + count
        cost = cost + def.price * count
    end
    if total == 0 then return nil, "заявка пуста" end
    if total > C.Supply.requestMaxItems then return nil, "слишком много предметов (максимум " .. C.Supply.requestMaxItems .. ")" end
    return lines, cost
end

function Supply.createRequest(ply, raw, reason)
    local ok, why = canRequest(ply)
    if not ok then return false, "Нельзя подать заявку: " .. why .. "." end
    local div = ply.SVChar.division
    local lines, cost = Supply.parseLines(div, raw)
    if not lines then return false, "Заявка отклонена: " .. cost .. "." end
    reason = U.cleanText(reason, 200)
    if U.utf8len(reason) < 5 then return false, "Укажите обоснование заявки." end
    local open = tonumber(DB.queryValue("SELECT COUNT(*) FROM sv_supply_requests WHERE requester_char = ? AND status = 'pending'", ply.SVChar.id)) or 0
    if open >= 3 then return false, "У вас уже три нерассмотренные заявки." end
    DB.query([[INSERT INTO sv_supply_requests (division, requester_char, requester_name, lines, cost, reason, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)]], div, ply.SVChar.id, ply.SVChar.name, DB.encode(lines), cost, reason, os.time())
    local id = DB.lastInsertId()
    SV.Audit.log("supply", "request", ply, nil, {id = id, cost = cost, lines = lines})
    SV.Bus.emit("supply.requested", {ply = ply, id = id, division = div, cost = cost})
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and Supply.canDecide(p, div) and p.SVChar then
            DarkRP.notify(p, 0, 5, "Новая заявка на снабжение #" .. id .. " (" .. (Roles.getDivision(div).name) .. ", " .. cost .. " ед.)")
        end
    end
    return true, "Заявка #" .. id .. " подана (" .. cost .. " ед.)."
end

local function deliveryDelay()
    return C.Supply.deliveryDelay * Supply.delayMultiplier
end

function Supply.decide(ply, id, approve, note)
    local row = DB.queryRow("SELECT * FROM sv_supply_requests WHERE id = ?", id)
    if not row or row.status ~= "pending" then return false, "Заявка не найдена или уже рассмотрена." end
    if not Supply.canDecide(ply, row.division) then return false, "Нет полномочий рассматривать заявки этого подразделения." end
    if ply.SVChar and tonumber(row.requester_char) == ply.SVChar.id and not isAdminDuty(ply) then
        return false, "Нельзя рассматривать собственную заявку."
    end
    note = U.cleanText(note, 200)
    if not approve and U.utf8len(note) < 3 then return false, "Укажите причину отказа." end
    local cost = tonumber(row.cost)

    local decider = ply.SVChar and ply.SVChar.name or ply:SteamName()
    local okTx, err = DB.transaction(function()
        if approve then
            local ok = Supply.adjustBudget(row.division, -cost, "Заявка #" .. id, ply)
            if not ok then error("budget", 0) end
        end
        DB.query("UPDATE sv_supply_requests SET status = ?, decided_char = ?, decided_name = ?, note = ?, decided_at = ? WHERE id = ?",
            approve and "approved" or "rejected", ply.SVChar and ply.SVChar.id or 0, decider, note, os.time(), id)
    end)
    if not okTx then
        if err == "budget" then return false, "Недостаточно бюджета (" .. Supply.budget(row.division) .. " из " .. cost .. ")." end
        return false, "Ошибка базы данных."
    end
    if approve then Supply.deliveries[id] = CurTime() + deliveryDelay() end

    SV.Audit.log("supply", approve and "approve" or "reject", ply, nil, {id = id, cost = cost, note = note})
    SV.Bus.emit("supply.decided", {ply = ply, id = id, approved = approve, division = row.division})
    local requester = SV.Chars.active[tonumber(row.requester_char)]
    if IsValid(requester) then
        DarkRP.notify(requester, approve and 0 or 1, 6, "Заявка #" .. id .. (approve and " одобрена. Поставка в пути." or (" отклонена: " .. note)))
    end
    return true, approve and ("Заявка #" .. id .. " одобрена.") or ("Заявка #" .. id .. " отклонена.")
end

function Supply.cancel(ply, id)
    local row = DB.queryRow("SELECT * FROM sv_supply_requests WHERE id = ?", id)
    if not row or row.status ~= "pending" then return false, "Заявка не найдена или уже рассмотрена." end
    if not ply.SVChar or tonumber(row.requester_char) ~= ply.SVChar.id then return false, "Это не ваша заявка." end
    DB.query("UPDATE sv_supply_requests SET status = 'cancelled', decided_at = ? WHERE id = ?", os.time(), id)
    return true, "Заявка отменена."
end

--[[---------------------------------------------------------------------------
Deliveries
---------------------------------------------------------------------------]]
local function bookDelivery(id, how, actor)
    local row = DB.queryRow("SELECT * FROM sv_supply_requests WHERE id = ?", id)
    if not row or row.status ~= "approved" then return false end
    local lines = DB.decode(row.lines)
    DB.transaction(function()
        for itemId, n in pairs(lines) do Supply.addStock(row.division, itemId, n) end
        DB.query("UPDATE sv_supply_requests SET status = 'delivered', delivered_at = ? WHERE id = ?", os.time(), id)
    end)
    SV.Audit.log("supply", "delivered", actor, nil, {id = id, how = how})
    return true, row
end
Supply.bookDelivery = bookDelivery

local function spawnCrate(id, row)
    local points = SV.MapCfg.points("logistics")
    if #points == 0 or not scripted_ents.GetStored("sv_supply_crate") then return nil end
    local p = points[(id % #points) + 1]
    local ent = ents.Create("sv_supply_crate")
    if not IsValid(ent) then return nil end
    ent:SetPos(SV.MapCfg.toVec(p.pos) + Vector(math.random(-40, 40), math.random(-40, 40), 16))
    ent:SetDivision(row.division)
    ent:SetRequestId(id)
    ent:Spawn()
    Supply.crates[ent] = {id = id, expires = CurTime() + C.Supply.crateLifetime}
    return ent
end

local function processDeliveries()
    if Supply.blocked then return end
    local now = CurTime()
    for id, at in pairs(Supply.deliveries) do
        if now >= at then
            Supply.deliveries[id] = nil
            local row = DB.queryRow("SELECT * FROM sv_supply_requests WHERE id = ? AND status = 'approved'", id)
            if row then
                local crate = spawnCrate(id, row)
                local div = Roles.getDivision(row.division)
                if crate then
                    DB.query("UPDATE sv_supply_requests SET status = 'arrived' WHERE id = ?", id)
                    SV.Bus.emit("supply.arrived", {id = id, division = row.division, crate = crate})
                    for _, p in ipairs(player.GetAll()) do
                        if p.SVChar and (p.SVChar.division == row.division or U.contains(C.Supply.unpackDivisions, p.SVChar.division)) then
                            DarkRP.notify(p, 0, 6, "Поставка по заявке #" .. id .. " (" .. div.name .. ") прибыла на площадку снабжения.")
                        end
                    end
                else
                    bookDelivery(id, "direct")
                end
            end
        end
    end
    for ent, info in pairs(Supply.crates) do
        if not IsValid(ent) then
            Supply.crates[ent] = nil
            DB.query("UPDATE sv_supply_requests SET status = 'approved' WHERE id = ? AND status = 'arrived'", info.id)
            bookDelivery(info.id, "crate-lost")
        elseif now >= info.expires then
            Supply.crates[ent] = nil
            ent:Remove()
            DB.query("UPDATE sv_supply_requests SET status = 'approved' WHERE id = ? AND status = 'arrived'", info.id)
            bookDelivery(info.id, "auto")
        end
    end
end
timer.Create("SiteVeil.Supply.Deliveries", 2, 0, processDeliveries)

--- Opening a crate (called by the sv_supply_crate entity after its action).
function Supply.unpackCrate(ply, ent)
    local info = Supply.crates[ent]
    if not info then return false, "Поставка уже разобрана." end
    local char = ply.SVChar
    local div = ent:GetDivision()
    if not char or not (char.division == div or U.contains(C.Supply.unpackDivisions, char.division)) then
        return false, "Разбирать поставку могут сотрудники подразделения-получателя, класс D, администрация и инженеры."
    end
    return SV.Actions.start(ply, {
        id = "unpack", label = "Разбор поставки", duration = 6, target = ent, maxDist = 120,
        onComplete = function(p)
            if not Supply.crates[ent] then return end
            Supply.crates[ent] = nil
            DB.query("UPDATE sv_supply_requests SET status = 'approved' WHERE id = ? AND status = 'arrived'", info.id)
            local ok, row = bookDelivery(info.id, "unpacked", p)
            if IsValid(ent) then ent:Remove() end
            if ok then
                DarkRP.notify(p, 0, 5, "Поставка #" .. info.id .. " принята на склад (" .. (Roles.getDivision(row.division).name) .. ").")
                SV.Bus.emit("supply.unpacked", {ply = p, id = info.id, division = row.division})
            end
        end,
    })
end

-- Approved deliveries survive restarts only as bookkeeping: they are booked
-- into stock directly.
hook.Add("SiteVeil.DatabaseReady", "SiteVeil.Supply", function()
    applyStartState()
    for _, row in ipairs(DB.query("SELECT id FROM sv_supply_requests WHERE status IN ('approved', 'arrived')") or {}) do
        DB.query("UPDATE sv_supply_requests SET status = 'approved' WHERE id = ?", row.id)
        bookDelivery(tonumber(row.id), "restart")
    end
    publishBudgets()
end)

SV.Bus.on("shift.started", "supply", function(data)
    if data.previous == 0 then return end
    for div, amount in pairs(C.Supply.allocation) do
        if amount > 0 then Supply.adjustBudget(div, amount, "Плановое финансирование, смена №" .. data.id) end
    end
end)

--[[---------------------------------------------------------------------------
Lockers
---------------------------------------------------------------------------]]
local function lockerUsage(char, kind, itemId)
    return tonumber(DB.queryValue("SELECT count FROM sv_locker_usage WHERE char_id = ? AND shift = ? AND locker = ? AND item_id = ?",
        char.id, SV.Shift.id, kind, itemId)) or 0
end

local function addUsage(char, kind, itemId, delta)
    DB.query("INSERT OR IGNORE INTO sv_locker_usage (char_id, shift, locker, item_id, count) VALUES (?, ?, ?, ?, 0)", char.id, SV.Shift.id, kind, itemId)
    DB.query("UPDATE sv_locker_usage SET count = MAX(count + ?, 0) WHERE char_id = ? AND shift = ? AND locker = ? AND item_id = ?",
        delta, char.id, SV.Shift.id, kind, itemId)
end

--- Whether ply may use a locker. Returns ok, reason.
function Supply.canUseLocker(ply, kind)
    local L = C.Lockers[kind]
    if not L then return false, "неизвестный шкаф" end
    local char = ply.SVChar
    if not char or char.isSCP then return false, "нет персонажа" end
    if isAdminDuty(ply) then return true end
    if L.divisions and not U.contains(L.divisions, char.division) then return false, "шкаф не для вашего подразделения" end
    if L.tags and SV.Access then
        local ok = false
        for _, t in ipairs(L.tags) do
            if SV.Access.hasTag(ply, t) then ok = true break end
        end
        if not ok then return false, "нужна карта с доступом к этому складу" end
    end
    return true
end

function Supply.lockerView(ply, ent)
    local kind = ent:GetLockerKind()
    local L = C.Lockers[kind]
    local ok, reason = Supply.canUseLocker(ply, kind)
    local items = {}
    for itemId, quota in pairs(L.items) do
        items[#items + 1] = {id = itemId, quota = quota, used = ply.SVChar and lockerUsage(ply.SVChar, kind, itemId) or 0, stock = Supply.stock(L.stock, itemId)}
    end
    table.sort(items, function(a, b) return a.id < b.id end)
    Net.send(ply, "supply.locker", {ent = ent:EntIndex(), kind = kind, name = L.name, ok = ok, reason = reason, items = items,
        stockOwner = Roles.getDivision(L.stock) and Roles.getDivision(L.stock).name or L.stock})
end

Net.handle("supply.lockerTake", function(ply, ent, itemId)
    if not IsValid(ent) or ent:GetClass() ~= "sv_locker" then return false, "Шкаф не найден." end
    if not U.within(ply, ent, 130) then return false, "Подойдите к шкафу." end
    local kind = ent:GetLockerKind()
    local L = C.Lockers[kind]
    local ok, reason = Supply.canUseLocker(ply, kind)
    if not ok then return false, "Шкаф: " .. reason .. "." end
    local quota = L.items[itemId]
    if not quota then return false, "Этого предмета нет в шкафу." end
    local char = ply.SVChar
    if lockerUsage(char, kind, itemId) >= quota then return false, "Лимит выдачи за смену исчерпан (" .. quota .. ")." end
    local fits, why = Inv.fits(ply, itemId, 1)
    if not fits then return false, "Не помещается: " .. why end
    if not Supply.takeStock(L.stock, itemId, 1) then return false, "На складе нет: " .. C.Items[itemId].name .. ". Подайте заявку на снабжение." end
    local added = Inv.add(ply, itemId, 1, {data = {locker = kind, stockOf = L.stock}})
    if not added then
        Supply.addStock(L.stock, itemId, 1)
        return false, "Не удалось выдать предмет."
    end
    addUsage(char, kind, itemId, 1)
    SV.Audit.log("supply", "locker.take", ply, nil, {locker = kind, item = itemId})
    SV.Bus.emit("supply.lockerTake", {ply = ply, locker = kind, item = itemId, ent = ent})
    Supply.lockerView(ply, ent)
    return true
end)

Net.handle("supply.lockerReturn", function(ply, ent, uid)
    if not IsValid(ent) or ent:GetClass() ~= "sv_locker" then return false, "Шкаф не найден." end
    if not U.within(ply, ent, 130) then return false, "Подойдите к шкафу." end
    local kind = ent:GetLockerKind()
    local L = C.Lockers[kind]
    local item = Inv.getItem(ply, uid)
    if not item then return false, "Предмет не найден." end
    if not L.items[item.id] then return false, "Этот предмет сюда не сдаётся." end
    if item.issuedTo then return false, "Служебное снаряжение должности сдавать не нужно." end
    if item.lock then return false, "Предмет занят." end
    local count = item.count
    Inv.removeUid(ply, uid, count)
    Supply.addStock(L.stock, item.id, count)
    if item.data.locker == kind then addUsage(ply.SVChar, kind, item.id, -count) end
    SV.Audit.log("supply", "locker.return", ply, nil, {locker = kind, item = item.id, count = count})
    Supply.lockerView(ply, ent)
    return true, "Сдано на склад: " .. C.Items[item.id].name .. " ×" .. count
end)

--[[---------------------------------------------------------------------------
Overview for the supply tab
---------------------------------------------------------------------------]]
Net.handle("supply.overview", function(ply)
    local char = ply.SVChar
    local div = char.division
    local admin = Roles.hasFlag(ply, "logistics") or div == "administration" or isAdminDuty(ply)
    local requests = admin
        and DB.query("SELECT * FROM sv_supply_requests ORDER BY id DESC LIMIT 40")
        or DB.query("SELECT * FROM sv_supply_requests WHERE division = ? ORDER BY id DESC LIMIT 25", div)
    for _, r in ipairs(requests or {}) do
        r.lines = DB.decode(r.lines)
        r.canDecide = r.status == "pending" and Supply.canDecide(ply, r.division) and tonumber(r.requester_char) ~= char.id
        r.own = tonumber(r.requester_char) == char.id
        r.created = U.clockString(tonumber(r.created_at))
    end
    local ledger = DB.query("SELECT delta, balance, reason, actor_name, time FROM sv_budget_ledger WHERE division = ? ORDER BY id DESC LIMIT 20", div) or {}
    for _, l in ipairs(ledger) do l.when = U.clockString(tonumber(l.time)) l.time = nil end
    local catalog = {}
    for id, def in pairs(C.Items) do
        if def.price and (not def.division or U.contains(def.division, div)) then catalog[#catalog + 1] = {id = id, price = def.price} end
    end
    table.sort(catalog, function(a, b) return a.id < b.id end)
    local okReq, whyReq = canRequest(ply)
    Net.send(ply, "supply.overview", {
        division = div, budget = Supply.budget(div), stock = Supply.stockList(div), requests = requests or {},
        ledger = ledger, catalog = catalog, canRequest = okReq, requestBlocked = whyReq,
        blocked = Supply.blocked, delay = math.Round(deliveryDelay()),
    })
end)

Net.handle("supply.request", function(ply, lines, reason)
    return Supply.createRequest(ply, lines, reason)
end)

Net.handle("supply.decide", function(ply, id, approve, note)
    return Supply.decide(ply, id, approve, note)
end)

Net.handle("supply.cancel", function(ply, id)
    return Supply.cancel(ply, id)
end)

SV.Perf.registry("supply.crates", function() return U.count(Supply.crates) end)
SV.Perf.registry("supply.pendingDeliveries", function() return U.count(Supply.deliveries) end)

--[[---------------------------------------------------------------------------
Administration panel (client): players, whitelist, tickets, audit search.
Opened from the admin tab ("Панель администратора").
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Roles = SV.Roles

local panelData = {}

local function whitelistWindow(steamid, name)
    local w = vgui.Create("SVFrame")
    w:SetHeader("ДОПУСКИ (WHITELIST)", name)
    w:SetSize(S(560), S(560))
    w:Center()
    w:MakePopup()
    local scroll = UI.scroll(w)
    local current = UI.card(scroll, "Выданные допуски")
    UI.text(current, "Загрузка…", "SV.Small", C.dim)
    w.current = current
    UI.whitelistWindow = w
    local give = UI.card(scroll, "Выдать / отозвать")
    local options = {}
    for _, d in ipairs(Roles.divisions) do
        if d.whitelist then options[#options + 1] = {"Подразделение: " .. d.name, {"division", d.id}} end
    end
    for _, r in ipairs(Roles.list) do
        if r.whitelist and r.division then options[#options + 1] = {"Роль: " .. r.name, {"role", r.id}} end
    end
    local note = vgui.Create("SVEntry", give)
    note:Dock(TOP)
    note:SetHint("Основание (заявка, решение администрации)")
    for _, o in ipairs(options) do
        local row = UI.row(give, S(30))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Small")
        lbl:SetTextColor(C.text)
        lbl:SetText(o[1])
        local rev = UI.button(row, "Отозвать", function() Net.call("admin.whitelist", steamid, o[2][1], o[2][2], false, "") end, "ghost")
        rev:Dock(RIGHT)
        rev:SetWide(S(100))
        local add = UI.button(row, "Выдать", function() Net.call("admin.whitelist", steamid, o[2][1], o[2][2], true, note:GetValue()) end, "primary")
        add:Dock(RIGHT)
        add:SetWide(S(90))
        add:DockMargin(0, 0, S(4), 0)
    end
    Net.call("admin.whitelistOf", steamid)
end

Net.on("admin.whitelistOf", function(data)
    local w = UI.whitelistWindow
    if not IsValid(w) then return end
    w.current:Clear()
    if #data.list == 0 then UI.text(w.current, "Нет допусков.", "SV.Small", C.dim) end
    for _, e in ipairs(data.list) do
        UI.text(w.current, e.scope .. ": " .. e.value .. (e.note ~= "" and (" — " .. e.note) or ""), "SV.Small")
    end
end)

local function buildPlayers(panel)
    local scroll = UI.scroll(panel)
    local list = panelData.players
    if not list then
        UI.text(scroll, "Загрузка…", "SV.Small", C.dim)
        Net.call("admin.players")
        return
    end
    for _, p in ipairs(list) do
        local row = UI.row(scroll, S(34))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Small")
        lbl:SetTextColor(p.duty and C.warn or C.text)
        lbl:SetText(string.format("%s (%s) · %s · %s%s · %d мс", p.steam, p.steamid, p.char and (p.char .. " № " .. p.number) or "без персонажа",
            p.role, p.alive and "" or " · мёртв", p.ping))
        local wl = UI.button(row, "Допуски", function() whitelistWindow(p.steamid, p.steam) end)
        wl:Dock(RIGHT)
        wl:SetWide(S(110))
        if not LocalPlayer():IsAdmin() then wl:SetBlocked("нет прав") end
    end
    local refresh = UI.button(scroll, "Обновить", function() panelData.players = nil Net.call("admin.players") end, "ghost")
    refresh:Dock(TOP)
end

local function buildTickets(panel)
    local scroll = UI.scroll(panel)
    local list = panelData.tickets
    if not list then
        UI.text(scroll, "Загрузка…", "SV.Small", C.dim)
        Net.call("admin.tickets")
        return
    end
    if #list == 0 then UI.text(scroll, "Обращений нет.", "SV.Small", C.dim) end
    local names = {open = "новое", claimed = "в работе", closed = "закрыто"}
    for _, t in ipairs(list) do
        local card = UI.card(scroll, "#" .. t.id .. " · " .. t.name .. " · " .. (names[t.status] or t.status) .. (t.claimedBy and (" · " .. t.claimedBy) or ""),
            t.status == "closed" and C.faint or C.accent)
        for _, m in ipairs(t.messages) do UI.text(card, os.date("%H:%M", m.t) .. " " .. m.from .. ": " .. m.text, "SV.Small") end
        if t.status ~= "closed" then
            local entry = vgui.Create("SVEntry", card)
            entry:Dock(TOP)
            entry:SetHint("Ответ игроку")
            local row = UI.row(card, S(32))
            for _, a in ipairs({{"claim", "Взять"}, {"reply", "Ответить"}, {"close", "Закрыть"}}) do
                local b = UI.button(row, a[2], function() Net.call("admin.ticket", t.id, a[1], entry:GetValue()) end, a[1] == "close" and "danger" or nil)
                b:Dock(LEFT)
                b:SetWide(S(120))
                b:DockMargin(0, 0, S(4), 0)
                if a[1] == "claim" and t.status == "claimed" then b:SetBlocked("уже в работе") end
            end
        end
    end
    UI.text(scroll, "Обращения хранятся до перезапуска сервера; все действия записываются в журнал аудита.", "SV.Tiny", C.faint)
end

local function buildAudit(panel)
    local scroll = UI.scroll(panel)
    local form = UI.card(scroll, "Фильтр")
    local cat = vgui.Create("SVEntry", form)
    cat:Dock(TOP)
    cat:SetHint("Категория (security, scp, research, admin, ...)")
    local actor = vgui.Create("SVEntry", form)
    actor:Dock(TOP)
    actor:DockMargin(0, S(4), 0, 0)
    actor:SetHint("SteamID64 участника")
    local text = vgui.Create("SVEntry", form)
    text:Dock(TOP)
    text:DockMargin(0, S(4), 0, 0)
    text:SetHint("Текст в действии или деталях")
    local go = UI.button(form, "Искать за последние 24 часа", function()
        Net.call("admin.audit", {category = cat:GetValue(), actor = actor:GetValue(), text = text:GetValue(), minutes = 1440})
    end, "primary")
    go:Dock(TOP)
    go:DockMargin(0, S(6), 0, 0)
    local res = UI.card(scroll, "Результаты (точные записи, видны только администрации)")
    for _, r in ipairs(panelData.audit or {}) do
        UI.text(res, string.format("%s [%s] %s · %s%s", r.when, r.category, r.action, r.actor or "система", r.target and (" → " .. r.target) or ""), "SV.Small")
        if r.details and r.details ~= "" and r.details ~= "[]" then UI.text(res, r.details, "SV.Mono", C.dim) end
    end
end

local function frame()
    if IsValid(UI.adminPanel) then return UI.adminPanel end
    local f = vgui.Create("SVFrame")
    UI.adminPanel = f
    f:SetHeader("ПАНЕЛЬ АДМИНИСТРАТОРА")
    f:SetSize(math.min(S(980), ScrW() - 40), math.min(S(720), ScrH() - 40))
    f:Center()
    f:MakePopup()
    local tabs = vgui.Create("SVTabs", f)
    tabs:Dock(FILL)
    f.tabs = tabs
    tabs:AddTab("players", "Игроки", buildPlayers)
    tabs:AddTab("tickets", "Обращения", buildTickets)
    tabs:AddTab("audit", "Журнал аудита", buildAudit)
    return f
end

function UI.openAdminPanel(tab)
    frame().tabs:Select(tab or "players")
end

local function refresh(tab)
    local f = UI.adminPanel
    if IsValid(f) and f.tabs.active == tab then f.tabs:Select(tab) end
end

Net.on("admin.players", function(data) panelData.players = data.list refresh("players") end)
Net.on("admin.tickets", function(data) panelData.tickets = data.list refresh("tickets") end)
Net.on("admin.audit", function(data) panelData.audit = data.list refresh("audit") end)

hook.Add("SiteVeil.AdminTab", "SiteVeil.AdminPanel", function(scroll)
    local b = UI.button(scroll, "Панель администратора: игроки, допуски, обращения, журнал", function()
        panelData = {}
        UI.openAdminPanel()
    end, "primary")
    b:Dock(TOP)
    b:DockMargin(0, 0, 0, S(8))
end)

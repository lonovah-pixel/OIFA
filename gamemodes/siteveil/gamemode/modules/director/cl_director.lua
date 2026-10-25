--[[---------------------------------------------------------------------------
Director (client): running events for the divisions that can solve them
(HUD list and a marker for places to attend) and the admin panel section.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local Roles = SV.Roles
local Director = SV.Director

local function concernsMe(ev)
    local ply = LocalPlayer()
    local char = UI.myChar()
    if not char or char.isSCP then return false end
    for _, s in ipairs(ev.solvers or {}) do
        if char.division == s or Roles.hasFlag(ply, s) then return true end
    end
    return false
end

UI.hudElement("director", 31, function()
    local list = SV.Sync.get("director", "events") or {}
    local x, y = ScrW() - S(20), S(190)
    local now = CurTime()
    for _, ev in ipairs(list) do
        if concernsMe(ev) then
            local left = math.max(math.ceil(ev.endsAt - now), 0)
            draw.SimpleText((ev.warning and "ОЖИДАЕТСЯ: " or "") .. ev.name .. " · " .. string.format("%d:%02d", math.floor(left / 60), left % 60),
                "SV.HUDSmall", x, y, ev.warning and C.warn or C.accent, TEXT_ALIGN_RIGHT)
            y = y + S(18)
            local lines = UI.wrap("SV.Tiny", ev.text .. (ev.progress and (" (" .. ev.progress .. "%)") or ""), S(380))
            for _, line in ipairs(lines) do
                draw.SimpleText(line, "SV.Tiny", x, y, C.dim, TEXT_ALIGN_RIGHT)
                y = y + S(15)
            end
            y = y + S(6)
            if ev.pos and not ev.warning then
                local pos = Vector(ev.pos[1], ev.pos[2], ev.pos[3] + 40)
                local scr = pos:ToScreen()
                if scr.visible then
                    local dist = math.floor(LocalPlayer():GetPos():Distance(pos) / 52.5)
                    draw.SimpleText("◆ " .. ev.name, "SV.Tiny", scr.x, scr.y, C.accent, TEXT_ALIGN_CENTER)
                    draw.SimpleText(dist .. " м", "SV.Tiny", scr.x, scr.y + S(14), C.dim, TEXT_ALIGN_CENTER)
                end
            end
        end
    end
end)

--[[---------------------------------------------------------------------------
Admin panel section
---------------------------------------------------------------------------]]
Director.adminView = Director.adminView or nil

hook.Add("SiteVeil.AdminTab", "SiteVeil.Director", function(scroll)
    local card = UI.card(scroll, "Директор напряжения")
    -- Cached view; refreshed at most every 5 s so that two sections of the
    -- tab cannot keep re-requesting each other.
    local v = Director.adminView
    if not v or RealTime() - (Director.adminViewAt or 0) > 5 then
        if RealTime() - (Director.adminAsked or 0) > 5 then
            Director.adminAsked = RealTime()
            Net.call("director.status")
        end
        if not v then
            UI.text(card, "Загрузка…", "SV.Small", C.dim)
            return
        end
    end
    UI.text(card, string.format("%s · напряжение %d/100%s", v.enabled and "включён" or "ВЫКЛЮЧЕН", v.tension,
        v.nextIn and (" · следующее решение через " .. v.nextIn .. " с") or ""), "SV.Small", v.enabled and C.ok or C.warn)
    if not v.convar then UI.text(card, "Отключён переменной сервера sv_director 0.", "SV.Tiny", C.warn) end
    local toggle = UI.button(card, v.enabled and "Выключить директора" or "Включить директора", function() Net.call("director.toggle", not v.enabled) end,
        v.enabled and "danger" or "primary")
    toggle:Dock(TOP)
    if not SV.Admin.isOnDuty(LocalPlayer()) then toggle:SetBlocked("заступите на дежурство") end
    for _, a in ipairs(v.active) do
        local row = UI.row(card, S(30))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Small")
        lbl:SetTextColor(C.accent)
        lbl:SetText(string.format("Идёт: %s (%s, сектор %s, осталось %d с)", a.name, a.phase == "warn" and "предупреждение" or "активно", a.sector or "—", a.left))
        local b = UI.button(row, "Снять", function() Net.call("director.cancel", a.id) end, "ghost")
        b:Dock(RIGHT)
        b:SetWide(S(90))
    end
    for _, e in ipairs(v.events) do
        local row = UI.row(card, S(30))
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(FILL)
        lbl:SetFont("SV.Small")
        lbl:SetTextColor(e.enabled and C.text or C.faint)
        lbl:SetText(e.name .. (e.blocked and (" — " .. e.blocked) or " — готово") .. (e.cooldownLeft > 0 and (" · " .. e.cooldownLeft .. " с") or ""))
        local sw = UI.button(row, e.enabled and "Откл." or "Вкл.", function() Net.call("director.event", e.id, not e.enabled) end, "ghost")
        sw:Dock(RIGHT)
        sw:SetWide(S(70))
        local force = UI.button(row, "Запустить", function() Net.call("director.force", e.id) end)
        force:Dock(RIGHT)
        force:SetWide(S(110))
        force:DockMargin(0, 0, S(4), 0)
        if e.blocked and e.blocked ~= "перезарядка" then force:SetBlocked(e.blocked) end
    end
    if #v.history > 0 then
        UI.text(card, "Журнал:", "SV.Small", C.dim)
        local outcomes = {success = "решено", failed = "провалено", withdrawn = "снято"}
        for _, h in ipairs(v.history) do
            UI.text(card, h.when .. " · " .. h.name .. " · " .. (outcomes[h.outcome] or "идёт"), "SV.Tiny", C.dim)
        end
    end
end)

Net.on("director.status", function(data)
    Director.adminView = data
    Director.adminViewAt = RealTime()
    UI.refreshTab("admin")
end)

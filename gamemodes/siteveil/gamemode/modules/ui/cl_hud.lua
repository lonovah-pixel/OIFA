--[[---------------------------------------------------------------------------
HUD.

Element registry: UI.hudElement(id, order, fn) - modules add their own HUD
pieces (facility banner, sector status, blink meter, ...) without touching
this file. Elements draw in ascending order.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Sync = SV.Sync

UI.hudElements = UI.hudElements or {}

function UI.hudElement(id, order, fn)
    for i, e in ipairs(UI.hudElements) do
        if e.id == id then table.remove(UI.hudElements, i) break end
    end
    table.insert(UI.hudElements, {id = id, order = order, fn = fn})
    table.sort(UI.hudElements, function(a, b) return a.order < b.order end)
end

local hidden = {
    CHudHealth = true, CHudBattery = true, CHudSuitPower = true, CHUDQuickInfo = true,
    CHudAmmo = true, CHudSecondaryAmmo = true,
}

function GM:HUDShouldDraw(name)
    if hidden[name] then return false end
    return self.Sandbox.HUDShouldDraw(self, name)
end

function GM:HUDDrawTargetID()
    return false
end

function UI.myChar()
    return Sync.get("self", "char")
end

--[[---------------------------------------------------------------------------
Identity and vitals (bottom left)
---------------------------------------------------------------------------]]
local function bar(x, y, w, h, frac, col, label)
    surface.SetDrawColor(C.panel2)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(col)
    surface.DrawRect(x, y, math.Round(w * math.Clamp(frac, 0, 1)), h)
    surface.SetDrawColor(C.border)
    surface.DrawOutlinedRect(x, y, w, h)
    if label then draw.SimpleText(label, "SV.HUDSmall", x + S(6), y + h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
end
UI.hudBar = bar

UI.hudElement("identity", 10, function(ply)
    local char = UI.myChar()
    if not char then return end
    local role = SV.Roles.ofPlayer(ply)
    local w, h = S(360), S(124)
    local x, y = S(20), ScrH() - h - S(20)
    UI.drawPanel(x, y, w, h, C.panel)
    UI.drawAccent(x, y, h, UI.divisionColor(char.division))

    local name = SV.Chars.displayName(ply)
    draw.SimpleText(name, "SV.HUD", x + S(14), y + S(8), C.text)
    draw.SimpleText("№ " .. (char.number or ""), "SV.HUDSmall", x + w - S(10), y + S(10), C.dim, TEXT_ALIGN_RIGHT)
    local rankName = SV.Roles.rankName(char.division, char.rank)
    draw.SimpleText((role and role.name or "") .. " · " .. rankName, "SV.HUDSmall", x + S(14), y + S(32), C.dim)

    local clearance = Sync.get("self", "clearance") or (role and role.clearance) or 0
    draw.SimpleText("Допуск " .. clearance, "SV.HUDSmall", x + w - S(10), y + S(32), clearance >= 3 and C.warn or C.dim, TEXT_ALIGN_RIGHT)

    local hp, maxHp = ply:Health(), math.max(ply:GetMaxHealth(), 1)
    bar(x + S(14), y + S(60), w - S(28), S(22), hp / maxHp, hp / maxHp < 0.3 and C.danger or C.ok, "Здоровье " .. math.max(hp, 0))
    local armor = ply:Armor()
    bar(x + S(14), y + S(88), w - S(28), S(18), armor / 100, C.info, armor > 0 and ("Защита " .. armor) or "Без защиты")
end)

--[[---------------------------------------------------------------------------
Weapon / ammo (bottom right)
---------------------------------------------------------------------------]]
UI.hudElement("ammo", 15, function(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or not ply:Alive() then return end
    local name = wep.PrintName or wep:GetClass()
    if language and language.GetPhrase then name = language.GetPhrase(name) end
    local clip, ammoType = wep:Clip1(), wep:GetPrimaryAmmoType()
    local w, h = S(260), S(64)
    local x, y = ScrW() - w - S(20), ScrH() - h - S(20)
    UI.drawPanel(x, y, w, h, C.panel)
    draw.SimpleText(name, "SV.HUDSmall", x + S(12), y + S(8), C.dim)
    if clip >= 0 and ammoType >= 0 then
        draw.SimpleText(clip .. " / " .. ply:GetAmmoCount(ammoType), "SV.HUDBig", x + S(12), y + S(26), C.text)
    end
end)

--[[---------------------------------------------------------------------------
Tasks (right side)
---------------------------------------------------------------------------]]
UI.hudElement("tasks", 30, function()
    local tasks = Sync.get("self", "tasks")
    if not tasks or #tasks == 0 then return end
    local w = S(320)
    local x, y = ScrW() - w - S(20), S(340)
    draw.SimpleText("ЗАДАЧИ", "SV.HUDSmall", x, y, C.dim)
    y = y + S(20)
    for _, t in ipairs(tasks) do
        local h = S(46)
        UI.drawPanel(x, y, w, h, C.panel)
        UI.drawAccent(x, y, h, C.accent)
        draw.SimpleText(t.name, "SV.HUDSmall", x + S(12), y + S(6), C.text)
        draw.SimpleText(t.text, "SV.Tiny", x + S(12), y + S(26), C.dim)
        y = y + h + S(4)
    end
end)

--[[---------------------------------------------------------------------------
Timed action progress (center)
---------------------------------------------------------------------------]]
UI.hudElement("action", 40, function()
    local a = Sync.get("self", "action")
    if not a then return end
    local frac = (CurTime() - a.started) / math.max(a.duration, 0.01)
    local w, h = S(360), S(30)
    local x, y = ScrW() / 2 - w / 2, ScrH() * 0.62
    bar(x, y, w, h, frac, C.accent, nil)
    draw.SimpleText(a.label, "SV.HUDSmall", ScrW() / 2, y + h / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Отменить: /cancel", "SV.Tiny", ScrW() / 2, y + h + S(4), C.faint, TEXT_ALIGN_CENTER)
end)

--[[---------------------------------------------------------------------------
Death screen
---------------------------------------------------------------------------]]
UI.hudElement("death", 50, function(ply)
    if ply:Alive() or not UI.myChar() then return end
    local at = Sync.get("self", "respawnAt")
    surface.SetDrawColor(0, 0, 0, 170)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    draw.SimpleText("СОТРУДНИК ВЫВЕДЕН ИЗ СТРОЯ", "SV.Banner", ScrW() / 2, ScrH() * 0.4, C.danger, TEXT_ALIGN_CENTER)
    local left = at and math.max(at - CurTime(), 0) or 0
    local text = left > 0 and ("Возвращение на смену через " .. math.ceil(left) .. " с") or "Нажмите любую клавишу, чтобы вернуться на смену"
    draw.SimpleText(text, "SV.HUD", ScrW() / 2, ScrH() * 0.4 + S(40), C.text, TEXT_ALIGN_CENTER)
end)

--[[---------------------------------------------------------------------------
Looking at a player: designation and role at close range.
---------------------------------------------------------------------------]]
UI.hudElement("target", 60, function(ply)
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end
    if tr.StartPos:DistToSqr(tr.HitPos) > 250 * 250 then return end
    if ent:GetNoDraw() then return end
    local role = SV.Roles.ofPlayer(ent)
    if not role or role.id == SV.Config.LobbyRole then return end
    local x, y = ScrW() / 2, ScrH() / 2 + S(30)
    local name = role.scp and role.name or SV.Chars.displayName(ent)
    draw.SimpleText(name, "SV.HUD", x, y, C.text, TEXT_ALIGN_CENTER)
    if not role.scp then
        local div = ent:getDarkRPVar("sv_div")
        draw.SimpleText(role.name .. " · " .. SV.Roles.rankName(div, ent:getDarkRPVar("sv_rank")), "SV.HUDSmall", x, y + S(22), UI.divisionColor(div), TEXT_ALIGN_CENTER)
    end
    hook.Run("SiteVeil.HUDTargetInfo", ent, x, y + S(44))
end)

function GM:HUDPaint()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    for _, e in ipairs(UI.hudElements) do
        local ok, err = pcall(e.fn, ply)
        if not ok then
            ErrorNoHalt("[SITE-VEIL] HUD " .. e.id .. ": " .. tostring(err) .. "\n")
            e.failedAt = RealTime()
        end
    end
    UI.drawToasts()
    self.Sandbox.HUDPaint(self)
end

-- Voice indicators of the sandbox base stay; DarkRP's chat indicator module
-- is kept as well.

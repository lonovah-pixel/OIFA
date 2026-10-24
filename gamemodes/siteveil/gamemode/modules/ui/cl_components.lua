--[[---------------------------------------------------------------------------
UI components shared by every SITE-VEIL screen.

  SVFrame    window with title bar and close button
  SVButton   button; SetBlocked(reason) disables it and shows the reason on
             hover and on click (no silently dead buttons)
  SVText     auto-height wrapped label for long Russian strings
  SVCard     titled section
  SVTabs     sidebar tab container
  SVEntry    text entry

Helpers: UI.row(parent, h), UI.badge(parent, text, color), UI.scroll(parent)
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S

--[[---------------------------------------------------------------------------
SVFrame
---------------------------------------------------------------------------]]
local FRAME = {}

function FRAME:Init()
    self:SetTitle("")
    self:ShowCloseButton(false)
    self:SetDraggable(false)
    self:DockPadding(S(10), S(46), S(10), S(10))
    self.titleText = "SITE-VEIL"
    self.subText = ""

    self.close = vgui.Create("DButton", self)
    self.close:SetText("")
    self.close.Paint = function(btn, w, h)
        local col = btn:IsHovered() and C.danger or C.dim
        draw.SimpleText("✕", "SV.Header", w / 2, h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    self.close.DoClick = function() self:Close() end
end

function FRAME:SetHeader(title, sub)
    self.titleText = title or ""
    self.subText = sub or ""
end

function FRAME:PerformLayout(w, h)
    self.close:SetSize(S(40), S(36))
    self.close:SetPos(w - S(44), S(4))
end

function FRAME:Paint(w, h)
    surface.SetDrawColor(C.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(C.panel2)
    surface.DrawRect(0, 0, w, S(40))
    surface.SetDrawColor(C.accent)
    surface.DrawRect(0, S(40), w, S(2))
    surface.SetDrawColor(C.border)
    surface.DrawOutlinedRect(0, 0, w, h)
    draw.SimpleText(self.titleText, "SV.Header", S(14), S(20), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if self.subText ~= "" then
        local tw = UI.textSize("SV.Header", self.titleText)
        draw.SimpleText(self.subText, "SV.Small", S(24) + tw, S(21), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

function FRAME:OnKeyCodePressed(key)
    if key == KEY_ESCAPE then self:Close() end
end

vgui.Register("SVFrame", FRAME, "DFrame")

--[[---------------------------------------------------------------------------
SVButton
---------------------------------------------------------------------------]]
local BUTTON = {}

function BUTTON:Init()
    self:SetText("")
    self.label = ""
    self.style = "default"
    self.blockedReason = nil
    self:SetTall(S(34))
    self:SetCursor("hand")
end

function BUTTON:SetLabel(text)
    self.label = text or ""
end

--- "default", "primary", "danger", "ghost"
function BUTTON:SetStyle(style)
    self.style = style
end

--- Blocks the button with a visible reason; nil unblocks.
function BUTTON:SetBlocked(reason)
    self.blockedReason = reason
    self:SetTooltip(reason and ("Недоступно: " .. reason) or nil)
    self:SetCursor(reason and "no" or "hand")
end

function BUTTON:IsBlocked()
    return self.blockedReason ~= nil
end

function BUTTON:DoClickInternal()
    if self.blockedReason then
        UI.notify("Недоступно: " .. self.blockedReason, 1)
        surface.PlaySound(SV.Config.Sounds.denied)
        return true
    end
end

function BUTTON:DoClick()
    if self.blockedReason then return end
    if self.OnPressed then self:OnPressed() end
end

local styleColors = {
    default = {C.panel2, C.panelHover, C.text},
    primary = {Color(36, 78, 110), Color(46, 98, 136), C.text},
    danger = {Color(96, 32, 32), Color(124, 40, 40), C.text},
    ghost = {Color(0, 0, 0, 0), C.panelHover, C.dim},
}

function BUTTON:Paint(w, h)
    local sc = styleColors[self.style] or styleColors.default
    local bg = self.blockedReason and C.disabled or (self:IsHovered() and sc[2] or sc[1])
    surface.SetDrawColor(bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(self.blockedReason and C.border or (self.style == "primary" and C.accent or C.border))
    surface.DrawOutlinedRect(0, 0, w, h)
    draw.SimpleText(self.label, "SV.Body", w / 2, h / 2, self.blockedReason and C.faint or sc[3], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

vgui.Register("SVButton", BUTTON, "DButton")

--- Shortcut: creates a docked button.
function UI.button(parent, label, onPressed, style)
    local b = vgui.Create("SVButton", parent)
    b:SetLabel(label)
    b:SetStyle(style or "default")
    b.OnPressed = onPressed
    return b
end

--[[---------------------------------------------------------------------------
SVText: wrapped label whose height follows its content.
---------------------------------------------------------------------------]]
local TEXT = {}

function TEXT:Init()
    self:SetWrap(true)
    self:SetAutoStretchVertical(true)
    self:SetFont("SV.Body")
    self:SetTextColor(C.text)
end

vgui.Register("SVText", TEXT, "DLabel")

function UI.text(parent, text, font, color)
    local l = vgui.Create("SVText", parent)
    l:SetFont(font or "SV.Body")
    l:SetTextColor(color or C.text)
    l:SetText(text or "")
    l:Dock(TOP)
    l:DockMargin(0, 0, 0, S(4))
    return l
end

--[[---------------------------------------------------------------------------
SVCard: a titled block.
---------------------------------------------------------------------------]]
local CARD = {}

function CARD:Init()
    self.title = ""
    self.accent = C.accent
    self:DockPadding(S(12), S(36), S(12), S(10))
    self:SetTall(S(80))
end

function CARD:SetTitle(t, accent)
    self.title = t or ""
    self.accent = accent or C.accent
end

-- Height follows the children. Wrapped labels change height after their own
-- layout, so the check runs every frame (a handful of children, cheap).
function CARD:Think()
    local maxY = 0
    for _, child in ipairs(self:GetChildren()) do
        if child:IsVisible() then
            local _, y = child:GetPos()
            maxY = math.max(maxY, y + child:GetTall())
        end
    end
    local want = math.max(maxY + S(10), S(48))
    if self:GetTall() ~= want then self:SetTall(want) end
end

function CARD:Paint(w, h)
    UI.drawPanel(0, 0, w, h, C.panel)
    UI.drawAccent(0, 0, h, self.accent)
    draw.SimpleText(self.title, "SV.Sub", S(12), S(18), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("SVCard", CARD, "DPanel")

function UI.card(parent, title, accent)
    local c = vgui.Create("SVCard", parent)
    c:SetTitle(title, accent)
    c:Dock(TOP)
    c:DockMargin(0, 0, 0, S(8))
    return c
end

--[[---------------------------------------------------------------------------
Helpers
---------------------------------------------------------------------------]]
function UI.scroll(parent)
    local s = vgui.Create("DScrollPanel", parent)
    s:Dock(FILL)
    local bar = s:GetVBar()
    bar:SetWide(S(8))
    bar.Paint = function(_, w, h) surface.SetDrawColor(C.panel) surface.DrawRect(0, 0, w, h) end
    bar.btnGrip.Paint = function(_, w, h) surface.SetDrawColor(C.border) surface.DrawRect(0, 0, w, h) end
    bar.btnUp.Paint = function() end
    bar.btnDown.Paint = function() end
    return s
end

function UI.row(parent, h)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(h or S(34))
    p:DockMargin(0, 0, 0, S(6))
    p.Paint = function() end
    return p
end

function UI.badge(parent, text, color)
    local b = vgui.Create("DPanel", parent)
    local tw = UI.textSize("SV.Small", text)
    b:SetWide(tw + S(16))
    b.Paint = function(_, w, h)
        surface.SetDrawColor(ColorAlpha(color or C.accent, 40))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(color or C.accent)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(text, "SV.Small", w / 2, h / 2, color or C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

--[[---------------------------------------------------------------------------
SVEntry
---------------------------------------------------------------------------]]
local ENTRY = {}

function ENTRY:Init()
    self:SetFont("SV.Body")
    self:SetTall(S(34))
    self:SetTextColor(C.text)
    self:SetCursorColor(C.accent)
    self:SetHighlightColor(ColorAlpha(C.accent, 90))
    self:SetPaintBackground(false)
end

function ENTRY:Paint(w, h)
    surface.SetDrawColor(C.panel2)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(self:HasFocus() and C.accent or C.border)
    surface.DrawOutlinedRect(0, 0, w, h)
    if self:GetText() == "" and self.placeholder then
        draw.SimpleText(self.placeholder, "SV.Body", S(8), h / 2, C.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    self:DrawTextEntryText(C.text, ColorAlpha(C.accent, 90), C.accent)
end

function ENTRY:SetHint(text)
    self.placeholder = text
end

vgui.Register("SVEntry", ENTRY, "DTextEntry")

--[[---------------------------------------------------------------------------
SVTabs: sidebar + content.
---------------------------------------------------------------------------]]
local TABS = {}

function TABS:Init()
    self.sidebar = vgui.Create("DPanel", self)
    self.sidebar:Dock(LEFT)
    self.sidebar:SetWide(S(230))
    self.sidebar:DockPadding(0, 0, S(8), 0)
    self.sidebar.Paint = function() end
    self.content = vgui.Create("DPanel", self)
    self.content:Dock(FILL)
    self.content.Paint = function(_, w, h) UI.drawPanel(0, 0, w, h, C.panel) end
    self.content:DockPadding(S(12), S(12), S(12), S(12))
    self.tabs = {}
    self:SetPaintBackground(false)
end

function TABS:AddTab(id, name, build, note)
    local btn = vgui.Create("DButton", self.sidebar)
    btn:SetText("")
    btn:Dock(TOP)
    btn:SetTall(S(40))
    btn:DockMargin(0, 0, 0, S(4))
    btn.Paint = function(b, w, h)
        local active = self.active == id
        surface.SetDrawColor(active and C.panelHover or (b:IsHovered() and C.panel2 or C.panel))
        surface.DrawRect(0, 0, w, h)
        if active then UI.drawAccent(0, 0, h, C.accent) end
        draw.SimpleText(name, "SV.Body", S(14), h / 2, active and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if note then
            draw.SimpleText(note, "SV.Tiny", w - S(8), h / 2, C.warn, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    btn.DoClick = function() self:Select(id) end
    self.tabs[id] = {build = build, button = btn}
    if not self.active then self:Select(id) end
end

function TABS:Select(id)
    local tab = self.tabs[id]
    if not tab then return end
    self.active = id
    self.content:Clear()
    local ok, err = pcall(tab.build, self.content)
    if not ok then
        UI.text(self.content, "Ошибка интерфейса: " .. tostring(err), "SV.Body", C.danger)
    end
    if self.OnTabChanged then self:OnTabChanged(id) end
end

function TABS:Rebuild()
    if self.active then self:Select(self.active) end
end

vgui.Register("SVTabs", TABS, "DPanel")

--[[---------------------------------------------------------------------------
Confirmation dialog with optional typed confirmation.
---------------------------------------------------------------------------]]
function UI.confirm(title, text, onYes, typedWord)
    local f = vgui.Create("SVFrame")
    f:SetHeader(title)
    f:SetSize(S(520), S(typedWord and 280 or 220))
    f:Center()
    f:MakePopup()
    UI.text(f, text)
    local entry
    if typedWord then
        UI.text(f, "Для подтверждения введите: " .. typedWord, "SV.Small", C.dim)
        entry = vgui.Create("SVEntry", f)
        entry:Dock(TOP)
    end
    local row = UI.row(f, S(36))
    row:Dock(BOTTOM)
    local yes = UI.button(row, "Подтвердить", function()
        if entry and entry:GetValue() == "" then
            UI.notify("Введите подтверждение.", 1)
            return
        end
        f:Close()
        onYes(entry and entry:GetValue() or nil)
    end, "danger")
    yes:Dock(RIGHT)
    yes:SetWide(S(160))
    local no = UI.button(row, "Отмена", function() f:Close() end)
    no:Dock(RIGHT)
    no:SetWide(S(120))
    no:DockMargin(0, 0, S(8), 0)
    return f
end

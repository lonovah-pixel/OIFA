--[[---------------------------------------------------------------------------
Client realm stubs for the client smoke test (tests/client/*.lua).

Loaded after gmod_mock.lua when the runner starts a file in client mode.
Rendering and VGUI do nothing; panels accept every method call. The goal is
to execute the client modules' load-time code, HUD painters and tab
builders to catch Lua errors (nil indexing, wrong arguments, typos). It
does NOT check what is drawn - that needs the game (TESTING.md).
---------------------------------------------------------------------------]]

local Dummy
local dummyMeta = {}
dummyMeta.__index = function() return Dummy end
dummyMeta.__call = function() return Dummy end
dummyMeta.__concat = function(a, b) return tostring(a == Dummy and "" or a) .. tostring(b == Dummy and "" or b) end
Dummy = setmetatable({}, dummyMeta)
MOCK.Dummy = Dummy

-- Panels -------------------------------------------------------------------------
vgui = {registered = {}}
local PANEL = {}
local panelGetters = {
    GetWide = 200, GetTall = 40, GetValue = "", GetText = "", GetChecked = false, IsHovered = false, IsVisible = true,
    GetSelectedID = 1, IsDown = false, HasFocus = false, ChildCount = 0, GetCaretPos = 0,
}
local makePanel
-- Unknown members are callable sub-panels: `p:SetX(...)` returns p, while
-- `p.btnGrip.Paint = ...` (child panels of engine controls) also works.
local function member(owner)
    local sub = {children = {}, valid = true}
    setmetatable(sub, {
        __call = function() return owner end,
        __index = function(self, k)
            if PANEL[k] then return PANEL[k] end
            if panelGetters[k] ~= nil then local v = panelGetters[k] return function() return v end end
            local m = member(self)
            rawset(self, k, m)
            return m
        end,
    })
    return sub
end

makePanel = function(name, parent)
    local p = {name = name, parent = parent, children = {}, valid = true}
    local reg = vgui.registered[name]
    local chain = {}
    while reg do
        table.insert(chain, reg.tbl)
        reg = vgui.registered[reg.base]
    end
    setmetatable(p, {__index = function(self, k)
        for _, t in ipairs(chain) do
            if t[k] ~= nil then return t[k] end
        end
        if PANEL[k] then return PANEL[k] end
        if panelGetters[k] ~= nil then
            local v = panelGetters[k]
            return function() return v end
        end
        return member(self)
    end})
    for i = #chain, 1, -1 do
        if rawget(chain[i], "Init") then chain[i].Init(p) end
    end
    return p
end
function PANEL:IsValid() return self.valid end
function PANEL:Remove() self.valid = false end
function PANEL:Close() self.valid = false end
function PANEL:GetSize() return 200, 40 end
function PANEL:GetPos() return 0, 0 end
function PANEL:LocalToScreen(x, y) return x, y end
function PANEL:GetChildren() return self.children end
function PANEL:Clear() self.children = {} end
function PANEL:GetParent() return self.parent end
function vgui.Register(name, tbl, base) vgui.registered[name] = {tbl = tbl, base = base} return tbl end
function vgui.Create(name, parent)
    local p = makePanel(name, parent)
    if parent and type(parent) == "table" and parent.children then table.insert(parent.children, p) end
    return p
end
function vgui.GetKeyboardFocus() return nil end
function vgui.GetHoveredPanel() return nil end
MOCK.makePanel = makePanel

-- Drawing ------------------------------------------------------------------------
local noop = function() end
surface = setmetatable({GetTextSize = function() return 40, 12 end, ScreenWidth = function() return 1920 end, ScreenHeight = function() return 1080 end},
    {__index = function() return noop end})
draw = setmetatable({SimpleText = function() return 40, 12 end, SimpleTextOutlined = function() return 40, 12 end, GetFontHeight = function() return 12 end},
    {__index = function() return noop end})
render = setmetatable({}, {__index = function() return noop end})
cam = setmetatable({}, {__index = function() return noop end})
function ScrW() return 1920 end
function ScrH() return 1080 end
function ColorAlpha(c, a) return Color(c.r, c.g, c.b, a) end
function DrawColorModify() end
function DrawBloom() end
function DrawMotionBlur() end
function DisableClipping() end
function Material() return Dummy end
function CreateMaterial() return Dummy end
chat = {AddText = function(...) MOCK.chat = MOCK.chat or {} table.insert(MOCK.chat, {...}) end, PlaySound = noop, Open = noop, Close = noop}
input = setmetatable({IsKeyDown = function() return false end, IsMouseDown = function() return false end, LookupBinding = function() return "F4" end},
    {__index = function() return noop end})
gui = setmetatable({MouseX = function() return 0 end, MouseY = function() return 0 end}, {__index = function() return noop end})
language = {GetPhrase = function(s) return s end, Add = noop}
system = {IsWindows = function() return true end, HasFocus = function() return true end}
function CreateClientConVar(name, default)
    return {GetString = function() return tostring(default) end, GetBool = function() return default == "1" or default == 1 end,
        GetInt = function() return tonumber(default) or 0 end, GetFloat = function() return tonumber(default) or 0 end, SetString = noop}
end
function GetRenderTarget() return Dummy end
function ClientsideModel() return Dummy end
function EyePos() return Vector() end
function EyeAngles() return Angle() end
function RunConsoleCommand() end
function net.SendToServer() end

local VEC = FindMetaTable and getmetatable(Vector())
if VEC then
    local idx = VEC.__index
    if type(idx) == "table" then idx.ToScreen = function() return {x = 0, y = 0, visible = true} end end
end

-- Local player -------------------------------------------------------------------
local localPlayer
function LocalPlayer()
    if not localPlayer then localPlayer = MOCK.addPlayer({name = "LocalPlayer"}) end
    return localPlayer
end

-- Unknown globals are NOT stubbed: a missing one is reported as an error.
usermessage = {Hook = function(name, fn) MOCK.usermessages = MOCK.usermessages or {} MOCK.usermessages[name] = fn end}
notification = {AddLegacy = function() end, AddProgress = function() end, Kill = function() end}

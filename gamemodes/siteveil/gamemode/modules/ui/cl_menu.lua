--[[---------------------------------------------------------------------------
Service system menu (F4, replaces DarkRP's F4 menu) and help (F1).

Tabs are registered by modules:
    UI.registerTab{id = "inventory", name = "Инвентарь", order = 20,
        visible = function(ply) return true end, build = function(panel) end}
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local S = UI.S

UI.tabs = UI.tabs or {}

function UI.registerTab(def)
    for i, t in ipairs(UI.tabs) do
        if t.id == def.id then table.remove(UI.tabs, i) break end
    end
    table.insert(UI.tabs, def)
    table.sort(UI.tabs, function(a, b) return a.order < b.order end)
end

function UI.closeMenu()
    if IsValid(UI.menuPanel) then UI.menuPanel:Close() end
end

function UI.openMenu(tabId)
    if not UI.myChar() then
        UI.openCharMenu()
        return
    end
    if IsValid(UI.menuPanel) then
        if tabId then UI.menuPanel.tabs:Select(tabId) end
        return
    end

    local ply = LocalPlayer()
    local f = vgui.Create("SVFrame")
    UI.menuPanel = f
    local char = UI.myChar()
    f:SetHeader("СЛУЖЕБНАЯ СИСТЕМА", char.name .. " · № " .. char.number)
    f:SetSize(math.min(ScrW() - S(40), S(1280)), math.min(ScrH() - S(40), S(800)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f.OnClose = function() UI.menuPanel = nil end

    local tabs = vgui.Create("SVTabs", f)
    tabs:Dock(FILL)
    f.tabs = tabs
    for _, t in ipairs(UI.tabs) do
        if not t.visible or t.visible(ply) then
            tabs:AddTab(t.id, t.name, t.build, t.note and t.note(ply) or nil)
        end
    end
    if tabId then tabs:Select(tabId) end
end

function UI.toggleMenu()
    if IsValid(UI.menuPanel) then UI.closeMenu() else UI.openMenu() end
end

--- Rebuilds the open tab when its data arrives from the server.
function UI.refreshTab(id)
    local f = UI.menuPanel
    if IsValid(f) and f.tabs.active == id then f.tabs:Rebuild() end
end

function GM:ShowHelp()
    UI.openMenu("help")
end

-- F2: quick access to the service ID.
function GM:ShowTeam()
    UI.openMenu("character")
end

hook.Add("SiteVeil.Sync", "SiteVeil.UI.MenuTitle", function(channel, key, value)
    if channel == "self" and key == "char" then
        if value == nil then
            UI.closeMenu()
        elseif IsValid(UI.menuPanel) then
            UI.menuPanel:SetHeader("СЛУЖЕБНАЯ СИСТЕМА", value.name .. " · № " .. value.number)
        end
    end
end)

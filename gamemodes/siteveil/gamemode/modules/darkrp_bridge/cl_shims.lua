--[[---------------------------------------------------------------------------
Client-side implementations of interface stubs of disabled DarkRP modules
(f1menu, f4menu, hitmenu). F1 and F4 open the SITE-VEIL service system.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local plyMeta = FindMetaTable("Player")

function DarkRP.openF4Menu()
    if SV.UI and SV.UI.openMenu then SV.UI.openMenu() end
end

function DarkRP.closeF4Menu()
    if SV.UI and SV.UI.closeMenu then SV.UI.closeMenu() end
end

function DarkRP.toggleF4Menu()
    if SV.UI and SV.UI.toggleMenu then SV.UI.toggleMenu() end
end

function DarkRP.getF4MenuPanel()
    return SV.UI and SV.UI.menuPanel or nil
end

-- The SITE-VEIL menu is built from its own tab registry (modules/ui).
function DarkRP.addF4MenuTab() end
function DarkRP.removeF4MenuTab() end
function DarkRP.switchTabOrder() end

function DarkRP.openF1Menu()
    if SV.UI and SV.UI.openMenu then SV.UI.openMenu("help") end
end

function DarkRP.closeF1Menu()
    if SV.UI and SV.UI.closeMenu then SV.UI.closeMenu() end
end

function DarkRP.refreshF1Menu() end

function DarkRP.openHitMenu() end
function plyMeta:drawHitInfo() end
function plyMeta:stopHitInfo() end

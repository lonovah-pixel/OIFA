--[[---------------------------------------------------------------------------
Interaction menu (right click with empty hands on a player) and the HUD
hint for entities the player looks at.

Modules register entries:
    UI.registerInteraction{id = "give", name = "Передать предмет", order = 10,
        visible = function(target) return true end,
        blocked = function(target) return nil or "причина" end,
        action = function(target) ... end}
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S

UI.interactions = UI.interactions or {}

function UI.registerInteraction(def)
    for i, d in ipairs(UI.interactions) do
        if d.id == def.id then table.remove(UI.interactions, i) break end
    end
    table.insert(UI.interactions, def)
    table.sort(UI.interactions, function(a, b) return a.order < b.order end)
end

function UI.openInteraction(target)
    if IsValid(UI.interactionPanel) then UI.interactionPanel:Remove() end
    if not IsValid(target) or not target:IsPlayer() then return end
    local f = vgui.Create("SVFrame")
    UI.interactionPanel = f
    f:SetHeader("ВЗАИМОДЕЙСТВИЕ", SV.Chars.displayName(target))
    f:SetSize(S(420), S(120))
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    local count = 0
    for _, d in ipairs(UI.interactions) do
        if not d.visible or d.visible(target) then
            local b = UI.button(f, d.name, function()
                f:Close()
                if IsValid(target) then d.action(target) end
            end)
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, S(6))
            local reason = d.blocked and d.blocked(target)
            if reason then b:SetBlocked(reason) end
            count = count + 1
        end
    end
    if count == 0 then UI.text(f, "Нет доступных действий.", "SV.Body", C.dim) count = 1 end
    f:SetTall(S(56) + count * S(40))
    f:Center()
end

--- Simple chooser dialog: options = {{label, value, blocked}}; onPick(value).
function UI.choose(title, text, options, onPick)
    local f = vgui.Create("SVFrame")
    f:SetHeader(title)
    f:SetSize(S(460), math.min(S(110) + #options * S(40) + (text and S(40) or 0), ScrH() * 0.8))
    f:Center()
    f:MakePopup()
    if text then UI.text(f, text, "SV.Small", C.dim) end
    local list = UI.scroll(f)
    for _, o in ipairs(options) do
        local b = UI.button(list, o[1], function()
            f:Close()
            onPick(o[2])
        end)
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, S(6))
        if o[3] then b:SetBlocked(o[3]) end
    end
    return f
end

--- Players within distance of the local player (excluding self).
function UI.nearbyPlayers(dist)
    local me = LocalPlayer()
    local out = {}
    for _, p in ipairs(player.GetAll()) do
        if p ~= me and p:Alive() and p:GetPos():DistToSqr(me:GetPos()) <= dist * dist and not SV.Roles.isLobby(p) then
            out[#out + 1] = p
        end
    end
    table.sort(out, function(a, b) return a:GetPos():DistToSqr(me:GetPos()) < b:GetPos():DistToSqr(me:GetPos()) end)
    return out
end

-- Entity look-at hints (items, lockers, terminals, nodes ...).
UI.hudElement("lookat", 61, function(ply)
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or ent:IsPlayer() then return end
    if tr.StartPos:DistToSqr(tr.HitPos) > 140 * 140 then return end
    hook.Run("SiteVeil.HUDLookAt", ent, ScrW() / 2, ScrH() / 2 + S(30))
end)

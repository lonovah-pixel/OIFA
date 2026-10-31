--[[---------------------------------------------------------------------------
CCTV (client): monitor window, camera overlay and controls.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

Net.on("cctv.open", function(data)
    local ent = Entity(data.ent)
    local f = vgui.Create("SVFrame")
    f:SetHeader("ПОСТ ВИДЕОНАБЛЮДЕНИЯ")
    f:SetSize(S(520), math.min(S(560), ScrH() * 0.8))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    if #data.cameras == 0 then UI.text(scroll, "Камеры не настроены администрацией.", "SV.Body", C.dim) end
    for _, cam in ipairs(data.cameras) do
        local b = UI.button(scroll, cam.name .. (cam.sector and (" · " .. cam.sector) or ""), function()
            Net.call("cctv.view", ent, cam.index)
            f:Close()
        end)
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, S(4))
        if not cam.powered then b:SetBlocked("нет сигнала") end
    end
    UI.text(scroll, "Внимание: не смотрите на SCP-096 через камеры вне его камеры содержания.", "SV.Tiny", C.warn)
end)

UI.hudElement("cctv", 2, function()
    local v = SV.Sync.get("self", "cctv")
    if not v then return end
    surface.SetDrawColor(0, 0, 0, 120)
    surface.DrawRect(0, 0, ScrW(), S(40))
    draw.SimpleText("● REC  " .. v.name .. "  (" .. v.index .. "/" .. v.count .. ")", "SV.HUD", S(20), S(8), C.danger)
    draw.SimpleText("Колесо мыши — другая камера · ПКМ или E — выход", "SV.Tiny", ScrW() - S(20), S(14), C.text, TEXT_ALIGN_RIGHT)
    draw.SimpleText(os.date("%H:%M:%S"), "SV.Mono", S(20), ScrH() - S(40), C.text)
end)

hook.Add("PlayerBindPress", "SiteVeil.Cctv", function(_, bind, pressed)
    local v = SV.Sync.get("self", "cctv")
    if not v or not pressed then return end
    local terminal = Entity(v.terminal)
    if bind == "invnext" or bind == "invprev" then
        local i = v.index + (bind == "invnext" and 1 or -1)
        if i < 1 then i = v.count elseif i > v.count then i = 1 end
        Net.call("cctv.view", terminal, i)
        return true
    elseif string.find(bind, "+attack2", 1, true) or string.find(bind, "+use", 1, true) then
        Net.call("cctv.stop")
        return true
    end
end)

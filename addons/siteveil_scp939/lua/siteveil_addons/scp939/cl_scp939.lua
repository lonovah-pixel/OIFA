--[[---------------------------------------------------------------------------
SCP-939 (client): the blind picture - darkness with noises drawn as
pulsing marks; ability hints.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local SCP = SV.SCP

SCP.hints.scp939 = {"Вы слепы: видите только звуки", "ЛКМ — атака", "ПКМ — голос-приманка там, куда вы смотрите"}

local heard = {}
SV.Net.on("scp939.heard", function(data) heard = data.list or {} end)

UI.hudElement("scp939", 0, function(ply)
    if SCP.of(ply) ~= "scp939" or not ply:Alive() then return end
    surface.SetDrawColor(0, 0, 0, 235)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    for _, n in ipairs(heard) do
        local scr = Vector(n.pos[1], n.pos[2], n.pos[3] + 40):ToScreen()
        if scr.visible then
            local r = UI.S(10 + n.weight * 8) * (1 + math.sin(RealTime() * 6) * 0.2)
            draw.SimpleText("◉", "SV.Banner", scr.x, scr.y, ColorAlpha(C.danger, math.Clamp(255 - n.age * 50, 60, 255)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            surface.SetDrawColor(C.danger)
            surface.DrawOutlinedRect(scr.x - r, scr.y - r, r * 2, r * 2)
        end
    end
end)

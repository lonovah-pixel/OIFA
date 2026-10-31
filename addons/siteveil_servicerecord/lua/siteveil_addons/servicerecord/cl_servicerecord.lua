--[[---------------------------------------------------------------------------
Service record (client): personal file window, interaction entries.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net
local K = SV.Config.ServiceRecord

Net.on("srec.view", function(v)
    if IsValid(UI.srecFrame) then UI.srecFrame:Remove() end
    local f = vgui.Create("SVFrame")
    UI.srecFrame = f
    f:SetHeader("ЛИЧНОЕ ДЕЛО", v.name .. " · № " .. (v.number or "—"))
    f:SetSize(S(600), math.min(S(640), ScrH() * 0.85))
    f:Center()
    f:MakePopup()
    local scroll = UI.scroll(f)
    UI.text(scroll, "Действующих взысканий: " .. v.active .. ". При " .. v.limit .. " и более повышение задерживается.", "SV.Small",
        v.active >= v.limit and C.danger or C.dim)
    local target = Entity(v.target)
    local row = UI.row(scroll, S(34))
    for _, kind in ipairs({"commendation", "reprimand"}) do
        local b = UI.button(row, K.kinds[kind], function()
            UI.prompt(string.upper(K.kinds[kind]), "Основание будет видно сотруднику и в личном деле.", "Основание (не менее " .. K.reasonMin .. " символов)",
                function(text) Net.call("srec.issue", target, kind, text) end, {style = kind == "reprimand" and "danger" or "primary"})
        end, kind == "reprimand" and "danger" or "primary")
        b:Dock(LEFT)
        b:SetWide(S(200))
        b:DockMargin(0, 0, S(6), 0)
        if not v.canIssue[kind] then b:SetBlocked("нет полномочий или лимит") end
    end
    if #v.records == 0 then UI.text(scroll, "Записей нет.", "SV.Small", C.dim) end
    for _, r in ipairs(v.records) do
        local card = UI.card(scroll, r.kindName .. " · " .. r.when .. " · " .. (r.by or "?"), r.revoked and C.faint or (r.kind == "reprimand" and C.danger or C.ok))
        UI.text(card, r.reason, "SV.Body", r.revoked and C.faint or C.text)
        if r.revoked then UI.text(card, "Отменено: " .. r.revoked, "SV.Tiny", C.faint) end
        if r.canRevoke then
            local rv = UI.button(card, "Отменить запись", function()
                UI.prompt("ОТМЕНА ЗАПИСИ", nil, "Основание отмены", function(text) Net.call("srec.revoke", r.id, text) end)
            end, "ghost")
            rv:Dock(TOP)
        end
    end
end)

UI.registerInteraction{
    id = "servicerecord", name = "Личное дело сотрудника", order = 60,
    visible = function(target) return not SV.Roles.isSCP(target) end,
    action = function(target) Net.call("srec.view", target) end,
}

concommand.Add("sv_myrecord", function() Net.call("srec.view", LocalPlayer()) end)

table.insert(UI.helpSections, {"Личное дело", {
    "Консоль sv_myrecord — своё личное дело; меню взаимодействия → «Личное дело сотрудника» (для начальства).",
    "Два действующих взыскания задерживают повышение; благодарность даёт опыт.",
}})

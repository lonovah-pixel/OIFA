--[[---------------------------------------------------------------------------
Class-D labor (client): mini-game windows.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local UI = SV.UI
local C = UI.Colors
local S = UI.S
local Net = SV.Net

local function frame(data)
    if IsValid(UI.laborFrame) then UI.laborFrame:Remove() end
    local f = vgui.Create("SVFrame")
    UI.laborFrame = f
    f:SetHeader(string.upper(data.name), "до " .. data.timeLimit .. " с")
    f:SetSize(S(560), S(360))
    f:Center()
    f:MakePopup()
    UI.text(f, data.hint, "SV.Small", C.dim)
    return f
end

local function progressText(f, answer, total)
    if IsValid(f.progress) then f.progress:SetText("Выполнено: " .. #answer .. " / " .. total) end
end

local builders = {}

builders.sorting = function(f, data)
    local answer = {}
    local row = UI.row(f, S(40))
    for i, s in ipairs(data.items) do
        local lbl = vgui.Create("DLabel", row)
        lbl:Dock(LEFT)
        lbl:SetWide(S(60))
        lbl:SetFont("SV.Title")
        lbl:SetText(data.symbols[s])
        lbl:SetTextColor(i == 1 and C.accent or C.text)
    end
    f.progress = UI.text(f, "", "SV.Small")
    local bins = UI.row(f, S(48))
    for i, sym in ipairs(data.symbols) do
        local b = UI.button(bins, sym, function()
            answer[#answer + 1] = i
            progressText(f, answer, #data.items)
            if #answer == #data.items then
                Net.call("labor.answer", data.id, answer)
                f:Close()
            end
        end)
        b:Dock(LEFT)
        b:SetWide(S(120))
        b:DockMargin(0, 0, S(6), 0)
    end
    progressText(f, answer, #data.items)
end

builders.assembly = function(f, data)
    local answer = {}
    f.progress = UI.text(f, "", "SV.Small")
    local row = UI.row(f, S(48))
    for i, n in ipairs(data.numbers) do
        local b
        b = UI.button(row, tostring(n), function()
            answer[#answer + 1] = i
            b:SetBlocked("установлена")
            progressText(f, answer, #data.numbers)
            if #answer == #data.numbers then
                Net.call("labor.answer", data.id, answer)
                f:Close()
            end
        end)
        b:Dock(LEFT)
        b:SetWide(S(96))
        b:DockMargin(0, 0, S(6), 0)
    end
    progressText(f, answer, #data.numbers)
end

builders.cleaning = function(f, data)
    local dirty, picked = {}, {}
    for _, c in ipairs(data.dirty) do dirty[c] = true end
    f.progress = UI.text(f, "", "SV.Small")
    local side = math.floor(math.sqrt(data.grid) + 0.5)
    for r = 1, side do
        local row = UI.row(f, S(44))
        for c = 1, side do
            local idx = (r - 1) * side + c
            local b
            b = UI.button(row, dirty[idx] and "грязно" or "чисто", function()
                picked[#picked + 1] = idx
                b:SetBlocked("отмечено")
                progressText(f, picked, #data.dirty)
                if #picked == #data.dirty then
                    Net.call("labor.answer", data.id, picked)
                    f:Close()
                end
            end, dirty[idx] and "danger" or nil)
            b:Dock(LEFT)
            b:SetWide(S(150))
            b:DockMargin(0, 0, S(6), 0)
        end
    end
    progressText(f, picked, #data.dirty)
end

Net.on("labor.challenge", function(data)
    local build = builders[data.job]
    if not build then return end
    build(frame(data), data)
end)

--[[---------------------------------------------------------------------------
Notes and notice boards (server).

Notes: a player writes a note that appears in front of them. Anybody can
read it (E); players do not see the author, admins do. The author, or
staff with the search flag, can take it away. Limits per character and for
the map; notes expire. Boards (map point kind "board", optional prop
"division"): signed posts, limited per character and per board, removable
by the author, division heads and admins. Everything is in memory (gone
after a restart) and audited.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Notes = SV.Notes
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Notes
local Roles = SV.Roles

SV.MapCfg.editorProps.board = {name = true, division = true}

Notes.world = Notes.world or {}     -- note entity -> record
Notes.boards = Notes.boards or {}   -- board entity -> {posts = {...}, nextId}

local function countNotes(charId)
    local n = 0
    for ent, r in pairs(Notes.world) do
        if not IsValid(ent) then Notes.world[ent] = nil elseif r.char == charId then n = n + 1 end
    end
    return n
end

local function removeOldestNote()
    local oldest, at
    for ent, r in pairs(Notes.world) do
        if IsValid(ent) and (not at or r.created < at) then oldest, at = ent, r.created end
    end
    if oldest then
        Notes.world[oldest] = nil
        oldest:Remove()
    end
end

function Notes.write(ply, title, text)
    title = U.cleanText(title, K.titleMax)
    text = U.cleanText(text, K.textMax)
    if U.utf8len(text) < 3 then return false, "Записка пуста." end
    if title == "" then title = "Записка" end
    if (ply.SVNoteAt or -1e9) + K.writeCooldown > CurTime() then return false, "Не так быстро." end
    if countNotes(ply.SVChar.id) >= K.perCharacter then return false, "Вы уже оставили " .. K.perCharacter .. " записки." end
    if U.count(Notes.world) >= K.worldMax then removeOldestNote() end
    local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 70, filter = ply})
    local ent = ents.Create("sv_note")
    if not IsValid(ent) then return false end
    ent:SetPos(tr.HitPos + Vector(0, 0, 2))
    ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ent:SetNoteTitle(title)
    ent:Spawn()
    ply.SVNoteAt = CurTime()
    Notes.world[ent] = {char = ply.SVChar.id, author = ply.SVChar.name, steam = ply:SteamID64(), title = title, text = text, created = CurTime()}
    SV.Audit.log("notes", "write", ply, nil, {title = title, text = text})
    return true, "Записка оставлена."
end

Net.handle("notes.write", function(ply, title, text) return Notes.write(ply, title, text) end)

Net.handle("notes.read", function(ply, ent)
    local r = IsValid(ent) and Notes.world[ent]
    if not r then return false end
    if not U.within(ply, ent, 120) then return false, "Подойдите ближе." end
    local admin = SV.Admin.isOnDuty(ply)
    Net.send(ply, "notes.text", {ent = ent:EntIndex(), title = r.title, text = r.text, minutes = math.floor((CurTime() - r.created) / 60),
        author = admin and (r.author .. " (" .. r.steam .. ")") or nil, own = ply.SVChar and ply.SVChar.id == r.char,
        canTake = (ply.SVChar and ply.SVChar.id == r.char) or Roles.hasFlag(ply, "search") or admin})
    SV.Bus.emit("notes.read", {ply = ply, note = ent})
end)

Net.handle("notes.take", function(ply, ent)
    local r = IsValid(ent) and Notes.world[ent]
    if not r then return false end
    if not U.within(ply, ent, 120) then return false, "Подойдите ближе." end
    local own = ply.SVChar and ply.SVChar.id == r.char
    if not own and not Roles.hasFlag(ply, "search") and not SV.Admin.isOnDuty(ply) then return false, "Убрать записку могут автор и охрана." end
    Notes.world[ent] = nil
    ent:Remove()
    SV.Audit.log("notes", "take", ply, nil, {title = r.title, author = r.author})
    return true, own and "Вы забрали записку." or "Записка изъята."
end)

timer.Create("SiteVeil.Notes.Expire", 30, 0, function()
    local now = CurTime()
    for ent, r in pairs(Notes.world) do
        if not IsValid(ent) then
            Notes.world[ent] = nil
        elseif now - r.created > K.lifetime then
            Notes.world[ent] = nil
            ent:Remove()
        end
    end
    for _, b in pairs(Notes.boards) do
        for i = #b.posts, 1, -1 do
            if now - b.posts[i].created > K.boardLifetime then table.remove(b.posts, i) end
        end
    end
end)

--[[---------------------------------------------------------------------------
Notice boards
---------------------------------------------------------------------------]]
function Notes.registerBoard(ent) Notes.boards[ent] = {posts = {}, nextId = 1} end
function Notes.unregisterBoard(ent) Notes.boards[ent] = nil end

local function boardDivision(ent)
    return ent.SVPoint and ent.SVPoint.props.division or nil
end

local function canModerate(ply, ent)
    if SV.Admin.isOnDuty(ply) then return true end
    local div = boardDivision(ent)
    return Roles.hasFlag(ply, "divisionHead") and (not div or (ply.SVChar and ply.SVChar.division == div))
end

local function boardView(ply, ent)
    local b = Notes.boards[ent]
    local posts = {}
    for i = #b.posts, 1, -1 do
        local p = b.posts[i]
        posts[#posts + 1] = {id = p.id, author = p.author, division = p.division, text = p.text, when = U.clockString(p.time),
            canRemove = (ply.SVChar and ply.SVChar.id == p.char) or canModerate(ply, ent)}
    end
    local div = boardDivision(ent)
    local d = div and Roles.getDivision(div)
    return {ent = ent:EntIndex(), title = (ent.SVPoint and ent.SVPoint.props.name) or (d and ("Доска: " .. d.name)) or "Доска объявлений",
        posts = posts, canPost = div == nil or (ply.SVChar and ply.SVChar.division == div) or canModerate(ply, ent)}
end

Net.handle("board.view", function(ply, ent)
    if not IsValid(ent) or not Notes.boards[ent] then return false end
    if not U.within(ply, ent, 150) then return false, "Подойдите к доске." end
    Net.send(ply, "board.view", boardView(ply, ent))
end)

Net.handle("board.post", function(ply, ent, text)
    local b = IsValid(ent) and Notes.boards[ent]
    if not b then return false end
    if not U.within(ply, ent, 150) then return false, "Подойдите к доске." end
    if not boardView(ply, ent).canPost then return false, "Это доска другого подразделения." end
    text = U.cleanText(text, K.boardPostMax)
    if U.utf8len(text) < 5 then return false, "Объявление слишком короткое." end
    local mine = 0
    for _, p in ipairs(b.posts) do if p.char == ply.SVChar.id then mine = mine + 1 end end
    if mine >= K.boardPostsPerCharacter then return false, "У вас уже " .. K.boardPostsPerCharacter .. " объявления на этой доске." end
    if #b.posts >= K.boardMax then table.remove(b.posts, 1) end
    local div = Roles.getDivision(ply.SVChar.division)
    table.insert(b.posts, {id = b.nextId, char = ply.SVChar.id, author = SV.Chars.displayName(ply), division = div and div.short or "",
        text = text, time = os.time(), created = CurTime()})
    b.nextId = b.nextId + 1
    SV.Audit.log("notes", "board.post", ply, nil, {text = text})
    Net.send(ply, "board.view", boardView(ply, ent))
    return true
end)

Net.handle("board.remove", function(ply, ent, id)
    local b = IsValid(ent) and Notes.boards[ent]
    if not b then return false end
    for i, p in ipairs(b.posts) do
        if p.id == id then
            if not ((ply.SVChar and ply.SVChar.id == p.char) or canModerate(ply, ent)) then return false, "Нет прав снять объявление." end
            table.remove(b.posts, i)
            SV.Audit.log("notes", "board.remove", ply, nil, {text = p.text, author = p.author})
            Net.send(ply, "board.view", boardView(ply, ent))
            return true
        end
    end
    return false, "Объявление не найдено."
end)

SV.Perf.registry("notes.world", function() return U.count(Notes.world) end)

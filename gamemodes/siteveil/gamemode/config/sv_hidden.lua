--[[---------------------------------------------------------------------------
"Двойные задачи" (SERVER ONLY): optional hidden tasks. See BALANCE.md.

Rules enforced by modules/hidden/sv_hidden.lua:
  - only for players who opted in (character tab), never forced;
  - an offer can be declined, an accepted task abandoned - no penalty;
  - no task asks to kill, injure, destroy or sabotage permanently;
  - every task leaves something for the other side to find (stash traces,
    leak records, a person who notices being followed);
  - per character limits, a server-wide limit, a time limit; admins can
    switch the system off (admin panel / sv_hidden_tasks 0).

Objective types:
  stash     bring an item (`item`, optionally a document printed by you
            from clearance >= `minClearance`) to a stash point and leave it
  visit     stay `hold` seconds at a point of `points` kind outside your
            sector with nobody who can detain within `unseenRadius`
  shadow    stay within `radius` of a chosen colleague for `hold` seconds
  event     perform a bus event (`event`, optional `match`)
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Hidden = {
    enabled = true,
    offerInterval = 300,      -- seconds between offer rounds
    offerChance = 0.35,
    minOnline = 8,
    minOnShift = 300,         -- seconds in the role before the first offer
    perShift = 2,             -- per character
    maxActive = 3,            -- whole server
    declineCooldown = 900,
    offerTimeout = 60,
    timeLimit = 900,
    stashRadius = 120,
    xpSource = "hidden",
}

C.HiddenTasks = {
    {
        id = "leak_document", name = "Утечка документа", type = "stash", weight = 3,
        divisions = {"science", "administration", "engineering"},
        text = "Неизвестный предлагает обмен: распечатайте раздел досье с допуском не ниже 2 и оставьте его в тайнике.",
        item = "document", minClearance = 2, xp = 40,
    },
    {
        id = "smuggle_parts", name = "Контрабанда запчастей", type = "stash", weight = 3,
        divisions = {"classd"},
        text = "Сокамерники просят добыть запасные части и оставить их в тайнике.",
        item = "spare_parts", xp = 30,
    },
    {
        id = "recon", name = "Разведка маршрута", type = "visit", weight = 2,
        divisions = {"classd", "engineering"},
        text = "Кто-то хочет знать, где стоит охрана: постойте у поста в чужом секторе, оставаясь незамеченным.",
        points = {"checkpoint"}, hold = 20, unseenRadius = 500, xp = 25,
    },
    {
        id = "shadow_audit", name = "Негласная проверка", type = "shadow", weight = 3,
        flags = {"audit"},
        text = "Отдел внутренней безопасности поручает негласно понаблюдать за сотрудником.",
        radius = 700, hold = 90, xp = 35,
    },
    {
        id = "false_hypothesis", name = "Ложный след", type = "event", weight = 2,
        divisions = {"science"},
        text = "Конкурирующая группа просит внести в досье правдоподобную, но ложную гипотезу.",
        event = "dossier.submitted", match = {kind = "hypothesis"}, xp = 25,
    },
    {
        id = "archive_copy", name = "Копия из архива", type = "event", weight = 2,
        divisions = {"engineering", "medical", "security"},
        text = "Друг из другого отдела просит заглянуть в архивный терминал и пересказать, что там.",
        event = "terminal.used", match = {kind = "records"}, xp = 20,
    },
}

--[[---------------------------------------------------------------------------
Emotes (shared): catalogue and network schema. `act` names are engine
ACT_* enums resolved on the client; `text` is shown to people nearby.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Emotes = SV.Emotes or {}
local Net = SV.Net

SV.Config.Emotes = {
    cooldown = 2,
    textRange = 350,
    animRange = 2500,
    offerTimeout = 20,
    list = {
        {id = "wave", name = "Помахать", act = "ACT_GMOD_GESTURE_WAVE", text = "машет рукой"},
        {id = "salute", name = "Отдать честь", act = "ACT_GMOD_TAUNT_SALUTE", text = "отдаёт честь"},
        {id = "agree", name = "Кивнуть", act = "ACT_GMOD_GESTURE_AGREE", text = "кивает"},
        {id = "disagree", name = "Покачать головой", act = "ACT_GMOD_GESTURE_DISAGREE", text = "качает головой"},
        {id = "beckon", name = "Подозвать", act = "ACT_GMOD_GESTURE_BECON", text = "подзывает жестом"},
        {id = "halt", name = "Стоп", act = "ACT_SIGNAL_HALT", text = "показывает жест «стоп»"},
        {id = "forward", name = "Вперёд", act = "ACT_SIGNAL_FORWARD", text = "указывает вперёд"},
        {id = "group", name = "Собраться", act = "ACT_SIGNAL_GROUP", text = "даёт знак собраться"},
        {id = "bow", name = "Поклониться", act = "ACT_GMOD_GESTURE_BOW", text = "кланяется"},
        {id = "laugh", name = "Засмеяться", act = "ACT_GMOD_TAUNT_LAUGH", text = "смеётся"},
    },
}

SV.Emotes.byId = {}
for _, e in ipairs(SV.Config.Emotes.list) do SV.Emotes.byId[e.id] = e end

Net.define("emote.play", {args = {"str:16"}, alive = true, rate = {burst = 3, refill = 0.5}, rateMessage = false})
Net.define("emote.offer", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.2}})
Net.define("emote.answer", {args = {"bool"}, alive = true, rate = {burst = 3, refill = 0.5}})

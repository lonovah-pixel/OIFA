--[[---------------------------------------------------------------------------
SCP-999 content (SERVER ONLY): dossier and research protocol.

The dossier text is an original Russian summary written for SITE-VEIL,
based on SCP-999 of the SCP Foundation (scp-wiki.wikidot.com/scp-999,
CC BY-SA 3.0), and is licensed under CC BY-SA 3.0. See THIRD_PARTY.md.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Dossiers.scp999 = {
    title = "SCP-999 «Щекоточный монстр»", class = "Безопасный",
    sections = {
        {id = "desc", clearance = 0, kind = "open", title = "Описание",
            text = "Студенистое существо оранжевого цвета массой около пятидесяти килограммов. Дружелюбно ко всем, кого встречает; прикосновение объекта вызывает у людей чувство радости."},
        {id = "procedures", clearance = 1, kind = "clearance", title = "Особые условия содержания",
            text = "Объект содержится в просторной камере и может свободно общаться с персоналом. Требуются регулярные посещения и сладости. Запирание объекта без общения ухудшает его состояние."},
        {id = "effect", clearance = 2, kind = "clearance", title = "Воздействие",
            text = "Контакт с объектом снимает боль и тревогу. Объект стремится к людям в беде, в том числе во время инцидентов, и не проявляет агрессии."},
    },
    facts = {
        mood = {title = "Настроение персонала", clearance = 1, text = "После контакта с объектом сотрудники заметно спокойнее и работают сосредоточеннее."},
        sweets = {title = "Сладости", clearance = 1, text = "Объект охотно следует за человеком со сладостями — это самый надёжный способ вернуть его в камеру."},
        calm = {title = "Успокоение объектов", clearance = 3, text = "Присутствие SCP-999 рядом с возбуждённым SCP-096 сокращает приступ."},
    },
}

local function cellPowered()
    return SV.Facility.devicePowered(SV.SCP.cellSector("scp999"), "containment")
end

SV.Research.registerProtocol({
    id = "p999_mood", name = "Влияние SCP-999 на настроение персонала", subject = "scp999", zone = "cell",
    danger = 1, clearance = 1, cooldown = 600,
    desc = "Испытуемый проводит время с объектом, исследователь фиксирует изменения настроения. Подходит для малого онлайна.",
    participants = {{category = "classd", min = 1, label = "Испытуемый"}, {category = "science", min = 1, label = "Наблюдатель"}},
    equipment = {required = {}, optional = {sensor_kit = 0.2, sweets = 0.1}},
    environment = {
        {id = "power", text = "Питание замка камеры", riskIfNot = 0.1, check = cellPowered},
    },
    safety = {},
    steps = {
        {id = "enter", name = "Ввод испытуемого", by = "lead", time = 5},
        {id = "contact", name = "Контакт с объектом", by = "classd", time = 15},
        {id = "record", name = "Запись наблюдений", by = "lead", time = 5},
    },
    outcomes = {
        {id = "data", name = "Описано влияние на настроение", kind = "data", weight = 50, fact = "mood", reward = {xp = 20, budget = 10},
            text = "Испытуемый спокоен и разговорчив."},
        {id = "partial", name = "Объект отвлёкся на сладости", kind = "partial", weight = 25, fact = "sweets", reward = {xp = 15},
            text = "Объект всё время тянулся к сладостям."},
        {id = "none", name = "Объект спал", kind = "none", weight = 15, reward = {xp = 5}, text = "Контакта не было."},
        {id = "stuck", name = "Инцидент: испытуемого не отпускают", kind = "incident", weight = 5, reward = {xp = 5},
            text = "Объект обнял испытуемого и долго не отпускал.",
            effect = function(ctx)
                local p = ctx.byCategory.classd[1]
                if IsValid(p) then
                    SV.Move.set(p, "scp999", {speed = 0.6})
                    timer.Simple(30, function() if IsValid(p) then SV.Move.clear(p, "scp999") end end)
                end
            end},
        {id = "discovery", name = "Объект успокаивает другие объекты", kind = "discovery", weight = 5, fact = "calm", unlock = "calm_boost",
            reward = {xp = 40, budget = 30}, text = "Успокоение SCP-999 перезаряжается вдвое быстрее."},
    },
})

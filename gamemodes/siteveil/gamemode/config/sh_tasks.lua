--[[---------------------------------------------------------------------------
Duty tasks (штатные задачи) - shared definitions.

Objective types (implemented in modules/tasks/sv_tasks.lua):
  visit   visit `count` distinct map points of `point` kind
  event   `count` bus events `event` performed by the player
          (data.ply == player; optional `match` table compared to data)

Fields:
  roles / divisions  who can take the task (nil = everyone with a character)
  reward             {xp = n, budget = n (division budget), source = cap key}
  perShift           how many times one character may complete it per shift
  minOnline          hide the task on small servers
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

-- Experience caps per shift and source (anti-farm). "default" applies to
-- every source without its own cap.
C.XPCaps = {
    default = 150,
    task = 200,
    research = 250,
    medical = 150,
    engineering = 200,
    security = 200,
    hidden = 120,
    evacuation = 60,
}

C.Tasks = {
    maxActive = 2,
    visitRadius = 110,
    visitCheckInterval = 1,
}

C.TaskList = {
    {
        id = "orientation", name = "Ознакомительный обход",
        description = "Пройдите по постам комплекса, чтобы знать расположение секторов. Обязателен для новых сотрудников, засчитывается раз в смену.",
        objective = {type = "visit", point = "checkpoint", count = 3},
        reward = {xp = 25, source = "task"}, perShift = 1,
    },
    {
        id = "sec_patrol", name = "Патрулирование постов",
        description = "Обойдите посты и проверьте обстановку. Сообщайте о нарушениях по рации.",
        divisions = {"security", "mtf"},
        objective = {type = "visit", point = "checkpoint", count = 4},
        reward = {xp = 40, budget = 25, source = "security"}, perShift = 3,
    },
    {
        id = "sec_checks", name = "Проверка пропусков",
        description = "Проверьте удостоверения у трёх сотрудников (действие «Проверить документы» в меню взаимодействия).",
        divisions = {"security"},
        objective = {type = "event", event = "security.idChecked", count = 3},
        reward = {xp = 35, source = "security"}, perShift = 2,
    },
    {
        id = "eng_inspect", name = "Профилактика узлов",
        description = "Проведите диагностику трёх инфраструктурных узлов инструментом техника.",
        divisions = {"engineering"},
        objective = {type = "event", event = "node.diagnosed", count = 3},
        reward = {xp = 40, budget = 30, source = "engineering"}, perShift = 3,
    },
    {
        id = "eng_repair", name = "Устранение неисправностей",
        description = "Отремонтируйте два повреждённых узла.",
        divisions = {"engineering"},
        objective = {type = "event", event = "node.repaired", count = 2},
        reward = {xp = 60, budget = 40, source = "engineering"}, perShift = 3,
    },
    {
        id = "med_checkup", name = "Плановый медосмотр",
        description = "Проведите медосмотр трёх сотрудников медицинским сканером.",
        divisions = {"medical"},
        objective = {type = "event", event = "medical.examined", count = 3},
        reward = {xp = 35, budget = 20, source = "medical"}, perShift = 2,
    },
    {
        id = "med_treat", name = "Помощь пострадавшим",
        description = "Окажите медицинскую помощь двум сотрудникам (перевязка, шина, вывод из недееспособности).",
        divisions = {"medical"},
        objective = {type = "event", event = "medical.treated", count = 2},
        reward = {xp = 45, source = "medical"}, perShift = 3,
    },
    {
        id = "sci_experiment", name = "Проведение эксперимента",
        description = "Проведите или помогите провести эксперимент по утверждённому протоколу.",
        divisions = {"science"},
        objective = {type = "event", event = "experiment.participated", count = 1},
        reward = {xp = 50, budget = 30, source = "research"}, perShift = 3,
    },
    {
        id = "sci_report", name = "Отчёт о наблюдении",
        description = "Внесите наблюдение или гипотезу в досье SCP через исследовательский терминал.",
        divisions = {"science"},
        objective = {type = "event", event = "dossier.submitted", count = 1},
        reward = {xp = 30, source = "research"}, perShift = 2,
    },
    {
        id = "d_cleanup", name = "Наряд на уборку",
        description = "Выполните уборку в трёх точках сектора (взаимодействие с отмеченными постами).",
        divisions = {"classd"},
        objective = {type = "visit", point = "checkpoint", count = 3},
        reward = {xp = 30, source = "task"}, perShift = 3,
    },
    {
        id = "d_cargo", name = "Разгрузка поставки",
        description = "Помогите вскрыть и разобрать поставку на площадке снабжения.",
        divisions = {"classd", "administration", "engineering"},
        objective = {type = "event", event = "supply.unpacked", count = 1},
        reward = {xp = 35, source = "task"}, perShift = 2,
    },
    {
        id = "d_volunteer", name = "Участие в эксперименте",
        description = "Примите участие в эксперименте научного отдела.",
        divisions = {"classd"},
        objective = {type = "event", event = "experiment.participated", count = 1},
        reward = {xp = 50, source = "research"}, perShift = 2,
    },
    {
        id = "adm_approve", name = "Рассмотрение заявок",
        description = "Рассмотрите две заявки на снабжение (одобрение или мотивированный отказ).",
        divisions = {"administration"},
        objective = {type = "event", event = "supply.decided", count = 2},
        reward = {xp = 40, source = "task"}, perShift = 3,
    },
    {
        id = "mtf_inspect", name = "Инспекция камер содержания",
        description = "Проверьте панели содержания двух объектов.",
        divisions = {"mtf"},
        objective = {type = "event", event = "containment.inspected", count = 2},
        reward = {xp = 40, source = "security"}, perShift = 3, minOnline = 10,
    },
}

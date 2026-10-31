# Аддоны SITE-VEIL

SITE-VEIL расширяется обычными аддонами Garry's Mod (`garrysmod/addons/<папка>/`). Аддон подключается через публичный API режима и **не меняет файлы режима**: его можно поставить, отключить или удалить независимо.

> Аддоны, как и сам режим, **проверены только автоматическими тестами без игры** ([TESTING.md](TESTING.md)); в Garry's Mod не запускались.

## Установка

1. Скопируйте нужные каталоги из `addons/` репозитория в `garrysmod/addons/` сервера (например, `addons/siteveil_tesla` → `garrysmod/addons/siteveil_tesla`).
2. Перезапустите сервер. Клиенты получат файлы аддонов автоматически: они распространяются как Lua самого сервера, отдельного контента нет.
3. Проверьте F4 → «Администрирование» → «Состояние сервера»: в списке «Аддоны SITE-VEIL» каждый аддон должен быть в состоянии «работает».

Отключить аддон, не удаляя его: `siteveil_addons_disabled "tesla,cctv"` в `server.cfg` (идентификаторы через запятую, нужен перезапуск).

## Аддоны в комплекте

| Папка | id | Что делает | Разметка карты |
|---|---|---|---|
| `siteveil_intercom` | `intercom` | **Интерком**: голосовое (20 с) или текстовое обращение на весь комплекс с терминала. Нужны карта с допуском 2 и зоной `administration`/`security`/`science`, питание и исправная связь сектора. Общая пауза 120 с, личная 300 с; говорящий не должен отходить от терминала. | `terminal` с `terminal=intercom` |
| `siteveil_decontamination` | `decontamination` | **Обеззараживание сектора**: решение руководства (флаги `declareBreach`/`declareEvac` или дежурный администратор) во вкладке «Комплекс». 120 с предупреждения → блокировка сектора и газ на 90 с: урон всем без противогаза или защитного костюма (до недееспособности) → снятие блокировки. Нельзя во время эвакуации; одно за раз; повтор для сектора через 30 мин; можно отменить. | — |
| `siteveil_tesla` | `tesla` | **Тесла-ворота**: заграждение в коридоре. На посторонних и любые SCP заряжается 0,8 с со звуком и бьёт током (80 урона) всех внутри. Не срабатывает на сотрудников с допуском 3 и зоной `security`. Работает только при питании и исправной системе безопасности сектора. Командиры охраны и МОГ (`lockdown`/`recontain`) отключают ворота сектора до 120 с. | точка `tesla` (`name`, `sector`, `radius`) |
| `siteveil_cctv` | `cctv` | **Видеонаблюдение**: камеры и пост наблюдения. Колесо мыши — другая камера, ПКМ/E — выход; отход от монитора или урон прерывают просмотр. Камеры зависят от питания и подсистемы наблюдения сектора. **Лицо SCP-096 на мониторе делает зрителя целью**, кроме камеры внутри камеры содержания 096, пока она замаскирована процедурой. Для SCP-173 камеры наблюдателями не считаются. | точка `camera` (`name`, `sector`; направление — угол точки), `terminal` с `terminal=cctv` |
| `siteveil_scp999` | `scp999` | **SCP-999**: игровой безобидный объект. ЛКМ — объятие (лечит 25 HP и снимает боль, не поднимает недееспособных), ПКМ — успокоение (переводит бушующего SCP-096 рядом в успокоение, иначе снижает напряжение директора). Выход из камеры — локальная тревога, а не нарушение содержания. Возвращается конфетами. Досье, протокол исследования «Влияние SCP-999 на настроение персонала», предмет «Конфеты». | зона `cell` с `scp=scp999`, точка `spawn` с `group=scp999`, `panel` с `scp=scp999` |
| `siteveil_scoreboard` | `scoreboard` | **Табель** на TAB: сотрудники по подразделениям (имя персонажа, номер, звание, должность, пинг). Повстанцы Хаоса для остальных — «Посторонние» без имён. Администрация дополнительно видит имя Steam, SteamID и дежурство. Заменяет табло FAdmin; меню FAdmin — по `+FAdmin_menu`. | — |

Числа каждого аддона — в его `sh_*.lua` (`SiteVeil.Config.Intercom`, `.Decontamination`, `.Tesla`, `.Cctv`, `.SCP.scp999`, `.Scoreboard`).

## Как написать свой аддон

### Структура

```
garrysmod/addons/my_addon/
  addon.json                          (необязательно; для публикации)
  lua/siteveil_addons/myaddon/
    addon.lua                         описание (обязательно)
    sh_myaddon.lua  sv_myaddon.lua  cl_myaddon.lua
  lua/entities/<класс>/shared.lua     свои сущности (по правилам GMod)
  lua/weapons/<класс>/shared.lua      своё оружие
```

`addon.lua` возвращает таблицу:

```lua
return {
    id = "myaddon",                    -- = имя папки в lua/siteveil_addons/
    name = "Мой аддон", version = "1.0.0", author = "...", description = "...",
    requires = {"facility", "scp"},    -- модули режима (sh_manifest.lua)
    depends = {"cctv"},                -- аддоны, без которых этот не работает
    after = {"tesla"},                 -- загрузиться после них, если они есть
    config = {"sh_config.lua"},        -- этап config
    files = {"sh_x.lua", "sv_x.lua", "cl_x.lua"},  -- этап main
}
```

Сторона файла определяется префиксом, как в режиме: `sh_` — общий, `sv_` — только сервер (клиенту не отправляется: сюда кладите всё, что игрок не должен видеть заранее), `cl_` — только клиент.

### Этапы загрузки

1. **config** — сразу после `config/*` режима, **до** индексации ролей и создания профессий DarkRP. Здесь можно дописывать `SiteVeil.Config`: роли (`table.insert(C.Roles, {...})`), подразделения, предметы (`C.Items.x = {...}`), стартовый склад, параметры SCP. DarkRP ещё не загружен — функции DarkRP вызывать нельзя.
2. **main** — после всех модулей режима (в том же порядке на сервере и клиенте). Доступен весь API.

Ошибка Lua в файле аддона, отсутствующий модуль или аддон из `requires`/`depends`, неверный `id` — аддон помечается «ошибка», причина видна в консоли и в админ-панели, режим продолжает работать. Порядок аддонов — по `id`, с учётом `depends` и `after`.

### Точки расширения

| Что | Как |
|---|---|
| Новый тип точки карты со своей сущностью | `SiteVeil.MapCfg.pointKinds.x = {name = "...", entity = "класс"}` (shared) + `SiteVeil.MapCfg.editorProps.x = {prop = true}` (server). Сущность получает `self.SVPoint` (id, props). |
| Новый тип зоны | `SiteVeil.MapCfg.zoneKinds.x = {name = "..."}` (+ `editorProps`). |
| Терминал | `SiteVeil.MapCfg.terminalKinds.x = "Название"` (shared) и `SiteVeil.Facility.registerTerminal("x", {name, req = {clearance, tags}, power, open = function(ply, ent) end})` (server). Доступ, питание и журнал проверяет режим. |
| Объект SCP | `SiteVeil.SCP.register(id, def)` — условия, процедуры, способности, повторное содержание, `minor = true` для безобидных. Роль — на этапе config. Подсказки — `SiteVeil.SCP.hints[id]` (client). |
| Досье | `SiteVeil.Config.Dossiers.id = {...}` в `sv_`-файле (формат — `config/sv_dossiers.lua`). |
| Протокол исследования | `SiteVeil.Research.registerProtocol({...})` (server; формат — `config/sv_protocols.lua`). |
| Событие директора | `SiteVeil.Director.registerEvent({...})`; вид `custom` с `custom = {prepare, apply, check, tick, success, fail}`. Директор сам проверит решающих, перезарядки и лимиты. |
| Голос на весь комплекс | `SiteVeil.Comms.setBroadcast(ply, untilTime)` / `nil`. |
| Вкладка F4, элемент HUD, пункт меню взаимодействия | `UI.registerTab{...}`, `UI.hudElement(id, order, fn)`, `UI.registerInteraction{...}` (client). |
| Блок во вкладке «Комплекс» / «Администрирование» | хуки `SiteVeil.FacilityTab(scroll)` и `SiteVeil.AdminTab(scroll)` (client). |
| Подсказка при взгляде на сущность | хук `SiteVeil.HUDLookAt(ent, x, y)` (client). |
| Сетевые действия | `SiteVeil.Net.define(name, {args, rate, alive, admin})` в `sh_`, `Net.handle` на сервере, `Net.call`/`Net.on` на клиенте. Схема, лимит и права проверяются до обработчика. |
| Реакция на события | `SiteVeil.Bus.on(event, id, fn)`: `scp.breached`, `scp.recontained`, `medical.down`, `facility.stateChanged`, `node.repaired`, `experiment.finished`, `director.started`, `intercom.broadcast`, `tesla.discharge`, `decon.ordered`… (полный список — `grep -r "Bus.emit"`). |
| Синхронизация состояния для HUD | `SiteVeil.Sync.define(name, {scope = "global"})`, `Sync.set` / `Sync.setFor(ply, "self", key, v)`. |
| Журнал аудита | `SiteVeil.Audit.log(category, action, actor, target, details)`. |

### Правила

- Решения принимает сервер; клиент только показывает и просит.
- Любое действие игрока — через `Net.define` со схемой и лимитом; проверяйте права, расстояние и состояние в обработчике.
- Игровые числа — в конфигурации аддона, не в коде.
- Никаких скрытых команд, бэкдоров и телеметрии; административные действия — через `SiteVeil.Admin.can` и в аудит.
- Контент — только из Garry's Mod/HL2 или ваш собственный с ясной лицензией; материалы SCP Foundation — CC BY-SA 3.0 с атрибуцией.

### Тесты

Стенд `tests/harness` видит `addons/*/lua/` как виртуальную файловую систему Lua GMod, так что аддон проверяется так же, как режим: положите тест в `tests/server/` и запустите `tools/check.sh`. Пример — `tests/server/test_addons.lua`; устойчивость загрузчика — `tests/server/test_addon_loader.lua` с намеренно сломанными аддонами из `tests/fixtures/addons/`.

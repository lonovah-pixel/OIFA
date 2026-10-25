# Изменения относительно DarkRP

## Главное

**Исходники DarkRP не изменены.** `gamemodes/darkrp` — точная копия апстрима:

```
repo   https://github.com/FPtje/DarkRP.git
commit 5abcf7abab9e489b2d882a55d95f84c206d9d05c   (tools/darkrp.lock)
```

Все изменения поведения сделаны в производном режиме `gamemodes/siteveil` (`siteveil.txt`: `"base" "darkrp"`) штатными механизмами DarkRP и Garry's Mod. Проверить, что копия DarkRP чистая, можно сравнением с апстримом на коммите из `tools/darkrp.lock`.

## Механизмы, которые использует SITE-VEIL

| Механизм | Где | Зачем |
|---|---|---|
| `DeriveGamemode("darkrp")` + `DEFINE_BASECLASS` | `gamemode/init.lua`, `cl_init.lua` | наследование; `SiteVeil.BaseClass` — методы DarkRP для вызова из переопределений |
| хук `DarkRPPreLoadModules` | `modules/darkrp_bridge/sh_preload.lua` | `DarkRP.disabledDefaults`: модули, стандартные профессии, товары, сущности, боеприпасы, повестки, группы дверей и понижений; значения `GM.Config` |
| хук `DarkRPFinishedLoading` | `modules/darkrp_bridge/sh_jobs.lua` | создание профессий (`DarkRP.createJob`, `createCategory`) из реестра ролей SITE-VEIL |
| реализации интерфейсов отключённых модулей | `sh_shims.lua`, `sv_shims.lua`, `cl_shims.lua` | DarkRP загружает `*_interface.lua` всех модулей; без реализации вызовы копились бы бесконечно |
| `GM:canChatCommand` + удаление команд после `InitPostEntity` | `sh_commands.lua`, `sv_gate.lua` | разрешены только команды SITE-VEIL и `credits` |
| хук `playerCanChangeTeam` с одноразовым токеном | `sv_gate.lua` | профессию меняет только модуль персонажей |
| переопределения `GM:*` экономики и имущества | `sv_gate.lua` | закрытие серверных обработчиков, не только интерфейса |
| `DarkRP.notify` / usermessage `_Notify` | `modules/ui/cl_notify.lua` | уведомления DarkRP показываются в стиле SITE-VEIL |
| `DarkRP.talkToPerson` | `modules/comms` | вывод чата |
| переменные DarkRP (`rpname`, `job`, `sv_num`, `sv_div`, `sv_rank`) | `modules/characters` | имя и должность персонажа видны остальным системам DarkRP и FAdmin |
| `DarkRP.addLanguage("ru", …)` | `modules/darkrp_bridge/sh_language.lua` | русские формулировки оставшихся сообщений DarkRP |
| CAMI | `modules/admin/sh_admin.lua` | права SITE-VEIL выдаются через любой админ-мод |

## Отключённые модули DarkRP

| Модуль | Чем заменён |
|---|---|
| `money` | бюджеты подразделений (`modules/supply`) |
| `police` | система безопасности (`modules/security`) |
| `hud` | HUD SITE-VEIL (`modules/ui`) |
| `f4menu` | служебная система F4 |
| `f1menu` | справка F1 |
| `sleep` | недееспособность (`modules/medical`) |
| `events` | директор напряжения (`modules/director`) |
| `hungermod`, `hitmenu`, `hobo`, `tipjar` | удалены (городские механики) |
| `afk`, `chatsounds` | не используются |

Отключены все стандартные профессии DarkRP (`citizen`, `cp`, `gangster`, `mobboss`, `gundealer`, `medic`, `chief`, `mayor`, `hobo`, `cook`), партии товаров, сущности (принтеры, лаборатории, банка для чаевых), боеприпасы, повестки, группы дверей и понижений.

## Перекрытые значения `GM.Config`

Полный список — `Bridge.configOverrides` в `sh_preload.lua`. Основное:

- деньги и экономика: `startingmoney = 0`, `normalsalary = 0`, налоги, лотерея, лицензии, покупка пистолета, деньги за NPC, выпадение денег — выключены;
- имущество: владение транспортом, ордера на двери, `canforcedooropen`, отпирание дверей при старте — выключены (двери управляются `modules/access`);
- профессии: `allowjobswitch`, `customjobs`, `allowrpnames`, голосования — выключены;
- предметы: спавн пропов, выпадение оружия и кармана — выключены (все предметы принадлежат серверному инвентарю);
- чат и голос: OOC, alltalk, радиус голоса, звуки чата DarkRP — выключены (`modules/comms`);
- оружие по умолчанию и админское оружие — пустые списки.

## Закрытые серверные точки входа (`sv_gate.lua`)

Независимо от интерфейса сервер отклоняет:

- все чат- и консольные команды DarkRP вне списка разрешённых (двойная защита: удаление и вето в `canChatCommand`), консольные команды `rp_<профессия>`;
- смену профессии без токена модуля персонажей;
- изменения кошелька, зарплату, покупку дверей и транспорта, карман, понижения, голосования, налоги, смену RP-имени;
- создание городских сущностей (принтеры, лаборатории, партии) даже администраторами; выдачу и спавн оружия в обход инвентаря.

`sv_verify.lua` после загрузки проверяет, что всё это действительно так (модули выключены, команд нет, профессии созданы), и показывает найденные расхождения как ошибки загрузки в консоли и в админ-панели.

## Реализованные интерфейсы отключённых модулей

`DarkRP.payPlayer`, `createMoneyBag` (без эффекта: денег нет), `lockdown`/`unLockdown` (комендантский час отключён: игрок получает подсказку о режимах комплекса), `iterateArrestedPlayers`, `arrestedPlayers`, `arrestedPlayerCount` и метод игрока `arrest` (→ задержание SITE-VEIL), `addHitmanTeam`, `getHitmanTeams`, `getHits`, `createFood`, `removeFoodItem`, `getFoodItems`, `toggleSleep` (→ без эффекта), `openF4Menu`/`closeF4Menu`/`toggleF4Menu`/`getF4MenuPanel`/`addF4MenuTab`/`removeF4MenuTab`/`switchTabOrder` (→ служебная система), `openF1Menu`/`closeF1Menu`/`refreshF1Menu` (→ справка), `openHitMenu`.

## Обновление DarkRP

1. Получите новую ревизию DarkRP и замените `gamemodes/darkrp` целиком.
2. Обновите `tools/darkrp.lock`.
3. Запустите `tools/check.sh` и сервер; проверьте вкладку «Состояние сервера» в админ-панели: `sv_verify` сообщит о новых командах, профессиях или модулях, которые не закрыты.
4. Сверьте списки в `sh_preload.lua` со стандартными профессиями, товарами и сущностями новой версии DarkRP (`gamemode/config/jobrelated.lua`, `addentities.lua`, `ammotypes.lua`) и с обработкой `DarkRP.disabledDefaults` в `gamemode/libraries/modificationloader.lua`.

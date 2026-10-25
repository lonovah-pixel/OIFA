# Сторонние материалы и атрибуция

## Код, распространяемый вместе с режимом

| Компонент | Путь | Лицензия |
|---|---|---|
| DarkRP (FPtje Falco и соавторы), коммит `5abcf7a` | `gamemodes/darkrp` | MIT, `gamemodes/darkrp/LICENSE.txt` |
| Модули, входящие в DarkRP: FPP, FAdmin, FSpectate, CAMI, библиотеки DarkRP | `gamemodes/darkrp/gamemode/modules`, `gamemodes/darkrp/gamemode/libraries` | лицензии указаны в самих файлах и в репозитории DarkRP |

DarkRP не изменён. Список изменённого поведения — [DARKRP_CHANGES.md](DARKRP_CHANGES.md).

## Инструменты разработки (не распространяются с режимом)

| Инструмент | Использование | Лицензия |
|---|---|---|
| glualint 1.30.0 | статическая проверка; скачивается `tools/install_glualint.sh` в `tools/bin` (не хранится в репозитории) | см. https://github.com/FPtje/GLuaFixer |
| lupa, LuaJIT | запуск тестов | MIT |
| Python 3, SQLite | запуск тестов | PSF, public domain |

## Игровой контент

Модели, материалы и звуки — **только из Half-Life 2 / Garry's Mod**, установленных вместе с игрой (`models/player/*.mdl`, `models/weapons/*.mdl`, звуки `npc/`, `physics/`, `ambient/`, `vo/`). Они не входят в репозиторий и принадлежат Valve. Контент из Steam Workshop не используется и не требуется.

## SCP Foundation — CC BY-SA 3.0

SITE-VEIL использует концепции вселенной SCP Foundation (http://scp-wiki.wikidot.com, русский филиал http://scpfoundation.net). Материалы вики распространяются по лицензии **Creative Commons Attribution-ShareAlike 3.0** (https://creativecommons.org/licenses/by-sa/3.0/).

Тексты досье, протоколов и описаний в SITE-VEIL (`gamemodes/siteveil/gamemode/config/sv_dossiers.lua`, `config/sv_protocols.lua`, описания ролей и подсказки об объектах) — **оригинальные русскоязычные пересказы**, написанные для SITE-VEIL по мотивам статей вики, а не переводы и не копии. Как производные от материалов CC BY-SA 3.0 они **распространяются по той же лицензии CC BY-SA 3.0**; при использовании этих текстов укажите SITE-VEIL и оригинальные статьи ниже.

| Объект | Оригинальная статья | Автор(ы) оригинала |
|---|---|---|
| SCP-173 «Скульптура» | http://scp-wiki.wikidot.com/scp-173 | Moto42 |
| SCP-106 «Старик» | http://scp-wiki.wikidot.com/scp-106 | Dr Gears |
| SCP-049 «Чумной доктор» | http://scp-wiki.wikidot.com/scp-049 | Gabriel Jade |
| SCP-096 «Скромник» | http://scp-wiki.wikidot.com/scp-096 | Dr Dan |
| Мобильные оперативные группы, Повстанцы Хаоса, Совет О5, класс D, классы объектов | http://scp-wiki.wikidot.com (статьи о Фонде, группах интересов и классах объектов) | участники SCP Wiki |

Авторы указаны по данным страниц вики на момент написания; перед публичным распространением сверьте их с разделом лицензирования каждой страницы (у многих статей есть переработки других авторов, которые тоже указываются).

Изображения со страниц вики **не используются**. В частности, известная скульптура «Untitled 2004» (Izumi Kato), связанная с SCP-173, не распространяется по CC BY-SA и в SITE-VEIL отсутствует.

Аномальные предметы AO-3127 «Эхо» и AO-5510 «Ртутный мёд», протоколы экспериментов и их исходы, события директора и скрытые задания придуманы для SITE-VEIL.

## Код SITE-VEIL

Лицензия собственного кода SITE-VEIL (`gamemodes/siteveil`, `tests`, `tools`) не выбрана: файл LICENSE не добавлен, решение за владельцем репозитория. Ограничения сверху: совместимость с MIT (DarkRP) и CC BY-SA 3.0 для текстов по мотивам SCP Foundation.

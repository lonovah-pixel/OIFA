return {
    id = "polygraph", name = "Полиграф", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Проверка на полиграфе: вопрос, 15 секунд, вероятностный результат. Реакция чаще у тех, кто выполняет скрытое задание или допускал утечки; ложные срабатывания возможны.",
    requires = {"security", "inventory", "knowledge"},
    after = {"hidden"},
    config = {"sh_config.lua"},
    files = {"sh_polygraph.lua", "sv_polygraph.lua", "cl_polygraph.lua"},
}

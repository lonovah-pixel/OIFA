return {
    id = "cctv", name = "Видеонаблюдение", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Камеры на карте и мониторный терминал. Камеры зависят от питания и наблюдения сектора; лицо SCP-096 на мониторе тоже опасно.",
    requires = {"facility", "scp", "mapcfg", "admin"},
    files = {"sh_cctv.lua", "sv_cctv.lua", "cl_cctv.lua"},
}

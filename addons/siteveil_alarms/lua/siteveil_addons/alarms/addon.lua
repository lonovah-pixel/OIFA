return {
    id = "alarms", name = "Аварийная сигнализация", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Лампы на карте: цвет и сирена по состоянию сектора (тревога, блокировка, нарушение содержания, эвакуация, обеззараживание).",
    requires = {"facility", "mapcfg"},
    after = {"decontamination"},
    files = {"sh_alarms.lua", "sv_alarms.lua", "cl_alarms.lua"},
}

return {
    id = "notes", name = "Записки и доска объявлений", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Записки, которые можно оставить в мире и прочитать (анонимно для игроков), и доски объявлений подразделений.",
    requires = {"characters", "security", "mapcfg", "admin"},
    files = {"sh_notes.lua", "sv_notes.lua", "cl_notes.lua"},
}

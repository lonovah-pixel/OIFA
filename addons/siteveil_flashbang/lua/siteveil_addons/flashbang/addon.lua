return {
    id = "flashbang", name = "Светошумовая граната", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Снаряжение охраны: ослепляет и оглушает на секунды. Ослеплённые не удерживают SCP-173 взглядом и не видят лицо SCP-096.",
    requires = {"inventory", "scp", "evidence", "supply"},
    config = {"sh_config.lua"},
    files = {"sv_flashbang.lua", "cl_flashbang.lua"},
}

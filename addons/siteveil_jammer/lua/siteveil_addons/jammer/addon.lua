return {
    id = "jammer", name = "Глушилка и пеленгатор", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Диверсанты ставят глушилку, и радиосвязь в секторе тонет в помехах; инженеры находят её пеленгатором и обезвреживают.",
    requires = {"comms", "inventory", "facility", "evidence"},
    config = {"sh_config.lua"},
    files = {"sh_jammer.lua", "sv_jammer.lua", "cl_jammer.lua"},
}

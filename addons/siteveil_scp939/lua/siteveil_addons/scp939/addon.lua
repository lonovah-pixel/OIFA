return {
    id = "scp939", name = "SCP-939", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Игровой SCP-939: слепой хищник, видит только источники шума и подманивает чужими голосами. Тишина — защита.",
    requires = {"scp", "medical", "knowledge", "comms"},
    config = {"sh_config.lua"},
    files = {"sv_scp939.lua", "sv_content.lua", "cl_scp939.lua"},
}

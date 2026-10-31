return {
    id = "crafting", name = "Мастерская", version = "1.0.0", author = "SITE-VEIL contributors",
    description = "Верстаки и рецепты по подразделениям; металлолом с работ класса D; отмычка для дверей низкого допуска (шумно, с риском и следом).",
    requires = {"inventory", "access", "mapcfg", "evidence"},
    after = {"labor", "jammer"},
    config = {"sh_config.lua"},
    files = {"sh_crafting.lua", "sv_crafting.lua", "cl_crafting.lua"},
}

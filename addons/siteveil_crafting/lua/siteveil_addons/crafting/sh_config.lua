--[[---------------------------------------------------------------------------
Crafting (shared configuration, boot stage): new items.
---------------------------------------------------------------------------]]

local C = SiteVeil.Config

C.Items.scrap = {name = "Металлолом", category = "misc", weight = 0.4, stack = 10, model = "models/props_c17/tools_wrench01a.mdl",
    desc = "Обрезки металла. Пригодятся в мастерской.", price = 1}
C.Items.lockpick = {name = "Отмычка", category = "tool", weight = 0.1, stack = 3, use = "lockpick", contraband = true,
    model = "models/props_c17/tools_wrench01a.mdl", desc = "Самодельная отмычка. Открывает простые замки — не всегда."}

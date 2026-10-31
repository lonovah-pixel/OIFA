--[[---------------------------------------------------------------------------
Jammer (shared configuration, boot stage): items, kits, numbers.
---------------------------------------------------------------------------]]

local C = SiteVeil.Config

C.Items.jammer = {name = "Глушилка", category = "tool", weight = 1.5, stack = 1, use = "jammer", contraband = true,
    model = "models/props_lab/reciever01b.mdl", desc = "Самодельный подавитель связи. Работает несколько минут."}
C.Items.rf_tracker = {name = "Пеленгатор", category = "tool", weight = 1, stack = 1, use = "rftrack",
    model = "models/props_lab/reciever01b.mdl", desc = "Показывает направление на источник радиопомех.", price = 30, division = {"engineering", "security"}}
C.Supply.startStock.engineering = C.Supply.startStock.engineering or {}
C.Supply.startStock.engineering.rf_tracker = 2
for _, role in ipairs(C.Roles) do
    if role.id == "chaos_operative" then table.insert(role.kit, {"jammer", 1}) end
    if role.id == "eng_engineer" then table.insert(role.kit, {"rf_tracker", 1}) end
end

C.Jammer = {
    lifetime = 180,
    quality = 0.15,            -- radio quality factor for anyone in the jammed sector
    maxActive = 2,
    placeCooldown = 300,
    health = 30,
    disarmTime = 5,
    trackRange = 4000,
    trackCooldown = 4,
    disarmXP = 10,
}

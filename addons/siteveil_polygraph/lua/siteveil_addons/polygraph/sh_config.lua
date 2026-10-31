--[[---------------------------------------------------------------------------
Polygraph (shared configuration, boot stage): item and numbers.
---------------------------------------------------------------------------]]

local C = SiteVeil.Config

C.Items.polygraph = {name = "Полиграф", category = "tool", weight = 3, stack = 1, model = "models/props_lab/reciever01b.mdl",
    desc = "Переносной полиграф. Результат — повод для расследования, не доказательство.", price = 60, division = {"security", "administration"}}
C.Supply.startStock.security = C.Supply.startStock.security or {}
C.Supply.startStock.security.polygraph = 1
for _, role in ipairs(C.Roles) do
    if role.id == "sec_investigator" then table.insert(role.kit, {"polygraph", 1}) end
end

C.Polygraph = {
    time = 15,
    range = 120,
    targetCooldown = 600,
    hitChance = 0.7,           -- reaction when the person hides something
    falseChance = 0.2,         -- reaction when they do not
    leakWindow = 3600,
    hiddenWindow = 1800,
}

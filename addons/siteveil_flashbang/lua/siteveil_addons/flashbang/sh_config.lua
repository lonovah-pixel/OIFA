--[[---------------------------------------------------------------------------
Flashbang (shared configuration, boot stage): item, stock, numbers.
---------------------------------------------------------------------------]]

local C = SiteVeil.Config

C.Items.flashbang = {
    name = "Светошумовая граната", category = "weapon", weight = 0.5, stack = 3, weapon = "sv_flashbang",
    desc = "Ослепляет и оглушает на несколько секунд. Осторожно рядом с SCP-173.", model = "models/weapons/w_grenade.mdl",
    price = 25, division = {"security"},
}
C.Supply.startStock.security = C.Supply.startStock.security or {}
C.Supply.startStock.security.flashbang = 6
C.Lockers.armory.items.flashbang = 1

C.TraceKinds.flash = {name = "Следы светошумового заряда", ttl = 900}

C.Flashbang = {
    fuse = 1.6,
    throwSpeed = 650,
    radius = 700,
    blindMin = 1.5,
    blindMax = 5,
    facingDot = 0.3,      -- looking away halves the effect
    cooldown = 1.5,
}

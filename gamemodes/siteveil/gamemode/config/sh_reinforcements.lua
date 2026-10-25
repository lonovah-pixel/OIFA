--[[---------------------------------------------------------------------------
Reinforcement waves (shared configuration). See BALANCE.md.

MTF: called by staff with the callReinforcements flag (or an admin on duty)
during a breach, lockdown or evacuation. Chaos Insurgency: arrives on its
own during a breach or evacuation on populated servers, at most once per
shift. Waves take players from a queue (FIFO): lobby players with a
character of the division, and MTF garrison on shift.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Reinforcements = {
    mtf = {
        name = "МОГ Эпсилон-11", division = "mtf", group = "mtf",
        roles = {lead = "mtf_commander", member = "mtf_operative"},
        called = true, states = {breach = true, lockdown = true, evacuation = true},
        minOnline = 8, delay = 60, cooldown = 600, perShift = 3,
        size = {base = 2, perPlayers = 10, max = 6},
        recallAfter = 180,      -- seconds of normal state before the wave stands down
    },
    chaos = {
        name = "Повстанцы Хаоса", division = "chaos", group = "chaos",
        roles = {lead = "chaos_leader", member = "chaos_operative"},
        called = false, states = {breach = true, evacuation = true},
        minOnline = 16, delay = 90, cooldown = 1800, perShift = 1, chance = 0.5,
        size = {base = 2, perPlayers = 12, max = 5},
        lifetime = 900,         -- the cell withdraws after this
    },
}

--[[---------------------------------------------------------------------------
Radio channels (shared).

  divisions   divisions allowed to use the channel (nil = any staff)
  flags       alternatively any of these role flags
  item        required radio item ("radio" by default)
  default     channels a player listens to after spawning
  open        can be intercepted with an ordinary radio by anyone (rarely used)
---------------------------------------------------------------------------]]

local SV = SiteVeil
local C = SV.Config

C.Radio = {
    shortRange = 700,          -- radio works without infrastructure within this distance
    localHearDistance = 200,   -- people nearby hear what you say into the radio
    garbleFrom = 0.75,         -- comms health below which messages are garbled
    silentBelow = 0.2,         -- comms health below which only static is heard
    channels = {
        {id = "common", name = "Общий", freq = "101.1", default = true,
            divisions = {"science", "security", "engineering", "medical", "administration", "mtf", "classd"}},
        {id = "security", name = "Охрана", freq = "205.4", divisions = {"security", "mtf", "administration"}, default = true},
        {id = "science", name = "Научный", freq = "310.2", divisions = {"science", "administration"}, default = true},
        {id = "engineering", name = "Инженерный", freq = "415.7", divisions = {"engineering", "administration"}, default = true},
        {id = "medical", name = "Медицинский", freq = "520.3", divisions = {"medical", "administration"}, default = true},
        {id = "command", name = "Командный", freq = "777.0", flags = {"divisionHead", "declareAlert", "callReinforcements"}, default = true},
        {id = "mtf", name = "МОГ Эпсилон-11", freq = "880.8", divisions = {"mtf"}, default = true},
        {id = "chaos", name = "Ячейка", freq = "???", divisions = {"chaos"}, item = "radio_chaos", default = true},
        -- Intercept: the Chaos radio can listen (not transmit) to the open common channel.
    },
    chaosIntercept = {"common"},
}

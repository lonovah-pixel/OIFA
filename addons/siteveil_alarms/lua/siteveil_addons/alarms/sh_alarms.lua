--[[---------------------------------------------------------------------------
Alarm lights (shared): modes, map kind.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Alarms = SV.Alarms or {}

-- Mode -> look. Priority: first matching rule in sv_alarms.lua.
SV.Config.Alarms = {
    modes = {
        decon = {color = Color(80, 255, 120), period = 0.5, siren = "ambient/alarms/klaxon1.wav", name = "обеззараживание"},
        evac = {color = Color(255, 40, 40), period = 0.4, siren = "ambient/alarms/alarm1.wav", name = "эвакуация"},
        breach = {color = Color(255, 40, 40), period = 0.8, siren = "ambient/alarms/alarm1.wav", name = "нарушение содержания"},
        lockdown = {color = Color(255, 140, 0), period = 1.0, name = "блокировка"},
        alert = {color = Color(255, 210, 0), period = 1.4, name = "тревога"},
    },
    lightSize = 300,
    tick = 1,
}

SV.MapCfg.pointKinds.alarm = {name = "Аварийная лампа", entity = "sv_alarm_light"}

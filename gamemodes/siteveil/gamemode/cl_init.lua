--[[---------------------------------------------------------------------------
SITE-VEIL client entry point. Mirrors init.lua.
---------------------------------------------------------------------------]]

include("sh_boot.lua")

DeriveGamemode("darkrp")
DEFINE_BASECLASS("gamemode_darkrp")

GM.Name = "SITE-VEIL"
GM.Author = "SITE-VEIL contributors (based on DarkRP by FPtje Falco et al.)"
GM.SiteVeil = true

SiteVeil.BaseClass = BaseClass
SiteVeil.Loader.loadStage("main")
SiteVeil.Startup()

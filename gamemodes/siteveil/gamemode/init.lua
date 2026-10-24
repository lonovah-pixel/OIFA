--[[---------------------------------------------------------------------------
SITE-VEIL server entry point.

Load order:
  1. sh_boot.lua          namespace, shared config, DarkRP pre-load hooks
  2. DeriveGamemode       loads the vendored DarkRP (gamemodes/darkrp)
  3. "main" stage         all SITE-VEIL modules from sh_manifest.lua
  4. SiteVeil.Startup()   database migrations and post-load validation
---------------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("sh_boot.lua")
include("sh_boot.lua")

DeriveGamemode("darkrp")
DEFINE_BASECLASS("gamemode_darkrp")

GM.Name = "SITE-VEIL"
GM.Author = "SITE-VEIL contributors (based on DarkRP by FPtje Falco et al.)"
GM.SiteVeil = true

SiteVeil.BaseClass = BaseClass
SiteVeil.Loader.loadStage("main")
SiteVeil.Startup()

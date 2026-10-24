--[[---------------------------------------------------------------------------
SITE-VEIL boot stage.

Runs on both realms BEFORE DeriveGamemode("darkrp"). It creates the global
namespace, loads the shared configuration and registers the two DarkRP hooks
that must exist before DarkRP's own files run:

  * DarkRPPreLoadModules  - disables city modules and overrides GM.Config
  * DarkRPFinishedLoading - creates SITE-VEIL roles as DarkRP jobs

Nothing in this file may call DarkRP functions directly: DarkRP is not loaded
yet when it runs.
---------------------------------------------------------------------------]]

SiteVeil = SiteVeil or {}
local SV = SiteVeil

SV.Version = "0.1.0"
SV.FolderName = (GM and GM.FolderName) or SV.FolderName or "siteveil"
SV.Root = SV.FolderName .. "/gamemode/"
SV.Loaded = SV.Loaded or {}

if SERVER then
    AddCSLuaFile(SV.Root .. "sh_loader.lua")
    AddCSLuaFile(SV.Root .. "sh_manifest.lua")
end

include(SV.Root .. "sh_loader.lua")
include(SV.Root .. "sh_manifest.lua")

SV.Loader.loadStage("boot")

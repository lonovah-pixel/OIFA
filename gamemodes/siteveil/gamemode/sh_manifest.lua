--[[---------------------------------------------------------------------------
SITE-VEIL module manifest: the complete, ordered list of source files.

stage "boot": loaded before DeriveGamemode("darkrp") - configuration and the
              DarkRP pre-load hooks. Must not call DarkRP functions.
stage "main": loaded after DarkRP has finished loading.

A module may only depend on modules listed above it. Cross-module reactions
in the other direction go through SiteVeil.Bus events (core/sh_bus.lua).
---------------------------------------------------------------------------]]

local M = SiteVeil.Loader.module

-- boot ---------------------------------------------------------------------
M{name = "config", stage = "boot", files = {
    "config/sh_config.lua",
    "config/sh_roles.lua",
    "config/sh_tasks.lua",
    "config/sh_items.lua",
    "config/sh_access.lua",
    "config/sh_comms.lua",
    "config/sh_supply.lua",
}}

M{name = "roles", stage = "boot", deps = {"config"}, files = {
    "modules/roles/sh_roles.lua",
}}

M{name = "darkrp_preload", stage = "boot", deps = {"roles"}, files = {
    "modules/darkrp_bridge/sh_preload.lua",
    "modules/darkrp_bridge/sh_jobs.lua",
}}

-- main ---------------------------------------------------------------------
M{name = "core", deps = {"config"}, files = {
    "core/sh_util.lua",
    "core/sh_log.lua",
    "core/sh_perf.lua",
    "core/sh_bus.lua",
    "core/sv_db.lua",
    "core/sv_settings.lua",
    "core/sv_audit.lua",
    "core/sv_rng.lua",
    "core/sh_net.lua",
    "core/sh_sync.lua",
    "core/sh_actions.lua",
    "core/sh_startup.lua",
}}

M{name = "darkrp_bridge", deps = {"core", "darkrp_preload"}, files = {
    "modules/darkrp_bridge/sh_shims.lua",
    "modules/darkrp_bridge/sv_shims.lua",
    "modules/darkrp_bridge/cl_shims.lua",
    "modules/darkrp_bridge/sh_commands.lua",
    "modules/darkrp_bridge/sv_gate.lua",
    "modules/darkrp_bridge/sv_verify.lua",
}}

M{name = "shift", deps = {"core"}, files = {
    "modules/shift/sh_shift.lua",
    "modules/shift/sv_shift.lua",
}}

M{name = "characters", deps = {"core", "darkrp_bridge", "shift"}, files = {
    "modules/characters/sh_characters.lua",
    "modules/characters/sv_characters.lua",
}}

M{name = "ui_base", deps = {"core", "characters"}, files = {
    "modules/ui/cl_theme.lua",
    "modules/ui/cl_components.lua",
    "modules/ui/cl_notify.lua",
    "modules/ui/cl_hud.lua",
    "modules/ui/cl_menu.lua",
    "modules/ui/cl_interact.lua",
}}

M{name = "mapcfg", deps = {"core", "characters"}, files = {
    "modules/mapcfg/sh_mapcfg.lua",
    "modules/mapcfg/sv_mapcfg.lua",
}}

M{name = "tasks", deps = {"characters", "mapcfg", "shift"}, files = {
    "modules/tasks/sh_tasks.lua",
    "modules/tasks/sv_tasks.lua",
}}

M{name = "inventory", deps = {"characters", "ui_base", "shift"}, files = {
    "modules/inventory/sh_inventory.lua",
    "modules/inventory/sv_inventory.lua",
    "modules/inventory/sv_use.lua",
    "modules/inventory/sv_world.lua",
    "modules/inventory/cl_inventory.lua",
}}

M{name = "access", deps = {"inventory", "mapcfg"}, files = {
    "modules/access/sh_access.lua",
    "modules/access/sv_access.lua",
    "modules/access/cl_access.lua",
}}

M{name = "comms", deps = {"inventory", "darkrp_bridge"}, files = {
    "modules/comms/sh_comms.lua",
    "modules/comms/sv_radio.lua",
    "modules/comms/sv_chat.lua",
    "modules/comms/cl_comms.lua",
}}

M{name = "supply", deps = {"inventory", "access", "shift"}, files = {
    "modules/supply/sh_supply.lua",
    "modules/supply/sv_supply.lua",
    "modules/supply/cl_supply.lua",
}}

M{name = "ui", deps = {"ui_base", "tasks", "supply"}, files = {
    "modules/ui/cl_charmenu.lua",
    "modules/ui/cl_tab_character.lua",
    "modules/ui/cl_tab_division.lua",
    "modules/ui/cl_tab_tasks.lua",
    "modules/ui/cl_tab_help.lua",
}}

--[[---------------------------------------------------------------------------
Chat command registry on top of DarkRP's chat command system.

SITE-VEIL commands are declared with Bridge.chatCommand() which uses DarkRP's
declareChatCommand/defineChatCommand, so they work from chat ("/me ...") and
from the console ("darkrp me ..."). After everything is loaded, every DarkRP
command that is not on the allow list is removed on both realms (sv_gate.lua
additionally vetoes them in canChatCommand as a second line of defence).
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Bridge = SV.DarkRP

Bridge.ownCommands = Bridge.ownCommands or {}

-- DarkRP commands kept as they are.
Bridge.keptDarkRPCommands = {
    credits = true,
}

--- Declares (shared) and defines (server) a chat command.
--  def: {command, description, delay, tableArgs, condition}
function Bridge.chatCommand(def, callback)
    def.delay = def.delay or 1
    DarkRP.declareChatCommand(def)
    Bridge.ownCommands[string.lower(def.command)] = true
    if SERVER and callback then
        DarkRP.defineChatCommand(def.command, callback)
    end
end

function Bridge.isAllowedCommand(cmd)
    cmd = string.lower(cmd or "")
    return Bridge.ownCommands[cmd] == true or Bridge.keptDarkRPCommands[cmd] == true
end

--- Removes all DarkRP chat commands that SITE-VEIL does not allow. Job
--- commands are declared by DarkRP one tick after job creation, so this runs
--- after InitPostEntity.
function Bridge.pruneCommands()
    local removed = 0
    for cmd in pairs(DarkRP.getChatCommands()) do
        if not Bridge.isAllowedCommand(cmd) then
            DarkRP.removeChatCommand(cmd)
            removed = removed + 1
        end
    end
    Bridge.prunedCount = removed
    return removed
end

hook.Add("InitPostEntity", "SiteVeil.PruneCommands", function()
    timer.Simple(1, function()
        local n = Bridge.pruneCommands()
        SV.Log.info("DarkRP: удалено %d отключённых чат-команд", n)
    end)
end)

-- /cancel interrupts the current timed action (core/sh_actions.lua).
Bridge.chatCommand({command = "cancel", description = "Прервать текущее действие.", delay = 0.5}, function(ply)
    SV.Actions.cancel(ply, "отменено")
    return ""
end)

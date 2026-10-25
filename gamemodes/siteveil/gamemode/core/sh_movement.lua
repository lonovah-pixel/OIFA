--[[---------------------------------------------------------------------------
Movement and input restrictions from several sources (injuries, restraints,
SCP-173 observation, SCP-096 states, ...), combined into networked player
values so that client prediction matches the server.

    SiteVeil.Move.set(ply, "fracture", {speed = 0.55})
    SiteVeil.Move.set(ply, "restrained", {speed = 0.6, nojump = true, noattack = true})
    SiteVeil.Move.clear(ply, "fracture")

Combined result: speed multiplier (product), absolute speed cap (minimum),
frozen / nojump / noattack / nouse flags (any).
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Move = SV.Move or {}
local Move = SV.Move

if SERVER then
    Move.sources = Move.sources or {} -- ply -> source -> mods

    local function apply(ply)
        local mul, cap, frozen, nojump, noattack, nouse = 1, 0, false, false, false, false
        for _, m in pairs(Move.sources[ply] or {}) do
            if m.speed then mul = mul * m.speed end
            if m.cap and (cap == 0 or m.cap < cap) then cap = m.cap end
            frozen = frozen or m.frozen == true
            nojump = nojump or m.nojump == true
            noattack = noattack or m.noattack == true
            nouse = nouse or m.nouse == true
        end
        ply:SetNW2Float("sv_speedmul", mul)
        ply:SetNW2Float("sv_speedcap", cap)
        ply:SetNW2Bool("sv_frozen", frozen)
        ply:SetNW2Bool("sv_nojump", nojump)
        ply:SetNW2Bool("sv_noattack", noattack)
        ply:SetNW2Bool("sv_nouse", nouse)
    end

    function Move.set(ply, source, mods)
        Move.sources[ply] = Move.sources[ply] or {}
        Move.sources[ply][source] = mods
        apply(ply)
    end

    function Move.clear(ply, source)
        if Move.sources[ply] and Move.sources[ply][source] then
            Move.sources[ply][source] = nil
            apply(ply)
        end
    end

    function Move.has(ply, source)
        return Move.sources[ply] ~= nil and Move.sources[ply][source] ~= nil
    end

    function Move.reset(ply)
        Move.sources[ply] = nil
        apply(ply)
    end

    hook.Add("PlayerDisconnected", "SiteVeil.Move", function(ply) Move.sources[ply] = nil end)
end

hook.Add("SetupMove", "SiteVeil.Move", function(ply, mv)
    if ply:GetNW2Bool("sv_frozen", false) then
        mv:SetForwardSpeed(0)
        mv:SetSideSpeed(0)
        mv:SetUpSpeed(0)
        mv:SetVelocity(Vector(0, 0, math.min(mv:GetVelocity().z, 0)))
        mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))
        return
    end
    local mul = ply:GetNW2Float("sv_speedmul", 1)
    local cap = ply:GetNW2Float("sv_speedcap", 0)
    if mul ~= 1 or cap > 0 then
        local speed = mv:GetMaxClientSpeed() * mul
        if cap > 0 then speed = math.min(speed, cap) end
        mv:SetMaxClientSpeed(speed)
        mv:SetMaxSpeed(speed)
    end
    if ply:GetNW2Bool("sv_nojump", false) then
        mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))
    end
end)

hook.Add("StartCommand", "SiteVeil.Move", function(ply, cmd)
    if ply:GetNW2Bool("sv_noattack", false) then
        cmd:RemoveKey(IN_ATTACK)
        cmd:RemoveKey(IN_ATTACK2)
        cmd:RemoveKey(IN_RELOAD)
    end
    if ply:GetNW2Bool("sv_nouse", false) then
        cmd:RemoveKey(IN_USE)
    end
end)

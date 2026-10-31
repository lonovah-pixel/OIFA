--[[---------------------------------------------------------------------------
CCTV (server).

Viewing a camera sets the player's view entity on the server (and adds the
camera to the player's PVS); the player stays at the monitor terminal.
A camera works only with sector power and a functional surveillance
subsystem. A camera that shows SCP-096's face makes the viewer a target,
except cameras inside SCP-096's cell while they are masked (containment
procedure). Cameras never count as observers of SCP-173.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Cctv = SV.Cctv
local Net = SV.Net
local U = SV.Util
local K = SV.Config.Cctv
local Facility = SV.Facility

SV.MapCfg.editorProps.camera = {name = true, sector = true}

Cctv.cameras = Cctv.cameras or {}   -- ent -> true
Cctv.viewers = Cctv.viewers or {}   -- ply -> {cam, terminal}

function Cctv.register(ent) Cctv.cameras[ent] = true end
function Cctv.unregister(ent) Cctv.cameras[ent] = nil end

--- Cameras in a stable order (by map point id).
function Cctv.list()
    local list = {}
    for ent in pairs(Cctv.cameras) do
        if IsValid(ent) then list[#list + 1] = ent end
    end
    table.sort(list, function(a, b) return (a.SVPoint and a.SVPoint.id or "") < (b.SVPoint and b.SVPoint.id or "") end)
    return list
end

local function camName(ent, i)
    local p = ent.SVPoint
    return (p and p.props.name) or ("Камера " .. i)
end

function Cctv.powered(cam)
    local p = cam.SVPoint
    local sector = p and p.props.sector or Facility.sectorAt(cam:GetPos())
    return Facility.devicePowered(sector, "cameras")
end

local function stopView(ply, reason)
    local v = Cctv.viewers[ply]
    if not v then return end
    Cctv.viewers[ply] = nil
    if IsValid(ply) then
        ply:SetViewEntity(ply)
        SV.Sync.setFor(ply, "self", "cctv", nil)
        if reason then DarkRP.notify(ply, 3, 4, "Видеонаблюдение: " .. reason .. ".") end
    end
end
Cctv.stop = stopView

function Cctv.view(ply, terminal, index)
    if not SV.Terminals.canUse(ply, terminal, "cctv") then return false end
    local list = Cctv.list()
    if #list == 0 then return false, "Камеры на карте не настроены." end
    index = math.Clamp(index, 1, #list)
    local cam = list[index]
    if not Cctv.powered(cam) then return false, camName(cam, index) .. ": нет сигнала." end
    Cctv.viewers[ply] = {cam = cam, terminal = terminal}
    ply:SetViewEntity(cam)
    SV.Sync.setFor(ply, "self", "cctv", {name = camName(cam, index), index = index, count = #list, terminal = terminal:EntIndex()})
    SV.Bus.emit("cctv.viewed", {ply = ply, camera = cam})
    return true
end

Net.handle("cctv.view", function(ply, terminal, index) return Cctv.view(ply, terminal, index) end)
Net.handle("cctv.stop", function(ply)
    stopView(ply)
    return true
end)

-- SCP-096's face on a monitor.
local function showsFace(cam, scp)
    local K096 = SV.Config.SCP.scp096
    local from = cam:GetPos()
    local head = scp:EyePos()
    local dir = head - from
    if dir:LengthSqr() > K.range * K.range then return false end
    dir:Normalize()
    if cam:GetForward():Dot(dir) < K.fov then return false end
    local back = from - head
    back:Normalize()
    if scp:GetAimVector():Dot(back) < K096.facingDot then return false end
    return not util.TraceLine({start = from, endpos = head, filter = {cam, scp}, mask = MASK_OPAQUE}).Hit
end

local function check096(ply, cam)
    local S096 = SV.SCP.S096
    local scp = SV.SCP.playerOf("scp096")
    local st = SV.SCP.get("scp096")
    if not S096 or not scp or not scp:Alive() or not st or st.data.bagged then return end
    local masked = st.data.maskedUntil and CurTime() < st.data.maskedUntil
    if masked and SV.SCP.inCell("scp096", cam:GetPos()) then return end
    if showsFace(cam, scp) then S096.addTarget(ply, "cctv") end
end

timer.Create("SiteVeil.Cctv", K.tick, 0, function()
    for ply, v in pairs(Cctv.viewers) do
        if not IsValid(ply) or not ply:Alive() then
            stopView(ply)
        elseif not IsValid(v.terminal) or not U.within(ply, v.terminal, K.stayRadius) then
            stopView(ply, "вы отошли от монитора")
        elseif not IsValid(v.cam) or not Cctv.powered(v.cam) then
            stopView(ply, "сигнал камеры потерян")
        else
            check096(ply, v.cam)
        end
    end
end)

hook.Add("EntityTakeDamage", "SiteVeil.Cctv", function(ent)
    if ent:IsPlayer() and Cctv.viewers[ent] then stopView(ent, "вас отвлекли") end
end)
hook.Add("PlayerDisconnected", "SiteVeil.Cctv", function(ply) Cctv.viewers[ply] = nil end)
hook.Add("SiteVeil.CharacterUnloading", "SiteVeil.Cctv", function(ply) stopView(ply) end)

hook.Add("SetupPlayerVisibility", "SiteVeil.Cctv", function(ply)
    local v = Cctv.viewers[ply]
    if v and IsValid(v.cam) then AddOriginToPVS(v.cam:GetPos()) end
end)

Facility.registerTerminal("cctv", {
    name = "Пост видеонаблюдения", req = {clearance = K.clearance, tags = K.tags}, power = 0.5,
    open = function(ply, ent)
        local cams = {}
        for i, cam in ipairs(Cctv.list()) do
            cams[#cams + 1] = {index = i, name = camName(cam, i), sector = Facility.sectorAt(cam:GetPos()), powered = Cctv.powered(cam)}
        end
        Net.send(ply, "cctv.open", {ent = ent:EntIndex(), cameras = cams})
    end,
})

SV.Perf.registry("cctv.viewers", function() return U.count(Cctv.viewers) end)

--[[---------------------------------------------------------------------------
Reproducible server randomness.

Gameplay rolls that matter (experiment outcomes, director choices, SCP
effects) use a seeded xorshift32 generator. Every roll source derives its
seed from the session seed and a stable identifier, and the seed is written
to the corresponding record, so any outcome can be reproduced with
`sv_rng_replay <seed>` or by starting the server with `sv_rng_seed <n>`.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.RNG = SV.RNG or {}
local RNG = SV.RNG

local seedConvar = CreateConVar("sv_rng_seed", "", FCVAR_ARCHIVE + FCVAR_PROTECTED,
    "SITE-VEIL: fixed session seed for reproducible tests (empty = random)")

local Gen = {}
Gen.__index = Gen

local function u32(x)
    if x < 0 then x = x + 4294967296 end
    return x
end

function RNG.new(seed)
    local s = bit.tobit(math.floor(seed or 0) % 4294967296)
    if s == 0 then s = bit.tobit(0x6d2b79f5) end
    local g = setmetatable({state = s, seed = u32(s), calls = 0}, Gen)
    -- Discard the first outputs: xorshift output is weak right after seeding.
    for _ = 1, 4 do g:nextU32() end
    g.calls = 0
    return g
end

function Gen:nextU32()
    local x = self.state
    x = bit.bxor(x, bit.lshift(x, 13))
    x = bit.bxor(x, bit.rshift(x, 17))
    x = bit.bxor(x, bit.lshift(x, 5))
    self.state = x
    self.calls = self.calls + 1
    return u32(x)
end

--- Uniform float in [0, 1).
function Gen:float()
    return self:nextU32() / 4294967296
end

--- Uniform integer in [lo, hi].
function Gen:int(lo, hi)
    return lo + math.floor(self:float() * (hi - lo + 1))
end

function Gen:chance(p)
    return self:float() < p
end

--- Picks a key from {key = weight, ...} (weights <= 0 are skipped).
--- Keys are visited in sorted order so the result does not depend on pairs().
function Gen:weighted(weights)
    local keys = SV.Util.keys(weights)
    local total = 0
    for _, k in ipairs(keys) do
        if weights[k] > 0 then total = total + weights[k] end
    end
    if total <= 0 then return nil end
    local roll = self:float() * total
    for _, k in ipairs(keys) do
        local w = weights[k]
        if w > 0 then
            if roll < w then return k end
            roll = roll - w
        end
    end
    return keys[#keys]
end

function Gen:pick(list)
    if #list == 0 then return nil end
    return list[self:int(1, #list)]
end

--[[---------------------------------------------------------------------------
Session seed
---------------------------------------------------------------------------]]
function RNG.sessionSeed()
    if not RNG._session then
        local fixed = tonumber(seedConvar:GetString())
        if fixed then
            RNG._session = math.floor(fixed) % 4294967296
            SV.Log.info("RNG: fixed session seed %d (sv_rng_seed)", RNG._session)
        else
            RNG._session = (os.time() * 7919 + math.floor(SysTime() * 1000)) % 4294967296
            SV.Log.info("RNG: session seed %d", RNG._session)
        end
    end
    return RNG._session
end

--- Seed for a roll source, e.g. RNG.seedFor("experiment", 42).
function RNG.seedFor(kind, id)
    return SV.Util.hash(RNG.sessionSeed() .. ":" .. kind .. ":" .. tostring(id))
end

function RNG.forSource(kind, id)
    return RNG.new(RNG.seedFor(kind, id))
end

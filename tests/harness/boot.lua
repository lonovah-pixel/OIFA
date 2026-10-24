--[[---------------------------------------------------------------------------
Emulates the SITE-VEIL load sequence of init.lua on top of gmod_mock.lua and
defines the test helpers used by tests/server/*.lua.

Real load:  sh_boot -> DeriveGamemode("darkrp") -> main stage -> Startup
Here:       sh_boot -> DarkRP hooks fired by hand -> main stage -> Startup
---------------------------------------------------------------------------]]

include("siteveil/gamemode/sh_boot.lua")

-- What DarkRP does while loading, reduced to the hooks SITE-VEIL relies on.
hook.Call("DarkRPPreLoadModules", GM)
hook.Call("DarkRPFinishedLoading", GM)

SiteVeil.BaseClass = MOCK.BaseClass
SiteVeil.Loader.loadStage("main")

-- Scripted entities and weapons of the gamemode (the engine loads these).
for _, class in ipairs(__host_list("siteveil/entities/entities")) do
    ENT = {}
    include("siteveil/entities/entities/" .. class .. "/shared.lua")
    scripted_ents.Register(ENT, class)
    ENT = nil
end
for _, class in ipairs(__host_list("siteveil/entities/weapons")) do
    SWEP = {Primary = {}, Secondary = {}}
    include("siteveil/entities/weapons/" .. class .. "/shared.lua")
    weapons.stored[class] = SWEP
    SWEP = nil
end
SiteVeil.Startup()
hook.Run("InitPostEntity")
MOCK.advance(2)

-- Test helpers ---------------------------------------------------------------
TEST_RESULTS = {passed = 0, failed = 0}

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function TEST(name, fn)
    MOCK.notifications = {}
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        TEST_RESULTS.passed = TEST_RESULTS.passed + 1
        io.write("  ok   " .. TESTFILE .. " :: " .. name .. "\n")
    else
        TEST_RESULTS.failed = TEST_RESULTS.failed + 1
        io.write("  FAIL " .. TESTFILE .. " :: " .. name .. "\n" .. tostring(err) .. "\n")
    end
    io.write("")
end

function expect(cond, msg)
    if not cond then error("expectation failed: " .. (msg or "?"), 2) end
end

function eq(a, b, msg)
    if a ~= b then error(string.format("expected %s, got %s%s", fmt(b), fmt(a), msg and (" (" .. msg .. ")") or ""), 2) end
end

function contains(haystack, needle, msg)
    if type(haystack) ~= "string" or not string.find(haystack, needle, 1, true) then
        error(string.format("expected %s to contain %s%s", fmt(haystack), fmt(needle), msg and (" (" .. msg .. ")") or ""), 2)
    end
end

--- Creates a joined player with a character in the given division and role.
function makeStaff(opts)
    opts = opts or {}
    local p = MOCK.join({name = opts.steam or "Tester", admin = opts.admin, superadmin = opts.superadmin})
    local div = opts.division or "classd"
    if opts.whitelist then
        SiteVeil.Chars.grantWhitelist(p:SteamID64(), "division", div, nil, "test")
    end
    MOCK.rpc(p, "char.create", opts.name or "Иван Петров", div, 1)
    local list = SiteVeil.Chars.listFor(p:SteamID64())
    local char = list[#list]
    assert(char, "character not created: " .. tostring(MOCK.lastNotify(p)))
    if opts.rank then
        SiteVeil.DB.query("UPDATE sv_characters SET rank = ? WHERE id = ?", opts.rank, char.id)
    end
    MOCK.rpc(p, "char.select", char.id)
    assert(p.SVChar, "character not selected: " .. tostring(MOCK.lastNotify(p)))
    if opts.role then
        local ok, msg = SiteVeil.Chars.assignRole(p, SiteVeil.Roles.get(opts.role), {reason = "test"})
        assert(ok, "role not assigned: " .. tostring(msg))
    end
    MOCK.advance(0.1) -- next-tick work (card sync)
    return p
end

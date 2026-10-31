--[[---------------------------------------------------------------------------
Addon loader robustness. The runner installs the broken test addons from
tests/fixtures/addons only for this file.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Addons = SV.Addons

local function status(id)
    local rec = Addons.byId[id]
    return rec and rec.status, rec and rec.error
end

TEST("broken addons are reported and do not stop the gamemode", function()
    for _, m in ipairs({"core", "characters", "facility", "scp", "admin"}) do expect(SV.Loaded[m], "module not loaded: " .. m) end
    local s, e = status("zz_broken_runtime")
    eq(s, "error")
    contains(e, "boom from a test addon")
    s, e = status("zz_missing_dep")
    eq(s, "error")
    contains(e, "zz_not_installed")
    s, e = status("zz_bad_id")
    eq(s, "error")
    contains(e, "does not match")
    s, e = status("zz_missing_module")
    eq(s, "error")
    contains(e, "no_such_module")
    expect(not SiteVeilTestMissingModuleRan, "files of an addon with a missing module ran")
    s = status("zz_noprefix")
    eq(s, "error")
    -- Errors are visible to admins.
    local seen = 0
    for _, err in ipairs(SV.Loader.errors) do
        if string.find(err, "addon 'zz_", 1, true) then seen = seen + 1 end
    end
    expect(seen >= 5, "addon errors not in the loader report")
    -- The real addons still work.
    for _, id in ipairs({"intercom", "decontamination", "tesla", "cctv", "scp999", "scoreboard"}) do eq(status(id), "loaded", id) end
end)

TEST("load order follows 'after'; config stage runs before roles are indexed", function()
    eq(status("zz_order_first"), "loaded")
    eq(status("zz_order_second"), "loaded")
    eq(SiteVeilTestOrder[1], "second")
    eq(SiteVeilTestOrder[2], "first")
    eq(SV.Config.TestAddonValue, 42)
    expect(not SiteVeilTestConfigSawRoles, "addon config ran after roles were indexed")
end)

TEST("disabled addons are not loaded", function()
    RunConsoleCommand("siteveil_addons_disabled", "zz_order_first, tesla")
    Addons.discover()
    eq(status("zz_order_first"), "disabled")
    eq(status("tesla"), "disabled")
    RunConsoleCommand("siteveil_addons_disabled", "")
end)

--[[---------------------------------------------------------------------------
Stage 7: administration panel (rights, whitelist, tickets, audit search).
---------------------------------------------------------------------------]]

local SV = SiteVeil

TEST("admin panel: rights are checked on the server", function()
    local user = MOCK.join({name = "User"})
    local admin = MOCK.join({name = "Admin", admin = true})
    MOCK.clearSent()
    MOCK.rpc(user, "admin.players")
    eq(#MOCK.pushes(user, "admin.players"), 0, "a normal player got the player list")
    MOCK.rpc(admin, "admin.players")
    local list = MOCK.pushes(admin, "admin.players")[1]
    expect(list and #list.data.list >= 2, "admin got no player list")
    MOCK.rpc(user, "admin.whitelist", user:SteamID64(), "division", "mtf", true, "")
    expect(not SV.Chars.hasWhitelist(user:SteamID64(), "division", "mtf"), "a player granted himself a whitelist")
end)

TEST("admin panel: whitelist grant/revoke validated and logged", function()
    local admin = MOCK.join({name = "Admin2", admin = true})
    local target = MOCK.join({name = "Target"})
    local sid = target:SteamID64()
    MOCK.rpc(admin, "admin.whitelist", sid, "division", "nonexistent", true, "")
    expect(not SV.Chars.hasWhitelist(sid, "division", "nonexistent"), "unknown division accepted")
    MOCK.rpc(admin, "admin.whitelist", "abc", "division", "mtf", true, "")
    expect(not SV.Chars.hasWhitelist("abc", "division", "mtf"), "bad SteamID accepted")
    MOCK.rpc(admin, "admin.whitelist", sid, "division", "mtf", true, "Заявка №1")
    expect(SV.Chars.hasWhitelist(sid, "division", "mtf"), "grant failed")
    MOCK.advance(0.5)
    MOCK.rpc(admin, "admin.whitelist", sid, "division", "mtf", false, "")
    expect(not SV.Chars.hasWhitelist(sid, "division", "mtf"), "revoke failed")
    SV.Audit.flush()
    local n = tonumber(SV.DB.queryValue("SELECT COUNT(*) FROM sv_audit WHERE action LIKE 'whitelist.%'"))
    expect(n >= 2, "whitelist actions not in the audit log")
end)

TEST("admin panel: tickets can be claimed, answered and closed; audit search filters", function()
    local admin = MOCK.join({name = "Admin3", admin = true})
    local user = MOCK.join({name = "User3"})
    local ok = SV.Comms.openTicket(user, "Застрял в текстурах у шлюза")
    expect(ok)
    local id = SV.Comms.nextTicket - 1
    MOCK.rpc(admin, "admin.ticket", id, "claim", "")
    eq(SV.Comms.tickets[id].status, "claimed")
    MOCK.advance(1)
    MOCK.rpc(admin, "admin.ticket", id, "reply", "Сейчас помогу")
    eq(#SV.Comms.tickets[id].messages, 2)
    MOCK.advance(1)
    MOCK.rpc(admin, "admin.ticket", id, "close", "")
    eq(SV.Comms.tickets[id].status, "closed")
    SV.Audit.flush()
    MOCK.clearSent()
    MOCK.rpc(admin, "admin.audit", {category = "admin", text = "ticket", minutes = 60})
    local res = MOCK.pushes(admin, "admin.audit")[1]
    expect(res and #res.data.list >= 3, "audit search returned nothing")
    for _, r in ipairs(res.data.list) do eq(r.category, "admin") end
end)

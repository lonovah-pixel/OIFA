--[[---------------------------------------------------------------------------
Access control (shared): network schema and requirement helpers.

A requirement is {clearance = 0..5, tags = {...}, tagMode = "any"|"all"}.
Credentials are cards registered in sv_cards (service ID cards issued with
every role kit, temporary passes). A credential grants its clearance and tags
while it is not revoked and not expired.
---------------------------------------------------------------------------]]

local SV = SiteVeil
SV.Access = SV.Access or {}
local Access = SV.Access
local Net = SV.Net

Access.CLEARANCE_NAMES = {
    [0] = "Допуск 0 — общий",
    [1] = "Допуск 1 — служебный",
    [2] = "Допуск 2 — ограниченный",
    [3] = "Допуск 3 — секретный",
    [4] = "Допуск 4 — совершенно секретный",
    [5] = "Допуск 5 — особой важности",
}

Access.TAG_NAMES = {
    dblock = "Блок D", storage = "Склады", science = "Научный сектор", labs = "Лаборатории",
    containment = "Камеры содержания", security = "Пост охраны", armory = "Оружейная",
    investigation = "Следственный отдел", engineering = "Инженерный сектор", maintenance = "Техзоны",
    power = "Энергоузлы", medical = "Медблок", administration = "Администрация", logistics = "Логистика",
    mtf = "МОГ", chaos = "Хаос",
}

--- Checks a requirement against clearance + tag set. Returns ok, reason.
function Access.meets(req, clearance, tags)
    if not req then return true end
    if (req.clearance or 0) > clearance then
        return false, "требуется допуск " .. req.clearance
    end
    local reqTags = req.tags
    if reqTags and #reqTags > 0 then
        if req.tagMode == "all" then
            for _, t in ipairs(reqTags) do
                if not tags[t] then return false, "нет допуска к зоне «" .. (Access.TAG_NAMES[t] or t) .. "»" end
            end
        else
            local any = false
            for _, t in ipairs(reqTags) do
                if tags[t] then any = true break end
            end
            if not any then
                local names = {}
                for _, t in ipairs(reqTags) do names[#names + 1] = Access.TAG_NAMES[t] or t end
                return false, "нужен доступ: " .. table.concat(names, " / ")
            end
        end
    end
    return true
end

Net.define("access.emergency", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.2}})
Net.define("access.issuePass", {args = {"ent", "u8", "str:120", "u8"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("access.revoke", {args = {"str:16", "str:120"}, rate = {burst = 3, refill = 0.2}})
Net.define("access.cards", {args = {}, rate = {burst = 2, refill = 0.3}})
Net.define("access.log", {args = {"ent"}, rate = {burst = 3, refill = 0.5}})
Net.define("access.crank", {args = {"ent"}, alive = true, rate = {burst = 2, refill = 0.3}})

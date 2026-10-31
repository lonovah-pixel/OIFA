--[[---------------------------------------------------------------------------
Polygraph (server).

An investigator with a polygraph asks one question. A cuffed or detained
person is tested without consent; anybody else must agree. The person
"hides something" if they hold or recently finished a hidden task, or read a
document above their clearance (a leak) recently. The reaction is rolled:
hitChance if hiding, falseChance otherwise (seeded, reproducible). The result
goes to the investigator and the audit log - never as proof.
---------------------------------------------------------------------------]]

local SV = SiteVeil
local Poly = SV.Polygraph
local Net = SV.Net
local DB = SV.DB
local U = SV.Util
local K = SV.Config.Polygraph

Poly.lastAt = Poly.lastAt or {}    -- char id -> CurTime
Poly.pending = Poly.pending or {}  -- target -> {by, question, expires}
Poly.count = Poly.count or 0

--- Whether the character has something to hide (server-side facts only).
function Poly.hiding(ply)
    local char = ply.SVChar
    if not char then return false end
    if SV.Hidden and SV.Hidden.active and SV.Hidden.active[ply] then return true end
    local since = os.time()
    if DB.queryValue("SELECT 1 FROM sv_leaks WHERE reader_char = ? AND time > ?", char.id, since - K.leakWindow) then return true end
    if SV.Hidden and DB.queryValue("SELECT 1 FROM sv_hidden_log WHERE char_id = ? AND outcome = 'done' AND ended_at > ?", char.id, since - K.hiddenWindow) then
        return true
    end
    return false
end

function Poly.blockedReason(by, target)
    if not SV.Inv.has(by, "polygraph") then return "нужен полиграф" end
    if not IsValid(target) or not target:IsPlayer() or not target.SVChar or target == by or SV.Roles.isSCP(target) then return "нет подходящего человека" end
    if not U.within(by, target, K.range) then return "подойдите ближе" end
    local last = Poly.lastAt[target.SVChar.id]
    if last and CurTime() - last < K.targetCooldown then return "этого человека недавно проверяли" end
    return nil
end

local function run(by, target, question)
    local why = Poly.blockedReason(by, target)
    if why then return false, "Проверка невозможна: " .. why .. "." end
    Poly.lastAt[target.SVChar.id] = CurTime()
    DarkRP.notify(target, 3, K.time, "Вас проверяют на полиграфе: «" .. question .. "»")
    return SV.Actions.start(by, {
        id = "polygraph", label = "Проверка на полиграфе", duration = K.time, target = target, maxDist = K.range + 20,
        canContinue = function(p) return SV.Inv.has(p, "polygraph"), "полиграф потерян" end,
        onComplete = function(p)
            Poly.count = Poly.count + 1
            local rng = SV.RNG.new(SV.RNG.seedFor("polygraph", target.SVChar.id * 10000 + Poly.count))
            local hiding = Poly.hiding(target)
            local reaction = rng:chance(hiding and K.hitChance or K.falseChance)
            Net.send(p, "poly.result", {name = SV.Chars.displayName(target), question = question,
                reaction = reaction and "выраженная реакция (стресс)" or "незначительная реакция"})
            SV.Audit.log("polygraph", "test", p, target, {question = question, reaction = reaction, hiding = hiding})
            SV.Bus.emit("polygraph.tested", {ply = p, target = target, reaction = reaction})
        end,
    })
end

Net.handle("poly.start", function(by, target, question)
    question = U.cleanText(question, 120)
    if U.utf8len(question) < 5 then return false, "Сформулируйте вопрос." end
    local why = Poly.blockedReason(by, target)
    if why then return false, "Проверка невозможна: " .. why .. "." end
    if SV.Security.restrained[target] or SV.Security.isDetained(target) then return run(by, target, question) end
    Poly.pending[target] = {by = by, question = question, expires = CurTime() + 20}
    Net.send(target, "poly.consent", {name = SV.Chars.displayName(by), question = question})
    return true, "Запрошено согласие на проверку."
end)

Net.handle("poly.consent", function(target, yes)
    local p = Poly.pending[target]
    Poly.pending[target] = nil
    if not p or p.expires < CurTime() or not IsValid(p.by) then return false, "Запрос больше не действует." end
    if not yes then
        DarkRP.notify(p.by, 3, 5, SV.Chars.displayName(target) .. " отказывается от проверки.")
        return true
    end
    local ok, msg = run(p.by, target, p.question)
    if msg then DarkRP.notify(p.by, ok and 0 or 1, 5, msg) end
    return ok
end)

hook.Add("PlayerDisconnected", "SiteVeil.Polygraph", function(ply) Poly.pending[ply] = nil end)

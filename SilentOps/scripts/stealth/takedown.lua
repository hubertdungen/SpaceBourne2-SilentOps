--[[
  Melee takedowns, witnesses and bodies (DESIGN.md section 5).

  A takedown is the vanilla melee swing (no takedown animation exists for the player).
  If it hits an unaware NPC from behind, the NPC dies at once and silently.

  STATUS (tested 2026-10-30): the kill from behind and the refusals (too far, not behind) work,
  with a melee-type hit applied the way the knife applies it (the test save had no melee weapon).
  Witnesses of a kill and found bodies verified in game on 2026-10-31.
]]

local U = require("stealth.util")
local G = require("stealth.gamedefs")
local P = G.P

local T = { bodies = {}, nextScan = 0, silent = {} }
local MAX_BODIES = 40

local function cfg() return STEALTH.cfg end

-- Post-hook of Q1_Shooter_AI:ReceivePointDamage, before awareness.onHit.
-- Returns true when the hit was a takedown (the NPC is dead).
function T.tryTakedown(A, N, npc, damageType, causer)
    local c = cfg().Takedown
    if not c.Enabled then return false end
    local e = A.entry(npc)
    if not (e and e.managed) or U.get(npc, P.Dead, false) then return false end
    local function no(why)
        if U.Verbose then U.log("no takedown: " .. why) end
        return false
    end
    if e.state == A.SEARCHING and not c.AllowSearchingTarget then return no("target is searching") end
    local dtn = U.className(damageType)
    if dtn ~= G.MeleeDamageTypeName then return no("damage type " .. tostring(dtn)) end
    local player = U.playerPawn(npc)
    if not (player and causer and U.addr(causer) == U.addr(player)) then
        return no("causer " .. tostring(U.className(causer)) .. " is not the player")
    end
    local kind = G.MeleeKind[U.className(U.get(player, P.MeleeWeapon, nil)) or ""] or "knife"
    if not c.Weapons[kind] then return no("melee kind " .. kind .. " not allowed") end
    if c.RequireCrouch and U.get(player, P.Stance, 0) ~= G.Stance.Crouching then return no("not crouched") end
    local np, nf, pp = U.location(npc), U.forward(npc), U.location(player)
    if not (np and nf and pp) then return no("no location") end
    local d, ang = U.dist(np, pp), U.angleTo(nf, np, pp)
    if d > c.MaxDistance then return no(string.format("too far (%.1f m)", d / 100)) end
    if ang < c.BehindAngle then return no(string.format("not behind it (%.0f deg)", ang)) end
    T.silent[U.addr(npc) or 0] = os.clock() -- before ForceToDead: OnDeadEvent may run inside it
    local ok = pcall(function() npc:ForceToDead() end) -- verified in game
    if not ok then return false end
    local n = cfg().Noise
    N.emit(np, kind == "hammer" and n.HeavyTakedown or n.Takedown, "takedown", "suspect", n.HeardBump)
    U.log("takedown (" .. kind .. ")")
    return true
end

-- Was this NPC just killed by a silent takedown?
function T.wasSilent(npc)
    local a = U.addr(npc)
    local t = a and T.silent[a]
    if t then T.silent[a] = nil end
    return t ~= nil and os.clock() - t < 5
end

local function los(from, to)
    local ok, v = pcall(function() return from.Controller:LineOfSightTo(to, { X = 0, Y = 0, Z = 0 }, false) end)
    return ok and v == true
end

-- Post-hook of Q1_Shooter_AI:OnDeadEvent: a body, a thud, maybe a cry, and witnesses.
--   Seeing a mate shot dead: weapon drawn, meter almost full, calls the others, maybe crouches
--   for cover, without knowing where the shooter is (it hunts: the first movement draws fire).
--   Seeing a mate knifed: the killer is right there, so if it can see you, combat.
function T.onDeath(A, N, npc, player)
    local pos = U.location(npc)
    if not pos then return end
    local silent = T.wasSilent(npc)
    N.emit(pos, cfg().Noise.BodyFall, "body", "suspect", cfg().Noise.HeardBump)
    if not silent then N.onPain(pos, true) end
    if cfg().Bodies.Enabled then
        if #T.bodies >= MAX_BODIES then table.remove(T.bodies, 1) end
        T.bodies[#T.bodies + 1] = { pos = pos, t = os.clock(), obj = npc, a = U.addr(npc), found = false }
    end
    local w = cfg().Witness
    local d = cfg().Detection
    local now = os.clock()
    local budget = d.MaxLineOfSightPerTick
    for _, e in pairs(A.npcs) do
        if budget <= 0 then break end
        local extra = d.Senses.ExtraAngle[A.senses(e, now)] or 0
        if e.managed and e.pos and e.fwd and U.dist(e.pos, pos) < w.Range
            and U.angleTo(e.fwd, e.pos, pos) <= d.PeripheralHalfAngle + extra then
            local wo = A.objOf(e)
            budget = budget - 1
            if wo and los(wo, npc) then
                if silent and player and U.dist(e.pos, U.location(player)) < w.Range and los(wo, player) then
                    A.alert(e, player, "saw a takedown")
                else
                    e.wantCover = math.random() < w.CoverChance
                    A.hunt(e, pos, "saw a mate die", w.SawKillMeter)
                    A.callHelp(e, pos, true, "mate called: man down")
                end
            end
        end
    end
end

-- About once a second from the tick: managed NPCs that walk into view of a body.
function T.tick(A, now)
    local b = cfg().Bodies
    if not b.Enabled or now < T.nextScan then return end
    T.nextScan = now + 1.0
    local keep = {}
    for _, body in ipairs(T.bodies) do
        if now - body.t < b.KeepSeconds then
            keep[#keep + 1] = body
            if not body.found then
                local actor = U.alive(body.obj, body.a) and body.obj or nil
                for _, e in pairs(A.npcs) do
                    if e.managed and e.pos and e.fwd and U.dist(e.pos, body.pos) < b.SeeRange
                        and U.angleTo(e.fwd, e.pos, body.pos) <= cfg().Detection.PeripheralHalfAngle then
                        local seen
                        if actor then
                            local w = A.objOf(e)
                            local ok, los = false, false
                            if w then ok, los = pcall(function() return w.Controller:LineOfSightTo(actor, { X = 0, Y = 0, Z = 0 }, false) end) end
                            seen = ok and los == true
                        else
                            seen = U.dist(e.pos, body.pos) < b.CloseRange -- body actor gone: only right next to it
                        end
                        if seen then
                            -- more aware and calls for help, but not a full alert (no shooter seen)
                            A.search(e, body.pos, "found a body", cfg().Witness.BodyMeter)
                            A.callHelp(e, body.pos, false, "mate called: body found")
                            body.found = true
                            break
                        end
                    end
                end
            end
        end
    end
    T.bodies = keep
end

return T

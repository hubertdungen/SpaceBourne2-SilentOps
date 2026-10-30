--[[
  Awareness of hostile NPCs (DESIGN.md sections 2 and 3).

  While an NPC is unaware the mod "manages" it with three vanilla switches:
    eyes off   (XVisionEye / RifleEye :SetActive(false))  -> vanilla sight cannot fire
    deaf       (AttackPlayerWhenSpawn = true)              -> every vanilla alert is a no-op
    melee lock (SwordAttackOn = true)                      -> no melee swing at a player 2 m away
  and runs its own sight model. When the NPC notices the player it is handed back to vanilla
  combat (switches restored, CheckForFirstFocus(player)).

  STATUS (tested in game 2026-10-30): the switches, sight meter, handover, shout, losing them and
  release on toggle-off all work. Anything not exercised yet is marked NOT TESTED YET.
]]

local U = require("stealth.util")
local G = require("stealth.gamedefs")
local P, BB = G.P, G.BB

local A = {
    npcs = {},          -- address -> entry (see newEntry)
    count = 0,
    on = false,         -- stealth active (main.lua)
    lastContact = 0,    -- os.clock() when an ALERT NPC last saw the player
    compromised = false,
    patrolBT = nil,     -- 1_VAL_New_BT asset, looked up once it is loaded
}

local FRESH = 3.0       -- s; an NPC's own 1 s hook refreshes its entry
local function cfg() return STEALTH.cfg end

-- States -----------------------------------------------------------------------
A.CALM, A.SUSPICIOUS, A.SEARCHING, A.ALERT, A.VANILLA = "calm", "suspicious", "searching", "alert", "vanilla"

local function newEntry(a, npc)
    return {
        a = a, obj = npc, seenAt = os.clock(),
        state = A.VANILLA, managed = false, meter = 0, stateAt = os.clock(),
        pos = nil, fwd = nil, lastKnown = nil, proxT = 0,
        orig = nil,              -- { deaf = bool, lock = bool } saved when first managed
        perception = 1.0, rangeMul = 1.0, alertedUntil = 0,
        logicStopped = false, moveUntil = 0,
    }
end

local function setState(e, s)
    if e.state ~= s then
        if U.Verbose then U.log(string.format("state %s %s -> %s (meter %.2f)", tostring(e.a), e.state, s, e.meter)) end
        e.state, e.stateAt = s, os.clock()
    end
end

-- Who can be managed: hostile, ready, not a wave spawn, not a boss/tank unless configured.
-- early: called at spawn (CalculateStats), before the NPC is Ready? and can see.
function A.eligible(npc, early)
    if (not early and not U.get(npc, P.Ready, false)) or U.get(npc, P.Dead, false) then return false, "not ready" end
    if U.get(npc, P.IsCompanion, false) or U.get(npc, P.CivilCompanion, false) then return false, "ally/civil" end
    if U.get(npc, P.AIType, 0) ~= G.AIType.Enemy then return false, "not hostile" end
    local c = cfg().Detection
    if U.get(npc, P.IsBoss, false) and not c.AffectBosses then return false, "boss" end
    if U.get(npc, P.SubType, 0) == G.SubType.Tank and not c.AffectTanks then return false, "tank" end
    return true
end

-- Base sight range of an NPC. With SightSource "eye" it is what the NPC's own eye is set to:
-- HTR 0.4.2 writes its doctrine's relaxed sight there (vanilla: 3500). The mod never resizes
-- the eyes itself. Verified in game (HTR 0.4.5: 25 m relaxed, 56 m alert).
local function rangeOf(npc)
    local c = cfg().Detection
    if c.SightSource == "eye" then
        local ok, d = pcall(function() return npc[P.EyeSight].DetectPyramidExtent.Distance end)
        if ok and type(d) == "number" and d > 0 then return d end
    end
    return c.SightRange
end

-- Per-NPC perception (small doctrine table; does not depend on HTR).
local function perceptionOf(npc)
    local c = cfg().Detection
    local p, r = 1.0, 1.0
    if U.get(npc, P.Raider, false) then p = c.Perception.Pirate
    elseif U.get(npc, P.Tier, 2) <= 1 then p = c.Perception.Militia
    elseif U.get(npc, P.Tier, 2) >= 3 then p = c.Perception.Elite end
    if U.get(npc, P.Sniper, false) then r = c.SniperRangeFactor end
    return p, r
end

-- Switches ----------------------------------------------------------------------
-- SetActive on both XVision eyes, as vanilla's TacticleMove does (verified in game).
local function setEyes(npc, on)
    for _, name in ipairs({ P.EyeSight, P.EyeRifle }) do
        local eye = U.get(npc, name, nil)
        if U.valid(eye) then pcall(function() eye:SetActive(on, false) end) end
    end
end

-- Blind at once; deaf + melee lock only once the NPC is Ready? (verified in game: vanilla reads
-- AttackPlayerWhenSpawn when the NPC becomes ready, so setting it earlier turns the NPC into a
-- spawn attacker that charges the player). Until then the deaf switch is "pending".
local function manage(e, npc)
    if not e.managed then
        setEyes(npc, false)
        e.managed = true
    end
    if e.deafOn then return end
    if not U.get(npc, P.Ready, false) then e.deafPending = true; return end
    if not e.orig then
        e.orig = { deaf = U.get(npc, P.Deaf, false), lock = U.get(npc, P.MeleeLock, false) }
    end
    U.set(npc, P.Deaf, true)
    if cfg().Takedown.MeleeLock then U.set(npc, P.MeleeLock, true) end
    e.deafOn, e.deafPending = true, false
end

-- StopLogic / RestartLogic on the NPC's behaviour tree (verified in game).
local function brain(npc)
    local ok, b = pcall(function() return npc.Controller.BrainComponent end)
    if ok and U.valid(b) then return b end
    return nil
end

local function stopLogic(e, npc)
    if e.logicStopped then return end
    local b = brain(npc)
    if b then pcall(function() b:StopLogic("SilentOps") end) end
    e.logicStopped = true
end

local function restartLogic(e, npc)
    if not e.logicStopped then return end
    pcall(function() npc.Controller:K2_ClearFocus() end)
    local b = brain(npc)
    if b then pcall(function() b:RestartLogic() end) end
    e.logicStopped, e.lookAt = false, nil
end

-- Suspicious: stop and turn to look at what was seen or heard (no walking yet).
local function look(e, npc)
    if not e.lastKnown or (e.lookAt and U.dist(e.lookAt, e.lastKnown) < 100) then return end
    stopLogic(e, npc)
    pcall(function() npc.CharacterMovement:StopMovementImmediately() end)
    pcall(function() npc.Controller:K2_SetFocalPoint(e.lastKnown) end)
    e.lookAt = e.lastKnown
end

local function release(e, npc)
    if not e.managed then return end
    restartLogic(e, npc)
    if e.deafOn then
        U.set(npc, P.Deaf, e.orig and e.orig.deaf or false)
        U.set(npc, P.MeleeLock, e.orig and e.orig.lock or false)
    end
    setEyes(npc, true)
    e.managed, e.deafOn, e.deafPending = false, false, false
end

-- Forget what the eyes last saw. Switching the eyes off does not fire OnTargetLost, so vanilla
-- keeps CurrentDetected / CanSeeTheTarget: then CheckForFirstFocus ignores the next alert and the
-- mod would read "can see" forever (verified in game; clearing them works).
local function forgetTarget(npc)
    pcall(function() npc.CurrentDetected.DetectedActor = nil end)
    U.set(npc, P.CanSee, false)
end

-- Registry ----------------------------------------------------------------------
-- Called from the NPC's own hooks (spawn, 1 s think, damage, death). Refreshes the kept reference.
-- early = true from the spawn hook: manage it before its eyes can fire for the first time.
function A.track(npc, early)
    local a = U.addr(npc)
    if not a then return nil end
    local e = A.npcs[a]
    if not e then
        if A.count > 400 then
            -- drop stale entries only: a live managed NPC must never be forgotten (it would stay deaf)
            for k, old in pairs(A.npcs) do
                if os.clock() - old.seenAt > FRESH then A.npcs[k] = nil; A.count = A.count - 1 end
            end
            if A.count > 400 then return nil end
        end
        e = newEntry(a, npc)
        A.npcs[a] = e
        A.count = A.count + 1
    end
    e.obj, e.seenAt = npc, os.clock()
    e.pos, e.fwd = U.location(npc), U.forward(npc)
    -- HTR's relaxed sight, not its alert one: after "losing them" HTR needs up to a second (its
    -- own 1 Hz think) to switch the eyes back to relaxed, so wait 3 s (seen in game).
    if e.state ~= A.ALERT and os.clock() - (e.unalertAt or -1e9) > 3 then e.baseRange = rangeOf(npc) end
    if e.managed then
        -- Vanilla turns the eyes back on after a TacticleMove and clears SwordAttackOn after
        -- its own attacks: re-assert once a second. If vanilla combat started anyway, follow it.
        if U.get(npc, P.CanSee, false) then
            A.alert(e, U.playerPawn(npc), "vanilla")
        else
            if e.deafPending then manage(e, npc) end -- now Ready?: deaf + lock
            setEyes(npc, false)
            if e.deafOn and cfg().Takedown.MeleeLock then U.set(npc, P.MeleeLock, true) end
        end
    elseif A.on and e.state == A.VANILLA and not e.everAlert then
        local ok = A.eligible(npc, early)
        if ok and (U.bbGetBool(npc, BB.InCombat) or U.get(npc, P.CanSee, false)) then
            -- already fighting when stealth was switched on: stays in vanilla combat
            -- (counted as ALERT, so "losing them" can still calm it down later)
            e.everAlert = true
            setState(e, A.ALERT)
            A.compromised, A.lastContact = true, os.clock()
        elseif ok and not U.get(npc, P.Deaf, false) then
            -- (wave / drop-ship spawns come with AttackPlayerWhenSpawn already true: left vanilla)
            e.perception, e.rangeMul = perceptionOf(npc)
            manage(e, npc)
            e.state, e.stateAt, e.meter = A.CALM, os.clock(), 0
        end
    end
    return e
end

function A.entry(npc) local a = U.addr(npc); return a and A.npcs[a] or nil end

-- Usable object of an entry, or nil (stale / destroyed / unloaded).
local function objOf(e)
    if os.clock() - e.seenAt > FRESH then return nil end
    if U.alive(e.obj, e.a) and not U.get(e.obj, P.Dead, false) then return e.obj end
    return nil
end
A.objOf = objOf

-- Transitions -------------------------------------------------------------------
-- Hand an NPC to vanilla combat. (Verified in game.)
function A.alert(e, player, reason)
    local npc = objOf(e)
    if not npc then return end
    release(e, npc)
    setState(e, A.ALERT)
    e.everAlert, e.meter = true, 1
    -- InCombat? = true: HTR 0.4.2 switches it to alert sight at its next think (<= 1 s) and keeps
    -- it firing; the vanilla patrol tree also takes its combat branch (verified in game).
    U.bbSetBool(npc, BB.InCombat, true)
    if player then pcall(function() npc:CheckForFirstFocus(player) end) end
    A.compromised, A.lastContact = true, os.clock()
    U.log("ALERT " .. tostring(e.a) .. " (" .. tostring(reason) .. ")")
    if reason ~= "shout" and cfg().Detection.Shout then A.shout(e, player) end
end

-- Neighbours that can see the alerted NPC are alerted too (vanilla WarnOthers does nothing on
-- deaf NPCs). Verified in game: a shout alerted a neighbour.
function A.shout(src, player)
    local r = cfg().Detection.ShoutRadius
    local srcObj = objOf(src)
    if not (srcObj and src.pos) then return end
    for _, e in pairs(A.npcs) do
        if e ~= src and e.managed and e.pos and U.dist(e.pos, src.pos) < r then
            local npc = objOf(e)
            local ok, los = false, false
            if npc then
                ok, los = pcall(function() return npc.Controller:LineOfSightTo(srcObj, { X = 0, Y = 0, Z = 0 }, false) end)
            end
            if ok and los == true then A.alert(e, player, "shout") end
        end
    end
end

-- Something is wrong, position unknown (loud noise, body, mate hit).
function A.search(e, where, why)
    if U.Verbose then U.log("search " .. tostring(e.a) .. ": " .. tostring(why)) end
    if e.state == A.ALERT or e.state == A.VANILLA then return end
    e.lastKnown = where or e.lastKnown
    e.meter = math.max(e.meter, cfg().Detection.SuspiciousAt)
    e.alertedUntil = os.clock() + cfg().Detection.AlertedMemorySeconds
    setState(e, A.SEARCHING)
    e.moveUntil = 0 -- pick a search point on the next tick
end

-- A heard or half-seen event.
function A.suspect(e, where, bump, why)
    if U.Verbose then U.log("suspect " .. tostring(e.a) .. ": " .. tostring(why)) end
    if e.state == A.ALERT or e.state == A.VANILLA then return end
    e.lastKnown = where or e.lastKnown
    e.meter = math.min(0.99, e.meter + (bump or 0))
    if e.state == A.CALM and e.meter >= cfg().Detection.SuspiciousAt then setState(e, A.SUSPICIOUS) end
end

-- Losing them: ALERT NPCs go back to searching (verified in game).
-- Eyes off first: HTR 0.4.2 re-starts firing from the RifleEye hook, which then cannot run.
-- InCombat? = false also returns the NPC to HTR's relaxed sight.
local function unalert(e)
    local npc = objOf(e)
    if not npc then return end
    manage(e, npc)
    e.unalertAt = os.clock()
    pcall(function() npc:StopShoot() end)
    forgetTarget(npc)
    U.bbSetBool(npc, BB.InCombat, false)
    U.bbSetBool(npc, BB.CanSeeTarget, false)
    pcall(function() npc.Controller:K2_ClearFocus() end)
    -- The patrol tree is loaded whenever shooters exist, so this lookup should hit; a miss costs
    -- ~37 ms, so after one miss wait 30 s before trying again.
    if not U.valid(A.patrolBT) and os.clock() - (A.patrolBTMissAt or -1e9) > 30 then
        A.patrolBT = StaticFindObject(G.PatrolBT)
        if not U.valid(A.patrolBT) then A.patrolBTMissAt = os.clock() end
    end
    if U.valid(A.patrolBT) then pcall(function() npc.Controller:RunBehaviorTree(A.patrolBT) end) end
    setState(e, A.CALM) -- leave ALERT first: search() ignores ALERT NPCs
    e.meter = 0
    A.search(e, e.lastKnown, "lost contact")
end

-- Sight model (pure maths) ----------------------------------------------------------
-- me: snapshot of the player { pos, stance, speed, gait, light }. Returns the meter fill rate
-- per second if the NPC could see the player (line of sight is checked by the caller), 0 if not,
-- plus a flag for "instant" alert.
function A.sightRate(e, me)
    local c = cfg().Detection
    if not (e.pos and e.fwd and me.pos) then return 0, false end
    local d = U.dist(e.pos, me.pos)
    local searching = e.state == A.SEARCHING or os.clock() < e.alertedUntil
    local base = (e.baseRange or c.SightRange) * (searching and c.SearchingRangeFactor or 1.0)
    local rangeMul = e.rangeMul * (me.light and c.FlashlightRangeFactor or 1.0)
    if d > base * rangeMul then return 0, false end
    local ang = U.angleTo(e.fwd, e.pos, me.pos)
    local cone = 0
    if ang <= c.CentralHalfAngle then cone = 1.0 elseif ang <= c.PeripheralHalfAngle then cone = c.PeripheralFactor end
    if cone <= 0 then return 0, false end
    -- Realism (tuned in game): posture and light decide HOW FAR you can be made out; movement
    -- mostly decides HOW FAST attention builds. Standing still in the open is still seen.
    local stance = (me.stance == G.Stance.Crouching) and c.Stance.Crouching or c.Stance.Standing
    local key
    if me.speed < c.StillSpeed then key = "Still"
    elseif me.gait == G.Gait.Sprinting then key = "Sprint"
    elseif me.gait == G.Gait.Running then key = "Run"
    else key = "Walk" end
    local light = me.light and c.FlashlightFactor or 1.0
    local effRange = base * rangeMul * stance * c.MovementRange[key] * c.AmbientLight
    if d >= effRange then return 0, false end
    local perception = e.perception * (searching and c.AlertedPerception or 1.0)
    local instant = d < c.InstantAlertRange and cone >= 1.0 and not (me.stance == G.Stance.Crouching and key == "Still")
    local rate = U.lerp(c.FillNearPerSec, c.FillFarPerSec, d / effRange) * cone * stance * c.Movement[key] * light
        * c.AmbientLight * perception
    return rate, instant
end

-- Investigation movement: StopLogic + focal point + MoveToLocation (verified in game).
local function investigate(e, npc, now)
    if not e.lastKnown or now < e.moveUntil then return end
    local c = cfg().Detection
    local target = e.lastKnown
    if e.state == A.SEARCHING then -- a random point around the last known position
        local ang, r = math.random() * 2 * math.pi, math.random() * c.SearchRadius
        target = { X = e.lastKnown.X + r * math.cos(ang), Y = e.lastKnown.Y + r * math.sin(ang), Z = e.lastKnown.Z }
    end
    stopLogic(e, npc)
    e.lookAt = target
    pcall(function() npc.Controller:K2_SetFocalPoint(target) end)
    pcall(function() npc.Controller:MoveToLocation(target, 100.0, true, true, true, false, nil, true) end)
    e.moveUntil = now + c.InvestigateStepSeconds
end

-- Tick ------------------------------------------------------------------------------
-- Called ~5 times a second on the game thread. player: live pawn. Returns a HUD summary.
-- LineOfSightTo costs ~0.015 ms; kept references read invalid once collected (verified in game).
function A.tick(player, me, dt)
    local c = cfg().Detection
    local now = os.clock()
    local sum = { suspicious = 0, searching = 0, alert = 0, maxMeter = 0 }
    local losBudget = c.MaxLineOfSightPerTick
    for a, e in pairs(A.npcs) do
        local npc = objOf(e)
        if not npc then
            if now - e.seenAt > FRESH then A.npcs[a] = nil; A.count = math.max(0, A.count - 1) end
        elseif e.state == A.ALERT then
            if U.get(npc, P.CanSee, false) then A.lastContact = now end
        elseif e.managed and me.pos and e.pos and U.dist(e.pos, me.pos) < c.BubbleRadius then
            e.pos, e.fwd = U.location(npc) or e.pos, U.forward(npc) or e.fwd
            local rate, instant = A.sightRate(e, me)
            local seen = false
            if rate > 0 and losBudget > 0 then
                losBudget = losBudget - 1
                local ok, v = pcall(function() return npc.Controller:LineOfSightTo(player, { X = 0, Y = 0, Z = 0 }, false) end)
                seen = ok and v == true
                if U.Verbose and not ok then e.dbgErr = tostring(v) end
            end
            if U.Verbose then e.dbgRate, e.dbgSeen, e.dbgAng = rate, seen, U.angleTo(e.fwd, e.pos, me.pos) end
            -- proximity: someone right next to you notices unless you are crouched and still
            local d = U.dist(e.pos, me.pos)
            local quiet = me.stance == G.Stance.Crouching and me.speed < c.StillSpeed
            if d < c.ProximityRange and not quiet then e.proxT = e.proxT + dt else e.proxT = 0 end
            if (seen and instant) or e.proxT > c.ProximitySeconds then
                A.alert(e, player, "close")
            elseif seen then
                e.meter = e.meter + rate * dt
                e.lastKnown = me.pos
                if e.meter >= 1.0 then A.alert(e, player, "seen")
                elseif e.state == A.CALM and e.meter >= c.SuspiciousAt then setState(e, A.SUSPICIOUS) end
            else
                e.meter = math.max(0, e.meter - c.DecayPerSec * dt)
            end
            if (e.state == A.SUSPICIOUS and e.meter >= c.InvestigateAt) or e.state == A.SEARCHING then
                investigate(e, npc, now)
            elseif e.state == A.SUSPICIOUS then
                look(e, npc)
            end
            if e.state == A.SUSPICIOUS and e.meter <= 0.02 then
                restartLogic(e, npc); setState(e, A.CALM)
            elseif e.state == A.SEARCHING and now - e.stateAt > c.SearchSeconds and e.meter < c.SuspiciousAt then
                restartLogic(e, npc); setState(e, A.CALM)
            end
            if e.state == A.SUSPICIOUS then sum.suspicious = sum.suspicious + 1 end
            if e.state == A.SEARCHING then sum.searching = sum.searching + 1 end
            if e.state ~= A.ALERT then sum.maxMeter = math.max(sum.maxMeter, e.meter) end
        end
    end
    -- count ALERT NPCs after this tick's changes (alerts and shouts above)
    for _, e in pairs(A.npcs) do if e.state == A.ALERT then sum.alert = sum.alert + 1 end end
    -- losing them
    if A.compromised and sum.alert > 0 and now - A.lastContact > c.LoseSeconds then
        for _, e in pairs(A.npcs) do if e.state == A.ALERT then unalert(e) end end
        A.compromised = false
        sum.lost = true
    elseif sum.alert == 0 then
        A.compromised = false
    end
    sum.compromised = A.compromised
    return sum
end

-- Hooks -----------------------------------------------------------------------------
-- After ReceivePointDamage: a managed NPC that survives a hit knows it is under attack.
-- (Takedowns are decided first, in takedown.lua.)
function A.onHit(npc, causer)
    local e = A.entry(npc)
    if not (e and e.managed) or U.get(npc, P.Dead, false) then return end
    local player = U.playerPawn(npc)
    if causer and player and U.addr(causer) == U.addr(player) then
        A.alert(e, player, "shot")
    else
        A.search(e, U.location(npc), "hit by " .. tostring(U.className(causer))) -- squad, explosion...
    end
end

-- Debug.Log: one line per NPC near the player (state, meter, distance, sight range).
function A.debugLines(me)
    local out = {}
    for a, e in pairs(A.npcs) do
        if e.pos and me.pos and e.state ~= A.VANILLA then
            local d = U.dist(e.pos, me.pos)
            if d < cfg().Detection.BubbleRadius then
                out[#out + 1] = string.format("  %s %s m=%.2f d=%.0fm range=%.0fm managed=%s ang=%.0f rate=%.2f seen=%s%s",
                    tostring(a), e.state, e.meter, d / 100, (e.baseRange or 0) / 100, tostring(e.managed), e.dbgAng or -1,
                    e.dbgRate or -1, tostring(e.dbgSeen), e.dbgErr and (" err=" .. e.dbgErr) or "")
            end
        end
    end
    return out
end

function A.onDead(npc)
    local a = U.addr(npc)
    local e = a and A.npcs[a]
    if e then A.npcs[a] = nil; A.count = math.max(0, A.count - 1) end
    return e
end

-- Stealth switched off (or a level unloads): give every NPC back to vanilla, silently.
function A.releaseAll()
    for a, e in pairs(A.npcs) do
        local npc = objOf(e)
        if npc and e.managed then release(e, npc) end
        e.state = A.VANILLA
    end
    A.compromised = false
end

return A

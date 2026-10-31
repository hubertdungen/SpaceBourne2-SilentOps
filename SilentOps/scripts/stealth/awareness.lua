--[[
  Awareness of hostile NPCs (DESIGN.md sections 2 and 3).

  While an NPC is unaware the mod "manages" it with three vanilla switches:
    eyes off   (XVisionEye / RifleEye :SetActive(false))  -> vanilla sight cannot fire
    deaf       (AttackPlayerWhenSpawn = true)              -> every vanilla alert is a no-op
    melee lock (SwordAttackOn = true)                      -> no melee swing at a player 2 m away
  and runs its own sight model. When the NPC notices the player it is handed back to vanilla
  combat (switches restored, CheckForFirstFocus(player)).

  0.2 adds (DESIGN.md section 14): instant combat when you stand a few metres in front of an NPC,
  "at least suspicious" when you stand in view far away, senses that sharpen with suspicion,
  training (militia notice slower, elites faster and react faster), and hunting: an NPC that heard
  gunfire or saw a mate die draws its weapon, searches towards it and reacts to the first movement.

  STATUS (tested in game 2026-10-30 and 2026-10-31): the switches, sight meter, instant combat up
  close, far notice, sharpened senses, hunting (weapon drawn), handover, shout, losing them and
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
        perception = 1.0, rangeMul = 1.0, training = "Regular", alertedUntil = 0,
        logicStopped = false, moveUntil = 0,
        hunting = false,         -- heard gunfire / saw a mate die: weapon drawn, first movement draws fire
        drawn = false, crouched = false, -- poses set by the mod (restored when it calms down)
        reactAt = nil,           -- spotted: hands over to combat at this time (reaction time)
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

-- Training, same rule as HTR's doctrines (raiders = pirates, Tier 1 = militia, Tier 3+ = elite,
-- else regulars). It scales how fast an NPC notices you, its "instant" distances and its
-- reaction time. Does not need HTR.
local function trainingOf(npc)
    if U.get(npc, P.Raider, false) then return "Pirate" end
    local tier = U.get(npc, P.Tier, 2)
    if tier <= 1 then return "Militia" end
    if tier >= 3 then return "Elite" end
    return "Regular"
end

local function perceptionOf(npc)
    local c = cfg().Detection
    local t = trainingOf(npc)
    local r = U.get(npc, P.Sniper, false) and c.SniperRangeFactor or 1.0
    return c.Perception[t] or 1.0, r, t
end

-- Alert level (Cooper colours, DESIGN.md 17.1): 1 Blue relaxed, 2 Green normal attention,
-- 3 Yellow suspicious, 4 Orange danger known (hunting), 5 Red combat. Levels 1-4 index the
-- Detection.Senses tables. Blue/Green is the NPC's baseline (training), raised to Green for a few
-- minutes after any evidence (alertedUntil) and near a recent fight.
A.BLUE, A.GREEN, A.YELLOW, A.ORANGE, A.RED = 1, 2, 3, 4, 5
A.fights = {} -- { pos, t } where NPCs went Red recently (max 8)
local function nearFight(e, now)
    local c = cfg().Detection
    if not e.pos then return false end
    for _, f in ipairs(A.fights) do
        if now - f.t < c.AreaSeconds and U.dist(e.pos, f.pos) < c.AreaRadius then return true end
    end
    return false
end
local function level(e, now)
    if e.state == A.ALERT then return A.RED end
    if e.hunting then return A.ORANGE end
    if e.state == A.SUSPICIOUS or e.state == A.SEARCHING then return A.YELLOW end
    if (e.baseline or A.BLUE) >= A.GREEN or now < e.alertedUntil or nearFight(e, now) then return A.GREEN end
    return A.BLUE
end
A.level = level
local function senses(e, now) return math.min(level(e, now), A.ORANGE) end
A.senses = senses

-- Hearing factor of an NPC right now (noise.lua).
function A.hearing(e, now)
    return cfg().Detection.Senses.Hearing[senses(e, now)] or 1.0
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

-- Weapon drawn: the ALS "aiming" pose vanilla uses when an NPC spots a target (SetRotationMode(2)).
-- The eyes stay off, so nothing fires (HTR resumes fire only from the eye hook).
local function draw(e, npc, on)
    if on == e.drawn then return end
    if on then
        -- patrols walk in mode 0 (VelocityDirection); an NPC back from a fight is still aiming
        local r = U.get(npc, P.RotationMode, 0)
        e.origRot = (r == G.Rotation.Aiming) and 0 or r
    end
    pcall(function() npc:SetRotationMode(on and G.Rotation.Aiming or (e.origRot or 0)) end)
    e.drawn = on
end

-- Taking cover without knowing where the shooter is: crouch where it stands (vanilla's own
-- cover routine needs a target).
local function crouch(e, npc, on)
    if on == e.crouched then return end
    pcall(function() npc:SetStance(on and G.Stance.Crouching or G.Stance.Standing) end)
    e.crouched = on
end

-- Back to patrol: behaviour tree on, weapon lowered, standing.
local function calm(e, npc)
    restartLogic(e, npc)
    draw(e, npc, false)
    crouch(e, npc, false)
    e.hunting, e.reactAt, e.wantCover, e.raiseAt = false, nil, false, nil
    setState(e, A.CALM)
end

-- keepPose: handing over to combat (vanilla sets its own pose); else restore ours.
local function release(e, npc, keepPose)
    if not e.managed then return end
    restartLogic(e, npc)
    if not keepPose then draw(e, npc, false); crouch(e, npc, false) end
    e.drawn, e.crouched, e.hunting, e.reactAt, e.wantCover, e.raiseAt = false, false, false, nil, false, nil
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
            e.perception, e.rangeMul, e.training = perceptionOf(npc)
            e.baseline = (cfg().Detection.Baseline[e.training] == "Green") and A.GREEN or A.BLUE
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
    release(e, npc, true)
    setState(e, A.ALERT)
    e.everAlert, e.meter = true, 1
    -- InCombat? = true: HTR 0.4.2 switches it to alert sight at its next think (<= 1 s) and keeps
    -- it firing; the vanilla patrol tree also takes its combat branch (verified in game).
    U.bbSetBool(npc, BB.InCombat, true)
    if player then pcall(function() npc:CheckForFirstFocus(player) end) end
    A.compromised, A.lastContact = true, os.clock()
    -- a fight here: everyone around stays at least Green for a while (DESIGN.md 17.5)
    if e.pos then
        if #A.fights >= 8 then table.remove(A.fights, 1) end
        A.fights[#A.fights + 1] = { pos = e.pos, t = os.clock() }
    end
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

-- Something is wrong, position unknown (body found, mate calling, moans). meter: at least this.
function A.search(e, where, why, meter)
    if U.Verbose then U.log("search " .. tostring(e.a) .. ": " .. tostring(why)) end
    if e.state == A.ALERT or e.state == A.VANILLA or e.reactAt then return end
    e.lastKnown = where or e.lastKnown
    e.meter = math.min(0.99, math.max(e.meter, meter or cfg().Detection.SuspiciousAt))
    e.alertedUntil = os.clock() + cfg().Detection.AlertedMemorySeconds
    if e.state ~= A.SEARCHING then
        setState(e, A.SEARCHING)
        e.moveUntil = 0 -- pick a search point on the next tick
    else
        e.stateAt = os.clock() -- a new clue: search longer
    end
end

-- Gunfire heard or a mate killed in front of it: search towards it with the weapon drawn; the
-- first movement it sees draws fire. Never a full alert by itself: it does not know where you are.
function A.hunt(e, where, why, meter)
    if e.state == A.ALERT or e.state == A.VANILLA or e.reactAt then return end
    A.search(e, where, why, meter or 0.8)
    if not e.hunting and U.Verbose then U.log("hunt " .. tostring(e.a) .. ": " .. tostring(why)) end
    e.hunting = true
end

-- A heard or half-seen event.
function A.suspect(e, where, bump, why)
    if U.Verbose then U.log("suspect " .. tostring(e.a) .. ": " .. tostring(why)) end
    if e.state == A.ALERT or e.state == A.VANILLA or e.reactAt then return end
    e.lastKnown = where or e.lastKnown
    e.meter = math.min(0.99, e.meter + (bump or 0))
    if e.state == A.CALM and e.meter >= cfg().Detection.SuspiciousAt then setState(e, A.SUSPICIOUS) end
end

-- Gunfire, explosions, a turret: each one heard adds to the meter (closer = more). Past
-- HuntAt the NPC hunts; more shots keep pushing it, so the picture becomes obvious.
function A.hearAlarm(e, where, bump, why)
    if e.state == A.ALERT or e.state == A.VANILLA or e.reactAt then return end
    e.lastKnown = where or e.lastKnown
    e.meter = math.min(0.99, e.meter + bump)
    if e.meter >= cfg().Detection.HuntAt then
        A.hunt(e, where, why, e.meter)
    else
        A.suspect(e, where, 0, why)
    end
end

-- A mate calls for help (witness, body found): managed NPCs nearby hear the call, no sight needed.
function A.callHelp(src, where, hunt, why)
    local c = cfg().Witness
    if not (src.pos and c.CallRadius > 0) then return end
    for _, e in pairs(A.npcs) do
        if e ~= src and e.managed and e.pos and U.dist(e.pos, src.pos) < c.CallRadius then
            if hunt then A.hunt(e, where, why, c.CalledMeter) else A.search(e, where, why, c.CalledMeter) end
        end
    end
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
    -- still on edge after a fight: weapon drawn, the first movement it sees draws fire
    A.hunt(e, e.lastKnown, "lost contact", cfg().Detection.HuntAt)
end

-- Sight model (pure maths) ----------------------------------------------------------
-- me: snapshot of the target { pos, stance, speed, gait, light }. exp: exposure 0..1 (share of the
-- target's head / chest / knees the NPC can see, DESIGN.md 17.3); backdrop: 1.0 open, less with a
-- wall right behind the target. Returns the meter fill rate per second (0 if it cannot be made
-- out), a flag for "instant" (combat at once) and a meter cap (noticed but not identified).
function A.sightRate(e, me, now, exp, backdrop)
    local c = cfg().Detection
    if not (e.pos and e.fwd and me.pos) then return 0, false end
    now = now or os.clock()
    exp = exp or 1.0
    if exp <= 0 then return 0, false end
    local lv = senses(e, now)
    local s = c.Senses
    local d = U.dist(e.pos, me.pos)
    -- the alert level sharpens or dulls the senses: farther and wider when uneasy
    local base = (e.baseRange or c.SightRange) * e.rangeMul * (s.Range[lv] or 1.0)
        * (me.light and c.FlashlightRangeFactor or 1.0)
    local crouched = me.stance == G.Stance.Crouching
    if d > base * (crouched and 1.0 or c.FarNoticeFactor) then return 0, false end
    local ang = U.angleTo(e.fwd, e.pos, me.pos)
    local extra = s.ExtraAngle[lv] or 0
    local central = ang <= c.CentralHalfAngle + extra
    local cone = 0
    if central then cone = 1.0 elseif ang <= c.PeripheralHalfAngle + extra then cone = c.PeripheralFactor end
    if cone <= 0 then return 0, false end
    local train = e.perception
    local exposed = exp >= 0.66 -- most of the body in view
    local key
    if me.speed < c.StillSpeed then key = "Still"
    elseif me.gait == G.Gait.Sprinting then key = "Sprint"
    elseif me.gait == G.Gait.Running then key = "Run"
    else key = "Walk" end
    local light = me.light and c.FlashlightFactor or 1.0
    -- Crouching mostly makes you slower to notice; being covered (low exposure) or against a
    -- backdrop is what shortens the distance you can be made out at.
    local stanceRange = crouched and c.Stance.Crouching or c.Stance.Standing
    local stanceFill = crouched and c.StanceFill.Crouching or c.StanceFill.Standing
    local expRange = c.ExposureRangeMin + (1 - c.ExposureRangeMin) * exp
    local effRange = base * stanceRange * c.MovementRange[key] * c.AmbientLight * expRange * (backdrop or 1.0)
    if d >= effRange then
        -- Standing figure in plain view beyond the normal range: "someone is over there" -
        -- suspicious, it goes to look, but it cannot be sure from here (meter capped).
        if not crouched and central and exposed then return c.StandingNoticePerSec * train, false, c.InvestigateAt end
        return 0, false
    end
    -- In plain view a few metres away there is nothing to "notice": it is combat at once.
    local instant = false
    if exposed then
        if crouched then
            instant = central and key ~= "Still" and d < c.InstantRangeCrouched * train
        else
            instant = (central and d < c.InstantRange * train) or d < c.InstantRangeSide * train
        end
        -- Orange (hunting): the first movement it sees draws fire.
        if e.hunting and key ~= "Still" and (not crouched or d < effRange * 0.5) then instant = true end
    end
    local rate = U.lerp(c.FillNearPerSec, c.FillFarPerSec, d / effRange) * cone * stanceFill * c.Movement[key] * light
        * c.AmbientLight * train * (s.Speed[lv] or 1.0) * exp
    -- Standing in view, however far: at least suspicious within a couple of seconds.
    if not crouched then rate = math.max(rate, c.StandingNoticePerSec * cone * train * exp) end
    -- Noticing vs identifying: in the far part of its range it sees "something", not yet "an
    -- enemy": the meter stops short of combat (it walks over to look).
    local idf = crouched and c.IdentifyFraction.Crouching or c.IdentifyFraction.Standing
    local cap = (d > effRange * idf) and c.IdentifyCap or nil
    return rate, instant, cap
end

-- Exposure of the target to an NPC (DESIGN.md 17.3), seen from the target's side: the player's
-- controller checks LineOfSightTo(npc, point) from the target's head, chest and knees (each 0.015 ms,
-- the target's own pawn is ignored), plus one point 1.5 m behind it (blocked = a wall or cover
-- right behind breaks the silhouette). Returns exposure 0..1 and the backdrop factor.
local function exposure(pc, npc, me, e)
    local c = cfg().Detection
    local pts = (me.stance == G.Stance.Crouching) and c.ExposurePoints.Crouching or c.ExposurePoints.Standing
    local n, seenZ = 0, nil
    for _, z in ipairs(pts) do
        local ok, v = pcall(function() return pc:LineOfSightTo(npc, { X = me.pos.X, Y = me.pos.Y, Z = me.pos.Z + z }, false) end)
        if ok and v == true then n = n + 1; seenZ = seenZ or z end
    end
    local exp = n / #pts
    local back = 1.0
    if exp > 0 and c.BackdropFactor < 1 then
        local dx, dy = me.pos.X - e.pos.X, me.pos.Y - e.pos.Y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1 then
            local bd = c.BackdropDistance / len
            local p = { X = me.pos.X + dx * bd, Y = me.pos.Y + dy * bd, Z = me.pos.Z + (seenZ or 0) }
            local ok, v = pcall(function() return pc:LineOfSightTo(npc, p, false) end)
            if ok and v ~= true then back = c.BackdropFactor end
        end
    end
    return exp, back
end

-- Reaction time once spotted (training): the NPC turns to you and raises its weapon, then
-- combat starts. Elites react almost at once, militia hesitate.
local function react(e, npc, target, why, now)
    local delay = cfg().Detection.ReactionSeconds[e.training] or 0.3
    if delay <= 0 then A.alert(e, target, why); return end
    e.reactAt, e.reactWhy, e.reactTarget, e.meter = now + delay, why, target, 1
    stopLogic(e, npc)
    pcall(function() npc.CharacterMovement:StopMovementImmediately() end)
    pcall(function() npc.Controller:K2_SetFocus(target) end)
    draw(e, npc, true)
    if U.Verbose then U.log(string.format("spotted %s (%s, %s): reacting in %.2f s", tostring(e.a), why, e.training, delay)) end
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
-- Called ~5 times a second on the game thread. player: live pawn; pc: its controller (read fresh
-- each tick); squad: snapshots of quiet squad soldiers { obj, pos, stance, speed, gait } or {}.
-- Returns a HUD summary. LineOfSightTo costs ~0.015 ms; kept references read invalid once
-- collected (verified in game).
function A.tick(player, me, dt, squad, pc)
    local c = cfg().Detection
    local now = os.clock()
    local sum = { suspicious = 0, searching = 0, hunting = 0, alert = 0, maxMeter = 0, level = A.BLUE }
    local losBudget = c.MaxLineOfSightPerTick
    squad = squad or {}
    for a, e in pairs(A.npcs) do
        local npc = objOf(e)
        if not npc then
            if now - e.seenAt > FRESH then A.npcs[a] = nil; A.count = math.max(0, A.count - 1) end
        elseif e.state == A.ALERT then
            if U.get(npc, P.CanSee, false) then A.lastContact = now end
        elseif e.managed and e.reactAt then
            sum.maxMeter = 1
            if now >= e.reactAt then
                local tgt = U.valid(e.reactTarget) and e.reactTarget or player
                e.reactAt, e.reactTarget = nil, nil
                A.alert(e, tgt, e.reactWhy)
            end
        elseif e.managed and me.pos and e.pos and U.dist(e.pos, me.pos) < c.BubbleRadius then
            e.pos, e.fwd = U.location(npc) or e.pos, U.forward(npc) or e.fwd
            -- Weapon posture follows the level (DESIGN.md 17.8): from Yellow it raises its weapon and
            -- aims where it suspects you, after a delay set by training; it fires only at Red.
            if e.hunting or e.state == A.SUSPICIOUS or e.state == A.SEARCHING then
                if not e.drawn then
                    e.raiseAt = e.raiseAt or (now + (c.RaiseSeconds[e.training] or 0.8) * (e.hunting and 0.5 or 1.0))
                    if now >= e.raiseAt then draw(e, npc, true) end
                end
                if e.hunting and e.wantCover then crouch(e, npc, true) end
            end
            -- you: in range and in its view at all? then how much of you it can see (exposure)
            local rate, instant, cap = A.sightRate(e, me, now, 1.0, 1.0)
            local seen, target, tpos, why = false, player, me.pos, "seen"
            if rate > 0 and losBudget > 0 and pc then
                losBudget = losBudget - 1
                local exp, back = exposure(pc, npc, me, e)
                e.exposure = exp
                rate, instant, cap = A.sightRate(e, me, now, exp, back)
                seen = rate > 0
            end
            -- your quiet squad: one soldier per NPC per tick (round robin), plain line of sight
            if not seen and #squad > 0 and losBudget > 0 then
                e.sqIdx = (e.sqIdx or 0) % #squad + 1
                local s = squad[e.sqIdx]
                local sr, si, sc = A.sightRate(e, s, now, 1.0, 1.0)
                if sr > 0 then
                    losBudget = losBudget - 1
                    local ok, v = pcall(function() return npc.Controller:LineOfSightTo(s.obj, { X = 0, Y = 0, Z = 0 }, false) end)
                    if ok and v == true then
                        seen, rate, instant, cap, target, tpos, why = true, sr, si, sc, s.obj, s.pos, "saw your squad"
                    end
                end
            end
            if U.Verbose then e.dbgRate, e.dbgSeen, e.dbgAng = rate, seen, U.angleTo(e.fwd, e.pos, me.pos) end
            -- proximity: someone right next to you notices unless you are crouched and still
            local d = U.dist(e.pos, me.pos)
            local quiet = me.stance == G.Stance.Crouching and me.speed < c.StillSpeed
            if d < c.ProximityRange and not quiet then e.proxT = e.proxT + dt else e.proxT = 0 end
            if (seen and instant) or e.proxT > c.ProximitySeconds then
                if e.proxT > c.ProximitySeconds then target = player end
                react(e, npc, target, seen and instant and "in plain view" or "close", now)
            elseif seen then
                e.meter = e.meter + rate * dt
                if cap then e.meter = math.max(math.min(e.meter, cap), e.meter - rate * dt) end
                e.lastKnown = tpos
                if e.meter >= 1.0 then react(e, npc, target, why, now)
                elseif e.state == A.CALM and e.meter >= c.SuspiciousAt then setState(e, A.SUSPICIOUS) end
            else
                e.meter = math.max(0, e.meter - c.DecayPerSec * dt)
            end
            if e.reactAt then
                -- spotted this tick: it stays facing you until it reacts
            elseif (e.state == A.SUSPICIOUS and e.meter >= c.InvestigateAt) or e.state == A.SEARCHING then
                investigate(e, npc, now)
            elseif e.state == A.SUSPICIOUS then
                look(e, npc)
            end
            if e.reactAt then
                -- nothing
            elseif e.state == A.SUSPICIOUS and e.meter <= 0.02 then
                calm(e, npc)
            elseif e.state == A.SEARCHING and now - e.stateAt > c.SearchSeconds and e.meter < c.SuspiciousAt then
                calm(e, npc)
            end
            if e.state == A.SUSPICIOUS then sum.suspicious = sum.suspicious + 1 end
            if e.state == A.SEARCHING then sum.searching = sum.searching + 1 end
            if e.hunting then sum.hunting = sum.hunting + 1 end
            if e.state ~= A.ALERT then sum.maxMeter = math.max(sum.maxMeter, e.meter) end
            sum.level = math.max(sum.level, level(e, now))
        end
    end
    -- count ALERT NPCs after this tick's changes (alerts and shouts above)
    for _, e in pairs(A.npcs) do if e.state == A.ALERT then sum.alert = sum.alert + 1 end end
    if sum.alert > 0 then sum.level = A.RED end
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
                local COL = { "blue", "green", "yellow", "orange", "red" }
                out[#out + 1] = string.format("  %s %s %s m=%.2f d=%.0fm range=%.0fm exp=%.2f managed=%s ang=%.0f rate=%.2f seen=%s %s hunt=%s drawn=%s%s",
                    tostring(a), COL[level(e, os.clock())] or "?", e.state, e.meter, d / 100, (e.baseRange or 0) / 100,
                    e.exposure or -1, tostring(e.managed), e.dbgAng or -1, e.dbgRate or -1, tostring(e.dbgSeen),
                    tostring(e.training), tostring(e.hunting), tostring(e.drawn), e.dbgErr and (" err=" .. e.dbgErr) or "")
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

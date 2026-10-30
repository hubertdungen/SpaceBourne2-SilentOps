--[[
  Ally stealth orders (DESIGN.md section 7).

    Follow quietly : squad battle timer paused (no shooting), Lua walks them to their
                     formation slot, crouched. Companions: eyes off.
    Hold           : squad battle timer paused, stop, crouch. Companions: eyes off.
    Weapons free   : vanilla (timer running, FireAtWill order). Companions: eyes on.

  Squad soldiers are found with ONE FindAllOf on the order key press (~50 ms, a key press
  only) and kept as checked references. Companions come from the shooter registry.

  STATUS (tested 2026-10-30): pausing MainTimer, crouching and auto weapons free work. The Lua
  follow walk (MoveToActor) and companions are not tested yet (no companion in the test save).
]]

local U = require("stealth.util")
local G = require("stealth.gamedefs")
local P = G.P

local AL = { order = nil, soldiers = {}, companions = {}, nextFollow = 0 }
AL.ORDERS = { "follow", "hold", "free" }
AL.NAMES = { follow = "Follow quietly", hold = "Hold (hold fire)", free = "Weapons free" }

local function cfg() return STEALTH.cfg.Allies end

local KSL
local function ksl()
    if not U.valid(KSL) then KSL = StaticFindObject(G.KismetSystem) end -- a CDO: always found
    return KSL
end

-- The soldier's MainTimer (FTimerHandle) must be passed as a plain table { Handle = number }:
-- passing the struct read from the property fails in UE4SS 3.0.1 (verified in game).
local function setBattleTimer(sol, running)
    local lib = ksl()
    if not lib then return end
    pcall(function()
        local h = { Handle = sol[P.MainTimer].Handle }
        if running then lib:K2_UnPauseTimerHandle(sol, h) else lib:K2_PauseTimerHandle(sol, h) end
    end)
end

-- Companion hold fire. HTR 0.4.2 re-starts firing from the RifleEye hook while an NPC aims;
-- with the eyes off that hook cannot run, and StopShoot ends a burst already running.
local function setEyes(npc, on)
    for _, name in ipairs({ P.EyeSight, P.EyeRifle }) do
        local eye = U.get(npc, name, nil)
        if U.valid(eye) then pcall(function() eye:SetActive(on, false) end) end
    end
    if not on then pcall(function() npc:StopShoot() end) end
end

local function liveSoldiers()
    local out = {}
    for _, s in ipairs(AL.soldiers) do
        if U.alive(s.obj, s.a) and not U.get(s.obj, P.SoldierDead, false) then out[#out + 1] = s.obj end
    end
    return out
end

-- Key press only: FindAllOf costs ~50 ms.
function AL.findSquad()
    AL.soldiers = {}
    local all = FindAllOf(G.SquadShort)
    if not all then return 0 end
    for _, s in ipairs(all) do
        if U.valid(s) then AL.soldiers[#AL.soldiers + 1] = { obj = s, a = U.addr(s) } end
    end
    return #AL.soldiers
end

-- Companions report themselves from the shooter think hook.
function AL.trackCompanion(npc)
    local a = U.addr(npc)
    if not a then return end
    local known = AL.companions[a]
    AL.companions[a] = { obj = npc, a = a, t = os.clock() }
    if not known and AL.order and AL.order ~= "free" then setEyes(npc, false) end
end

function AL.apply(order, player)
    AL.order = order
    local quiet = order ~= "free"
    for _, sol in ipairs(liveSoldiers()) do
        setBattleTimer(sol, not quiet)
        pcall(function() sol:SetStance(quiet and G.Stance.Crouching or G.Stance.Standing) end)
        if order == "hold" then pcall(function() sol.CharacterMovement:StopMovementImmediately() end) end
    end
    if not quiet and U.valid(player) then pcall(function() player:SendOrderToSquad(G.Order.FireAtWill) end) end
    for a, c in pairs(AL.companions) do
        if U.alive(c.obj, a) then setEyes(c.obj, not quiet) else AL.companions[a] = nil end
    end
    AL.nextFollow = 0
end

-- Key press: next order. Returns the HUD text.
function AL.cycle(player)
    local n = AL.findSquad()
    local i = 1
    for k, o in ipairs(AL.ORDERS) do if o == AL.order then i = k % #AL.ORDERS + 1 end end
    AL.apply(AL.ORDERS[i], player)
    return string.format("Squad (%d): %s", n, AL.NAMES[AL.order])
end

-- About once a second: walk the squad to its formation slots, crouched.
-- HTR 0.4.2's keep-up (run / sprint) and vanilla's 30 m teleport rescue both run inside
-- UpdateBattle, which is paused here: we set the walking gait ourselves, and a soldier left
-- far behind gets one vanilla SetWalkSpeed() call (it teleports beyond 30 m from its slot).
-- NOT TESTED YET: MoveToActor / SetGait / SetWalkSpeed on a soldier whose battle timer is paused.
function AL.tick(now)
    if AL.order ~= "follow" or now < AL.nextFollow then return end
    AL.nextFollow = now + 1.0
    for _, sol in ipairs(liveSoldiers()) do
        if not U.get(sol, P.Injured, false) then
            local goal = U.get(sol, P.GoalActor, nil)
            local d = U.valid(goal) and U.dist(U.location(sol), U.location(goal)) or 0
            if d > cfg().CatchUpDistance then
                pcall(function() sol:SetWalkSpeed() end)
            elseif d > cfg().FollowDistance then
                pcall(function() sol:SetDesiredGait(G.Gait.Walking) end)
                pcall(function() sol:SetGait(G.Gait.Walking) end)
                pcall(function() sol:SetStance(G.Stance.Crouching) end)
                pcall(function() sol.Controller:MoveToActor(goal, 100.0, true, true, false, nil, true) end)
            end
        end
    end
end

-- Stealth broken: allies fight back.
function AL.onCompromised(player)
    if cfg().AutoWeaponsFree and AL.order and AL.order ~= "free" then
        AL.apply("free", player)
        return "Squad: weapons free"
    end
    return nil
end

-- Post-hook of Master_Soldier_C:BattleShoot / PistolShot: squad gunfire is noise.
function AL.onSoldierShot(N, sol)
    N.emit(U.location(sol), STEALTH.cfg.Noise.SquadShot, "squad", true)
end

-- Stealth switched off: everyone back to vanilla.
function AL.releaseAll(player)
    if AL.order and AL.order ~= "free" then AL.apply("free", player) end
    AL.order = nil
end

return AL

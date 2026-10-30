--[[
  Silent Ops - realistic stealth on foot for SpaceBourne 2 (UE4SS Lua mod)
  Entry point: loads settings, wires hooks, runs the awareness tick, binds keys.

  STATUS: first in-game tests passed on 2026-10-30 (DESIGN.md section 13.3). Not released yet.

  Layout:
    config.lua              user settings
    stealth/gamedefs.lua    every game-internal name (the only file to fix after a game patch)
    stealth/util.lua        helpers and safety rules
    stealth/hooks.lua       lazy, fault-isolated hook registration (same as HTR's)
    stealth/awareness.lua   who is managed, the sight meter, CALM/SUSPICIOUS/SEARCHING/ALERT
    stealth/noise.lua       noise queue, hearing, suppressor
    stealth/takedown.lua    melee takedowns, witnesses, bodies
    stealth/allies.lua      squad and companion orders
    stealth/hud.lua         on-screen messages
]]

local VERSION = "0.1.0"

local U = require("stealth.util")

-- Settings -------------------------------------------------------------------------
local defaults = {
    Enabled = false, ToggleKey = "Shift+F4",
    Detection = {
        SightSource = "eye", SightRange = 3500, SearchingRangeFactor = 2.0, BubbleRadius = 6000, CentralHalfAngle = 35, PeripheralHalfAngle = 75, PeripheralFactor = 0.35,
        Stance = { Standing = 1.0, Crouching = 0.6 }, Movement = { Still = 0.5, Walk = 1.0, Run = 1.5, Sprint = 2.2 },
        MovementRange = { Still = 0.85, Walk = 1.0, Run = 1.1, Sprint = 1.2 },
        StillSpeed = 50, FlashlightFactor = 2.0, FlashlightRangeFactor = 1.5, AmbientLight = 1.0,
        FillNearPerSec = 2.0, FillFarPerSec = 0.25, DecayPerSec = 0.12, SuspiciousAt = 0.35, InvestigateAt = 0.6,
        InstantAlertRange = 250, ProximityRange = 120, ProximitySeconds = 1.5,
        AlertedPerception = 1.5, AlertedMemorySeconds = 120, SearchRadius = 600, InvestigateStepSeconds = 6,
        SearchSeconds = 40, LoseSeconds = 25, Shout = true, ShoutRadius = 1500, SniperRangeFactor = 1.0,
        Perception = { Pirate = 0.85, Militia = 0.9, Elite = 1.15 },
        AffectBosses = false, AffectTanks = false, MaxLineOfSightPerTick = 8,
    },
    Noise = {
        Shot = { pistol = 5000, smg = 6000, rifle = 8000, shotgun = 7000, dmr = 9000, sniper = 10000, laser = 2500, beam = 1500 },
        SuppressedShot = { pistol = 1200, smg = 1500, rifle = 2500, dmr = 2500, sniper = 3500 }, Impact = 500, Footsteps = { Crouch = 100, Walk = 300, Run = 700, Sprint = 1200 },
        BodyFall = 500, Takedown = 250, HeavyTakedown = 600, SquadShot = 6000,
        OccludedFactor = 0.5, LoudFraction = 0.4, HeardBump = 0.4, MaxOcclusionChecksPerTick = 6,
    },
    Suppressor = {
        ToggleKey = "F4", Eligible = { pistol = true, smg = true, rifle = true, dmr = true, sniper = true },
        AlwaysSilenced = {}, VelocityFactor = 0.92,
    },
    Takedown = {
        Enabled = true, Weapons = { knife = true, sword = true, hammer = false }, MaxDistance = 220, BehindAngle = 110,
        RequireCrouch = false, AllowSearchingTarget = false, MeleeLock = true, WitnessRange = 1500,
    },
    Bodies = { Enabled = true, SeeRange = 1500, CloseRange = 300, KeepSeconds = 180 },
    Allies = { OrderKey = "F3", AutoWeaponsFree = true, FollowDistance = 400, CatchUpDistance = 3000 },
    Hud = { Messages = true, MinSecondsBetween = 2.0 },
    Debug = { Log = false, SlowHookMs = 8, TickMs = 200, Commands = false },
}

-- Fill every missing key of `user` from `def`, recursively (user values win).
local function merge(user, def)
    for k, v in pairs(def) do
        if user[k] == nil then
            user[k] = v
        elseif type(v) == "table" and type(user[k]) == "table" then
            merge(user[k], v)
        end
    end
    return user
end

local okCfg, userCfg = pcall(require, "config")
if not okCfg or type(userCfg) ~= "table" then
    U.warn("config.lua could not be read (" .. tostring(userCfg) .. "); using defaults")
    userCfg = {}
end
local cfg = merge(userCfg, defaults)
U.Verbose = cfg.Debug.Log

STEALTH = { version = VERSION, cfg = cfg, on = false, player = nil, playerAddr = nil }

local G = require("stealth.gamedefs")
local H = require("stealth.hooks")
local A = require("stealth.awareness")
local N = require("stealth.noise")
local T = require("stealth.takedown")
local AL = require("stealth.allies")
local HUD = require("stealth.hud")
H.SLOW = cfg.Debug.SlowHookMs / 1000

-- State file: on/off and fitted suppressors, kept between sessions -------------------
local STATE = U.Dir .. "stealth_state.txt"
local function loadState()
    local f = io.open(STATE, "r")
    local s = f and f:read("a") or ""
    if f then f:close() end
    local v = s:match("stealth=(%a+)")
    STEALTH.on = (v == "on") or (v == nil and cfg.Enabled == true)
    N.load(s)
end
local function saveState()
    local f = io.open(STATE, "w")
    if f then
        f:write("stealth=" .. (STEALTH.on and "on" or "off") .. "\n" .. N.serialize() .. "\n")
        f:close()
    end
end
loadState()
A.on = STEALTH.on
U.log(string.format("=== Silent Ops %s loaded, stealth=%s ===", VERSION, tostring(STEALTH.on)))

-- The on-foot player character (Q1_Character_C), not a ship.
local function onFoot(p) return p ~= nil and G.PlayerClassNames[U.className(p) or ""] == true end

-- The player pawn, kept between ticks and re-checked (any NPC hook can refresh it).
local function rememberPlayer(ctx)
    if U.alive(STEALTH.player, STEALTH.playerAddr) then return STEALTH.player end
    local p = U.playerPawn(ctx)
    if onFoot(p) then STEALTH.player, STEALTH.playerAddr = p, U.addr(p) end
    return p
end

-- Key presses: the pawn you control right now, or nil when you are not on foot (in a ship F3/F4
-- are fleet orders, so the stealth keys do nothing there). Without a cached object this is one
-- slower lookup (as HTR does), on key presses only.
local function playerForKey()
    local p
    if U.valid(STEALTH.player) then p = U.playerPawn(STEALTH.player) end
    if not p then
        for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
            local ok, pawn = pcall(function() return pc.Pawn end)
            if ok and U.valid(pawn) then p = pawn; break end
        end
    end
    if not onFoot(p) then return nil end
    STEALTH.player, STEALTH.playerAddr = p, U.addr(p)
    return p
end

-- Hooks (post-hooks on Blueprint functions) ----------------------------------------
-- At spawn, before the NPC is Ready? and its eyes can fire: manage it right away.
H.add(G.Fn.NpcStats, function(self)
    if not STEALTH.on then return end
    local npc = self:get()
    rememberPlayer(npc)
    if not U.get(npc, G.P.IsCompanion, false) then A.track(npc, true) end
end, "NPC spawn")

H.add(G.Fn.NpcThink, function(self)
    local npc = self:get()
    rememberPlayer(npc) -- also while off: switching on then needs no slow lookup (~50 ms)
    if not STEALTH.on then return end
    if U.get(npc, G.P.IsCompanion, false) then AL.trackCompanion(npc) else A.track(npc) end
end, "NPC think")

H.add(G.Fn.NpcReceivePoint, function(self, dmgP, dtypeP, locP, normP, compP, boneP, dirP, instigP, causerP)
    if not STEALTH.on then return end
    local npc = self:get()
    local dtype, causer = dtypeP:get(), causerP:get()
    if T.tryTakedown(A, N, npc, dtype, causer) then return end
    A.onHit(npc, causer)
end, "NPC hit")

H.add(G.Fn.NpcOnDead, function(self)
    if not STEALTH.on then return end
    local npc = self:get()
    A.onDead(npc)
    T.onDeath(A, N, npc)
end, "NPC death")

local function onShot(self) if STEALTH.on then N.onShot(self:get()) end end
H.add(G.Fn.WeaponShot, onShot, "player shot")
H.add(G.Fn.WeaponBeam, onShot, "player beam")

for i, path in ipairs(G.PlayerProjectileHits) do
    H.add(path, function(self, projP, hitP, attachP, locP)
        if not STEALTH.on then return end
        local l = locP:get()
        N.onImpact({ X = l.X, Y = l.Y, Z = l.Z })
    end, "impact " .. i)
end

H.add(G.Fn.WeaponAlarm, function(self, posP, radiusP)
    if not STEALTH.on then return end
    local p = posP:get()
    N.onAlarm(A, { X = p.X, Y = p.Y, Z = p.Z }, radiusP:get())
end, "vanilla alarm cleanup")

local function onSquadShot(self) if STEALTH.on then AL.onSoldierShot(N, self:get()) end end
H.add(G.Fn.SoldierShoot, onSquadShot, "squad shot")
H.add(G.Fn.SoldierPistol, onSquadShot, "squad pistol")

-- Tick -----------------------------------------------------------------------------
local lastTick, pollAt, slowAt, profileAt, statusAt, cmdAt = os.clock(), 0, -1e9, os.clock() + 30, 0, 0
local KEYS = {} -- key actions (filled below), also reachable through Debug.Commands

-- Debug.Commands (testing only, off by default): a file debug_cmd.txt in the mod folder with
-- lines "toggle", "suppressor" or "order" runs the same action as the key, then is deleted.
local function debugCommands(now)
    if not cfg.Debug.Commands or now < cmdAt then return end
    cmdAt = now + 1
    local path = U.Dir .. "debug_cmd.txt"
    local f = io.open(path, "r")
    if not f then return end
    local text = f:read("a"); f:close(); os.remove(path)
    for c in text:gmatch("%a+") do
        if KEYS[c] then U.log("debug command: " .. c); KEYS[c]() end
    end
end
local wasCompromised = false

local function snapshot(p)
    return {
        pos = U.location(p),
        stance = U.get(p, G.P.Stance, 0),
        gait = U.get(p, G.P.Gait, 0),
        speed = U.speed(p),
        light = U.get(p, G.P.LightOn, false) == true,
    }
end

local function tick()
    local now = os.clock()
    local dt = math.min(1.0, now - lastTick)
    lastTick = now
    if now >= pollAt then
        pollAt = now + 1.0
        H.poll(now)
        if U.Verbose and now > profileAt then
            profileAt = now + 30
            local prof = H.profile()
            if prof ~= "" then U.log("profile 30 s: " .. prof) end
        end
    end
    debugCommands(now)
    if not STEALTH.on then return end
    local player = U.alive(STEALTH.player, STEALTH.playerAddr) and STEALTH.player or nil
    if not player then return end -- refreshed by the next NPC think
    local me = snapshot(player)
    N.footsteps(me, now)
    N.process(A, player)
    local sum = A.tick(player, me, dt)
    T.tick(A, now)
    AL.tick(now)
    if sum.compromised and not wasCompromised then
        local msg = AL.onCompromised(player)
        if msg then U.log(msg) end
    end
    wasCompromised = sum.compromised
    HUD.update(sum, player)
    local cost = os.clock() - now
    if U.Verbose and now > statusAt then
        statusAt = now + 2
        local lines = A.debugLines(me)
        U.log(string.format("status: player stance=%s gait=%s speed=%.0f light=%s compromised=%s tick=%.2fms npcs=%d",
            tostring(me.stance), tostring(me.gait), me.speed, tostring(me.light), tostring(sum.compromised), cost * 1000, #lines))
        for _, l in ipairs(lines) do U.log(l) end
    end
    if cost > H.SLOW and now - slowAt > 30 then
        slowAt = now
        U.warn(string.format("slow stealth tick: %.1f ms (%d NPCs known)", cost * 1000, A.count))
    end
end

LoopAsync(cfg.Debug.TickMs, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(tick)
        if not ok then U.warn("tick: " .. tostring(err)) end
    end)
    return false
end)

-- Keys -----------------------------------------------------------------------------
local function toggleStealth()
    local player = playerForKey()
    if not player then return end -- on foot only
    STEALTH.on = not STEALTH.on
    A.on = STEALTH.on
    if not STEALTH.on then
        A.releaseAll()
        AL.releaseAll(player)
    end
    saveState()
    U.warn("stealth " .. (STEALTH.on and "ON" or "OFF"))
    HUD.say(STEALTH.on and "Stealth ON - enemies notice you gradually" or "Stealth OFF (vanilla)", player, true)
end

local function toggleSuppressor()
    local player = playerForKey()
    if not player then return end
    local text = N.toggleSuppressor(player)
    saveState()
    U.log("key suppressor: " .. text)
    HUD.say(text, player, true)
end

local function cycleOrder()
    local player = playerForKey()
    if not player then return end
    local text = AL.cycle(player)
    U.log("key ally order: " .. text)
    HUD.say(text, player, true)
end

-- Keys follow the realism set's shared key plan (revision 2), same rules and parser as HTR 0.4.4:
--   * a key is a UE4SS key name with optional modifiers: "F4", "Shift+F4" (only Shift is
--     recommended: on foot Ctrl opens the map and Alt crouches);
--   * never F1 F2 F5 F6 F8 F10 F12, plain or with Shift: the game reacts to them anyway;
--   * a plain bind stays quiet while any modifier is held, so Shift+F4 (stealth on/off) does not
--     also fit a suppressor (Shift+F3 is a spare Stealth key).
-- Verified in game (2026-10-30): Shift+F4, F4, F3, and the Shift guard on the plain keys.
local GAME_KEYS = { F1 = 1, F2 = 1, F5 = 1, F6 = 1, F8 = 1, F10 = 1, F12 = 1 }
local KEY_ALIAS = { INSERT = "INS", DELETE = "DEL", PAGEDOWN = "PAGE_DOWN", PAGEUP = "PAGE_UP", ESC = "ESCAPE" }
local MODS = { CTRL = "CONTROL", CONTROL = "CONTROL", SHIFT = "SHIFT", ALT = "ALT" }
local function parseKey(spec)
    if type(spec) ~= "string" or spec == "" then return nil end
    local mods, key = {}, nil
    for part in spec:upper():gsub("%s", ""):gmatch("[^+]+") do
        if MODS[part] then mods[#mods + 1] = MODS[part] else key = KEY_ALIAS[part] or part end
    end
    if not (key and Key and Key[key]) then return nil, "unknown key" end
    if GAME_KEYS[key] then return nil, "the game uses " .. key end
    return key, mods
end

local function bindKey(spec, fn, fallback, what)
    local key, mods = parseKey(spec)
    if not key and fallback and spec ~= "" then
        U.warn(string.format("%s key '%s' not usable (%s); using %s", what, tostring(spec), tostring(mods), fallback))
        key, mods = parseKey(fallback)
    end
    if not key then return end
    local function run()
        local ok, err = pcall(fn)
        if not ok then U.warn("key " .. what .. ": " .. tostring(err)) end
    end
    if #mods > 0 and ModifierKey then
        local list = {}
        for _, m in ipairs(mods) do list[#list + 1] = ModifierKey[m] end
        RegisterKeyBind(Key[key], list, function() ExecuteInGameThread(run) end)
    else
        RegisterKeyBind(Key[key], function()
            ExecuteInGameThread(function() if not U.modifierDown(STEALTH.player) then run() end end)
        end)
    end
end
KEYS.toggle, KEYS.suppressor, KEYS.order = toggleStealth, toggleSuppressor, cycleOrder
bindKey(cfg.ToggleKey, toggleStealth, "Shift+F4", "stealth on/off")
bindKey(cfg.Suppressor.ToggleKey, toggleSuppressor, "F4", "suppressor")
bindKey(cfg.Allies.OrderKey, cycleOrder, "F3", "ally orders")

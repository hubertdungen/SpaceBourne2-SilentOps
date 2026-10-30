--[[
  Noise model and the suppressor (DESIGN.md sections 4 and 6).

  Hooks only queue a noise record (O(1)); the tick resolves the queue against the NPC
  registry. Vanilla's own impact alarm cannot reach managed NPCs (they are deaf).

  STATUS (tested 2026-10-30): shot noise, suppressed shots, hearing and the suppressor toggle
  work. Anything not exercised yet is marked NOT TESTED YET.
]]

local U = require("stealth.util")
local G = require("stealth.gamedefs")
local P = G.P

local N = { queue = {}, suppressed = {}, nextStep = 0 }
local MAX_QUEUE = 32

local function cfg() return STEALTH.cfg end

-- Queue a noise. loud = heard as "something is very wrong" when near (shots).
function N.emit(pos, radius, kind, loud)
    if not pos or radius <= 0 or #N.queue >= MAX_QUEUE then return end
    N.queue[#N.queue + 1] = { pos = pos, r = radius, kind = kind, loud = loud }
end

-- Weapon in the player's hands ----------------------------------------------------
local function weaponOf(player)
    local comp = U.get(player, P.Weapon, nil)
    local w = comp and U.get(comp, "ChildActor", nil)
    if U.valid(w) then return w end
    return nil
end
N.weaponOf = weaponOf

function N.kindOf(weapon)
    return G.WeaponKind[U.className(weapon) or ""] or "rifle"
end

-- Weapons have no unique id: class + item level + rarity + damage stat is close enough.
-- Reading the Stats array works (suppressor fitted per item in game).
function N.itemKey(weapon)
    local cls = U.className(weapon) or "?"
    local lvl, tier, dmg = "?", "?", "?"
    pcall(function()
        local item = weapon[P.WeaponData][G.Item.WeaponItem]
        lvl, tier = tostring(item[G.Item.Level]), tostring(item[G.Item.Rarity])
        item[G.Item.Stats]:ForEach(function(_, elem)
            local s = elem:get()
            if s[G.Item.StatID]:ToString() == "C_W_DMG" then dmg = string.format("%.1f", s[G.Item.StatValue]) end
        end)
    end)
    return cls .. "|" .. lvl .. "|" .. tier .. "|" .. dmg
end

-- Per-shot check, so the item key is cached per weapon actor for a few seconds.
local keyCache, keyCount = {}, 0
function N.isSuppressed(weapon)
    local c = cfg().Suppressor
    local cls = U.className(weapon) or ""
    if c.AlwaysSilenced[cls] then return true end
    local a, now = U.addr(weapon), os.clock()
    local k = a and keyCache[a]
    if not k or now - k.t > 5 then
        if not k then keyCount = keyCount + 1 end
        if keyCount > 16 then keyCache, keyCount = {}, 1 end
        k = { key = N.itemKey(weapon), t = now }
        if a then keyCache[a] = k end
    end
    return N.suppressed[k.key] == true
end

-- Key press: fit / remove the suppressor on the weapon in hand. Returns a HUD text.
function N.toggleSuppressor(player)
    local w = weaponOf(player)
    if not w then return "No weapon in hand" end
    local kind = N.kindOf(w)
    if not cfg().Suppressor.Eligible[kind] then return "This weapon cannot take a suppressor" end
    local key = N.itemKey(w)
    keyCache, keyCount = {}, 0
    if N.suppressed[key] then
        N.suppressed[key] = nil
        N.applyVelocity(w, false)
        return "Suppressor removed"
    end
    N.suppressed[key] = true
    N.applyVelocity(w, true)
    return "Suppressor fitted"
end

-- Optional realism cost: slower bullets with a suppressor. NOT TESTED YET: weapon init resets
-- MuzzleSpeed on every equip, so this must be re-applied after an equip (Phase 2).
local origSpeed = {} -- weapon address -> MuzzleSpeed before the suppressor
function N.applyVelocity(w, fitted)
    local f = cfg().Suppressor.VelocityFactor
    if not f or f == 1 then return end
    local a = U.addr(w)
    local v = U.get(w, P.MuzzleSpeed, nil)
    if not a or type(v) ~= "number" then return end
    if fitted then
        origSpeed[a] = v
        U.set(w, P.MuzzleSpeed, v * f)
    elseif origSpeed[a] then
        U.set(w, P.MuzzleSpeed, origSpeed[a])
        origSpeed[a] = nil
    end
end

-- State file: one key per line.
function N.serialize()
    local t = {}
    for k in pairs(N.suppressed) do t[#t + 1] = "suppressed=" .. k end
    return table.concat(t, "\n")
end

function N.load(text)
    N.suppressed = {}
    for k in (text or ""):gmatch("suppressed=([^\r\n]+)") do N.suppressed[k] = true end
end

-- Hooks ---------------------------------------------------------------------------
-- Post-hook of Master_Hand_Weapon_C:SpawnProjectile / ActiveBeam1 (self = the weapon).
function N.onShot(weapon)
    local player = U.playerPawn(weapon)
    if not player then return end
    local c = cfg().Noise
    local kind = N.kindOf(weapon)
    if N.isSuppressed(weapon) then
        local s = c.SuppressedShot
        N.emit(U.location(player), type(s) == "table" and (s[kind] or s.rifle) or s, "shot", false)
    else
        N.emit(U.location(player), c.Shot[kind] or c.Shot.rifle, "shot", true)
    end
end

-- Post-hook of the player's OnProjectileHit_* (loc = impact point).
function N.onImpact(loc)
    N.emit(loc, cfg().Noise.Impact, "impact", false)
end

-- Footsteps, from the tick (me = player snapshot).
function N.footsteps(me, now)
    if now < N.nextStep or not me.pos then return end
    N.nextStep = now + 0.5
    local f = cfg().Noise.Footsteps
    local r
    if me.speed < cfg().Detection.StillSpeed then return
    elseif me.stance == G.Stance.Crouching then r = f.Crouch
    elseif me.gait == G.Gait.Sprinting then r = f.Sprint
    elseif me.gait == G.Gait.Running then r = f.Run
    else r = f.Walk end
    N.emit(me.pos, r, "steps", false)
end

-- Post-hook of Master_Hand_Weapon_C:Alarm Enemeis(SpherePos, SphereRadius): vanilla turned
-- NPCs beyond 24 m path towards the player; undo that on managed NPCs. NOT TESTED YET.
function N.onAlarm(A, pos, radius)
    for _, e in pairs(A.npcs) do
        if e.managed and e.pos and U.dist(e.pos, pos) < radius + 200 then
            local npc = A.objOf(e)
            if npc then pcall(function() npc.Controller:K2_ClearFocus() end) end
        end
    end
end

-- Resolve the queue (tick). player: live pawn, for line-of-sight occlusion checks.
-- LineOfSightTo from the NPC to the player is the occlusion test (verified in game).
function N.process(A, player)
    if #N.queue == 0 then return end
    local c = cfg().Noise
    local budget = c.MaxOcclusionChecksPerTick
    for _, n in ipairs(N.queue) do
        -- the occlusion test looks from the NPC to the player, so it only fits noises you make
        local fromPlayer = n.kind == "shot" or n.kind == "steps"
        for _, e in pairs(A.npcs) do
            if e.managed and e.pos then
                local d = U.dist(e.pos, n.pos)
                local r = n.r
                if fromPlayer and d < r and d > r * c.OccludedFactor and budget > 0 then
                    -- outer band: heard only with a clear line to the source
                    local npc = A.objOf(e)
                    budget = budget - 1
                    local ok, los = false, false
                    if npc and player then
                        ok, los = pcall(function() return npc.Controller:LineOfSightTo(player, { X = 0, Y = 0, Z = 0 }, false) end)
                    end
                    if not (ok and los == true) then r = r * c.OccludedFactor end
                end
                if d < r then
                    if n.loud and d < r * c.LoudFraction then
                        A.search(e, n.pos, string.format("loud %s at %.0f m", n.kind, d / 100))
                    else
                        A.suspect(e, n.pos, c.HeardBump, string.format("heard %s at %.0f m", n.kind, d / 100))
                    end
                end
            end
        end
    end
    N.queue = {}
end

return N

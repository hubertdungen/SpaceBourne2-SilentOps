--[[
  Noise model and the suppressor (DESIGN.md sections 4, 6 and 14).

  Hooks only queue a noise record (O(1)); the tick resolves the queue against the NPC
  registry. Vanilla's own impact alarm cannot reach managed NPCs (they are deaf).

  Every noise has a reaction:
    hunt     gunfire, explosions, a firing turret: each one heard adds to the NPC's meter by
             weapon class (pistol < SMG / rifle < shotgun < DMR < sniper < grenade); past
             Detection.HuntAt the NPC draws its weapon and searches towards the sound
    search   a mate moaning or dying: walk over and check
    suspect  footsteps, impacts, suppressed shots, a body falling, a turret being deployed

  STATUS (tested 2026-10-30 and 2026-10-31): shot noise by class, hunting, suppressed shots, the
  suppressor's spread, turret and grenade noise, cries of the dying. Anything not exercised yet is
  marked NOT TESTED YET.
]]

local U = require("stealth.util")
local G = require("stealth.gamedefs")
local P = G.P

local N = { queue = {}, suppressed = {}, nextStep = 0, grenades = {}, turretAt = {} }
local MAX_QUEUE = 32

local function cfg() return STEALTH.cfg end

-- Queue a noise. react: "hunt", "search" or "suspect"; bump: meter added when heard up close.
function N.emit(pos, radius, kind, react, bump)
    if not pos or radius <= 0 or #N.queue >= MAX_QUEUE then return end
    N.queue[#N.queue + 1] = { pos = pos, r = radius, kind = kind, react = react or "suspect", bump = bump }
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

-- Per-shot check, so the answer is cached per weapon actor for a few seconds. Only weapon kinds
-- in Suppressor.Eligible count (0.1 allowed rifles too; those saved suppressors are ignored).
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
        local key = N.itemKey(weapon)
        k = { on = N.suppressed[key] == true and c.Eligible[N.kindOf(weapon)] == true, t = now }
        if a then keyCache[a] = k end
    end
    return k.on
end

-- Key press: fit / remove the suppressor on the weapon in hand. Returns a HUD text.
function N.toggleSuppressor(player)
    local w = weaponOf(player)
    if not w then return "No weapon in hand" end
    local kind = N.kindOf(w)
    if not cfg().Suppressor.Eligible[kind] then return "Only pistols take a suppressor" end
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

-- Slower bullets with a suppressor. The weapon's init resets MuzzleSpeed on every equip, so this
-- is re-applied on every shot (onTrace) when the game has written a fresh value.
local speedState = {} -- weapon address -> { base = game value, mine = value written }
function N.applyVelocity(w, fitted)
    local f = cfg().Suppressor.VelocityFactor
    local a = U.addr(w)
    local v = U.get(w, P.MuzzleSpeed, nil)
    if not a or type(v) ~= "number" then return end
    local st = speedState[a]
    if fitted then
        if not f or f == 1 then return end
        if st and math.abs(v - st.mine) < 1e-3 then return end -- still ours
        speedState[a] = { base = v, mine = v * f }
        U.set(w, P.MuzzleSpeed, v * f)
    elseif st then
        if math.abs(v - st.mine) < 1e-3 then U.set(w, P.MuzzleSpeed, st.base) end
        speedState[a] = nil
    end
end

-- Post-hook of Master_Hand_Weapon_C:CalculateTrace(out Start, out End): the aim of every shot
-- (camera location + forward x 1000 m). A suppressor makes the pistol longer and front-heavy:
-- a little more spread. Writing the out parameter changes the shot (UE4SS 3.0, as HTR does).
-- Verified in game (2026-10-31, pistol): 0.25 deg mean, 0.35 deg max; bullet speed x0.92.
function N.onTrace(weapon, startP, endP)
    if not N.isSuppressed(weapon) then return end
    N.applyVelocity(weapon, true)
    local deg = cfg().Suppressor.SpreadDegrees or 0
    if deg <= 0 then return end
    local s, e = startP:get(), endP:get()
    local dx, dy, dz = e.X - s.X, e.Y - s.Y, e.Z - s.Z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1 then return end
    -- random offset inside a cone of `deg` (uniform over the disc)
    local r = len * math.tan(math.rad(deg)) * math.sqrt(math.random())
    local a = math.random() * 2 * math.pi
    -- two axes perpendicular to the shot
    local fx, fy, fz = dx / len, dy / len, dz / len
    local ux, uy, uz = 0, 0, 1
    if math.abs(fz) > 0.95 then ux, uy, uz = 1, 0, 0 end
    local rx, ry, rz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
    local rl = math.sqrt(rx * rx + ry * ry + rz * rz)
    rx, ry, rz = rx / rl, ry / rl, rz / rl
    local qx, qy, qz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    local c1, c2 = r * math.cos(a), r * math.sin(a)
    endP:set({ X = e.X + rx * c1 + qx * c2, Y = e.Y + ry * c1 + qy * c2, Z = e.Z + rz * c1 + qz * c2 })
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
        N.emit(U.location(player), type(s) == "table" and (s[kind] or s.pistol or 1200) or s, "shot", "suspect", c.HeardBump)
    else
        N.emit(U.location(player), c.Shot[kind] or c.Shot.rifle, "shot", "hunt", c.ShotAlarm[kind] or 0.6)
    end
end

-- Post-hook of the player's OnProjectileHit_* (loc = impact point).
function N.onImpact(loc)
    local c = cfg().Noise
    N.emit(loc, c.Impact, "impact", "suspect", c.HeardBump)
end

-- A shooter NPC hit by gunfire that survives cries out; one killed by gunfire too.
-- (A silent takedown makes no such sound.)
function N.onPain(pos, dying)
    local now = os.clock()
    if not dying and now - (N.painAt or -1e9) < 0.5 then return end -- automatic fire: one cry is enough
    N.painAt = now
    local c = cfg().Noise
    N.emit(pos, dying and c.Dying or c.Pain, dying and "dying" or "pain", "search", c.PainMeter)
end

-- Post-hook of Player_PerkTurret_C:ReceiveBeginPlay: setting a turret up is not silent.
function N.onTurretDeployed(turret)
    local c = cfg().Noise
    N.emit(U.location(turret), c.TurretDeploy, "turret deploy", "suspect", c.HeardBump)
end

-- Post-hook of Player_PerkTurret_C:JustShoot (10 rounds a second): one noise per turret every
-- half second is enough.
function N.onTurretShot(turret)
    local a, now = U.addr(turret), os.clock()
    if not a or now - (N.turretAt[a] or -1e9) < 0.5 then return end
    N.turretAt[a] = now
    local c = cfg().Noise
    N.emit(U.location(turret), c.Shot.turret or 6500, "turret", "hunt", c.ShotAlarm.turret or 0.7)
end

-- Shared noise channel of the realism set (Tactical Engineering publishes it with
-- ModRef:SetSharedVariable("SB2R_Noise", "id,x,y,z,radius_cm,kind,time;...")), read once a second.
-- Deploying and firing are already heard through the turret hooks above (same turret class), so
-- only the events those hooks cannot see are used: "pack" (packing a turret up).
local sharedAt, sharedId = 0, 0
function N.readShared(now)
    if now < sharedAt then return end
    sharedAt = now + 1.0
    local ok, s = pcall(function() return ModRef:GetSharedVariable("SB2R_Noise") end)
    if not ok or type(s) ~= "string" or s == "" then return end
    for ev in s:gmatch("[^;]+") do
        local id, x, y, z, r, kind = ev:match("^(%d+),([-%d%.e]+),([-%d%.e]+),([-%d%.e]+),([%d%.e]+),([%w_]+)")
        id = tonumber(id)
        if id and id > sharedId then
            sharedId = id
            if kind == "pack" then
                N.emit({ X = tonumber(x), Y = tonumber(y), Z = tonumber(z) }, tonumber(r) or 1500, "turret pack", "suspect",
                    cfg().Noise.HeardBump)
            end
        end
    end
end

-- Grenades: the launcher (Master_Hand_Weapon:GranedeLuncherPressed) spawns Grenade_launched_C,
-- whose actor stays at the map origin while it flies (seen in game: the visible grenade is not
-- its root), so it cannot be followed. The blast is heard GrenadeDelay seconds after the launch,
-- GrenadeDistance ahead of where you aimed (the launcher fires along the camera).
function N.onGrenadeLaunch(weapon)
    local player = U.playerPawn(weapon)
    if not player then return end
    local c = cfg().Noise
    local pos = U.location(player)
    if not pos then return end
    N.emit(pos, c.GrenadeLaunch, "launcher", "suspect", c.HeardBump)
    local yaw
    pcall(function() yaw = player.Controller:GetControlRotation().Yaw end)
    local f = yaw and { X = math.cos(math.rad(yaw)), Y = math.sin(math.rad(yaw)) } or U.forward(player) or { X = 1, Y = 0 }
    local d = c.GrenadeDistance or 1500
    if #N.grenades < 8 then
        N.grenades[#N.grenades + 1] = { pos = { X = pos.X + f.X * d, Y = pos.Y + f.Y * d, Z = pos.Z }, at = os.clock() + (c.GrenadeDelay or 1.5) }
    end
end

function N.trackGrenades(now)
    if #N.grenades == 0 then return end
    local keep = {}
    for _, g in ipairs(N.grenades) do
        if now >= g.at then
            local c = cfg().Noise
            N.emit(g.pos, c.Shot.grenade or 12000, "grenade", "hunt", c.ShotAlarm.grenade or 0.9)
            U.log(string.format("grenade blast at %.0f %.0f %.0f", g.pos.X, g.pos.Y, g.pos.Z))
        else
            keep[#keep + 1] = g
        end
    end
    N.grenades = keep
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
    N.emit(me.pos, r, "steps", "suspect", cfg().Noise.HeardBump)
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
local FROM_PLAYER = { shot = true, steps = true, launcher = true }
function N.process(A, player)
    if #N.queue == 0 then return end
    local c = cfg().Noise
    local now = os.clock()
    local budget = c.MaxOcclusionChecksPerTick
    for _, n in ipairs(N.queue) do
        -- the occlusion test looks from the NPC to the player, so it only fits noises you make
        local fromPlayer = FROM_PLAYER[n.kind]
        for _, e in pairs(A.npcs) do
            if e.managed and e.pos then
                local d = U.dist(e.pos, n.pos)
                local r = n.r * A.hearing(e, now) -- suspicion sharpens hearing too
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
                    local close = 1 - d / r -- 1 right next to it, 0 at the edge
                    local why = string.format("heard %s at %.0f m", n.kind, d / 100)
                    local bump = (n.bump or c.HeardBump) * (0.5 + 0.5 * close)
                    if n.react == "hunt" then
                        A.hearAlarm(e, n.pos, bump, why)
                    elseif n.react == "search" then
                        A.search(e, n.pos, why, n.bump)
                    else
                        A.suspect(e, n.pos, bump, why)
                    end
                end
            end
        end
    end
    N.queue = {}
end

return N

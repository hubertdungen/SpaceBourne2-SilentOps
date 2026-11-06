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
local looksAt = 0
local MAX_QUEUE = 32

local function cfg() return STEALTH.cfg end

-- Queue a noise. react: "hunt", "search" or "suspect"; bump: meter added when heard up close.
function N.emit(pos, radius, kind, react, bump, src)
    if not pos or radius <= 0 or #N.queue >= MAX_QUEUE then return end
    -- a loud noise masks quiet ones for a few seconds (DESIGN.md 17.5)
    if react == "hunt" then N.maskUntil = os.clock() + (cfg().Environment.MaskSeconds or 5) end
    N.queue[#N.queue + 1] = { pos = pos, r = radius, kind = kind, react = react or "suspect", bump = bump, src = src }
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

-- Key press: start screwing the suppressor on / off the weapon in hand. It takes
-- Suppressor.FitSeconds; meanwhile the weapon cannot fire (its own Reloading flag, which the fire
-- loop checks first) and the change applies when done (N.tickFitting). Returns a HUD text.
N.fitting = nil
function N.toggleSuppressor(player)
    if N.fitting then return "Busy with the suppressor" end
    local w = weaponOf(player)
    if not w then return "No weapon in hand" end
    local kind = N.kindOf(w)
    if not cfg().Suppressor.Eligible[kind] then return "Only pistols take a suppressor" end
    local key = N.itemKey(w)
    local fit = not N.suppressed[key]
    local secs = cfg().Suppressor.FitSeconds or 0
    N.fitting = { w = w, a = U.addr(w), key = key, fit = fit, at = os.clock() + secs }
    if secs <= 0 then return N.tickFitting(os.clock()) end
    U.set(w, P.Reloading, true)
    return string.format("%s suppressor... (%.0f s)", fit and "Fitting" or "Removing", secs)
end

-- From the tick: finish the fitting. Returns a HUD text when done, else nil.
function N.tickFitting(now)
    local f = N.fitting
    if not f then return nil end
    local alive = U.alive(f.w, f.a)
    if alive and now < f.at then
        U.set(f.w, P.Reloading, true) -- keep the weapon blocked (a reload could clear it)
        return nil
    end
    N.fitting = nil
    if not alive then return "Suppressor: interrupted" end -- weapon changed
    U.set(f.w, P.Reloading, false)
    keyCache, keyCount = {}, 0
    N.suppressed[f.key] = f.fit or nil
    N.applyVelocity(f.w, f.fit)
    looksAt = 0 -- show / hide the model at once
    return f.fit and "Suppressor fitted" or "Suppressor removed"
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

-- Visible suppressor and quieter shot (DESIGN.md 17.9), from the tick, on the weapon in hand:
--   model: the engine's cylinder (cooked into SB2) attached to the muzzle (EBBarrel, where shots
--          start), Suppressor.ModelLength x ModelDiameter cm, the pistol's own material; shown
--          only while a suppressor is fitted, removed on swap / holster / death / load.
--   sound: the pistol's own shot cues play quieter and higher while the suppressed pistol is
--          in hand (see setSound). No new sound asset can be added without a pak.
local CYL, SMC = "/Engine/BasicShapes/Cylinder.Cylinder", "/Script/Engine.StaticMeshComponent"
local model = { comp = nil, a = nil, cyl = nil, smc = nil, missing = false }
local sound = { a = nil }
local function dropModel()
    if model.comp then pcall(function() model.comp:K2_DestroyComponent(model.comp) end) end
    model.comp, model.a = nil, nil
end
-- The pistol you see is the character's own PistolSM (the weapon actor's mesh is a hidden copy;
-- verified in game: a cylinder on the weapon actor lay on the floor). Its "Muzzle" socket points
-- along the barrel; the tube follows the pistol's visibility.
local function addModel(player)
    local c = cfg().Suppressor
    if model.missing then return end
    if not U.valid(model.cyl) then
        model.cyl = StaticFindObject(CYL) -- once (a miss costs ~37 ms)
        if not U.valid(model.cyl) then model.missing = true; U.warn("engine cylinder not found: no suppressor model"); return end
    end
    if not U.valid(model.smc) then model.smc = StaticFindObject(SMC) end
    local pm = U.get(player, "PistolSM", nil)
    if not (U.valid(pm) and U.valid(model.smc)) then return end
    local ok, comp = pcall(function()
        return player:AddComponentByClass(model.smc, false, { Translation = { X = 0, Y = 0, Z = 0 }, Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
            Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    end)
    if not (ok and U.valid(comp)) then return end
    local len, dia = c.ModelLength or 15, c.ModelDiameter or 4
    pcall(function() comp:SetStaticMesh(model.cyl) end)
    pcall(function() comp:SetCollisionEnabled(0) end)
    pcall(function() comp:SetCastShadow(false) end)
    pcall(function() comp:K2_AttachToComponent(pm, FName("Muzzle"), 2, 2, 1, false) end)
    pcall(function() comp:K2_SetRelativeLocationAndRotation({ X = len / 2, Y = 0, Z = 0 }, { Pitch = -90, Yaw = 0, Roll = 0 }, false, {}, false) end)
    pcall(function() comp:SetWorldScale3D({ X = dia / 100, Y = dia / 100, Z = len / 100 }) end)
    pcall(function() comp:SetMaterial(0, pm:GetMaterial(0)) end)
    model.comp, model.a = comp, U.addr(player)
end
-- The pistol's shots come from its weapon SFX component (WeaponSFXCompoment_III): cues_OneShot
-- = { near shot, distant echo }, cues_Tail = the tail. Its cues_OneShot_Suppressor is empty in this
-- game, so while the suppressor is on the mod plays the same cues quieter and higher (near x
-- SoundVolume, echo x SoundDistantVolume, tail x SoundTailVolume, pitch x SoundPitch) and restores
-- them otherwise. The cues are shared by pistols of that type.
local cueOrig = {} -- cue name -> { obj, vol, pitch }
local function forCues(w, fn)
    local fx
    pcall(function() fx = w:GetWeaponFXComponent() end)
    if not U.valid(fx) then return end
    for _, arr in ipairs({ "cues_OneShot", "cues_Tail" }) do
        local i = 0
        pcall(function()
            fx[arr]:ForEach(function(_, e)
                i = i + 1
                local cue = e:get()
                if U.valid(cue) then fn(arr, i, cue) end
            end)
        end)
    end
end
local function restoreCues()
    for k, o in pairs(cueOrig) do
        if U.valid(o.obj) then pcall(function() o.obj.VolumeMultiplier = o.vol; o.obj.PitchMultiplier = o.pitch end) end
        cueOrig[k] = nil
    end
end
local function setSound(w, on)
    local c = cfg().Suppressor
    if not on then
        if sound.a then restoreCues(); sound.a = nil end
        return
    end
    local a = U.addr(w)
    if sound.a == a then return end
    restoreCues()
    sound.a = a
    forCues(w, function(arr, i, cue)
        local k = cue:GetFName():ToString()
        if not cueOrig[k] then cueOrig[k] = { obj = cue, vol = U.get(cue, "VolumeMultiplier", 1.0), pitch = U.get(cue, "PitchMultiplier", 1.0) } end
        local o = cueOrig[k]
        local f = (arr == "cues_Tail") and (c.SoundTailVolume or 0.2) or (i == 1 and (c.SoundVolume or 0.3) or (c.SoundDistantVolume or 0))
        pcall(function() cue.VolumeMultiplier = o.vol * f; cue.PitchMultiplier = o.pitch * (c.SoundPitch or 1.2) end)
    end)
end
function N.updateLooks(player, now)
    if now < looksAt then return end
    looksAt = now + 0.5
    local w = U.valid(player) and weaponOf(player) or nil
    local on = w ~= nil and N.isSuppressed(w)
    if not on or (model.comp and (model.a ~= U.addr(player) or not U.valid(model.comp))) then dropModel() end
    if on and not model.comp and cfg().Suppressor.ShowModel then addModel(player) end
    if model.comp then -- shown only while the pistol model is
        local vis = U.get(U.get(player, "PistolSM", nil), "bVisible", true) == true
        pcall(function() model.comp:SetVisibility(vis, false) end)
    end
    setSound(w, on)
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

-- Post-hook of Q1_Shooter_AI_C:JustShoot: every shot of an on-foot NPC, allies' and enemies' (0.3.3).
-- Before, only your shots, the squad's and turrets' were noise, so enemies Silent Ops keeps deaf to
-- vanilla alarms walked on while allies fought in the next room. One noise per shooter per 0.5 s.
local npcShotAt, npcShotCount = {}, 0
function N.onNpcShot(npc)
    local a, now = U.addr(npc), os.clock()
    if not a or now - (npcShotAt[a] or -1e9) < 0.5 then return end
    if U.get(npc, P.Dead, false) == true then return end
    if npcShotAt[a] == nil then
        npcShotCount = npcShotCount + 1
        if npcShotCount > 64 then npcShotAt, npcShotCount = {}, 1 end
    end
    npcShotAt[a] = now
    local c = cfg().Noise
    local kind = U.get(npc, P.Sniper, false) == true and "sniper" or "rifle"
    N.emit(U.location(npc), c.Shot[kind] or 6500, "npc " .. kind, "hunt", c.ShotAlarm[kind] or 0.6, npc)
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
-- Environment (DESIGN.md 17.5): stations are noisy (machinery, crowds), dungeons quiet.
local function placeHearing(where)
    local h = cfg().Environment.Hearing
    if where == G.Where.StationTrans or where == G.Where.StationSubLevel then return h.Station or 1.0 end
    if where == G.Where.Dungeon then return h.Dungeon or 1.0 end
    return 1.0
end
function N.process(A, player, where)
    if #N.queue == 0 then return end
    local c = cfg().Noise
    local now = os.clock()
    local env = placeHearing(where)
    local masked = now < (N.maskUntil or 0)
    local budget = c.MaxOcclusionChecksPerTick or 6
    for _, n in ipairs(N.queue) do
        -- the occlusion test looks from the NPC to the source: you for the noises you make, the
        -- shooter for NPC gunfire (0.3.3); other noises have no source to look at
        local src = n.src
        if src == nil and FROM_PLAYER[n.kind] then src = player end
        if src ~= nil and not U.valid(src) then src = nil end
        local srcA = n.src and U.addr(n.src) -- a shooter does not hear its own shot
        for _, e in pairs(A.npcs) do
            if e.managed and e.pos and not (srcA and e.a == srcA) then
                local d = U.dist(e.pos, n.pos)
                local r = n.r * A.hearing(e, now) * env -- suspicion sharpens hearing; machinery dulls it
                if masked and n.react == "suspect" then r = r * (cfg().Environment.MaskFactor or 0.6) end
                local far = false -- gunfire beyond the next room (walls in between)
                if src and d < r and d > r * c.OccludedFactor and budget > 0 then
                    -- outer band: heard plainly only with a clear line to the source
                    local npc = A.objOf(e)
                    budget = budget - 1
                    local ok, los = false, false
                    if npc then
                        ok, los = pcall(function() return npc.Controller:LineOfSightTo(src, { X = 0, Y = 0, Z = 0 }, false) end)
                    end
                    if not (ok and los == true) then
                        if n.react == "hunt" and c.FarGunfire ~= false then far = true
                        else r = r * c.OccludedFactor end
                    end
                end
                if d < r then
                    local close = 1 - d / r -- 1 right next to it, 0 at the edge
                    local why = string.format("heard %s at %.0f m", n.kind, d / 100)
                    local bump = (n.bump or c.HeardBump) * (0.5 + 0.5 * close)
                    local train = e.perception or 1.0 -- Pirate 0.85 .. Elite 1.35 (Detection.Perception)
                    if far then
                        -- two rooms away: suspicious, they come to check; Regulars and Elites with
                        -- the weapon drawn, pirates and militia without
                        if train >= 1.0 then A.hunt(e, n.pos, why .. " through walls")
                        else A.search(e, n.pos, why .. " through walls", cfg().Detection.InvestigateAt) end
                    elseif n.react == "hunt" then
                        A.hearAlarm(e, n.pos, bump * train, why) -- trained ears react sooner
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

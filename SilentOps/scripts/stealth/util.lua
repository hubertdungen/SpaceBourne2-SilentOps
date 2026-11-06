--[[
  Shared helpers (adapted from HTR's htr/util.lua). Safety rules, measured in this game:
   * Never call RegisterLoadMapPreHook/PostHook: they crash this game.
   * Hooks only on Blueprint functions (native hooks crash UE4SS 3.0).
   * Never FindAllOf/FindFirstOf in per-shot or per-tick code (~50 ms each).
     The only FindAllOf in this mod runs on the ally-order key press.
   * GetAllActorsOfClass with a Lua out-table corrupts the Lua state in UE4SS 3.0.1.
   * HTR never keeps a game object from one frame to the next. This mod does, for NPCs
     near the player only, and checks U.alive() before every use (DESIGN.md section 2).
     Verified in game: a destroyed NPC's reference reads invalid once collected.
]]

local U = {}

-- Mod folder (UE4SS may report the path as ...\Scripts\ or ...\scripts\).
do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local lower = src:lower()
    local cut
    for i in lower:gmatch("()[\\/]scripts[\\/]") do cut = i end
    U.Dir = cut and src:sub(1, cut) or ".\\Mods\\SilentOps\\"
end
U.LogFile = U.Dir .. "stealth.log"
U.Verbose = false

function U.log(...)
    if not U.Verbose then return end
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), table.concat(t, " "), "\n"); f:close() end
end

-- Always printed (UE4SS.log) and logged.
function U.warn(...)
    local msg = table.concat({ ... }, " ")
    print("[Silent Ops] " .. msg .. "\n")
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), "WARN ", msg, "\n"); f:close() end
end

function U.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end

function U.addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

-- A reference kept from an earlier frame is usable only if it is still valid AND still
-- the same object (same address). Verified in game.
function U.alive(o, addr)
    return U.valid(o) and U.addr(o) == addr
end

function U.className(o)
    if not U.valid(o) then return nil end
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or nil
end

function U.get(o, prop, default)
    local ok, v = pcall(function() return o[prop] end)
    if ok and v ~= nil then return v end
    return default
end

function U.set(o, prop, value)
    return pcall(function() o[prop] = value end)
end

function U.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
function U.lerp(a, b, t) return a + (b - a) * t end

local GS
function U.gameplayStatics()
    if not U.valid(GS) then GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    return GS
end

-- The player's pawn through a live object in the world (instant engine lookup).
function U.playerPawn(ctx)
    if ctx == nil then return nil end
    local ok, p = pcall(function() return U.gameplayStatics():GetPlayerPawn(ctx, 0) end)
    if ok and U.valid(p) then return p end
    return nil
end

-- Vectors are plain tables { X, Y, Z } (never keep engine structs around).
function U.location(actor)
    local ok, l = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and l then return { X = l.X, Y = l.Y, Z = l.Z } end
    return nil
end

function U.forward(actor)
    local ok, f = pcall(function() return actor:GetActorForwardVector() end)
    if ok and f then return { X = f.X, Y = f.Y, Z = f.Z } end
    return nil
end

function U.dist(a, b)
    if not (a and b) then return 1e9 end
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Angle in degrees between `fwd` and the direction from `from` to `to`, ignoring height.
function U.angleTo(fwd, from, to)
    local dx, dy = to.X - from.X, to.Y - from.Y
    local len = math.sqrt(dx * dx + dy * dy)
    local flen = math.sqrt(fwd.X * fwd.X + fwd.Y * fwd.Y)
    if len < 1 or flen < 1e-6 then return 0 end
    local c = (fwd.X * dx + fwd.Y * dy) / (len * flen)
    return math.deg(math.acos(U.clamp(c, -1, 1)))
end

function U.speed(actor)
    local ok, v = pcall(function() local x = actor:GetVelocity(); return math.sqrt(x.X * x.X + x.Y * x.Y) end)
    return ok and v or 0
end

-- Blackboard helpers for shooter NPCs (same calls HTR uses).
function U.blackboard(npc)
    local ok, bb = pcall(function()
        local c = npc.Controller
        if c and c:IsValid() then return c.Blackboard end
    end)
    if ok and U.valid(bb) then return bb end
    return nil
end

function U.bbSetBool(npc, key, value)
    local bb = U.blackboard(npc)
    if not bb then return false end
    return pcall(function() bb:SetValueAsBool(FName(key), value) end)
end

function U.bbGetBool(npc, key)
    local bb = U.blackboard(npc)
    if not bb then return nil end
    local ok, v = pcall(function() return bb:GetValueAsBool(FName(key)) end)
    return ok and v or nil
end

-- Is Shift, Ctrl or Alt held right now? Asked of the game's own input (same technique as
-- HTR 0.4.4), so a plain F4 bind stays quiet when the player presses Shift+F4, and plain F3
-- stays quiet for Shift+F3. Key presses only. Verified in game.
-- The controller is looked up again on every press, never kept: after a load the old one's memory
-- can be reused by another object at the same address (HTR's finding, 2026-10-31).
local MOD_KEYS = { "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt" }
function U.modifierDown(player)
    local pc
    if U.valid(player) then
        local ok, c = pcall(function() return player.Controller end)
        if ok and U.valid(c) then pc = c end
    end
    if not pc then pc = FindFirstOf("PlayerController") end -- rare (no pawn controller), key presses only
    if not U.valid(pc) then return false end
    for _, k in ipairs(MOD_KEYS) do
        local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and down then return true end
    end
    return false
end

-- On-screen message on foot (verified by HTR 0.4.1), through the set's shared stealth/hudmsg.lua:
-- no HUD beep (the "tu-tu-tu" players heard), held about 5 s so it can be read, the same text at
-- most once per 30 s. force: shown even if repeated (key presses, COMPROMISED).
local HM = require("stealth.hudmsg")
function U.notify(text, ctx, force)
    local p = U.playerPawn(ctx) or ctx
    if not U.valid(p) then return false end
    return HM.show(p, text, nil, force)
end

return U

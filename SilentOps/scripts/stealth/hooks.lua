--[[
  Lazy, fault-isolated hook registration. Same code as HTR's htr/hooks.lua (verified there):
  hooks are grouped by class and registered when the class appears; a callback that keeps
  throwing Lua errors is switched off; slow callbacks are reported.

  Cost rule (measured): a StaticFindObject that misses costs ~37 ms, so missing classes are
  looked up with a growing pause (1, 2, 4, 8, 16 s), at most one miss per poll.

  UE4SS 3.0 facts for Blueprint functions (verified by HTR):
    - the callback runs AFTER the Blueprint body;
    - writing an OUT parameter with :set() changes what the caller receives.
]]

local U = require("stealth.util")

local H = { list = {}, groups = {}, order = {}, SLOW = 0.008 }
local MAX_ERRORS = 25
local CHECK_LOADED = 5
local RETRY_MAX = 16

function H.add(path, fn, tag)
    local h = { path = path, fn = fn, tag = tag or path, errors = 0, disabled = false, on = false, slow = 0, slowAt = -1e9,
        calls = 0, total = 0 }
    h.cb = function(...)
        if h.disabled or STEALTH_DISABLED then return end
        local t0 = os.clock()
        local ok, err = pcall(h.fn, ...)
        local dt = os.clock() - t0
        h.calls, h.total = h.calls + 1, h.total + dt
        if dt > H.SLOW then
            h.slow = h.slow + 1
            if t0 - h.slowAt > 30 then
                h.slowAt = t0
                U.warn(string.format("slow hook %s: %.0f ms (%d slow calls so far)", h.tag, dt * 1000, h.slow))
            end
        end
        if not ok then
            h.errors = h.errors + 1
            if h.errors <= 3 then U.warn("error in " .. h.tag .. ": " .. tostring(err)) end
            if h.errors >= MAX_ERRORS then
                h.disabled = true
                U.warn("hook " .. h.tag .. " disabled after repeated errors")
            end
        end
    end
    H.list[#H.list + 1] = h
    local cls = path:match("^(.-):") or path
    local g = H.groups[cls]
    if not g then
        g = { cls = cls, hooks = {}, addr = nil, retry = 1, nextTry = 0 }
        H.groups[cls] = g
        H.order[#H.order + 1] = g
    end
    g.hooks[#g.hooks + 1] = h
end

local function register(h)
    local ok, err = pcall(RegisterHook, h.path, h.cb)
    h.on = ok
    if ok then
        U.log("hooked " .. h.tag)
    else
        U.warn("could not hook " .. h.path .. ": " .. tostring(err))
    end
end

function H.wake()
    for _, g in ipairs(H.order) do
        if not g.addr then g.retry, g.nextTry = 1, 0 end
    end
end

-- Call on the game thread about once a second. Returns how many hooks were registered.
function H.poll(now)
    local probed, registered = false, 0
    for _, g in ipairs(H.order) do
        if now >= g.nextTry and (g.addr or not probed) then
            if not g.addr then probed = true end
            local c = StaticFindObject(g.cls)
            local a = (c and c:IsValid()) and c:GetAddress() or nil
            if a then
                g.nextTry, g.retry = now + CHECK_LOADED, 1
                if a ~= g.addr then
                    g.addr = a
                    for _, h in ipairs(g.hooks) do register(h); registered = registered + 1 end
                end
            else
                if g.addr then
                    g.addr = nil
                    for _, h in ipairs(g.hooks) do h.on = false end
                end
                g.nextTry = now + g.retry
                g.retry = math.min(g.retry * 2, RETRY_MAX)
            end
        end
    end
    return registered
end

function H.profile()
    local rows = {}
    for _, h in ipairs(H.list) do
        if h.calls > 0 then rows[#rows + 1] = { h.tag, h.calls, h.total * 1000 } end
        h.calls, h.total = 0, 0
    end
    table.sort(rows, function(a, b) return a[3] > b[3] end)
    local parts = {}
    for i = 1, math.min(#rows, 12) do parts[i] = string.format("%s %dx %.0fms", rows[i][1], rows[i][2], rows[i][3]) end
    return table.concat(parts, " | ")
end

function H.status()
    local on, off = 0, 0
    for _, h in ipairs(H.list) do if h.on and not h.disabled then on = on + 1 else off = off + 1 end end
    return on, off
end

return H

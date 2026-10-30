--[[
  HUD feedback (DESIGN.md section 8): short text messages on state changes only,
  through the on-foot warning HTR verified (TMWPerkWarning). Throttled.
  STATUS: verified in game (2026-10-30): "Suppressor fitted" shown on screen.
]]

local U = require("stealth.util")

local HUD = { last = "", lastAt = -1e9, pending = nil }

local function cfg() return STEALTH.cfg.Hud end

-- Show now (key presses) or queue (state changes, sent when the throttle allows).
function HUD.say(text, ctx, urgent)
    if not cfg().Messages or not text then return end
    local now = os.clock()
    if urgent or now - HUD.lastAt >= cfg().MinSecondsBetween then
        if U.notify(text, ctx) then HUD.last, HUD.lastAt, HUD.pending = text, now, nil end
    else
        HUD.pending = text
    end
end

-- From the tick: turn the awareness summary into one line when it changes.
function HUD.update(sum, ctx)
    local text
    if sum.compromised then
        text = "COMPROMISED"
    elseif sum.lost then
        text = "Lost them - enemies are searching"
    elseif sum.searching > 0 then
        text = string.format("Enemies searching (%d)", sum.searching)
    elseif sum.suspicious > 0 then
        text = string.format("Suspicious (%d) %d%%", sum.suspicious, math.floor(sum.maxMeter * 100 + 0.5))
    else
        text = "Hidden"
    end
    -- the percentage changes every tick: only the state word counts as "new"
    local key = text:gsub("%s*%d+%%$", "")
    if key ~= HUD.lastKey then
        HUD.lastKey = key
        HUD.say(text, ctx, text == "COMPROMISED")
    elseif HUD.pending and os.clock() - HUD.lastAt >= cfg().MinSecondsBetween then
        HUD.say(HUD.pending, ctx)
    end
end

return HUD

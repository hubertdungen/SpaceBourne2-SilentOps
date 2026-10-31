--[[
  HUD feedback (DESIGN.md section 8): short text messages on state changes only,
  through the on-foot warning HTR verified (TMWPerkWarning). Throttled.
  The game plays its warning sound with every such message, so 0.2 shows fewer of them:
  no "Hidden" line by default and no percentages, at most one every Hud.MinSecondsBetween.
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
    if not cfg().States then return end
    local text
    if sum.compromised then
        text = "COMPROMISED"
    elseif sum.lost then
        text = "Lost them - enemies are hunting for you"
    elseif sum.hunting > 0 then
        text = "Enemies on alert - weapons drawn"
    elseif sum.searching > 0 then
        text = "Enemies searching"
    elseif sum.suspicious > 0 then
        text = "Someone is suspicious"
    else
        text = cfg().ShowHidden and "Hidden" or nil
    end
    local key = text or "calm"
    if key ~= HUD.lastKey then
        HUD.lastKey = key
        if text then HUD.say(text, ctx, text == "COMPROMISED") else HUD.pending = nil end
    elseif HUD.pending and os.clock() - HUD.lastAt >= cfg().MinSecondsBetween then
        HUD.say(HUD.pending, ctx)
    end
end

return HUD

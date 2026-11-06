--[[
  On-screen lines for the SpaceBourne 2 realism set (the same file in each mod).

  Mods show a line through Q1_Character:TMWPerkWarning, the HUD line the game uses for "No Target
  Nearby". The game's HUD (Curved_Widget_Test, handler of the TMW_PerkWarning event) then plays the
  beep Beep_Tech_08 on every line and hides the line 2 s after the last one. Players heard a
  "tututu" on every pickup and could not read longer lines (2026-11-05). So:
  * quiet: the beep is muted around our own lines. The set keeps its normal volume in the shared
    variable SB2R_BeepVolume and the time to unmute in SB2R_BeepUntil, so one mod never restores
    the 0 another mod set, and the game's own lines beep again a second later;
  * readable: a line stays about HoldSeconds, sent again quietly every 1.5 s, unless a newer line
    (from any mod of the set: SB2R_LineStamp) took its place;
  * rare: the same text at most once per RepeatSeconds.
  Objects are never kept between frames: the pawn is found again by its path for each resend.
]]

local HM = { RepeatSeconds = 30, HoldSeconds = 5, Quiet = true }

-- The HUD's beep, and the "can't do that" alarm older builds of the set muted; normal volumes are
-- shared under these names (HTR and Tactical Engineering use SB2R_CantVolume too).
local SOUNDS = {
    { path = "/Game/11Misc/LGUI/Audio/Beep_Tech_08.Beep_Tech_08", key = "SB2R_BeepVolume" },
    { path = "/Game/11Misc/LGUI/Audio/GUI_Cant.GUI_Cant", key = "SB2R_CantVolume" },
}
local lastShown = {}  -- text -> os.clock()

local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end
local function shared(name)
    local ok, v = pcall(function() return ModRef:GetSharedVariable(name) end)
    if ok then return v end
end
local function setShared(name, v) pcall(function() ModRef:SetSharedVariable(name, v) end) end

local function normalVolume(snd, key)
    local normal = shared(key)
    if type(normal) == "number" and normal > 0 then return normal end
    local ok, v = pcall(function() return snd.Volume end)
    normal = (ok and type(v) == "number" and v > 0) and v or 1.0
    setShared(key, normal)
    return normal
end

local function mute(seconds)
    local untilT = os.clock() + seconds
    local cur = shared("SB2R_BeepUntil")
    if type(cur) ~= "number" or cur < untilT then setShared("SB2R_BeepUntil", untilT) end
    for _, sd in ipairs(SOUNDS) do
        local snd = StaticFindObject(sd.path)
        if valid(snd) then
            normalVolume(snd, sd.key)
            pcall(function() snd.Volume = 0.0 end)
        end
    end
    ExecuteWithDelay(math.floor(seconds * 1000) + 100, function()
        ExecuteInGameThread(function()
            local u = shared("SB2R_BeepUntil")
            if type(u) == "number" and os.clock() < u then return end -- a newer line is still quiet
            for _, sd in ipairs(SOUNDS) do
                local s = StaticFindObject(sd.path)
                if valid(s) then
                    local normal = normalVolume(s, sd.key)
                    pcall(function() s.Volume = normal end)
                end
            end
        end)
    end)
end

local function pathOf(o)
    local ok, full = pcall(function() return o:GetFullName() end)
    return ok and type(full) == "string" and full:match("^%S+%s+(.+)$") or nil
end

local function send(pawn, text)
    if HM.Quiet then mute(1.0) end
    return pcall(function() pawn:TMWPerkWarning(FText(text)) end)
end

-- Show text on the player's on-foot HUD line. force: show even if the same text was shown lately
-- (on/off switches). Returns true if shown, false if skipped or failed.
function HM.show(pawn, text, holdSeconds, force)
    if not (valid(pawn) and type(text) == "string" and text ~= "") then return false end
    local now = os.clock()
    if not force and lastShown[text] and now - lastShown[text] < HM.RepeatSeconds then return false end
    if not send(pawn, text) then return false end
    lastShown[text] = now
    local stamp = tostring(now) .. "|" .. text
    setShared("SB2R_LineStamp", stamp)
    local path, untilT = pathOf(pawn), now + (holdSeconds or HM.HoldSeconds)
    local function again()
        if os.clock() > untilT - 1.0 or shared("SB2R_LineStamp") ~= stamp then return end
        local p = path and StaticFindObject(path)
        if not valid(p) then return end
        send(p, text)
        ExecuteWithDelay(1500, function() ExecuteInGameThread(again) end)
    end
    ExecuteWithDelay(1500, function() ExecuteInGameThread(again) end)
    return true
end

return HM

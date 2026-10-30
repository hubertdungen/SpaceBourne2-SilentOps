--[[
  Silent Ops - realistic stealth on foot for SpaceBourne 2
  =========================================================
  USER SETTINGS. Edit with any text editor, then restart the game.
  Everything here is optional: delete a line and the default in main.lua is used.
  Distances are in cm (100 = 1 m). Angles in degrees.

  STATUS: first in-game tests passed (2026-10-30). Not released yet.
]]

return {
    -- Starting state. OFF by default; ToggleKey switches stealth on/off in game (remembered).
    -- Keys: a UE4SS key name, optionally with Shift: "F4", "Shift+F4". "" disables a key.
    -- They follow the realism set's shared key plan: only Shift as a modifier (on foot Ctrl opens
    -- the map and Alt crouches), never F1 F2 F5 F6 F8 F10 F12 (squad orders, quick save, quick
    -- load, bug report, Steam screenshot). Plain keys stay quiet while Shift is held, so Shift+F4
    -- does not also fit a suppressor. Stealth keys work on foot only.
    Enabled   = false,
    ToggleKey = "Shift+F4",

    Detection = {
        -- How far an NPC can see you at all. "eye": read from the NPC's own eye, which HTR 0.4.2
        -- sets to its doctrine's relaxed sight (vanilla: 35 m). "config": use SightRange.
        SightSource          = "eye",
        SightRange           = 3500,
        SearchingRangeFactor = 2.0,  -- NPCs searching (or who searched recently) see this much farther
        BubbleRadius        = 6000, -- NPCs farther than this are not processed
        CentralHalfAngle    = 35,   -- full attention inside this cone
        PeripheralHalfAngle = 75,   -- side vision up to here...
        PeripheralFactor    = 0.35, -- ...at this fraction
        -- Posture: a crouched silhouette is made out at a shorter range and noticed more slowly.
        Stance        = { Standing = 1.0, Crouching = 0.6 },
        -- Movement: motion draws the eye. Movement = how fast suspicion builds,
        -- MovementRange = how far away it still counts (standing still in the open is still seen).
        Movement      = { Still = 0.5, Walk = 1.0, Run = 1.5, Sprint = 2.2 },
        MovementRange = { Still = 0.85, Walk = 1.0, Run = 1.1, Sprint = 1.2 },
        StillSpeed           = 50,   -- cm/s; slower counts as standing still
        FlashlightFactor     = 2.0,  -- flashlight on: much easier to see...
        FlashlightRangeFactor = 1.5, -- ...and from farther away
        AmbientLight         = 1.0,  -- manual darkness factor (the game gives no light level)
        FillNearPerSec       = 2.0,  -- suspicion gained per second when seen up close...
        FillFarPerSec        = 0.25, -- ...and at the edge of sight
        DecayPerSec          = 0.12, -- suspicion lost per second out of sight
        SuspiciousAt         = 0.35, -- meter level where an NPC stops and looks
        InvestigateAt        = 0.6,  -- ...and where it walks over to check
        InstantAlertRange    = 250,  -- in front of an NPC and closer than this: spotted at once
        ProximityRange       = 120,  -- right next to an NPC (any side)...
        ProximitySeconds     = 1.5,  -- ...for this long, not crouched and still: noticed
        AlertedPerception    = 1.5,  -- NPCs that searched recently look harder
        AlertedMemorySeconds = 120,
        SearchRadius         = 600,  -- searching NPCs check points this far around the last clue
        InvestigateStepSeconds = 6,
        SearchSeconds        = 40,   -- then they give up and go back to patrol
        LoseSeconds          = 25,   -- out of every alerted enemy's sight this long: they lose you
        Shout                = true, -- an NPC that spots you alerts mates that can see it...
        ShoutRadius          = 1500, -- ...within this distance
        SniperRangeFactor    = 1.0,  -- extra range for relaxed snipers (HTR already sets theirs)
        Perception = { Pirate = 0.85, Militia = 0.9, Elite = 1.15 },
        AffectBosses         = false, -- bosses and robot tanks always behave as in vanilla
        AffectTanks          = false,
        MaxLineOfSightPerTick = 8,    -- performance cap
    },

    Noise = {
        -- Unsuppressed shot radius per weapon kind (a gunshot carries far; walls halve it).
        Shot = { pistol = 5000, smg = 6000, rifle = 8000, shotgun = 7000, dmr = 9000, sniper = 10000,
                 laser = 2500, beam = 1500 },
        -- Suppressed: real suppressors reduce, they do not silence. Pistols and SMGs thump; rifles
        -- keep their supersonic crack. Heard as "something odd" (NPCs investigate), not as an alarm.
        SuppressedShot = { pistol = 1200, smg = 1500, rifle = 2500, dmr = 2500, sniper = 3500 },
        Impact         = 500,   -- around where your bullet lands
        Footsteps = { Crouch = 100, Walk = 300, Run = 700, Sprint = 1200 },
        BodyFall       = 500,
        Takedown       = 250,
        HeavyTakedown  = 600,   -- hammer
        SquadShot      = 6000,
        OccludedFactor = 0.5,   -- no line of sight to the source: heard at half the distance
        LoudFraction   = 0.4,   -- a loud noise this close sends NPCs searching
        HeardBump      = 0.4,   -- suspicion added by a noise heard farther away
        MaxOcclusionChecksPerTick = 6,
    },

    Suppressor = {
        ToggleKey = "F4",      -- fit / remove a suppressor on the weapon in your hands
        Eligible  = { pistol = true, smg = true, rifle = true, dmr = true, sniper = true },
        AlwaysSilenced = {},   -- weapon classes that are always quiet, e.g. { Laser_Pistol_C = true }
        VelocityFactor = 0.92, -- suppressed bullets fly a little slower (1.0 = no change)
    },

    Takedown = {
        Enabled      = true,
        Weapons      = { knife = true, sword = true, hammer = false },
        MaxDistance  = 220,
        BehindAngle  = 110,    -- you must be at least this far behind the NPC's facing
        RequireCrouch = false,
        AllowSearchingTarget = false, -- NPCs already searching cannot be taken down
        MeleeLock    = true,   -- unaware NPCs never swing at you when you are 2 m away
        WitnessRange = 1500,
    },

    Bodies = { Enabled = true, SeeRange = 1500, CloseRange = 300, KeepSeconds = 180 },

    Allies = {
        OrderKey        = "F3",  -- cycles Follow quietly -> Hold -> Weapons free
        AutoWeaponsFree = true,  -- when you are spotted, quiet allies open fire
        FollowDistance  = 400,   -- squad walks back to its formation slot beyond this
        CatchUpDistance = 3000,  -- beyond this the game's own rescue teleports the soldier
    },

    Hud = { Messages = true, MinSecondsBetween = 2.0 },

    Debug = {
        Log        = false,  -- write SilentOps\stealth.log
        SlowHookMs = 8,      -- code slower than this is reported
        TickMs     = 200,    -- awareness tick (5 per second)
        Commands   = false,  -- testing only: SilentOps\debug_cmd.txt runs "toggle", "suppressor", "order"
    },
}

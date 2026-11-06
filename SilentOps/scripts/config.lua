--[[
  Silent Ops - realistic stealth on foot for SpaceBourne 2
  =========================================================
  USER SETTINGS. Edit with any text editor, then restart the game.
  Everything here is optional: delete a line and the default in main.lua is used.
  Distances are in cm (100 = 1 m). Angles in degrees.
]]

return {
    -- ON at every game start. ToggleKey switches stealth off / on for the session (for a
    -- situation where you want vanilla behaviour). RememberToggle = true keeps your last choice.
    -- Keys: a UE4SS key name, optionally with Shift: "F4", "Shift+F4". "" disables a key.
    -- They follow the realism set's shared key plan: only Shift as a modifier (on foot Ctrl opens
    -- the map and Alt crouches), never F1 F2 F5 F6 F8 F10 F11 F12 (squad orders, quick save, quick
    -- load, bug report, fullscreen, Steam screenshot). Plain keys stay quiet while Shift is held, so
    -- Shift+F4 does not also fit a suppressor, and Shift+F3 stays HTR's. Stealth keys work on foot only.
    Enabled        = true,
    RememberToggle = false,
    ToggleKey      = "Shift+F4",

    Detection = {
        -- How far an NPC can see you at all. "eye": read from the NPC's own eye, which HTR 0.4.2
        -- sets to its doctrine's relaxed sight (vanilla: 35 m). "config": use SightRange.
        SightSource          = "eye",
        SightRange           = 3500,
        -- A figure in plain view is made out at least this far, whatever the NPC's eye is set to
        -- (HTR's relaxed eye is 25 m: it decides when vanilla combat starts, not when you are seen).
        MinSightRange        = 4500,
        BubbleRadius        = 6000, -- NPCs farther than this are not processed
        CentralHalfAngle    = 35,   -- full attention inside this cone
        PeripheralHalfAngle = 75,   -- side vision up to here...
        PeripheralFactor    = 0.35, -- ...at this fraction
        -- Posture: crouching is not invisibility. In the open a crouched figure is made out almost
        -- as far (Stance = range) but noticed more slowly (StanceFill). What really hides you is
        -- cover: exposure = how much of your head / chest / knees the NPC can see (checked from
        -- your side with line-of-sight traces), and a wall right behind you breaking your outline.
        Stance        = { Standing = 1.0, Crouching = 0.85 },
        StanceFill    = { Standing = 1.0, Crouching = 0.55 },
        ExposureRangeMin = 0.35,  -- range factor with only one body part visible (all visible: 1.0)
        ExposurePoints = { Standing = { 70, 20, -50 }, Crouching = { 30, 0, -35 } }, -- cm above your centre
        BackdropFactor   = 0.8,   -- a wall or cover right behind you (silhouette broken)
        BackdropDistance = 150,
        -- Noticing vs identifying: in the far part of its range (beyond this fraction) the NPC sees
        -- "something" and its meter stops at IdentifyCap: it walks over to look before it is sure.
        IdentifyFraction = { Standing = 0.75, Crouching = 0.5 },
        IdentifyCap      = 0.85,
        -- ...but watched that long without a break, it is sure (seconds; twice as long past its
        -- normal range; trained NPCs are quicker).
        IdentifySeconds  = 3.0,
        IdentifySecondsCrouched = 6.0,
        -- Movement: motion draws the eye. Movement = how fast suspicion builds,
        -- MovementRange = how far away it still counts.
        Movement      = { Still = 0.5, Walk = 1.0, Run = 1.5, Sprint = 2.2 },
        MovementRange = { Still = 1.0, Walk = 1.0, Run = 1.1, Sprint = 1.2 },
        StillSpeed           = 50,   -- cm/s; slower counts as standing still
        FlashlightFactor     = 2.0,  -- flashlight on: much easier to see...
        FlashlightRangeFactor = 1.5, -- ...and from farther away
        AmbientLight         = 1.0,  -- manual darkness factor (the game gives mods no light level)
        FillNearPerSec       = 2.0,  -- suspicion gained per second when seen up close...
        FillFarPerSec        = 0.25, -- ...and at the edge of sight
        -- Standing in an NPC's view is always noticed: suspicion grows at least this fast, and
        -- up to FarNoticeFactor x its sight range it sees "someone over there" (suspicious, goes
        -- to look, but not sure enough to open fire from that far).
        StandingNoticePerSec = 0.2,
        FarNoticeFactor      = 1.6,
        DecayPerSec          = 0.12, -- suspicion lost per second out of sight
        SuspiciousAt         = 0.35, -- meter level where an NPC stops and looks
        InvestigateAt        = 0.6,  -- ...and where it walks over to check
        HuntAt               = 0.5,  -- gunfire pushing the meter past this: weapon drawn, hunting
        -- In plain view a few metres away there is nothing to notice: combat at once.
        InstantRange         = 800,  -- standing, in front of the NPC
        InstantRangeSide     = 300,  -- standing, anywhere it can see
        InstantRangeCrouched = 300,  -- crouched and moving, in front of it
        ProximityRange       = 150,  -- right next to an NPC (any side)...
        ProximitySeconds     = 1.0,  -- ...for this long, not crouched and still: noticed
        -- Alert levels (Cooper colours): Blue relaxed, Green normal attention, Yellow suspicious,
        -- Orange danger known (hunting, weapon drawn), Red combat. The level sharpens or dulls the
        -- senses (columns: Blue, Green, Yellow, Orange).
        Senses = {
            Range      = { 0.85, 1.0, 1.3, 1.7 }, -- sight range factor
            ExtraAngle = { -5, 0, 15, 30 },       -- attention cone (degrees added to both cones)
            Hearing    = { 0.85, 1.0, 1.3, 1.6 }, -- hearing range factor
            Speed      = { 0.8, 1.0, 1.4, 1.8 },  -- how fast suspicion builds
        },
        -- Resting level by training; any evidence raises it to Green for AlertedMemorySeconds, and
        -- everyone within AreaRadius of a fight stays Green for AreaSeconds.
        Baseline = { Pirate = "Blue", Militia = "Blue", Regular = "Blue", Elite = "Green" },
        AlertedMemorySeconds = 300,
        AreaRadius  = 6000,
        AreaSeconds = 300,
        SearchRadius         = 600,  -- searching NPCs check points this far around the last clue
        InvestigateStepSeconds = 6,
        SearchSeconds        = 40,   -- then they give up and go back to patrol
        LoseSeconds          = 25,   -- out of every alerted enemy's sight this long: they lose you
        Shout                = true, -- an NPC that spots you alerts mates that can see it...
        ShoutRadius          = 1500, -- ...within this distance
        SniperRangeFactor    = 1.0,  -- extra range for relaxed snipers (HTR already sets theirs)
        -- Training (same rule as HTR: raiders = pirates, Tier 1 = militia, Tier 3+ = elite):
        -- how fast they notice you (also scales the instant distances) and how long they take
        -- to raise the weapon and open fire once they have spotted you.
        Perception      = { Pirate = 0.85, Militia = 0.75, Regular = 1.0, Elite = 1.35 },
        ReactionSeconds = { Pirate = 0.5, Militia = 0.7, Regular = 0.4, Elite = 0.15 },
        -- Weapon posture: Blue / Green lowered; from Yellow it raises and aims at the suspected spot
        -- after this delay (half of it in Orange), without firing; it fires only at Red.
        RaiseSeconds    = { Pirate = 1.0, Militia = 1.4, Regular = 0.8, Elite = 0.3 },
        AffectBosses         = false, -- bosses and robot tanks always behave as in vanilla
        AffectTanks          = false,
        MaxLineOfSightPerTick = 8,    -- performance cap
    },

    Noise = {
        -- Hearing radius per weapon class (a gunshot carries far; walls halve it)...
        Shot = { pistol = 4500, smg = 6000, rifle = 6500, shotgun = 7500, dmr = 8500, sniper = 10000,
                 grenade = 12000, turret = 6500, laser = 2500, beam = 1500 },
        -- ...and how alarming one shot is when heard up close (half that at the edge). Each shot
        -- heard adds up: past Detection.HuntAt the NPC draws its weapon and hunts for you.
        ShotAlarm = { pistol = 0.5, smg = 0.6, rifle = 0.6, shotgun = 0.7, dmr = 0.75, sniper = 0.8,
                      grenade = 0.95, turret = 0.7, laser = 0.3, beam = 0.2 },
        -- Suppressed pistol: a thump heard as "something odd" (NPCs investigate), not an alarm.
        SuppressedShot = { pistol = 1200 },
        Impact         = 500,   -- around where your bullet lands
        Footsteps = { Crouch = 100, Walk = 300, Run = 700, Sprint = 1200 },
        BodyFall       = 500,
        Takedown       = 250,
        HeavyTakedown  = 600,   -- hammer
        SquadShot      = 6000,
        Pain           = 1500,  -- a wounded NPC cries out...
        Dying          = 1500,  -- ...and so does one shot dead (a silent takedown does not)
        PainMeter      = 0.7,   -- mates who hear it come to check
        TurretDeploy   = 1200,  -- setting up a turret
        GrenadeLaunch  = 1500,  -- the launcher's thump (the explosion is Shot.grenade)...
        GrenadeDistance = 1500, -- ...heard this far ahead of where you aimed...
        GrenadeDelay   = 1.5,   -- ...this many seconds after the launch
        OccludedFactor = 0.5,   -- no line of sight to the source: heard at half the distance
        HeardBump      = 0.4,   -- suspicion added by a quiet noise
        MaxOcclusionChecksPerTick = 6,
        -- Gunfire of every NPC, allies' and enemies', is noise too: a fight in the next room is heard.
        NpcShots       = true,
        -- Gunfire past the next room (no line of sight, beyond OccludedFactor of its range): enemies
        -- come to check, Regulars and Elites with the weapon drawn. false = not heard there.
        FarGunfire     = true,
    },

    Suppressor = {
        ToggleKey = "F4",       -- fit / remove a suppressor on the pistol in your hands
        Eligible  = { pistol = true }, -- weapon kinds that take one
        AlwaysSilenced = {},    -- weapon classes that are always quiet, e.g. { Laser_Pistol_C = true }
        -- A suppressor makes the pistol longer and front-heavy:
        SpreadDegrees  = 0.4,   -- extra random spread per shot
        VelocityFactor = 0.92,  -- bullets a little slower (1.0 = no change)
        FitSeconds     = 3.5,   -- screwing it on / off takes this long; the pistol cannot fire meanwhile
        ShowModel      = false, -- EXPERIMENTAL, does not work yet: a plain tube on the pistol's muzzle
                                -- (the game draws the pistol in your hand from a part not found yet)
        ModelLength    = 15,    -- cm
        ModelDiameter  = 4,     -- cm
        -- The game has no suppressed shot sound and mods cannot add one without a pak: the pistol's
        -- own shot cues play quieter and a little higher (no distant echo) while the suppressor is on.
        SoundVolume        = 0.1,  -- the near shot
        SoundDistantVolume = 0,    -- the distant echo (a suppressed pistol has none)
        SoundTailVolume    = 0.2,  -- the tail
        SoundPitch         = 1.2,
        -- The muffled thump played on top of a suppressed shot (one of the game's own impact
        -- sounds; "" = none), its volume and pitch.
        ThumpSound         = "/Game/BallisticsVFX/SFX/HitGround/Impact_Blanket_Hit_By_Metal_Pole_01.Impact_Blanket_Hit_By_Metal_Pole_01",
        ThumpVolume        = 0.6,
        ThumpPitch         = 1.4,
    },

    Takedown = {
        Enabled      = true,
        Weapons      = { knife = true, sword = true, hammer = false },
        MaxDistance  = 220,
        BehindAngle  = 110,    -- you must be at least this far behind the NPC's facing
        RequireCrouch = false,
        AllowSearchingTarget = false, -- NPCs already searching cannot be taken down
        MeleeLock    = true,   -- unaware NPCs never swing at you when you are 2 m away
    },

    Witness = {
        Range        = 1500,   -- how far a mate's death is seen
        SawKillMeter = 0.95,   -- saw a mate shot dead: weapon drawn, all but certain (hunting)
        CoverChance  = 0.5,    -- ...and this often it crouches for cover
        CallRadius   = 2500,   -- witnesses and body finders call mates this close
        CalledMeter  = 0.6,
        BodyMeter    = 0.75,   -- found a body without hearing the shot: searching, not hunting
    },

    Bodies = { Enabled = true, SeeRange = 1500, CloseRange = 300, KeepSeconds = 180 },

    Allies = {
        OrderKey        = "F3",  -- cycles Follow quietly -> Hold -> Weapons free
        AutoWeaponsFree = true,  -- when you are spotted, quiet allies open fire
        FollowDistance  = 400,   -- squad walks back to its formation slot beyond this
        CatchUpDistance = 3000,  -- beyond this the game's own rescue teleports the soldier
        SquadVisible    = true,  -- enemies can notice your quiet squad soldiers too
    },

    -- Place and noise: stations (machinery, crowds) dull hearing, dungeons are quiet. A gunshot or
    -- blast masks quiet noises (footsteps, impacts, suppressed shots) for MaskSeconds.
    Environment = { Hearing = { Station = 0.8, Dungeon = 1.1 }, MaskSeconds = 5, MaskFactor = 0.6 },

    -- Gamepad: quick presses of the flashlight button.
    --   2 presses: squad order   4 presses: stealth on / off   4 presses crouched: suppressor
    -- (an even number of presses leaves the light as it was)
    Gamepad = { Enabled = true, TapWindow = 0.45 },

    -- On-screen messages. The game's HUD beeps ("tu-tu-tu") with each one: Quiet silences it for
    -- the mod's own messages (the game's own keep it). A line stays about 5 s; the same line at
    -- most once per 30 s. Only state changes that matter (no "Hidden" line unless ShowHidden).
    Hud = { Messages = true, Quiet = true, States = true, ShowHidden = false, MinSecondsBetween = 5.0 },

    Debug = {
        Log        = false,  -- write SilentOps\stealth.log
        SlowHookMs = 8,      -- code slower than this is reported
        TickMs     = 200,    -- awareness tick (5 per second)
        Commands   = false,  -- testing only: SilentOps\debug_cmd.txt runs "toggle", "suppressor", "order"
    },
}

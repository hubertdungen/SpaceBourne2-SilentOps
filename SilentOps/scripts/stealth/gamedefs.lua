--[[
  Every SpaceBourne 2 internal name Silent Ops depends on lives in this file.
  When a game update renames something, this is the only file to fix.
  Names come from the game's Blueprints (UE 4.27, build 2026-10-26), same source as HTR.
  Used in game on 2026-10-30; anything not exercised yet is marked in the modules.
]]

local G = {}

-- Classes -------------------------------------------------------------------
G.Shooter    = "/Game/1Data/11_AI/Q1_Shooter_AI.Q1_Shooter_AI_C"           -- every on-foot NPC with a gun
G.Player     = "/Game/1Data/Q1_Character.Q1_Character_C"
G.Soldier    = "/Game/1Data/11_AI/BattleAI/Master_Soldier.Master_Soldier_C"
G.SquadShort = "Q1_GroundSquad_C"                                         -- the player's squad (FindAllOf on key press only)
G.HandWeapon = "/Game/1Data/Weapons/Hand_Weapons/Weapons/Master_Hand_Weapon.Master_Hand_Weapon_C"
G.PatrolBT   = "/Game/1Data/11_AI/1_VAL_New_BT.1_VAL_New_BT"                -- default (patrol) behaviour tree
G.KismetSystem = "/Script/Engine.Default__KismetSystemLibrary"
-- the player's perk turret (also the one Tactical Engineering deploys); loads with the player
G.PerkTurret = "/Game/IndustrialMachine2/Blueprints/Player_PerkTurret.Player_PerkTurret_C"
-- the grenade the hand weapons' launcher spawns (reference only: its actor stays at the map origin
-- while the visible grenade flies, so the mod does not follow it; see noise.lua)
G.Grenade    = "/Game/BallisticsVFX/FXSpawnerBlueprints/Projectiles/Grenade_launched.Grenade_launched_C"

-- Short class names (GetClass():GetFName()) -----------------------------------
G.PlayerClassNames    = { Q1_Character_C = true }
G.CompanionClassNames = { Q1_Companin_AI_C = true }
G.MeleeDamageTypeName = "MeleeDamageType_C"

-- Player hand weapon class -> weapon kind (noise radius, suppressor eligibility)
G.WeaponKind = {
    Bullet_Pistol_C      = "pistol",
    Laser_Pistol_C       = "laser",
    Bullet_Rifle_C       = "rifle",
    Pulse_Rifle_C        = "laser",
    SubmarineRifle_C     = "smg",
    Submachine_Laser_C   = "beam",
    MiscBeam_C           = "beam",
    Shotgun_Rifle_C      = "shotgun",
    Shotgun_Laser_C      = "laser",
    Sniper_Rifle_C       = "sniper",
    Sniper_Laser_C       = "laser",
    Hunter_BulletRifle_C = "dmr",
    Hunter_LaserRifle_C  = "laser",
}
G.MeleeKind = { KnifeType_C = "knife", KatanaType_C = "sword", HeavyType_C = "hammer" }

-- Hooked functions (post-hooks on Blueprint functions only) --------------------
G.Fn = {
    NpcStats        = G.Shooter .. ":CalculateStats",      -- once at spawn, ~0.2 s before it can see
    NpcThink        = G.Shooter .. ":CheckMeleeDistance",  -- 1 s timer on every normal shooter
    NpcReceivePoint = G.Shooter .. ":ReceivePointDamage",  -- (Damage, DamageType, HitLocation, HitNormal, HitComponent,
                                                           --  BoneName, ShotFromDirection, InstigatedBy, DamageCauser, HitInfo)
    NpcOnDead       = G.Shooter .. ":OnDeadEvent",
    WeaponShot      = G.HandWeapon .. ":SpawnProjectile",  -- (TypeName) once per shot of projectile guns (an SMG burst: once)
    WeaponBeam      = G.HandWeapon .. ":ActiveBeam1",      -- (Condition) beam weapons
    WeaponAlarm     = G.HandWeapon .. ":Alarm Enemeis",    -- (SpherePos, SphereRadius) vanilla impact alarm
    SoldierShoot    = G.Soldier .. ":BattleShoot",
    SoldierPistol   = G.Soldier .. ":PistolShot",
    -- 0.2
    WeaponTrace     = G.HandWeapon .. ":CalculateTrace",   -- (out Start Trace Point, out End Trace Point): aim of every shot
    WeaponGrenade   = G.HandWeapon .. ":GranedeLuncherPressed", -- spawns Grenade_launched_C
    TurretBeginPlay = G.PerkTurret .. ":ReceiveBeginPlay", -- a turret is deployed
    TurretShoot     = G.PerkTurret .. ":JustShoot",        -- one round (10 per second)
    -- gamepad flashlight button (the keyboard one is InpActEvt_C_ToggleLight_..._49)
    PadLight        = G.Player .. ":InpActEvt_GPC_ToggleLight_K2Node_EnhancedInputActionEvent_48",
}
-- Player bullet impacts (same seven functions HTR hooks for suppression).
-- Params: (OutProjectileObject, OutHitResult, OutAttachComponents, OutProjectileLocation, OutProjectileDirection)
G.PlayerProjectileHits = {}
for _, guid in ipairs({ "C6643AF84D4AB4342E72C7AF57715CE6", "9DAC8CC648A8DCFEE1BE598B9C94CA79", "52750BFC4CD152D861F06D9309C7FA39",
    "EFC583864537553C5A543D852264593A", "AEEB3FF9468D66E105DB4892C03A6C07", "C17D4B8141472A906D873E9C2C08887D",
    "808BFD2441DD8B73192818A6FB4C2BD5" }) do
    G.PlayerProjectileHits[#G.PlayerProjectileHits + 1] = G.HandWeapon .. ":OnProjectileHit_" .. guid
end

-- Properties (names exactly as in the Blueprints; some contain spaces or '?') --
G.P = {
    -- shooter NPC
    Ready = "Ready?", Dead = "NPCDead", AIType = "AIType", SubType = "SubType", IsBoss = "IsBoss",
    IsCompanion = "IsCompanian", CivilCompanion = "CivilCompanian?", Sniper = "IsSniper?", Raider = "Raider?",
    Tier = "Tier", CanSee = "CanSeeTheTarget", CurrentDetected = "CurrentDetected",
    EyeSight = "XVisionEye", EyeRifle = "RifleEye",
    Deaf = "AttackPlayerWhenSpawn",   -- true: CheckForFirstFocus does nothing (only other reader: spawn)
    MeleeLock = "SwordAttackOn",      -- true: CheckMeleeDistance never swings at the player
    RotationMode = "RotationMode",    -- ALS: 0 velocity direction (patrol), 2 aiming (weapon raised)
    CurrentHP = "CurrentHP", MaxHP = "MaxHP",
    -- player
    Stance = "Stance", Gait = "Gait", Speed = "Speed", MovementState = "MovementState", ViewMode = "ViewMode",
    LightOn = "LightOn?", MeleeOn = "MeleeAttackOn?", Weapon = "CurrentWeapon", MeleeWeapon = "As Master Melee Weapon",
    WhereIsPlayer = "WhereIsPlayer", -- ALS_Base, see G.Where
    -- squad soldier
    MainTimer = "MainTimer", Order = "Ground Squad Orders", GoalActor = "GoalActor", SoldierDead = "NPCDead",
    Injured = "InInjuredMode",
    -- weapon
    WeaponData = "Weapon_Data", MuzzleSpeed = "MuzzleSpeed",
    Reloading = "Reloading", -- the fire loop checks it first: true = no shots (used while fitting a suppressor)
}
-- Item data of the weapon in hand (same fields HTR's gear bonus reads)
G.Item = {
    WeaponItem = "ItemData_2_DAF7632548C524437769A9884E99CE86",
    Level      = "ItemLevel_32_36C68C8841BC84733BDEE38AC9296BF6",
    Rarity     = "ItemTier_31_620BE1F64621359F21DE589574539BBB",
    Stats      = "Stats_68_2DBCF43349587674EB3E7EBCDB207B6F",
    StatID     = "StatID_2_3D56815A44776C24FABF65BC039E7D84",
    StatValue  = "Value_5_05496F18443F5B8C8D041FA017A69B5C",
}

-- Blackboard keys (1_VAL_New_BB)
G.BB = { InCombat = "InCombat?", CanSeeTarget = "CanSeeTarget", MeleeOn = "MeleeOn?" }

-- Enums
G.AIType = { Enemy = 0, Ally = 1, Civil = 2, Natural = 3, Guard = 4 }
G.SubType = { Shooter = 0, Tank = 1, Melee = 2, Mage = 3 }
G.Stance = { Standing = 0, Crouching = 1 }
G.Gait = { Walking = 0, Running = 1, Sprinting = 2 }
G.Order = { FireAtWill = 0, Cover = 1, GetOut = 2 }        -- GroundSoldierOrders
G.Rotation = { VelocityDirection = 0, LookingDirection = 1, Aiming = 2 } -- ALS rotation modes
-- WhereIsPlayer (Tactical Engineering's dump): which kind of place you are in
G.Where = { Space = 0, PlanetSurface = 1, Dungeon = 2, Wormhole = 3, StationTrans = 4, StationSubLevel = 5 }

return G

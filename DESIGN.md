# Silent Ops: design

Status: **0.1.0 released (2026-10-30); 0.2.0 tested in game (2026-10-31, section 16.11)**. Written from the
decompiled Blueprints, then implemented and tested in the game with HTR 0.4.5: section 13.3 has
the 0.1 results, section 16 the 0.2 changes (from the user's play-test) and their results.

Product name: **Silent Ops** (UE4SS mod folder `SilentOps`; the design called it "HTR Stealth"). It is a separate mod that
works with or without Hardcore Tactical Realism (HTR). 0.1 shipped off by default; **0.2 is on by
default** (the user: whoever installs it wants it on; the key stays for situations).

---------------------------------------------------------------------------------------------

## 0. Summary

What the player gets:

* Sneaking that matters. Enemies notice you gradually (a suspicion meter) depending on distance,
  where they look, your stance, how fast you move and your flashlight.
* Noise. Unsuppressed shots are heard far away; suppressed shots, impacts, footsteps and bodies
  falling are heard close by.
* Silent takedowns with a melee weapon from behind, and quiet ranged kills with a suppressor.
* Bodies that other enemies can find.
* Squad orders: **Follow quietly**, **Hold** (stay put, hold fire) and **Weapons free**.

Feasibility at a glance:

| Feature | Feasible? | How |
|---|---|---|
| Suspicion meter before full alert | Yes | Lua takes over awareness of unaware NPCs (section 2) |
| Stance / movement / flashlight affect sight | Yes | Read from the player each tick |
| Real light and shadow | **No** | No way to sample scene lighting from Lua; only flashlight + a manual factor |
| Gunshot noise, suppressed shots | Yes | Our own noise model; vanilla's impact alarm is made harmless |
| Suppressor that changes the *sound you hear* | **Unknown** | No suppressed sound exists in the game; volume lever not found yet |
| Silent melee kill from behind | Yes | Vanilla melee swing + instant kill in a post-hook |
| Dedicated takedown animation (grab, stab) | **No** | No such animation exists for the player; would need new assets (pak mod) |
| Dragging / hiding bodies | **No** | No carry system to reuse |
| Enemies find bodies | Yes | Our own body registry |
| Squad: hold fire, follow quietly, hold, weapons free | Yes (verify) | Pause the squad's battle timer and drive the follow ourselves |
| Companions (`Q1_Companin_AI`): hold fire / weapons free | Yes (verify) | Switch their eyes off / on |
| Companions following you quietly | **No (v1)** | Vanilla companions have no follow logic at all |
| Per-enemy "?" / "!" icons | **Unknown** | No widget lever found; text messages and an optional outline instead |

---------------------------------------------------------------------------------------------

## 1. What the game does today (research)

Sources: the decompiled Blueprints in the main checkout (`code/`, `dump/`, `analysis/`, all
gitignored). Only names and numbers are quoted here, never decompiled code.

### 1.1 Sight: the XVision plugin

Every `Q1_Shooter_AI_C` (enemies, guards, companions...) has two `XVisionEye` components:

| Component | Purpose | SensingInterval | DetectPyramidExtent (distance / H / V, cm) | LostPyramidExtent |
|---|---|---|---|---|
| `XVisionEye` | sight, on the head | 0.3 s | 3500 / 6500 / 6500 | 4000 / 7000 / 7000 |
| `RifleEye` | line of fire, on the muzzle | 0.2 s | 3500 / 500 / 500 | 3600 / 450 / 450 |

`XVisionEye` also has `NearlyDetectDistance = 10500`, but no Blueprint event uses it.
HTR already rewrites these numbers per doctrine at spawn.

* **Detection is binary and instant.** When the pyramid contains the player and a line of sight
  exists, `OnTargetDetected` fires and the NPC is in combat on the spot. There is no delay and no
  meter.
* **Nothing about the player changes detection.** The player gives four fixed "vision points" to
  the plugin (`Q1_Character:GetVisionPoints`: head, right hand, left foot, above the head) through
  its `XVisionTarget` component. Stance, speed, crouching and light play no part.
* **There is no hearing.** No `PawnNoiseEmitter`, `MakeNoise` or `AIPerception` hearing is used
  by these NPCs. (The player has an unused `AIPerceptionStimuliSource`. The crew AI in
  `11Misc/1_AI/New_Q1_AI` uses another plugin, SenseSystem, but enemies never use it.)
* **Vanilla switches eyes off and on itself.** `TacticleMove` calls
  `XVisionEye:SetActive(false, false)` and `RifleEye:SetActive(false, false)` while the NPC
  moves, and `SetActive(true, false)` on arrival. Death and "bank characters" also switch them
  off. This is the lever we use to blind an NPC.

On detection of the player (`XVisionEye` `OnTargetDetected`), vanilla does, in order:
`CurrentDetected` / `LastDetectedActor` / BB `CanSeeTarget` = player; BB `InCombat?` = true;
`CanSeeTheTarget` = true; once per life: `WarnOthers()`, BB `IsFirstInteract` = true; and the
player's `UpdatePlayerInCombat()` (combat music).

### 1.2 Every way an NPC gets alerted

All of them end in `Q1_Shooter_AI:CheckForFirstFocus(actor)`, which sets focus on the actor
and runs the combat tree `1_VAL_ShootCover`:

1. **Own sight** (above). The first sighting also calls `WarnOthers()`.
2. **`WarnOthers()`**: sphere of 15 m around the NPC; every non-companion shooter in it with line
   of sight to the NPC gets `CheckForFirstFocus(player)`. Always pointed at the *player*.
3. **Being hit**: `ReceivePointDamage` calls `WarnOthers()` once and `CheckForFirstFocus(causer)`.
4. **Player bullet impacts**: the player weapon (`Master_Hand_Weapon`) calls
   `Alarm Enemeis(impact point, 2500)` on hits (at most once per 5 s per weapon; some paths only
   once per weapon). Every shooter within 25 m whose **path** to the impact is ≤ 24 m gets
   `CheckForFirstFocus(player)`; the others in the sphere only turn to face the player
   (`K2_SetFocus(player)`). Note: **firing itself makes no noise in vanilla**, only impacts do.
5. **HTR**: `alertAllies` (hit or death, doctrine radius) also calls `CheckForFirstFocus`.

`CheckForFirstFocus` returns immediately when the NPC has `IsBankCharacter`,
**`AttackPlayerWhenSpawn`** or `CivilCompanian?` set, or already has a detected target.
`AttackPlayerWhenSpawn` is read in exactly two places: at spawn (drop-ship and wave spawners set
it so the NPC charges you) and in `CheckForFirstFocus`. **Setting it to true on a live NPC makes
that NPC deaf to every alert path above**, with no other side effect found. This is the lever we
use to deafen an NPC.

### 1.3 Behaviour trees

* Patrol tree `1_VAL_New_BT`: if BB `InCombat?` is set → shoot when `CanSeeTarget`, otherwise run
  EQS `Val_FindTarget` (5 points on a 7 m circle **around the player**) and walk there. If not in
  combat → patrol: random reachable point within 10 m of `SpawnRoot`, walk, wait 2 s (±5).
* Combat tree `1_VAL_ShootCover`: cover, peeking, damage reactions, boss skills (see
  `analysis/npc_ai.md`). Every EQS query is centred on the player.
* **Nothing ever sets `InCombat?` back to false.** Once alerted, an NPC hunts the player forever and
  always knows where the player is ("search" is omniscient). Going back to calm is our job.
* `CheckMeleeDistance` runs every second on every normal shooter (HTR's "think" hook).
  **If the player is within 2 m, the NPC starts a melee attack, aware or not.** It skips that
  when its `SwordAttackOn` flag is set. That flag is otherwise set during its own melee/sword
  attacks, and the shooting loop refuses to fire while it is set (harmless on an unaware NPC,
  which should not be shooting anyway). Vanilla clears it after its attacks, so the mod
  re-asserts it every second.

### 1.4 Player state we can read

`ALS_Base` / `Q1_Character` properties: `Stance` (0 standing, 1 crouching; there is no prone),
`Gait` (0 walk, 1 run, 2 sprint), `Speed`, `IsMoving`, `MovementState` (1 = on the ground),
`RotationMode` (2 = aiming), `ViewMode` (1 = first person), `LightOn?` (flashlight),
`MeleeAttackOn?`, `CurrentWeapon`, `As Master Melee Weapon`, `SquadLocations`.
No light-level or "in shadow" value exists. The game has `IsNight`, `HideAllLights` and
`SkyLightInetnstySpace` event assets, but nothing usable as a per-position light reading.

### 1.5 Player melee

* `MeleeAttack` needs an equipped melee item, being on the ground, not reloading, enough stamina.
  **It forces third-person view** (`ForceToTP` when in first person).
* The swing spawns `KnifeType_C`, `KatanaType_C` or `HeavyType_C` (`MasterMeleeWeapon_C`). While
  the animation notify is open, a box trace 1 m in front hits each NPC once with
  `ApplyPointDamage(Base Damage, ..., DamageCauser = player, MeleeDamageType_C)`. Heavy/area
  attacks also apply radial damage.
* The victim treats it like a bullet (`ReceivePointDamage` → `WarnOthers`, `CheckForFirstFocus`,
  `CalculateDamage` ×4 / level, headshot ×3). There is **no backstab bonus, no execution**.
* The only paired "execute" animations in the game are the boss Sister executing **the player**
  (`EBP_Sister` uses the player's `ExecuteAnimStartPoint`). Nothing for player → NPC.
* NPC "gore mode" (`InGoreMode?`) is a crawling state after losing a limb, not a takedown.

### 1.6 Weapons and sound

* No suppressor, attachment or mod slot exists in item data (`S_Item_Data`, `Master_Hand_Weapon`).
  The `Attachments` array on NPCs is cosmetic meshes.
* Shot sounds are FMOD events per weapon class (`WeaponShotSound`: `HW_Pistol`, `HW_Rifle`,
  `HW_Sniper`, `HW_Shotgun`, `HW_Submarine`, laser variants...), played by `Sound()` through a
  `WeaponFXComponent` (`Play_OneShot` / `Play_OneShotLoop`) or `PlayEventAtLocation`. No
  suppressed sound exists in the dumped content.
* Per-shot Blueprint functions we can post-hook: `Master_Hand_Weapon_C:SpawnProjectile(TypeName)`
  (all projectile guns) and `ActiveBeam1` (beam weapons). Impacts: the seven
  `OnProjectileHit_<GUID>` functions HTR already hooks.

### 1.7 Allies

**Ground squad** (`Master_Soldier_C`; the player's squad is `Q1_GroundSquad_C`):

* Each soldier follows a formation slot: `SquadLocations[Crew Index]` on the player
  (`GoalActor` / `GoalRM`), walking, standing.
* A looping 1.5 s timer stored in **`MainTimer`** runs `UpdateBattle`: pick the nearest
  `'Enemy'`-tagged actor with line of sight, shoot it (`BattleShoot` burst) and walk to the slot.
  Vanilla itself pauses `MainTimer` in some states.
* Orders (`GroundSoldierOrders`): **0 FireAtWill**, **1 Cover**, **2 GetOut**, sent with
  `Q1_Character:SendOrderToSquad(order)` through the `SquadOrderTMW` global event; the game's own
  Order1/2/3 keys use it. "Cover" (`DefendMode`) still shoots (pistol) at visible targets and
  takes 40 % less damage. **There is no hold-fire order.**
* Enemies target soldiers by class (their eyes accept `Master_Soldier`).

**Companions** (`Q1_Companin_AI_C` = a `Q1_Shooter_AI` with `IsCompanian`):

* Target only non-companion live shooters, through the same XVision eyes. No follow logic: they
  patrol around their spawn point. Their first sighting calls `WarnOthers()`, which alerts
  *enemies* to the player (vanilla bug).
* Placed by levels/quests, not spawned by the player.

**The `'Enemy'` tag must not be touched**: besides the squad, it drives the player's aim assist and
red crosshair (`ALS_Base`), the chain-laser ability, allied turrets (`RTS_Turret`) and drones.

### 1.8 HTR 0.4.2: relaxed and alert enemies (the base this design builds on)

HTR 0.4.2 adds a first awareness model, and this design sits on top of it:

* In HTR's 1 Hz NPC think, each enemy reads BB `InCombat?`. **Relaxed** (false): both eyes'
  `DetectPyramidExtent.Distance` = doctrine sight × `Awareness.RelaxedSight` (0.55). **Alert**
  (true): × `Awareness.AlertSight` (1.25; snipers at least × 2). Lost extent = that + 500 / + 300.
  HTR writes the extents only when the state changes. Allies always use alert sight.
* So with HTR alone, relaxed enemies already notice you only up close, and alert ones see and
  shoot far. What HTR cannot give is everything *between* those two states: a meter, stance,
  movement, light, noise, searching, losing them. That is this mod's job.
* **Firing.** Vanilla starts an NPC's firing only when its `RifleEye` `OnTargetDetected` fires
  while `RotationMode == 2` (aiming), and `JustShoot` stops for good once it is not aiming.
  HTR 0.4.2 re-calls `StartShoot()` (guarded by a DoOnce, so safe) from its `RifleEye` hook every
  0.5 s while the NPC aims, unless it is throwing a grenade or `SwordAttackOn` is set.
* **Squad keep-up.** HTR 0.4.2 post-hooks `Master_Soldier:SetWalkSpeed(_Guarded)` (called from
  `UpdateBattle`) to make soldiers run or sprint after you (`Squad.KeepUp`).
* **Enemy markers.** HTR 0.4.2 can hide the arrow widgets the game draws above enemies
  (`HUD.EnemyArrows = false`), found with `K2_GetComponentsByClass(WidgetComponent)`.

### 1.9 The game's own keys (default preset)

From the dumped key-binding presets (`1Data/1_Keybings`): on foot **F1 / F2 / F5** are the squad
orders (`C_Order1/2/3`); shared **F6 quick save**, **F8 quick load**, **F10 bug report**; in a ship
F1–F5 are fleet orders. F12 is Steam's screenshot key. Insert, Home, End, PageUp and PageDown are
camera actions in some contexts, and many laptops lack them. On foot, Ctrl alone opens the map
and Alt crouches, so Shift is the only safe modifier. F3 and F4 are free on foot.

The realism set's shared key plan (revision 2, `key-plan.md` in the sessions' notes folder)
gives Stealth **F3**, **F4** and **Shift+F4**. HTR 0.4.4 uses F7, Shift+F7, F9, F11 (0.4.0–0.4.2
used F8, the game's quick load).

---------------------------------------------------------------------------------------------

## 2. Architecture: take over awareness while an NPC is unaware

UE4SS only gives us **post-hooks** on Blueprint functions (we run after vanilla). We cannot
stop a vanilla alert once it has started. So instead of undoing alerts, the mod switches an
unaware NPC into a state where vanilla *cannot* alert it, and runs its own perception in Lua.
When our model decides the NPC has noticed you, we switch it back and hand it to vanilla combat.

Three per-NPC switches, all vanilla flags:

| Switch | Unaware ("managed") | Aware (vanilla) |
|---|---|---|
| Eyes: `XVisionEye`, `RifleEye` `:SetActive()` | off | on |
| Deaf: `AttackPlayerWhenSpawn` | true | original value |
| Melee lock: `SwordAttackOn` | true (no melee on you within 2 m) | false |

Verified in game, with two rules learned there:

* **Deaf and melee lock only once the NPC is `Ready?`.** Vanilla reads `AttackPlayerWhenSpawn` when
  the NPC becomes ready; set earlier, it turns the NPC into a spawn attacker that charges you. So at
  spawn (`CalculateStats` hook) the mod only blinds the NPC, and deafens it on its first think.
* **Forget the target when blinding an alerted NPC.** Switching the eyes off does not fire
  `OnTargetLost`, so `CurrentDetected` and `CanSeeTheTarget` stay set; the mod clears both.

```
              hears/sees a little                   sees you clearly / shot at / shout
   CALM ───────────────────────► SUSPICIOUS ─────────────────────────────────────► ALERT
    ▲  ▲                            │   │                                   (vanilla combat:
    │  └──── meter decays ──────────┘   │ body found, loud noise,           eyes on, deaf off,
    │                                   ▼ mate hit                          CheckForFirstFocus)
    │                               SEARCHING ─────── sees you ─────────────────► │
    └──── SearchSeconds, nothing found ─┘ ◄──── LoseSeconds without contact ──────┘
```

* **CALM**: patrols (vanilla patrol tree). Managed (eyes off, deaf, melee lock).
* **SUSPICIOUS**: meter above `SuspiciousAt`. Stops and looks at the last known position
  (`AIController:K2_SetFocalPoint`). If the meter keeps rising, walks there to investigate
  (`BrainComponent:StopLogic`, `AIController:MoveToLocation`, then `RestartLogic`). Managed.
* **SEARCHING**: knows something is wrong but not where you are (heard a loud shot, found a body,
  saw a mate drop). Moves between points around the last known position, perception ×
  `AlertedPerception`. Managed.
* **ALERT**: handed to vanilla. Restore the three switches, set BB `InCombat?` = true, call
  `CheckForFirstFocus(player)`. Optionally shout: unaware NPCs within `ShoutRadius` with line of
  sight to it become ALERT too (vanilla's `WarnOthers` would do nothing on deaf NPCs, so we do it
  ourselves).
* **Losing them**: when no ALERT NPC has seen you (`CanSeeTheTarget`) for `LoseSeconds`, ALERT
  NPCs become SEARCHING: managed again (eyes off first), `StopShoot()`, BB `InCombat?` /
  `CanSeeTarget` false, `K2_ClearFocus()`, `RunBehaviorTree(1_VAL_New_BT)`. After
  `SearchSeconds` with nothing found they go back to CALM (but keep `AlertedPerception` for a
  while).

**How this maps onto HTR 0.4.2.** HTR has two states, relaxed and alert, keyed on BB `InCombat?`.
This mod splits "relaxed" into CALM / SUSPICIOUS / SEARCHING and never sets `InCombat?` there, so
HTR keeps relaxed sight on them (and its grenade logic, which needs `InCombat?`, never fires at a
searching NPC). The handover to ALERT sets `InCombat?` = true, so HTR switches the NPC to alert
sight at its next think (within 1 s) and its fire-resume logic keeps it shooting. "Losing them"
sets `InCombat?` back to false, so HTR returns it to relaxed sight. Without this mod (or with it
switched off) HTR's two-state model works on its own.

Who is managed: hostile shooters only (`AIType` 0, not companion, not civil), `Ready?` true,
`AttackPlayerWhenSpawn` originally false (wave/drop-ship spawns already know where you are and
stay vanilla). Bosses and tanks stay vanilla by default (config).

Where NPCs come from: like HTR, the mod never searches the world. NPCs register themselves from
their own 1 s `CheckMeleeDistance` hook and their damage/death hooks. The 5 Hz Lua tick works
on NPCs inside a "bubble" around the player (default 60 m) and keeps a reference to each
bubble NPC between frames, checked with `IsValid()` before every use and refreshed every
second by the NPC's own hook. **HTR's rule is to never keep a game object across frames**; this
is the one deliberate exception and must be tested (Phase 0). Fallback if it is unsafe: run the
whole model inside each NPC's 1 Hz hook (slower reactions, still playable).

Turning the mod off (key or config) releases every managed NPC: switches restored, nobody is
alerted.

---------------------------------------------------------------------------------------------

## 3. Detection model (sight)

**Sight range comes from HTR.** Each managed NPC's base range is read from its own
`XVisionEye.DetectPyramidExtent.Distance` once a second (`SightSource = "eye"`). With HTR 0.4.2
that is the doctrine's **relaxed** sight (doctrine × 0.55), so pirates, militia, regulars and elites
keep HTR's differences; without HTR it is vanilla's 35 m. `SightSource = "config"` uses
`SightRange` instead. SEARCHING NPCs (and NPCs that searched recently) look farther:
range × `SearchingRangeFactor` (2.0, a little under HTR's alert / relaxed ratio of 2.27, because they
are looking but have not found you).

Per managed NPC, every tick (`dt` ≈ 0.2 s), with `d` = distance to the player and `a` = angle
between the NPC's forward vector and the direction to the player:

```
range = eye range (or SightRange) * searching factor * sniper factor * flashlight range (1.5)
cone  = 1.0                  if a <= CentralHalfAngle      (35°)
        PeripheralFactor     if a <= PeripheralHalfAngle   (75°, factor 0.35)
        0                    otherwise (behind: only noise and proximity count)
-- how FAR you can be made out: posture and light; standing still helps only a little
effRange = range * stance * movementRange * ambient
        stance:        Standing 1.0, Crouching 0.6
        movementRange: still 0.85, walk 1.0, run 1.1, sprint 1.2
-- how FAST attention builds: movement mostly
rate  = lerp(FillNearPerSec 2.0, FillFarPerSec 0.25, d / effRange)
        * cone * stance * movement * light * ambient * perception
        movement:   still 0.5, walk 1.0, run 1.5, sprint 2.2
        light:      flashlight on 2.0
        ambient:    manual factor (config; 1.0). No light sampling exists.
        perception: pirates 0.85, militia 0.9, elites 1.15, searched recently 1.5
if cone > 0 and d < effRange and LineOfSightTo(player): meter += rate * dt
else:                                                    meter -= DecayPerSec * dt
```

* Realism tuning (from the tests): the first version halved the range of a player standing still,
  so a guard looking straight at you 16 m away never noticed you. Stillness now slows attention
  but does not hide you in the open. Measured with a relaxed HTR regular (25 m relaxed sight):
  standing still at 16 m: suspicious in ~1 s, spotted in ~3 s; crouched still at 9 m: suspicious
  ~2 s, spotted ~5 s; crouched still at 15 m: not noticed.
* Line of sight: `AController:LineOfSightTo(player)` (BlueprintCallable, returns a bool, no out
  parameters), ~0.015 ms per call in game. Called only when the cheap tests pass.
* SUSPICIOUS: the NPC stops and turns to look at what it saw or heard (focal point); above
  `InvestigateAt` it walks there.
* Instant alert: `d < InstantAlertRange` (2.5 m) inside the central cone with line of sight,
  standing or moving: ALERT now.
* Proximity: within 1.2 m behind or beside, the NPC "feels" you after `ProximitySeconds` unless
  you are crouched and still.
* Thresholds: `meter ≥ SuspiciousAt` (0.35) → SUSPICIOUS; `meter ≥ 1` → ALERT.
* SUSPICIOUS / SEARCHING NPCs look harder (`AlertedPerception`), so a second look fills faster.
* Squad members (Phase 4) are tested the same way as the player, with their own stance.
* Per-faction flavour: the range comes from HTR's doctrine (through the eye); the fill speed from
  the mod's own small `Perception` table, so the mod also works without HTR.
* Why read the eye instead of copying HTR's numbers: the mods run in separate Lua states, and the
  eye value is the one HTR actually applied (doctrine, config and future changes included).

---------------------------------------------------------------------------------------------

## 4. Noise model

Noise events are queued `{ position, radius, kind }` by hooks (O(1) work in the hook) and
resolved by the tick against the NPC registry.

| Source | Radius (default) | Hook |
|---|---|---|
| Player shot, unsuppressed | pistol 50 m, SMG 60 m, shotgun 70 m, rifle 80 m, DMR 90 m, sniper 100 m | `Master_Hand_Weapon_C:SpawnProjectile` (post) |
| Energy weapons | laser 25 m, beam 15 m (configurable; lore decides) | same / `ActiveBeam1` |
| Player shot, suppressed | pistol 12 m, SMG 15 m, rifle / DMR 25 m, sniper 35 m. Suppressors reduce, they do not silence (rifles keep their supersonic crack): heard as "something odd" (investigate), never as an alarm | same |
| Bullet impact | 5 m around the impact | the seven `OnProjectileHit_*` (post) |
| Footsteps | sprint 12 m, run 7 m, walk 3 m, crouch 1 m | tick (player speed and stance) |
| Body falling (a kill) | 5 m | `OnDeadEvent` (post) |
| Takedown | knife / sword 2.5 m, hammer 6 m | takedown code |
| Squad shot | 60 m | `Master_Soldier_C:BattleShoot` / `PistolShot` (post) |

* If the NPC has no line of sight to the noise source (we test against the player when the
  player made it), the radius is multiplied by `OccludedFactor` (0.5).
* Reaction: inside 40 % of the radius → SEARCHING (loud and near); inside the radius → SUSPICIOUS
  with the meter raised by `HeardBump` and the last known position set to the noise position.
  A loud shot heard while the NPC also sees you → ALERT.
* **Vanilla's impact alarm** (`Alarm Enemeis`) cannot hurt managed NPCs: they are deaf. Its side
  effect on NPCs beyond 24 m path (they turn to face you) is cleaned up in a post-hook of
  `Alarm Enemeis` with `K2_ClearFocus()` for managed NPCs.
* ALERT NPCs are vanilla: noise only matters before the fight.

---------------------------------------------------------------------------------------------

## 5. Takedowns and bodies

### Melee takedown

Uses the vanilla melee swing (no new animation is possible). Post-hook of
`Q1_Shooter_AI:ReceivePointDamage(Damage, DamageType, ..., DamageCauser, HitInfo)`:

```
if causer is the player and DamageType is MeleeDamageType_C
   and victim state is CALM or SUSPICIOUS (config: also SEARCHING)
   and the player is behind the victim (angle from victim forward > BehindAngle, 110°)
   and distance <= MaxDistance (2.2 m)
   and melee kind allowed (knife yes, sword yes, hammer no by default)
   [and the player is crouched, if RequireCrouch]
then  victim:ForceToDead()   -- silent: ForceToDead does not call WarnOthers
      queue a small noise (2.5 m, hammer 6 m)
```

* By the time this post-hook runs, vanilla has already called `WarnOthers()` and
  `CheckForFirstFocus` — harmless, because the victim and its neighbours are deaf.
* `ForceToDead` kills regardless of HTR's damage numbers, so hook order between the two mods
  does not matter.
* The melee lock (`SwordAttackOn`) stops the victim from swinging at you first when you get within
  2 m from behind.
* The victim cannot start firing either: its `RifleEye` is off, so vanilla never starts its fire
  loop and HTR 0.4.2's fire-resume (which runs from the `RifleEye` hook) never runs on it; that
  resume also skips NPCs with `SwordAttackOn` set.
* A failed takedown (from the front, or the victim is SEARCHING and saw you) is a normal hit:
  the victim goes ALERT.
* Melee forces third-person view in vanilla. That stays (the tactical-FPS work may change it).

### Ranged "assassination"

A suppressed shot is a normal shot with a small noise radius. Lethality is HTR's job (or vanilla's).
A victim that survives goes ALERT (it was shot). A victim that dies drops a body.

### Witnesses and bodies

* On every kill (`OnDeadEvent`, post): store a body `{ position, time, actor }` for `KeepSeconds`
  (180 s), and check witnesses: managed NPCs within `WitnessRange` (15 m) that have the victim in
  their cone and line of sight → SEARCHING, last known position = victim. If they also see you →
  ALERT.
* Managed NPCs that later see a body (cone + 15 m + line of sight to the body actor while it
  still exists) → SEARCHING. Each body is "found" once.
* Not feasible: dragging or hiding bodies.

---------------------------------------------------------------------------------------------

## 6. Silenced weapons

The game has no suppressors, so the mod adds a simple, explicit one:

* **Toggle key** (default F4): "fit / remove suppressor" on the weapon in your hands. Allowed only
  for weapon kinds in `Suppressor.Eligible` (default: bullet pistol, rifle, SMG, DMR, sniper; not
  shotguns, not energy weapons). A HUD message confirms.
* Remembered **per weapon item** in the mod's state file, keyed by the weapon class plus its item
  level, rarity and damage stat (weapons have no unique id; two identical drops would share the
  setting, which is acceptable).
* `Suppressor.AlwaysSilenced`: weapon classes that always count as quiet (empty by default).
* Optional realism cost: muzzle velocity × `VelocityFactor` (0.92) by scaling the weapon's
  `MuzzleSpeed` while fitted (re-applied after each equip, because weapon init resets it).
* The **sound you hear does not change** in v1. A lever to swap or lower the FMOD shot event is
  an open research item (Phase 5); there is no suppressed sound asset to swap to.

Alternative designs considered: an item property (no free field in `S_Item_Data`; adding a fake
stat could show up in the UI or break saves) and a pure config list (no in-game control). The
toggle plus an optional list covers both.

---------------------------------------------------------------------------------------------

## 7. Ally stealth orders

One key (default **F3**, next to the game's own squad orders on F1 / F2 / F5) cycles three
orders; a HUD message names the new one. Allies stay vanilla until you give the first order
(the first press is Follow quietly); whether stealth should apply Follow quietly by itself is
open question 5.

| Order | Squad (`Q1_GroundSquad_C`) | Companions (`Q1_Companin_AI_C`) |
|---|---|---|
| **Follow quietly** | `MainTimer` paused (no targeting, no shooting, no vanilla follow). Lua drives the follow: every second, if the soldier is more than 4 m from its formation slot, `MoveToActor(GoalActor)` at walking gait (`SetDesiredGait(0)`), crouched (`SetStance(1)`) | Eyes off + `StopShoot()` (hold fire) |
| **Hold** | `MainTimer` paused, stop moving, crouch | Eyes off + `StopShoot()` |
| **Weapons free** | `MainTimer` resumed, `SendOrderToSquad(FireAtWill)`, stand | Eyes on (vanilla) |

* **Auto weapons free**: when you are compromised (any NPC ALERT), allies on Follow quietly / Hold
  switch to Weapons free unless `AutoWeaponsFree = false`.
* **Hold fire vs HTR's fire-resume.** HTR 0.4.2 re-calls `StartShoot()` from the `RifleEye` hook
  while an NPC aims. With a companion's eyes off that hook cannot fire, and `StopShoot()` ends any
  burst already running, so hold fire holds. Squad soldiers are not shooters (`Master_Soldier`), so
  HTR's resume does not touch them; pausing `MainTimer` stops new targeting, but a `BattleShoot`
  burst already started (up to ~2 s) may finish.
* **Squad keep-up and teleport.** HTR's keep-up runs inside `UpdateBattle`, so it is paused along
  with `MainTimer`: no conflict, our follow sets the walking gait. Vanilla's own rescue (teleport
  next to you beyond 30 m) is paused too, so a soldier more than `CatchUpDistance` (30 m) from its
  slot gets one `SetWalkSpeed()` call: vanilla teleports it, then HTR's hook sets its gait.
* Squad soldiers are found with **one** `FindAllOf("Q1_GroundSquad_C")` when you press the order
  key (about 50 ms, only on a key press, like HTR's own key handlers), then kept as checked
  references. Companions come through the shooter registry.
* Squad shots are noise events (section 4). In Phase 4, squad members also count in the
  detection model so a careless squad can give you away.
* Not in v1: companions following you (they have no follow logic), and "shoot my target" /
  synchronized kills (possible later: set the soldier's `C_Target` + `CamSeeActor` and call
  `BattleShoot()`).

---------------------------------------------------------------------------------------------

## 8. HUD feedback

Feasible now:

* **Text messages** through `pawn:TMWPerkWarning(FText(text))` (HTR verified it on foot): on state
  changes only, at most one every `MinSecondsBetween` (2 s): "Stealth ON/OFF", "Suspicious (2) 60%",
  "Searching", "COMPROMISED", "Hidden again", "Suppressor fitted", "Squad: Follow quietly".
* **Combat music** is a natural "you've been spotted" cue: vanilla starts it only when an NPC
  detects you, and managed NPCs cannot.

To research (Phase 5):

* An outline on suspicious NPCs: vanilla calls `Mesh:SetRenderCustomDepth(true)` to highlight
  civilians who follow you, so a custom-depth outline may exist in the post-process. Verify, and
  whether `SetCustomDepthStencilValue` changes its colour.
* Per-enemy cue from the game's own enemy arrow markers: HTR 0.4.2 already finds and hides them
  (`HUD.EnemyArrows`). The mod could hide them on CALM enemies and show them on SUSPICIOUS /
  SEARCHING / ALERT ones. Only when HTR's `EnemyArrows` is left on, or the two mods would fight.
* A real meter widget: needs a UMG widget we can drive. A search of `1Widgets` found none.

---------------------------------------------------------------------------------------------

## 9. Working with HTR

* **Separate Lua states.** UE4SS runs each mod in its own Lua state, so the mods do not share
  tables. They cooperate through the game objects instead, which needs no coupling:
  * HTR's `alertAllies` and every vanilla alert call `CheckForFirstFocus`, which does nothing on
    deaf (managed) NPCs. HTR stays fully in charge of NPCs once they are ALERT.
  * HTR's damage model decides whether a suppressed headshot kills. Takedowns use `ForceToDead`,
    independent of HTR's numbers.
  * **Awareness (HTR 0.4.2):** the mod reads HTR's relaxed sight from each NPC's eye as its base
    range, never resizes the eyes itself, and drives HTR's relaxed / alert switch through BB
    `InCombat?` (false while managed, true on handover, false again when you lose them). Section 2
    has the mapping.
  * **Firing:** HTR's fire-resume runs from the `RifleEye` hook, which cannot fire on a managed NPC
    (eyes off) and skips `SwordAttackOn`; on handover it helps the NPC start shooting promptly.
  * HTR's suppression / panic requests set blackboard keys only read by the combat tree; on a
    patrolling NPC they do nothing.
  * **Squad:** HTR's keep-up hook runs inside the squad's `UpdateBattle`, which the quiet orders
    pause (section 7).
* Both mods post-hook some of the same functions (`CheckMeleeDistance`, `ReceivePointDamage`,
  `OnDeadEvent`, the weapon `OnProjectileHit_*`). UE4SS allows several callbacks per function;
  the costs add up and both must stay cheap.
* Optional later: a UE4SS shared variable (`ModRef:SetSharedVariable`, verify it exists in 3.0.1)
  so HTR can show "stealth active" or skip work on managed NPCs.
* **Keys** (section 1.9): stealth defaults are **F3** (ally orders), **F4** (suppressor) and
  **Shift+F4** (stealth on/off), per the shared key plan, with HTR 0.4.4's key handling:
  * keys are strings such as `"F4"` or `"Shift+F4"`; only Shift is used as a modifier;
  * F1, F2, F5, F6, F8, F10 and F12 are refused, plain or with Shift (the game reacts to them);
  * **a plain bind stays quiet while any modifier is held** (checked with the player
    controller's `IsInputKeyDown` for Left/Right Shift, Ctrl, Alt), so Shift+F4 does not also
    fit a suppressor (Shift+F3 is a spare Stealth key, on foot only);
  * the stealth keys act on foot only (in a ship F3 / F4 are fleet orders).

---------------------------------------------------------------------------------------------

## 10. Config (off by default)

`scripts/config.lua`, same style as HTR's: every line optional, defaults in `main.lua`.

* `Enabled = false` — starting state; `ToggleKey` (Shift+F4) switches it in game and it is
  remembered in `stealth_state.txt`, like HTR's toggles.
* `Detection` — `SightSource` ("eye" = HTR's relaxed sight, or "config"), `SearchingRangeFactor`,
  angles, stance/movement/light factors, fill and decay rates, thresholds, `LoseSeconds`,
  `SearchSeconds`, `AffectBosses`, `AffectTanks`, `BubbleRadius`.
* `Noise` — radii per source and weapon kind, `OccludedFactor`, reactions.
* `Suppressor` — `ToggleKey`, `Eligible`, `AlwaysSilenced`, `VelocityFactor`.
* `Takedown` — allowed melee kinds, `MaxDistance`, `BehindAngle`, `RequireCrouch`, `MeleeLock`,
  `WitnessRange`.
* `Bodies` — `Enabled`, `SeeRange`, `KeepSeconds`.
* `Allies` — `OrderKey`, `AutoWeaponsFree`, `FollowDistance`, `CatchUpDistance`.
* `Hud` — `Messages`, `MinSecondsBetween` (an `Outline` option comes with Phase 5 if the lever works).
* `Debug` — `Log`, `SlowHookMs`, `TickMs`.

---------------------------------------------------------------------------------------------

## 11. Performance risks

Rules inherited from HTR (all measured in this game): no `FindAllOf` (~50 ms) or failed
`StaticFindObject` (~37 ms) in per-shot or per-frame code; no `GetAllActorsOfClass` with a Lua
out-table (corrupts the Lua state); no hooks on native functions; time with `os.clock`.

| Risk | Mitigation |
|---|---|
| 5 Hz tick over many NPCs | Bubble (60 m, enough for a searching NPC with HTR's sight), cheap tests first (distance, cone), `LineOfSightTo` last and capped per tick (e.g. 8); budget ≤ 1 ms per tick; watchdog like HTR's `SlowHookMs` |
| Per-shot hooks (up to ~15/s) | Push one noise record and return; resolved in the tick |
| Footstep noise | Computed in the tick, not per step |
| Cross-frame object references | `IsValid()` + address check before use, refreshed every second, dropped when stale; Phase 0 test with deaths, despawns, elevators and level loads |
| Squad lookup | One `FindAllOf` only on the order key press |
| Behaviour tree asset lookup | `StaticFindObject` once it is loaded; growing retry pause like HTR |
| Two mods hooking the same functions | Keep every callback O(1) or O(bubble); profile both together |
| State switches (`SetActive`, `RunBehaviorTree`, `StopLogic`) | Only on state changes, never per tick |

Frame-time test before any release (user rule): a 10-NPC fight and a 20-NPC patrol area, with and
without HTR, compared to vanilla.

---------------------------------------------------------------------------------------------

## 12. Implementation phases

* **Phase 0 — lever tests** (a debug script, no gameplay yet). Verify each lever in section 13.0.
  Stop and rethink if the eyes switch or the deaf flag fail.
* **Phase 1 — core awareness.** Registry, bubble tick, CALM / SUSPICIOUS / ALERT, sight model,
  instant alert, handover to vanilla, release on toggle-off, HUD messages, Shift+F4 toggle,
  config, state file. Built and tested against HTR 0.4.2 (relaxed / alert sight) and without HTR.
* **Phase 2 — noise and suppressor.** Shot / impact / footstep noise, suppressor toggle and
  persistence, `Alarm Enemeis` focus cleanup, SEARCHING and investigation movement.
* **Phase 3 — takedowns, bodies, losing them.** Melee takedown and melee lock, witnesses, bodies,
  shout, LoseSeconds → SEARCHING → CALM.
* **Phase 4 — allies.** Squad orders (pause `MainTimer`, Lua follow, crouch), companion hold fire,
  auto weapons free, squad noise and squad visibility.
* **Phase 5 — polish and research.** Outline cue, suppressed sound lever, doctrine perception,
  synchronized shots, tuning, frame-time pass, docs, release.

---------------------------------------------------------------------------------------------

## 13. In-game test plan

### 13.0 Phase 0 (levers)

1. Eyes: `XVisionEye:SetActive(false,false)` + `RifleEye` on a patrolling NPC; stand in front of it
   for 10 s → no reaction. `SetActive(true,false)` → it detects you within 0.5 s.
2. Deaf: set `AttackPlayerWhenSpawn = true`; shoot a wall next to it, shoot its mate, call
   `CheckForFirstFocus(player)` from the console → nothing. Set it back → the same call alerts it.
3. Melee lock: `SwordAttackOn = true` on a calm NPC, stand behind it for 5 s → no melee swing;
   check it still walks/patrols normally.
4. `Controller:LineOfSightTo(player)`: true/false through a wall and an open door; time 100 calls.
5. Cross-frame references: keep 10 NPC references, kill some, take an elevator, load a save; every
   `IsValid()` check returns false cleanly, no crash.
6. Back to patrol: alert an NPC, then BB `InCombat?`/`CanSeeTarget` false + `StopShoot()` +
   `K2_ClearFocus()` + `RunBehaviorTree(1_VAL_New_BT)` → it patrols again. Check `CurrentDetected`
   clears (or can be cleared).
7. Silent kill: `ForceToDead()` from a `ReceivePointDamage` post-hook during a knife hit → dies, no
   mate reacts (with mates deaf).
8. Investigate: `BrainComponent:StopLogic`, `MoveToLocation`, `K2_SetFocalPoint`, `RestartLogic`.
9. Squad: pause `MainTimer` via `KismetSystemLibrary:K2_PauseTimerHandle` → squad stops shooting
   and following; `MoveToActor(GoalActor)` + `SetStance(1)` → crouch-follows; unpause → vanilla.
10. HUD: `TMWPerkWarning` repeated every 2 s does not stack badly.
11. HTR 0.4.2 link: on a relaxed enemy, read `XVisionEye.DetectPyramidExtent.Distance` → HTR's
    relaxed sight. Hand it over (`InCombat?` = true) → within 1 s the extent becomes HTR's alert
    sight and the NPC fires (HTR's fire-resume). "Lose them" (`InCombat?` = false) → relaxed again.
12. Companion hold fire: eyes off + `StopShoot()` mid-fight → it stops and does not resume
    (HTR's fire-resume cannot run without the `RifleEye`).
13. Keys: Shift+F4 toggles stealth and does **not** also fit a suppressor (the plain-key guard);
    F4 alone fits it; F3 cycles ally orders; Shift+F3 does nothing (spare) and does not cycle
    them. In a ship none of the three does anything.

### 13.1 Gameplay scenarios (after each phase)

* Sneak crouched behind a patrol to 2 m and knife it; its partner 10 m away facing away does not
  react; facing you → reacts.
* Walk standing into view at 30 m → meter rises slowly, NPC looks; crouch back behind cover →
  meter decays, NPC returns to patrol.
* Flashlight on at 30 m in a corridor → noticed much faster.
* Unsuppressed pistol shot at 30 m from a group → they search the shot position, not your exact
  position; suppressed → only NPCs within ~8 m react.
* Kill one of two guards with a suppressed headshot; the other has line of sight → SEARCHING; no
  line of sight → finds the body later.
* Get spotted, break line of sight, hide 30 s → enemies search, then return to patrol.
* Squad on Follow quietly through a patrol → no shots fired; get spotted → squad opens fire.
* Squad on Follow quietly, run 40 m ahead → the soldier left behind teleports once (vanilla
  rescue), then crouch-walks again; Weapons free → HTR's keep-up (run / sprint) is back.
* Toggle the mod off mid-mission → everyone behaves like vanilla, nobody gets stuck deaf or blind.
* Drop-ship / wave spawns → behave like vanilla (they charge you).
* Bosses → vanilla.

### 13.2 Performance (before any release)

* HTR-style profile log every 30 s: tick cost, per-hook calls and time.
* 20-NPC patrol area and a 10-NPC fight, with and without HTR: no tick over 2 ms, no hook over
  `SlowHookMs`, no stutter on shots or kills.

### 13.3 Results of the first in-game tests (2026-10-30)

Setup: HTR 0.4.5, the user's on-foot save copied to a test slot (`StealthTest`, deleted afterwards),
SB2 HOTAS off, a dev console mod, enemies spawned next to the player, squad ignoring them. The PC
was locked during the first run (key actions driven through `Debug.Commands`, results read from
logs); the real keys and the HUD text were tested in a second run with the PC unlocked.

| Test | Result |
|---|---|
| Eyes off (enemy 11 m away, facing you, 4 s) | OK: not spotted; eyes on: spotted in < 1 s, HTR switched it 25 m to 56 m |
| Deaf (`AttackPlayerWhenSpawn`) | OK after `Ready?`; wrong before it (spawn attacker), so the mod deafens on the first think |
| Melee lock | OK: no swing while set; swings once cleared |
| `LineOfSightTo` | OK: 0.015 ms per call |
| Kept references | OK: a destroyed NPC reads invalid once collected |
| Back to patrol | OK after clearing `CurrentDetected` / `CanSeeTheTarget` (the mod now does it) |
| Investigate (`StopLogic`, `MoveToLocation`, focal point, `RestartLogic`) | OK (moves slowly while aiming) |
| Squad `MainTimer` pause | OK with the handle passed as `{ Handle = number }` (the struct itself fails) |
| Ally order "Follow quietly" | OK: 4 soldiers paused and crouched; auto weapons free when spotted OK |
| Sight meter (numbers in section 3) | OK after the realism retune |
| Handover to vanilla + HTR | OK: eyes on, deaf off, HTR alert sight, the NPC charges and fires |
| Unsuppressed pistol | OK: enemies at 6 m and 11 m searched, turned and spotted you; 31 m behind cover did not hear |
| Suppressed pistol | OK: 30 m nothing; 10 m suspicious, turned, spotted you; 5 m suspicious (now also turns to look) |
| Melee takedown from behind | OK: instant kill (melee-type hit applied like the knife's: the save had no melee weapon) |
| Takedown refused (too far) | OK: normal hit, alert, its shout alerted a neighbour |
| Losing them | OK: 10 s without contact, back to searching (managed again); then it found you again at 6 m |
| Stealth off | OK: every managed NPC back to vanilla (eyes on, not deaf, no lock) |
| Real keys (second run, PC unlocked) | OK: Shift+F4 on and off; F4 fits the suppressor (saved per weapon); F3 sets "Follow quietly"; Shift+F4 and Shift+F3 do NOT trigger F4 / F3 (Shift guard) |
| HUD text | OK: "Suppressor fitted" shown on screen (right side, the game's warning style) |
| Frames, 8 enemies, 30 s | Mod on: 99 fps, median 9 ms, p99 19 ms, max 28 ms. Mod not loaded: 99 fps, median 9 ms, p99 20 ms, max 26 ms. No difference. (A first mod-on run had one 56 ms spike, not reproduced and not matched by any mod event.) |

Fixes made because of the tests: deaf after `Ready?`; forget the target when unalerting; squad timer
handle as a table; spawn hook (`CalculateStats`) so new enemies are blinded at once; realistic sight
and suppressor values; suspicious NPCs turn to look; base range not re-read for 3 s after unalert
(HTR needs up to 1 s to switch back to relaxed sight); the player is remembered even while stealth is
off (switching on no longer costs a ~50 ms lookup when NPCs are around).

Known limits seen in the tests:

* An enemy **spawned right in front of you** can still spot you: vanilla queues the sighting before
  the mod's spawn hook runs and completes it when the enemy becomes ready. Level enemies normally
  spawn out of sight, so this mostly matters for spawns next to you.
* Unalerting costs a one-off ~9 ms (the patrol behaviour tree lookup); the ally order key costs
  ~50 ms (one squad lookup), on the key press only.

Still **not tested**: a real knife swing, witnesses and found bodies, the squad's Lua follow walk, companions
(none in the save), suppressor velocity cost, the `Alarm Enemeis` focus cleanup, beam weapons.

---------------------------------------------------------------------------------------------

## 14. Open questions for the user

1. Separate mod or a module inside HTR? (Decided: separate mod, published as "Silent Ops".)
2. Suppressor: free toggle on eligible weapons, or tied to something (rarity, level, a cost)? Do
   energy weapons count as quiet (25 m) or loud?
3. Takedowns: knife only, or sword too (hammer is loud)? Require crouching?
4. Keys: F3 (ally orders), F4 (suppressor), Shift+F4 (stealth on/off), per the shared key
   plan. Gamepad combos like HTR's? (Separately for HTR: its F8 is also the game's quick load.)
5. Default ally order when stealth is on: Follow quietly? Auto weapons free when compromised?
6. Melee forces third person in vanilla. Keep it, or should the tactical-FPS work change it?
7. HUD: are text messages enough for v1, or is a visible meter a must (needs research)?
8. Difficulty: one realistic preset, or presets (Casual / Realistic / Hardcore)?

---------------------------------------------------------------------------------------------

## 15. Not feasible / out of scope (v1)

* Real light and shadow visibility (no light sampling from Lua).
* New animations: paired takedowns, body carry, prone stance.
* A suppressed shot *sound* (no asset; lever unknown).
* Companions that follow you (no vanilla follow logic to reuse).
* Cancelling a vanilla alert after it starts (post-hooks only) — avoided by design.
* Changing the `'Enemy'` tag (would break aim assist, crosshair, turrets, abilities).

---------------------------------------------------------------------------------------------

## 16. Version 0.2 (user play-test feedback, 2026-10-31)

The user played 0.1 and asked for these changes (backlog section B, plus gamepad from D).

### 16.1 On by default

`Enabled = true`, and on at **every game start**: the toggle (Shift+F4) is for a situation, not a
setting. `RememberToggle = true` keeps the last choice between sessions (0.1 behaviour). This also
ignores the `stealth=off` that 0.1 wrote into the state file whenever a key was pressed while off.

### 16.2 Detection realism

| Wish | How (awareness.lua) |
|---|---|
| Standing a few metres away: combat at once | `InstantRange` 8 m standing in the central cone, `InstantRangeSide` 3 m anywhere it can see, `InstantRangeCrouched` 3 m crouched and moving in front. Proximity: 1.5 m for 1 s (was 1.2 m, 1.5 s). All scaled by training. |
| Far away and standing: at least suspicious | Standing in view always fills at least `StandingNoticePerSec` (0.2/s, about 2 s to suspicious). Beyond the sight range, up to `FarNoticeFactor` (1.6x), a standing figure in the central cone makes the NPC suspicious and walk over, but the meter is capped at `InvestigateAt` there (not sure enough to open fire from that far). `MovementRange.Still` is now 1.0: standing still in the open is seen at the full range. |
| Crouched depends on distance and light | Unchanged: crouched shrinks the range (0.6) and the fill; the flashlight multiplies both. |
| A gunshot is much more suspicious than a far silhouette, and grows | Each shot heard adds `ShotAlarm[class]` x (0.5..1 by distance) to the meter. Past `HuntAt` (0.5) the NPC hunts (16.3); more shots keep adding. Hearing alone caps at 0.99: it never knows exactly where you are. |
| Suspicion sharpens sight (range / FOV) and hearing | Three levels: calm, wary (suspicious, or alerted in the last 120 s), searching / hunting. `Senses`: range x1 / 1.4 / 1.8, both cones +0 / 15 / 30 degrees, hearing x1 / 1.3 / 1.6, fill speed x1 / 1.4 / 1.8. |
| Trained troops notice faster and draw / shoot faster | Same classification as HTR's doctrines. `Perception` (fill speed and instant distances): militia 0.75, pirates 0.85, regulars 1.0, elites 1.35. `ReactionSeconds` once spotted (it turns to you and raises its weapon, then combat starts): elites 0.15 s, regulars 0.4, pirates 0.5, militia 0.7. After that HTR's doctrines (settle time, spread) decide how fast and well they shoot. |

### 16.3 Gunshots by weapon class, and hunting

Radius / alarm per shot: pistol 45 m / 0.5, SMG 60 m / 0.6, rifle 65 m / 0.6, shotgun 75 m / 0.7,
DMR 85 m / 0.75, sniper 100 m / 0.8, grenade 120 m / 0.95; turret 65 m / 0.7; energy weapons
25 m / 0.3, beams 15 m / 0.2. Walls still halve the radius of your own shots.

**Hunting**: an NPC that heard enough gunfire (or saw a mate shot dead, or lost you after a fight)
draws its weapon (ALS aiming pose, `SetRotationMode(2)`, what vanilla does on spotting a target),
searches towards the sound with sharpened senses, and **the first movement it sees draws fire**
(instant, standing or moving; crouched only within half its range). Standing still or crouched
still: it still fills fast. The eyes stay off while it hunts, so it cannot fire at nothing (HTR
resumes fire only from the eye hook). When the search ends it lowers its weapon and patrols again.

### 16.4 Witnesses

| Event | Reaction |
|---|---|
| Sees a mate shot dead | Hunts (meter 0.95), calls mates within 25 m (they hunt too, meter 0.6), and half the time crouches for cover where it stands (vanilla's cover routine needs a target). It does not know where the shooter is. |
| Sees a mate knifed (silent takedown) | The killer is right there: if it can see you, combat. Otherwise as above. |
| Finds a body without having heard anything | Searches (meter 0.75, sharpened senses) and calls mates within 25 m to search too. Not a full alert. |
| Near a wounded mate | A shooter hit by gunfire cries out (15 m); one shot dead too. Mates who hear it come to check. A silent takedown makes no cry. |

### 16.5 Suppressors: pistols only

`Suppressor.Eligible = { pistol = true }` (0.1 allowed SMGs, rifles, DMRs and snipers; those saved
suppressors now do nothing). A suppressor makes the pistol longer and front-heavy:
`SpreadDegrees` 0.4 extra random spread per shot (post-hook of `CalculateTrace`, the per-shot aim
trace, writing its `End Trace Point` out parameter) and `VelocityFactor` 0.92 (re-applied per shot,
because the weapon resets `MuzzleSpeed` when equipped).

Sound: the game plays shots through FMOD events (`WeaponShotSound`) or the weapon FX component
(`Play_OneShot`); UE4SS cannot play an external sound file without a pak asset. See 16.9 for what
was found in game. A 3D suppressor model needs a pak: skipped.

### 16.6 Light (research only)

The dumped Blueprints have no light level and no time-of-day value; sampling the scene's brightness
would need a scene capture and a render-target read every few frames (costly). Dropped:
`AmbientLight` stays a manual factor.

### 16.7 Turrets

Post-hooks on the player's perk turret (`Player_PerkTurret_C`, also the turret Tactical Engineering
deploys): `ReceiveBeginPlay` = deploying makes a 12 m noise; `JustShoot` (10 rounds a second) = a
loud 65 m noise every half second (alarm 0.7, hunting).

Shared noise channel of the set (agreed with Tactical Engineering): TE publishes
`ModRef:SetSharedVariable("SB2R_Noise", "id,x,y,z,radius_cm,kind,time;...")` with kinds `deploy`,
`pack`, `turret_fire`. Silent Ops reads it once a second and uses only `pack` (the hooks above
already hear deploying and firing, also without TE). Silent Ops publishes
`SetSharedVariable("SilentOps_On", bool)`; while it is true TE skips its own vanilla alert.

### 16.8 Grenades

`Master_Hand_Weapon:GranedeLuncherPressed` (the launcher, which spawns `Grenade_launched_C`): the
launch is a 15 m thump, and 1.5 s later the blast (120 m, alarm 0.95) is heard 15 m ahead of where
you aimed. The grenade itself cannot be followed: in game its actor stays at the map origin while
the visible grenade flies (UE4SS `NotifyOnNewObject` saw it, but its location never changed).

### 16.9 Gamepad (backlog D)

Quick presses of the **flashlight** button (`InpActEvt_GPC_ToggleLight`, the gamepad-only light
action; the keyboard light key is another action): **2 presses** = squad order, **4 presses** =
stealth on / off, **4 presses crouched** = suppressor. An even number of presses leaves the light as
it was (2 presses is a short flash, like a signal). Resolved 0.45 s after the last press. No clash
with HTR's 4 presses of "switch camera".

### 16.10 HUD

Each on-screen message plays the game's "can't do that" alarm (`GUI_Cant`, "tu-tu-tu"), and with
stealth on all the time 0.1 was too chatty. 0.2:

* `Hud.Quiet` (on): the same trick as HTR 0.4.6, the `GUI_Cant` SoundWave's `Volume` is set to 0 for
  2 s around the mod's own messages; the game's own warnings keep their sound. Both mods may mute
  it, so the real volume is shared through `ModRef` `SB2R_CantVolume` and a volume of 0 is never
  taken as the real one (the alarm can never be left silent). Verified in game with HTR 0.4.7:
  2.0 -> 0 during a message -> 2.0.
* Shows only "Someone is suspicious", "Enemies searching", "Enemies on alert - weapons drawn",
  "COMPROMISED", "Lost them" and key presses, at most one every 4 s; no "Hidden" line and no
  percentages (`Hud.ShowHidden` brings "Hidden" back).

### 16.11 Results of the 0.2 in-game tests (2026-10-31)

Setup: HTR 0.4.7, the user's on-foot save copied to a test slot (deleted afterwards), SB2 HOTAS
off, the user's Silent Ops 0.1 parked (its `enabled.txt` renamed: UE4SS starts any folder that has
one, even when mods.txt says 0), a dev console, enemies spawned near the player, squad ignoring
them. The PC was locked (no real input); actions were driven from the console. Only the
ahead-left direction of the test spot has open ground (elsewhere spawned enemies fell off).

| Test | Result |
|---|---|
| Load | OK: 0.2.0 starts with stealth on, all 21 hooks registered, no errors |
| Standing still, 6 m in front | OK: "in plain view", combat after the regular's 0.4 s reaction |
| Standing still, 20 m | OK: suspicious after ~2 s, combat after ~3 s |
| Standing still, 32 m (beyond the 25 m relaxed sight) | OK: suspicious (far notice); its sharpened sight then brought you in range: combat after ~5 s |
| Crouched still, 15 m | OK: not seen |
| Unsuppressed pistol, enemy 16 m away facing away | OK: 1st shot suspicious (0.41), 2nd shot hunting; it turned towards the sound, saw you standing, combat |
| Same at 32 m, you crouched, 3 shots | OK: suspicious after the 2nd, hunting after the 3rd: weapon drawn (aiming pose), eyes still off, no firing; walked towards the sound, saw you crouched at 24 m, combat at 21 m |
| Suppressed pistol, enemy 9 m away | OK: "something odd" only (meter 0.15), no hunting |
| Witness sees a mate shot dead | OK: hunts (0.95, weapon drawn) and calls; the called mate hunts too; both hear the dying cry; the mate then spotted you |
| Silent takedown, then a mate finds the body | OK: no cry; "found a body" (search 0.75), calls a mate (search, weapon not drawn); then saw you next to the body |
| Suppressor spread | OK: without 0.00° mean; with 0.25° mean, 0.35° max (0.4° cone); bullet speed 1.06 -> 0.975 (x0.92). Writing the `CalculateTrace` out parameter works |
| Turret | OK: deploying not heard at 29 m (12 m radius); firing heard at 27 m: hunting, then combat |
| Grenade | OK after a fix: launcher thump heard at 18 m; blast logged 1.5 s later 15 m ahead of the aim (first version followed the grenade actor, which stays at the map origin) |
| Gamepad (input event called from the console) | OK: 2 presses = squad order; 4 crouched = suppressor removed; 4 = stealth off, 4 = on; the light ends as it was |
| Quiet HUD | OK: `GUI_Cant` volume 2.0 -> 0 during a message -> 2.0 |
| Frames, 8 enemies, 34 s | Mod on: 53 fps, median 19 ms, p99 32 ms, max 47 ms, no spikes. Mod not loaded: 54 fps, median 19 ms, p99 32 ms, max 39 ms. No difference (the max is the game creating its warning box once). |

Seen in the tests:

* The first on-screen message of a session costs ~23 ms once (the game creates its warning box).
* The ally order key costs ~70 ms (one squad lookup), on the press only (as in 0.1).
* One **hang** during a first frames run: 3 enemies firing at a god-mode player, the console's frame
  recorder hooked on every character tick; all game threads waiting, no crash dump, last log lines
  normal. Not repeated in the second run. 0.1's tests had one similar unexplained hang with the same
  console setup. No evidence that Silent Ops causes it.

After the tests, two guards were added (HTR's finding: after a load an old pointer's address can
be reused by another object): the PlayerController is never kept, and a kept player pointer that
is no longer a `Q1_Character_C` is dropped. Smoke test of that final build (05:48): loads without
errors, stealth off / on, ally order, "in plain view" at 6 m.

Not tested: real gamepad and keyboard presses (PC locked; the 0.1 keys are unchanged), witness
cover crouch (50% chance, not rolled), the `pack` channel event (TE not installed), companions,
the squad's quiet follow walk over distance.

---------------------------------------------------------------------------------------------

## 17. Version 0.3: awareness model (user request, 2026-10-31)

Goal: crouching is not invisibility, suspicion is a spectrum that rises and decays with evidence,
and the place, the NPC's training and what it already knows all shape what it notices.

### 17.1 Concepts

* **Situation awareness (SA)**: what reaches the NPC. Sight = range x field of view x what is
  exposed of you (17.3); hearing = radius x environment (17.4).
* **Perception**: how fast evidence turns into suspicion and how sure it gets. Training (militia <
  regular < elite, as HTR's doctrines), distance (far = "something", near = "an enemy").
* **Alert level** (Cooper colours), per NPC, the result of both:

| Level | Meaning | Mod state | Senses (range / extra FOV / hearing / speed) |
|---|---|---|---|
| Blue | relaxed | calm, baseline of militia, pirates, regulars | 0.85 / -5 / 0.85 / 0.8 |
| Green | normal attention | calm, baseline of elites; floor for 120 s after any evidence, and for everyone near a fight in the last 5 min | 1.0 / 0 / 1.0 / 1.0 |
| Yellow | suspicious, uneasy | meter >= 0.35: looks, then walks over | 1.3 / 15 / 1.3 / 1.4 |
| Orange | danger known, not who or where | hunting (gunfire, a mate shot dead, lost contact): weapon drawn, searches | 1.7 / 30 / 1.6 / 1.8 |
| Red | combat | handed to vanilla + HTR | (vanilla / HTR alert sight) |

Levels only move with evidence: Red -> Orange when it loses you, Orange -> Yellow when the search
ends, Yellow -> Green as the meter decays, Green -> Blue after 5 min of nothing (baseline-Blue NPCs).
Never "saw something, full alert" except in plain view a few metres away.

### 17.2 Ownership with HTR and Tactical Engineering

* Silent Ops owns the levels and perception of unaware NPCs. HTR owns sight ranges (its relaxed /
  alert eye distance, read as the base range) and doctrines (combat behaviour after Red).
* Red = `InCombat?` = HTR's alert sight, as before. Silent Ops publishes the highest level among
  enemies near you as `ModRef` `SB2R_AlertLevel` (0 Blue .. 4 Red) for other mods (HTR, TE, HUDs).
* Tactical Engineering turret sensors: a simpler version on their side (range x exposure x noise).

### 17.3 Exposure (the light proxy)

The game gives no light level, so what decides "clearly seen" is how much of you is exposed:

* **Body points**: from your controller, `LineOfSightTo(npc, point)` from your head, chest and knees
  (the same 0.015 ms check, viewed from your side: you can see its eyes = it can see that part).
  Exposure = visible points / 3. 0 = hidden.
* **Backdrop**: the same check from a point 1.5 m behind you (away from the NPC). Blocked = a wall
  or cover right behind you breaks your silhouette (x0.8); open = skyline (x1.0).
* **Flashlight**: x2 fill, x1.5 range (as before).
* Recomputed every 0.6 s per NPC in range, at most 8 NPCs per tick (4 checks each).

Exposure scales the effective range and the fill rate. So crouched behind a low wall (head only,
1/3) is hard to see; crouched in the open (3/3) is seen.

### 17.4 Crouching and identification

* Crouched in the open: range x0.85 (was x0.6), fill x0.55. Exposure does the rest.
* **Noticing vs identifying**: beyond `IdentifyFraction` of the effective range (standing 0.75,
  crouched 0.5) the NPC sees "something" and the meter caps at 0.85 (yellow, walks over). Closer,
  or still moving while it closes in, it fills on to Red.
* Expected: an NPC facing you, you crouched and moving in the open at ~15 m: yellow in ~1-2 s, walks
  over, combat when it gets close or you keep moving in its view. Crouched still and partly covered:
  unseen beyond a few metres.

### 17.5 Environment

* Place (`WhereIsPlayer`): stations (machinery, crowds) hearing x0.8; dungeons (quiet, empty) x1.1;
  planet surface x1.0.
* Recent loud noise masks quiet ones: for 5 s after a gunshot or blast, footsteps, impacts and
  suppressed shots are heard at x0.6.
* A fight raises the floor of everyone within 60 m to Green for 5 min.

### 17.6 Allies

* Enemies also notice your squad soldiers (one soldier per NPC per tick, round robin): crouched
  quiet soldiers in the open can give you away. Seen -> the NPC hands over to combat against the
  soldier (vanilla `CheckForFirstFocus(soldier)`), and the squad goes weapons free.
* Your squad's own awareness stays the order system (quiet orders hold fire until Red).

### 17.7 Cost budget

Per tick (5 Hz): at most 8 NPCs x 4 exposure checks every third tick, plus the existing sight check
and one squad check per NPC. Expected < 0.5 ms per tick. Measured in 17.8.

### 17.8 Weapon posture

The level also decides the weapon (user, 2026-10-31): Blue / Green lowered; from Yellow into
Orange the NPC raises it and aims at the suspected spot or sound (ALS aiming pose,
`SetRotationMode(2)`, plus the focal point it already looks at), without firing; Red fires.
Raising takes `RaiseSeconds` by training (elite 0.3 s, regular 0.8, pirate 1.0, militia 1.4; half
in Orange). No fire before Red: the eyes stay off while the mod manages the NPC, and HTR resumes
fire only from the eye hook (checked in its code and in the 0.2 tests).

### 17.9 Suppressor: fitting, sound, model (user requests, 2026-10-31)

* **Fitting** takes `FitSeconds` (3.5 s): the weapon's own `Reloading` flag (the fire loop checks
  it first) blocks shots meanwhile; HUD "Fitting suppressor... / Suppressor fitted". Verified.
* **Sound**: the pistol plays through its weapon SFX component (`WeaponSFXCompoment_III`, child
  `3_07_PISTOL_SFXComponent_C`). It has `cues_OneShot_Suppressor` slots, but they are empty in
  this game. While the suppressor is on, the mod plays the pistol's own cues quieter and higher:
  near shot x0.3, distant echo x0, tail x0.2, pitch x1.2. Verified in game: the values change, and
  the user hears a slight difference that does not sound like a suppressor. A real suppressed
  sound needs a new sound asset, so a pak.
* **Model**: the engine cylinder is cooked into SB2 and attaches. But the weapon actor's
  `EBBarrel` / `SkeletalMesh` are not the pistol you see (a tube attached there lay on the floor),
  and the character's `PistolSM` stays hidden while the pistol is in hand. Which component draws
  the hand pistol is still unknown, so `ShowModel` is off. Next step: find the visible weapon mesh
  (or a pak with a real model).

### 17.10 Results of the 0.3 in-game test (2026-10-31, HTR 0.4.8)

| Test | Result |
|---|---|
| Load | OK, all hooks, no errors. The 2 crashes in this run came from console research scripts (a full property dump; a scan of all mesh components), not from the mod |
| Exposure in the open | 1.00 (3/3 body points) for every NPC with a clear view |
| Crouched still, 15 m, Blue regular | Blue -> Green -> Yellow in ~2-3 s, weapon raised (drawn), walks over; combat only once close enough to identify (~13 m) |
| Crouched, 15 m, near an earlier fight (Green floor) | Yellow in ~1 s, combat when it closed in |
| Weapon posture | drawn in Yellow ~0.8 s after suspicious (regular), no shots before Red |
| Alert level shared | `SB2R_AlertLevel` 0 / 4 read from another mod |
| Suppressor fitting | 3.5 s, `Reloading` true meanwhile, then fitted |
| Suppressed sound | cue values changed; user: slight difference, not a suppressor sound |
| Visible suppressor | not visible on the hand pistol (see 17.9): off |
| Frames, 8 enemies, 34 s | 98 fps, median 9 ms, p99 21 ms, max 75 ms (0.1 at the same spot: 99 fps, p99 19-20 ms). No measurable cost |

Not tested: partial exposure / backdrop (the test spot has no low cover), the squad being seen
(no quiet order active), environment hearing in stations / dungeons, crouched walking (the test
push made the player stand).

### 17.11 0.3.1 (2026-11-01)

* Bug (user, full set: HTR 0.4.9, Ammo Discipline, Ground Waypoints, Get Out of the Way, Faction
  Power, Tactical Engineering 0.2.1, Gear Without Levels, Split Controls): standing enemies 10-30 m
  away never saw you. Cause, seen in the test: the exposure traces from the player's side returned
  0.00 at 15 m while the NPC's own `LineOfSightTo` (centre) was true; 0.3.0 then counted you as
  hidden. Fix: the NPC-side check (`bAlternateChecks` = also head / sides) runs too, and a visible
  centre means exposure >= 0.67. A one-time warning in UE4SS.log reports blocked traces.
* Visible suppressor: cylinders attached to every candidate (weapon mesh "Muzzle" socket, weapon
  root, HeldObjectRoot, CurrentWeapon; all within 1 cm of the hand bone) do not render on the hand
  pistol; one attached to `EBBarrel` (not in the hand) did. Not feasible without more research or
  a pak; `ShowModel` stays off.
* Frames, full set, 8 enemies: 91 fps, median 9 ms, p99 21 ms, max 31 ms.

### 17.12 0.3.4 (2026-11-06, not tested in game yet)

* **Plain-view detection.** `sightRate` used `rangeOf(npc)` (the eye's `DetectPyramidExtent`) as
  the base range. HTR sets that to 25 m while relaxed, and `Senses.Range` (Blue 0.85), exposure and
  backdrop shortened it to about 13-17 m. Standing at 20-30 m you fell in the "beyond range" branch
  (meter capped at `InvestigateAt`); crouched beyond the base range you were not seen at all.
  The base is now at least `MinSightRange` (45 m).
* **Caps lift.** A capped meter (`IdentifyCap` past `IdentifyFraction`, `InvestigateAt` beyond
  range) used to stay at the cap while the NPC stood and watched. `e.capT` counts unbroken sight
  weighted by the sight rate (`dt * rate / IdentifyRefRate`, at most x4 per tick), so light,
  movement, stance, exposure, cone and the NPC's perception all count. The cap lifts at
  `IdentifySeconds` (3 s at the reference rate 0.3, about a figure standing still in the far part
  of the range), x2 beyond range. Losing sight resets it. Measured in game (test 14, 2026-11-06):
  standing still at 25 m the rate is 0.87, inside the identify range, so no cap: calm ->
  suspicious -> alert in about 2 s. Crouched still at 20-26 m it is 0.05-0.07: suspicious after
  about 5 s; the cap then lifts after about 15 s of unbroken staring (the meter needs that long to
  reach the cap anyway).
* **Suppressor sound.** The game has no suppressed shot sound. The near shot cue now plays at 0.1
  and `Impact_Blanket_Hit_By_Metal_Pole_01` (SoundWave, 0.38 s) plays as a 2D sound at pitch 1.4.
* **Visible suppressor, research.** `addModel` attaches the cylinder to the character's `PistolSM`.
  In `Q1_Character`, `PistolSM` (and `Slot_1_SKM`, `Slot_2_SKM`) are the holstered weapons, hidden
  while the weapon is drawn (`RefreshAllWeapons`), so a cylinder on them is hidden too. The weapon in
  your hand is the `CurrentWeapon` child actor (`Master_Hand_Weapon`, whose only mesh component is
  `SkeletalMesh`). Next test: `dev/q_handmesh.lua` (calc kit) with the pistol drawn lists every mesh
  component near the right hand, with visibility and mesh asset. Tried 2026-11-06: that scan
  crashed the game (access violation on the game thread, inside a call made from Lua) before the
  pistol was drawn, so it needs a narrower probe: read `CurrentWeapon.ChildActor.SkeletalMesh` alone,
  with the pistol drawn by hand.
  Narrow probe, 2026-11-06 (test 15, `dev/q_hand2.lua`: property reads only, no crash). The user
  drew by hand; the key gave the shotgun (`Shotgun_Laser_C`, slot 2), not the pistol, but the
  layout is the same `Master_Hand_Weapon` one:
  - `CurrentWeapon` is a ChildActorComponent added at draw time (`NODE_AddChildActorComponent-0`)
    and attached to `HeldObjectRoot`, which sits on the body mesh at socket `VB RHS_ik_hand_gun`.
    On holster it is gone (`CurrentWeapon` = none): the weapon actor is destroyed on every
    holster or swap and made again on the next draw.
  - The gun you see in hand is the weapon actor's `SkeletalMesh` (visible, asset
    `SK_Sci-fi_Shotgun`, at the child actor's origin). The holster copy (`Slot_2_SKM`) turns
    invisible while it is drawn and visible again on holster. `PistolSM` stays on the hip.
  - `EBBarrel` (hidden marker) is a child of that `SkeletalMesh` at the barrel tip (shotgun:
    relative 52, 0, 11 cm).
  - The holster mounts `Pistol` and `Rifle-Attach-Root_` are hidden static meshes that use the
    engine `Cylinder`, as our model does.
  So the 0.3.1 "tube on the floor" fits: the cylinder was the player's component, attached to a
  weapon actor that the game destroys on holster, so it fell off and stayed in the world. Next
  try: add the cylinder to the weapon actor itself (dies with it), attached to its `SkeletalMesh`
  at the `Muzzle` socket if the mesh has one, else at `EBBarrel`'s place; add it again on each
  draw (new `CurrentWeapon.ChildActor`). Needs a look in game with the pistol drawn.

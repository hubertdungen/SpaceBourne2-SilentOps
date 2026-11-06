# Changelog

## 0.3.4 — 2026-11-06

- **Fix: enemies did not see you in plain view at 20–30 m.** Silent Ops took the NPC's sight
  range from its eye, which HTR sets to 25 m while relaxed, and then shortened it further. Standing
  in the open at 25 m you were often out of range, and crouched you were not seen at all. Sight now
  reaches at least 45 m in plain view (`Detection.MinSightRange`).
- **Fix: the awareness meter could rise and stop for good.** Seen from far, an NPC only got to
  "someone is over there" and stayed there. Now, watched without a break for about 3 s (6 s
  crouched, twice as long beyond its normal range; trained NPCs quicker), it is sure and reacts.
  Out of sight, awareness still fades.
- **Suppressed pistol sound.** The game has no suppressed sound, so the pistol's own shot now plays
  very quietly with a short muffled thump on top (one of the game's own sounds;
  `Suppressor.ThumpSound`, `ThumpVolume`, `ThumpPitch`).
- Not tested in game yet (the test launch could not start overnight).

## 0.3.3 — 2026-11-06

- **Enemies hear a fight in the next room.** Before, only your shots, your squad's and turrets' were
  noise, so enemies walked on while allies fought them from the next room. Now every NPC's gunfire
  counts: an unsuppressed fight in the next room alerts them at once.
- **Two rooms away** (walls in between, far half of the range): they get suspicious and come to
  check. Regulars and elites come with the weapon drawn, pirates and militia without.
- Trained enemies react sooner to what they hear (Detection.Perception).
- New settings: `Noise.NpcShots`, `Noise.FarGunfire`.
- Tested in game with HTR 0.4.12: unaware enemies heard an NPC's rifle at 21 and 24 m and searched;
  no measurable cost. The through-walls case was not exercised yet.

## 0.3.2 — 2026-11-06

- **No more "tu-tu-tu".** 0.3.0 muted the wrong sound: the beep comes from the game's HUD on every
  line. Silent Ops' lines ("Enemies searching", "Someone is suspicious") are now silent, stay about
  5 seconds so you can read them, and the same line shows at most once in 30 seconds. The game's
  own warnings keep their beep.
- Tested in game through Ammo Discipline 0.1.2, which uses the same line code: no beep, the line
  still on screen after 3 s, a repeat skipped.

## 0.3.1 — 2026-11-01

- **Fix: enemies did not see you standing in front of them** (reported in play with the full
  realism set). In 0.3.0 the cover check ran from your side only, and in some setups those
  checks were blocked right around you, so you counted as hidden. Now the enemy's own line of
  sight to you counts too: if it can see you, you are at least two-thirds exposed. Tested in game
  with HTR 0.4.9 and the rest of the set: seen at 15 m (yellow, then combat in ~2 s), no frame cost.
- The visible suppressor is still off. The game does not draw extra parts on the pistol in your
  hand, so it would need a pak.

## 0.3.0 — 2026-10-31

A deeper awareness model (DESIGN.md, section 17).

- **Alert levels**: every enemy is Blue (relaxed), Green (normal attention), Yellow
  (suspicious), Orange (danger known, weapon drawn) or Red (combat). They rise and fall with
  evidence; never straight from "saw something" to combat, except in plain view up close.
  - The level sharpens or dulls sight, attention and hearing.
  - Militia, pirates and regulars rest at Blue, elites at Green.
  - Enemies stay Green for minutes after anything odd, and near a recent fight.
- **Crouching is not invisibility**. Crouched and moving in the open, an enemy facing you at
  ~15 m finds it odd (Yellow) and walks over. Keep moving or let it get close and it ends in
  combat.
- **Cover**: what hides you is how much of you is exposed. Line-of-sight checks from your head,
  chest and knees (the game gives mods no light level, so this stands in for it). A wall right
  behind you breaks your outline.
- **Noticing vs identifying**: far away an enemy sees "something" and walks over to look before
  it is sure.
- **Environment**: stations (machinery, crowds) dull hearing, dungeons are quiet. A gunshot
  masks footsteps and suppressed shots for a few seconds.
- **Your squad can give you away**: enemies notice quiet squad soldiers in the open too.
- Other mods can read the highest alert level near you (`SB2R_AlertLevel`, 0 Blue .. 4 Red).
- **Weapon posture**: from Yellow an enemy raises its weapon and aims where it suspects you,
  without firing; it fires only at Red. Elites raise it fast (0.3 s), militia slowly (1.4 s).
- **Fitting a suppressor takes 3.5 s**: the pistol cannot fire meanwhile, and the screen says
  so.
- **Suppressed shot sound**: the pistol's own shot plays quieter and a little higher, with no
  distant echo. The difference is slight. The game has no suppressed sound, and a real one
  would need a pak.
- **Visible suppressor**: not working yet (off). The engine's tube attaches, but not to the
  pistol you see in your hand.
- F11 (fullscreen) is refused as a key too.

## 0.2.0 — 2026-10-31

Changes from the first play-test.

- **On by default**, at every game start. Shift+F4 switches it off for the session
  (`RememberToggle = true` keeps your last choice, as 0.1 did).
- **Detection realism**:
  - Standing a few metres in front of an enemy is combat at once: 8 m in front, 3 m at the
    side, 3 m crouched and moving.
  - Standing in an enemy's view far away makes it suspicious at least. It walks over to look,
    but won't open fire from that far.
  - Suspicion sharpens the senses: farther sight, wider attention, better hearing, faster
    noticing.
  - Training matters. Militia notice you slower and hesitate before firing; elites notice
    faster and react almost at once (same classes as HTR's doctrines).
- **Gunshots by weapon class**: pistol < SMG / rifle < shotgun < DMR < sniper < grenade, both
  the hearing radius and how alarming each shot is. Shots add up. Enemies who heard enough
  draw their weapons, search towards the sound and react to the first movement they see.
- **Witnesses**:
  - Seeing a mate shot dead: the witness draws its weapon and calls the others. It may crouch
    for cover, without knowing where the shooter is.
  - Seeing a mate knifed in front of it: combat, if it can see you.
  - Finding a body without hearing the shot: it searches and calls for help (not a full
    alert).
  - Wounded or dying enemies cry out, and mates nearby come to check. A silent takedown makes
    no cry.
- **Suppressors: pistols only**. A suppressor adds a little spread (+0.4°) and slows the bullet
  slightly (longer, front-heavy pistol). Suppressors that 0.1 saved on other weapons are
  ignored.
- **Turrets**: setting one up makes noise, and a firing turret is loud (65 m). Packing a turret
  up is heard too when Tactical Engineering is installed (the set's shared noise channel).
  Silent Ops tells other mods whether it is on.
- **Grenades**: the blast is heard 120 m away.
- **Gamepad**: quick presses of the flashlight button. 2 = squad order, 4 = stealth on/off,
  4 while crouched = suppressor.
- **Quieter messages**: the game's "tu-tu-tu" alarm is muted for Silent Ops' own messages (same
  method as HTR 0.4.6; the game's own warnings keep it). There are also fewer messages: no
  "Hidden" line, no percentages, at most one every 4 s.
- Light level: researched. No cheap way to read it from the game, so it is still not modelled
  (only your flashlight counts).
- Tested in game with HTR 0.4.7 (DESIGN.md, section 16.11). No measurable frame cost.

## 0.1.0 — 2026-10-30

First release.

- Unaware enemies are taken over by the mod (their eyes off, deaf to vanilla alarms, no melee
  swing) and notice you through a suspicion meter: distance, view cone, stance, movement,
  flashlight, line of sight. Handed back to vanilla combat (and HTR) when they spot you.
- Noise: unsuppressed shots by weapon type, suppressed shots, bullet impacts, footsteps, bodies.
- Suppressor toggle (F4) per weapon, saved between sessions.
- Silent melee takedowns from behind on unaware enemies.
- Suspicious enemies turn to look, then investigate; searching enemies check the area; alerted
  enemies who lose you go back to searching, then to patrol.
- Squad orders (F3): Follow quietly, Hold, Weapons free; auto weapons free when spotted.
- Uses HTR 0.4.2+ relaxed / alert sight per faction when HTR is installed.
- Off by default; Shift+F4 switches it on (remembered).
- Tested in game (see DESIGN.md, section 13.3); no measurable frame cost.

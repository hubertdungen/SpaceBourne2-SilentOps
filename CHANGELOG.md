# Changelog

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

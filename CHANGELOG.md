# Changelog

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

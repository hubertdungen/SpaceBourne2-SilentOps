![Silent Ops](docs/banner.png)

# Silent Ops — realistic stealth for SpaceBourne 2

Enemies no longer spot you the instant you enter their view. They notice you gradually,
depending on distance, where they are looking, your stance, how fast you move and your
flashlight. Gunshots carry, suppressors reduce the sound without erasing it, a knife from
behind kills silently, and your squad can follow you quietly without opening fire.

Version 0.1.0 · [Nexus Mods page](https://www.nexusmods.com/spacebourne2/mods/6) · UE4SS Lua mod · works alone or with
[Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism).

## What it does

- **Suspicion before alarm.** An unaware enemy builds a suspicion meter instead of spotting you
  at once. Suspicious enemies stop and turn to look; at higher suspicion they walk over to check;
  when the meter fills they raise the alarm and normal combat starts.
- **Realistic sight.** Standing in the open is still seen. Crouching shrinks your silhouette
  (shorter range, slower to notice), moving draws the eye, sprinting draws it most, and the
  flashlight gives you away from farther. Side vision is weaker; enemies do not see behind them.
- **Noise.** Unsuppressed shots are heard 50–100 m away (half that through walls) and send
  enemies searching. Bullet impacts, footsteps and falling bodies make small noises.
- **Suppressors that reduce, not silence.** Fit one with a key on bullet pistols, rifles, SMGs,
  DMRs and snipers. A suppressed pistol is heard as "something odd" ~12 m away, a rifle ~25 m
  (it keeps its supersonic crack). Remembered per weapon.
- **Silent takedowns.** A melee hit from behind on an unaware enemy kills at once, without an
  alarm. From the front or the side it is a normal hit and the enemy shouts for help.
- **Searching and losing them.** Enemies who heard a shot or saw something search the area.
  Break line of sight long enough and alerted enemies go back to searching, then to patrol.
- **Quiet squad orders.** Follow quietly (crouched, no firing), Hold (stay put, hold fire) or
  Weapons free. Spotted while quiet? The squad opens fire on its own.
- **Off by default.** Nothing changes until you switch it on.

## Requirements

- SpaceBourne 2 (Steam).
- [UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1). Installing HTR
  installs it too.
- Recommended: [Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism)
  0.4.2 or later. Silent Ops then uses HTR's relaxed / alert sight per faction, and HTR handles
  damage, aim and combat once an enemy is alerted.

## Install

1. Download `SilentOps-0.1.0.zip` from the
   [releases](https://github.com/hubertdungen/SpaceBourne2-SilentOps/releases).
2. Extract it into the game folder
   (`...\steamapps\common\SpaceBourne 2\`). It adds
   `SB2\Binaries\Win64\Mods\SilentOps\` (the `enabled.txt` inside turns it on).
3. In game, on foot, press **Shift+F4** to switch stealth on (remembered between sessions).

Manual install: copy the `SilentOps` folder from this repository into
`SpaceBourne 2\SB2\Binaries\Win64\Mods\`.

Uninstall: delete `SB2\Binaries\Win64\Mods\SilentOps`.

## Keys (on foot)

| Key | Action |
|---|---|
| **Shift+F4** | Stealth on / off |
| **F4** | Fit / remove a suppressor on the weapon in your hands |
| **F3** | Squad order: Follow quietly → Hold → Weapons free |

F3 and F4 are the only F keys the game leaves free on foot (it uses F1, F2 and F5 for squad
orders, F6 quick save, F8 quick load, F10 bug report). Plain F3 / F4 stay quiet while Shift is
held. All keys can be changed in `scripts\config.lua`.

## Settings

Edit `Mods\SilentOps\scripts\config.lua` (every line is optional). The main ones:

- `Detection` — sight range source (HTR's per-faction relaxed sight, or a fixed range), stance,
  movement and flashlight factors, how fast suspicion builds and fades, how long enemies search.
- `Noise` — hearing radius per weapon, suppressed radius per weapon, footsteps.
- `Suppressor` — which weapons can take one, weapons that are always quiet.
- `Takedown` — allowed melee weapons (knife and sword yes, hammer no), reach, "from behind" angle.
- `Allies` — order key, auto weapons free when spotted.

## Status and known limits

Tested in game on 2026-10-30: the suspicion meter, sight and noise, suppressors, takedowns,
searching and losing enemies, squad orders, the keys and the on-screen messages, and frame times
(no measurable cost: 99 fps with or without the mod, 8 enemies around).

Not tested yet: a real knife swing (the takedown was tested with the same damage call the knife
makes), enemies finding bodies, witnesses of a kill, the squad's quiet follow walk over long
distances, companions. Bosses and robot tanks keep their vanilla behaviour.

Known limits:

- There is no real light or shadow model (the game gives no light level to mods); only your
  flashlight counts.
- An enemy that spawns right in front of you can still spot you instantly (vanilla).
- No new animations: takedowns use the normal melee swing, which the game shows in third person.
- The suppressed shot sound you hear does not change (the game has no suppressed sound).

Design notes, research and the full test log: [DESIGN.md](DESIGN.md).

## Part of the SpaceBourne 2 realism set

Separate mods that work alone or together:

| Mod | Status |
|---|---|
| **Hardcore Tactical Realism (HTR)** — realistic ballistics and tactical AI | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/4) · [Steam discussion](https://steamcommunity.com/app/1646850/discussions/0/573805072991123580) |
| **Silent Ops** — realistic stealth (this mod) | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-SilentOps) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/6) |
| **Split Controls** — separate invert for ship and on foot | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-SplitControls) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/5) |
| **Gear Without Levels** — use gear regardless of level | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-GearWithoutLevels) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/7) |
| Tactical Engineering | coming |
| Faction Power | coming |
| Tactical First Person | coming |

## License

MIT. See [LICENSE](LICENSE).

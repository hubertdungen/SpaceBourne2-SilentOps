![Silent Ops](docs/banner.png)

# Silent Ops — realistic stealth for SpaceBourne 2

Enemies no longer spot you the instant you enter their view, from any distance. Up close and in
plain view you are seen at once; farther away they notice you gradually, depending on distance,
where they are looking, your stance, how fast you move, your flashlight and how well trained they
are. Gunshots carry and put enemies on edge, a suppressed pistol thumps instead of cracking, a
knife from behind kills silently, and your squad can follow you quietly without opening fire.

**Links:** [GitHub](https://github.com/hubertdungen/SpaceBourne2-SilentOps) ·
[Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/6) · UE4SS Lua mod · works alone or with
[Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism)
([Nexus](https://www.nexusmods.com/spacebourne2/mods/4)).
**Install the whole realism set in one go:** the
[SpaceBourne 2 Realism installer](https://github.com/hubertdungen/SpaceBourne2-Realism)
([Nexus](https://www.nexusmods.com/spacebourne2/mods/11)).

## Features

### Being seen

- **Suspicion before alarm.** An unaware enemy builds a suspicion meter instead of spotting you at
  once. Suspicious enemies stop and turn to look; at higher suspicion they walk over to check; when
  the meter fills they raise their weapon and combat starts.
- **Alert levels.** Every enemy is Blue (relaxed), Green (normal attention), Yellow (suspicious),
  Orange (danger known) or Red (combat). Levels rise and fall with evidence, and sharpen or dull
  sight and hearing. From Yellow an enemy raises its weapon and aims where it suspects you; it
  fires only at Red.
- **Realistic sight.** Standing a few metres in front of an enemy is combat at once. Far away it
  sees "something" and walks over to look; if it keeps watching you, it becomes sure after a few
  seconds, quicker if you move or carry a light, slower if you crouch or are half hidden.
- **Cover, not invisibility.** Crouching in the open only slows them down. What hides you is cover:
  how much of your head, chest and knees an enemy can see, and a wall behind you breaking your
  outline. Moving draws the eye and the flashlight gives you away. Side vision is weaker, and
  enemies do not see behind them.
- **Training.** Militia notice you slower and hesitate before firing; elites notice faster and react
  almost at once. Harder, not impossible.

### Being heard

- **Gunshots by weapon class.** Pistol < SMG / rifle < shotgun < DMR < sniper < grenade: how far
  each is heard (45–120 m, half through walls) and how alarming it is. Shots add up. Enemies who
  heard enough draw their weapons, search towards the sound and fire at the first movement.
- **Every fight is noise.** Any NPC's gunfire counts too: a fight in the next room alerts the
  enemies there, and two rooms away they come to check (trained ones with the weapon drawn).
- **Turrets and grenades.** Setting up a turret makes noise and a firing turret is loud; a grenade
  blast is heard 120 m away.

### Suppressed pistol

- **Fit a suppressor** on the pistol in your hands (F4). It takes 3.5 s and the pistol cannot fire
  meanwhile; the pistol remembers it.
- **Quieter shots.** Enemies hear a suppressed shot as "something odd" about 12 m away instead of an
  alarm 45 m away. You hear the pistol quieter, with a muffled thump.
- **A small cost.** The pistol gets a little less accurate and its bullet a little slower.

### Bodies, witnesses and searches

- **Witnesses.** An enemy who sees a mate shot dead draws its weapon, calls the others and maybe
  crouches for cover. One who finds a body without hearing anything searches and calls for help.
- **Cries.** Wounded or dying enemies cry out and their mates come to check. A silent takedown makes
  no cry.
- **Losing them.** Break line of sight long enough and alerted enemies lose you, but they keep
  hunting with weapons drawn before they go back to patrol.

### Silent takedowns

- **From behind.** A melee hit (knife or sword) from behind on an unaware enemy kills at once,
  without an alarm. From the front or the side it is a normal hit and the enemy shouts for help.

### Your squad

- **Quiet squad orders** (F3): Follow quietly (crouched, no firing), Hold (stay put, hold fire) or
  Weapons free. Spotted while quiet? The squad opens fire on its own.

### On by default

- Stealth is on as soon as the mod is installed. Switch it off for a moment with Shift+F4; it is on
  again at the next start.

## Requirements

- SpaceBourne 2 (Steam).
- [UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) (the realism installer
  installs it for you).
- Recommended: [Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism).
  Silent Ops then uses HTR's relaxed / alert sight per faction, and HTR handles damage, aim and
  combat once an enemy is alerted.

## Install

**A. SpaceBourne 2 Realism installer (recommended)**
Get it on [Nexus](https://www.nexusmods.com/spacebourne2/mods/11) or
[GitHub](https://github.com/hubertdungen/SpaceBourne2-Realism/releases/latest). Tick Silent Ops
and any other mods of the set: it installs UE4SS if you don't have it, switches the mods on and
keeps them updated.

**B. Manual** (Nexus file, or the zip on the [releases page](https://github.com/hubertdungen/SpaceBourne2-SilentOps/releases))
1. Extract the zip into your game folder (`...\SpaceBourne 2`, the one with `SpaceBourne2.exe`).
   It creates `SB2\Binaries\Win64\Mods\SilentOps` and switches itself on.
2. No UE4SS yet? Get [RE-UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1)
   and copy `dwmapi.dll`, `UE4SS.dll` and `UE4SS-settings.ini` into
   `SpaceBourne 2\SB2\Binaries\Win64\`.

**Updating:** the installer does it for you, or extract the new zip the same way and let it replace
the files. **Uninstall:** untick Silent Ops in the installer or delete the `SilentOps` folder.
Silent Ops never writes to your saves.

## Keys (on foot)

| Key | Gamepad | Action |
|---|---|---|
| **Shift+F4** | flashlight button ×4 | Stealth on / off (for this session) |
| **F4** | flashlight button ×4, crouched | Fit / remove a suppressor on the pistol in your hands |
| **F3** | flashlight button ×2 | Squad order: Follow quietly → Hold → Weapons free |

F3 and F4 are the only F keys the game leaves free on foot (it uses F1, F2 and F5 for squad orders,
F6 quick save, F8 quick load, F10 bug report). Plain F3 / F4 stay quiet while Shift is held. All
keys can be changed in `scripts\config.lua`.
Gamepad: press the flashlight button quickly. An even number of presses leaves the light as it was
(two presses is a short flash, like a signal to your squad).

## Settings

Edit `Mods\SilentOps\scripts\config.lua` (every line is optional). The main ones:

- `Enabled`, `RememberToggle` — on at start; keep the last on/off between sessions instead.
- `Detection` — sight range source (HTR's per-faction relaxed sight, or a fixed range), the
  "combat at once" distances, stance, movement and flashlight factors, how much suspicion sharpens
  the senses, training (how fast each class notices and reacts), how long enemies search.
- `Noise` — hearing radius and alarm per weapon class, suppressed pistol, footsteps, cries,
  turrets, grenades.
- `Suppressor` — which weapons can take one (pistols), its spread and bullet-speed cost.
- `Takedown` — allowed melee weapons (knife and sword yes, hammer no), reach, "from behind" angle.
- `Witness` — how witnesses and body finders react and how far they call for help.
- `Allies` — order key, auto weapons free when spotted.
- `Gamepad`, `Hud` — the flashlight-button combos; which on-screen messages are shown.

## Known limits

- There is no real light or shadow model (the game gives no light level to mods); only your
  flashlight counts.
- An enemy that spawns right in front of you can still spot you instantly (as in the base game).
- No new animations: takedowns use the normal melee swing, which the game shows in third person.
- The game has no suppressed shot sound: the pistol's own shot plays very quietly with a muffled
  thump on top. The suppressor is not shown on the pistol.
- A grenade's blast is placed about 15 m ahead of where you aimed, 1.5 s after the launch (the game
  gives mods no way to follow the grenade itself).
- Bosses and robot tanks keep their base-game behaviour.

Design notes and research: [DESIGN.md](DESIGN.md). Version history: [CHANGELOG.md](CHANGELOG.md).

## The SpaceBourne 2 realism set

Separate mods that work alone or in any combination. The
[SpaceBourne 2 Realism installer](https://github.com/hubertdungen/SpaceBourne2-Realism)
([Nexus](https://www.nexusmods.com/spacebourne2/mods/11)) installs the ones you tick and keeps them updated.

- **[Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/4)): realistic ballistics, wounds and tactical AI. The core of the set.
- **[Silent Ops](https://github.com/hubertdungen/SpaceBourne2-SilentOps)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/6)): stealth, silent takedowns and suppressors.
- **[Ammo Discipline](https://github.com/hubertdungen/SpaceBourne2-AmmoDiscipline)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/12)): carried ammo limits and scavenging, so every magazine counts.
- **[Gear Without Levels](https://github.com/hubertdungen/SpaceBourne2-GearWithoutLevels)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/7)): use gear above your level, with small handling penalties.
- **[Tactical First Person](https://github.com/hubertdungen/SpaceBourne2-TacticalFirstPerson)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/15)): first person on foot, weapons held up, aiming down the sights.
- **[Tactical Engineering](https://github.com/hubertdungen/SpaceBourne2-TacticalEngineering)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/10)): realistic deployable turrets.
- **[Get Out of the Way](https://github.com/hubertdungen/SpaceBourne2-GetOutOfTheWay)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/14)): NPCs step aside naturally when you walk through them.
- **[Ground Waypoints](https://github.com/hubertdungen/SpaceBourne2-GroundWaypoints)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/13)): planet waypoints on foot and on the hoverbike.
- **[Faction Power](https://github.com/hubertdungen/SpaceBourne2-FactionPower)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/9)): dungeons, strategic sales and missions earn your faction power.
- **[Bigger Armies](https://github.com/hubertdungen/SpaceBourne2-BiggerArmies)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/17)): twice the general slots for your faction's ground and space forces.
- **[Clear HUD](https://github.com/hubertdungen/SpaceBourne2-ClearHUD)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/16)): a reticle you can see and HUD colours of your choice.
- **[Split Controls](https://github.com/hubertdungen/SpaceBourne2-SplitControls)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/5)): separate vertical invert for ship and on foot, per device.
- **[SB2 HOTAS](https://github.com/hubertdungen/SpaceBourne2-HOTAS)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/8)): HOTAS, rudder pedals, triple screens and head tracking.

## License

MIT. See [LICENSE](LICENSE).

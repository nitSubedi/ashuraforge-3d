# AshuraForge 3D

A 3D reimagining of [AshuraForge](https://github.com/nitSubedi/AshuraForge) (originally a 2D
Flutter/Flame platformer), built in **Godot 4.7**: a third-person melee action **descent
roguelite**. A half-demon aristocrat fights down through a New York swallowed by the
underworld — cane-sword and capoeira combat, signature powers (Phantom Blade, Hellfire Rain,
Wraithwing), and death that reforges him stronger in the Ashura Forge.

Design: [`docs/superpowers/specs/2026-09-28-ashuraforge-game-design.md`](docs/superpowers/specs/2026-09-28-ashuraforge-game-design.md)

## Status

Vertical slice on `feat/vertical-slice`:

- Streamed OSM hell-city (baked chunks, occlusion culling, FSR2), physics-interpolated camera
- MPFB2-based hero with cane-sword; phase-timed combat with lunge, hitstop and buffering
- Cane / sword stances, capoeira kicks, iai quick-draw
- Signature powers on a Blood meter: Phantom Blade, Hellfire Rain, Wraithwing
- Demons with hurt reactions, blood and dismemberment (placeholder rig; no AI yet)

## Run it

1. Install [Godot 4.7](https://godotengine.org) (`brew install --cask godot`) and
   [Git LFS](https://git-lfs.com) (`git lfs install`) **before cloning** — art is stored in LFS.
2. `godot --path .` (or open `project.godot` in the editor and press **Play**).
3. Optional, for full performance: bake the streamed city chunks once (without them the game
   builds the city at load):
   `godot --headless --path . -s res://tools/bake_city.gd`

## Controls

| Action | Input |
| --- | --- |
| Move / look | W A S D / mouse |
| Sprint | Hold Shift |
| Jump | Space |
| Dodge (i-frames) | Ctrl |
| Cane (hand) string | J / Left Mouse |
| Capoeira kicks | K / Right Mouse |
| Draw / sheathe cane-sword | Q |
| Phantom Blade / Hellfire Rain / Wraithwing | 1 / 2 / 3 (cost Blood) |
| Restart | R |
| Release mouse | Esc |

## Verify

- Combat sims: `godot --headless --path . -s res://tools/sim_combo.gd`
  (`SIM_INPUT=qhhhhq SIM_EXPECT_STANCE=cane` — prints PASS/FAIL)
- Powers: `godot --headless --path . -s res://tools/sim_abilities.gd`
- Performance: `godot --path . -s res://tools/perf_probe.gd`
- Screenshot a frame: `godot --path . -s res://tools/screenshot.gd` (writes `screenshot.png`)

## Rebuilding assets

- **Hero** — `tools/gen/make_hero.py` (Blender 5 + [MPFB2](https://github.com/makehumancommunity/mpfb2)
  + MakeHuman system assets; `HERO_EXPORT=1`), then
  `godot --headless --path . -s res://tools/build_hero.gd`.
- **Animations** — raw Mixamo clips are **not** in this repository (Mixamo's terms don't allow
  redistributing them as standalone files). Download them with your own Adobe account (FBX,
  *without skin*, X Bot) into `assets/animations/mixamo/` — see
  `assets/animations/mixamo/_DOWNLOAD_THESE.md`. The built `assets/characters/hero.tscn` already
  contains what the game uses; this is only needed to rebuild the hero.
- **Cane-sword** — `tools/gen/make_cane_sword.py` (Blender).

## Layout

- `scripts/` — gameplay (player, enemy, abilities/, anim driver, city streamer, game manager)
- `scenes/` — `main`, `player`, `hud`, `projectile`, …
- `assets/` — characters, enemies, weapons, city, shaders, animations
- `tools/` — asset builders, Blender generators, render/measure tools, headless sims
- `docs/superpowers/` — design specs and implementation plans

## Credits

See [`CREDITS.md`](CREDITS.md) for all third-party assets and licenses.

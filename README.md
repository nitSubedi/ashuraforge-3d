# AshuraForge 3D

A 3D roguelike reimagining of [AshuraForge](https://github.com/nitSubedi/AshuraForge)
(originally a 2D Flutter/Flame platformer), built in **Godot 4** with a
**third-person over-shoulder** camera and **free / CC0 assets**.

## Status

**Sub-project 1 — Playable Slice** (in progress). One hand-built dungeon room with:

- Third-person over-shoulder camera (SpringArm, mouse-look, wall pull-in)
- Camera-relative movement, sprint, jump, **dodge-roll with i-frames**
- **Melee** swing + **magic projectile** (maps to AshuraForge's Fire/Magic)
- Skeleton enemy with idle → chase → attack AI
- Player health + HUD, win (clear room) / lose (death) + restart
- Reuses the original game's free SFX

Now running with **CC0 KayKit art** — an animated Knight hero, animated Skeleton
enemies, and a torch-lit modular dungeon room (see `CREDITS.md`).

## Verify

- Logic tests: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/test_logic.gd`
- Screenshot a frame: `/Applications/Godot.app/Contents/MacOS/Godot --path . -s res://tools/screenshot.gd` (writes `screenshot.png`)

## Controls

| Action | Input |
| --- | --- |
| Move | W A S D |
| Look | Mouse |
| Sprint | Hold Shift |
| Jump | Space |
| Dodge-roll (i-frames) | Ctrl |
| Melee | Left Mouse |
| Cast magic | Right Mouse |
| Restart | R |
| Release mouse | Esc |

## Run it

1. Install Godot 4: `brew install --cask godot`
2. Open this folder in Godot (`Import` → select `project.godot`), or:
   `/Applications/Godot.app/Contents/MacOS/Godot --path . `
3. Press **Play** (F5).

## Layout

- `scripts/` — GDScript components (player, enemy, projectile, health, hud, game manager)
- `scenes/` — `main`, `player`, `enemy_skeleton`, `projectile`, `hud`
- `assets/` — CC0 3D art (characters / enemies / dungeon / vfx)
- `audio/` — free SFX reused from the original AshuraForge
- `docs/superpowers/specs/` — design doc

## Roadmap

1. **Playable Slice** ← current
2. Roguelike run loop — procedural multi-room dungeon, transitions, permadeath
3. Combat depth & enemy variety — mushroom enemy, more attacks, status effects
4. Items / upgrades / meta-progression
5. Polish — lighting, VFX, menus, export & share

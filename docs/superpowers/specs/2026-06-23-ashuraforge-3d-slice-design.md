# AshuraForge 3D — Playable Slice (Sub-project 1) — Design

**Date:** 2026-06-23
**Status:** Approved (user: "start work")

## Context

AshuraForge is currently a 2D Flutter/Flame platformer (`/Users/maauri/Projects/AshuraForge`):
a fantasy hero, skeleton + mushroom enemies, melee + magic-projectile combat, items, Tiled
levels, and a set of free SFX. We are reimagining it as a **3D roguelike** built in **Godot 4**,
using **free / CC0 assets only** (no paid generation; image-blaster was ruled out — it requires
paid World Labs / FAL / ElevenLabs keys the user does not have).

The original Flutter project is the **design reference** and stays untouched. New work lives in
`/Users/maauri/Projects/ashuraforge-3d/`.

## Goal of this sub-project

Build one hand-authored dungeon room the player can move, fight, and win/die in — a
**vertical slice** that proves the engine, third-person camera, controls, combat, and the
free-asset pipeline **before** any procedural / roguelike systems are added.

## Decisions (locked)

- **Engine:** Godot 4 (install via `brew install --cask godot`).
- **Genre / feel:** 3D roguelike, **third-person over-shoulder** (Souls-lite camera).
- **Assets:** free/CC0 only — KayKit Adventurers + Dungeon Remastered, Quaternius, Mixamo.
  All `.glb`. Every asset's source + license recorded in `CREDITS.md`.
- **Audio:** reuse AshuraForge's existing free SFX (`bgm.wav`, `Fire.mp3`, `Magic3.mp3`,
  `Punch.mp3`, `Scream.mp3`, `hitHurt.wav`, `Jump.*`).
- **Location:** `/Users/maauri/Projects/ashuraforge-3d/` (separate from cloned `AshuraForge`).

## Components (each isolated and testable)

1. **Project scaffold** — Godot 4 3D project, git, folders (`assets/`, `audio/`, `scenes/`,
   `scripts/`, `tests/`), `.gitignore` for Godot, `project.godot` with input map.
2. **Asset pipeline** — download + import CC0 hero (idle/run/attack/hit/die), 1 skeleton enemy,
   modular dungeon kit for one room. `CREDITS.md` documents source + CC0 license per asset.
3. **Third-person camera** — `SpringArm3D` over-shoulder offset, mouse-look, wall-collision pull-in.
4. **Player controller** — `CharacterBody3D`; WASD relative to camera; sprint; **dodge-roll with
   i-frames**; gravity/jump; drives animation state.
5. **Combat** — melee swing (animation + hitbox) and a **magic projectile** (ranged), mapping to
   AshuraForge's Fire/Magic. Reuses repo SFX.
6. **Enemy: skeleton** — state AI (idle → chase → attack), health, death animation.
7. **Player health + HUD** — HP bar, hit feedback (flash + sound).
8. **Loop** — clear the room = win screen; player death = restart.

## Data flow

input → player controller → movement resolved vs. dungeon colliders + attack spawns
hitbox/projectile → enemy/player takes damage → HUD + audio react → win/lose state.

## Out of scope (deliberately deferred to later sub-projects)

Procedural generation, multiple rooms / transitions, items / upgrades, meta-progression,
the mushroom enemy, web export. These are sub-projects 2–5:

2. Roguelike run loop — procedural multi-room dungeon, transitions, permadeath
3. Combat depth & enemy variety — mushroom enemy, more attacks, status effects
4. Items / upgrades / meta-progression
5. Polish — lighting, VFX, menus, export & share

## Testing

- **GUT** (Godot Unit Test) for logic: health, damage application, AI state transitions,
  i-frame timing.
- Manual play-test checklist for camera feel, movement, and combat responsiveness.

## Known constraint

Godot's editor is GUI-driven. Code, scenes (`.tscn`/`.gd`), assets, and licensing are fully
scriptable from outside, but a few steps (first `.glb` import, lightmap bake, pressing Play)
may need the user at the keyboard. We automate everything the CLI allows and give exact
click-by-click instructions for the rest.

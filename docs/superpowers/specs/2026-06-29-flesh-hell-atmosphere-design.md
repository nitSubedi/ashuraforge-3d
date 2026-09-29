# Flesh-Hell Atmosphere + AI Skybox

**Date:** 2026-06-29
**Status:** Design (awaiting implementation plan)
**Part of:** the "hell dimension world" effort. This is **sub-project 1 of 3**:
1. **Flesh-hell atmosphere + AI skybox** (this spec)
2. Procedural flesh-hell layout generator (future spec)
3. Flesh-hell props via Hunyuan3D / CC0 (ongoing, future)

## Goal

Transform the existing single-room dungeon into a visceral **flesh / organic hell
dimension** that reads as a *world* (depth, horizon, atmosphere), changing only
the environment/visuals — no gameplay, player, or enemy logic changes.

## Context

- `scenes/main.tscn` holds a `WorldEnvironment` (already reddish volumetric fog),
  a `DirectionalLight3D` (Sun), the Player, two Skeletons, and the HUD.
- `scripts/main.gd` procedurally tiles a 24×24 enclosed room from KayKit dungeon
  GLBs (floor/wall/pillar/torch) with invisible collision boxes for floor + 4 walls.
- The boxed room (walls + implicit ceiling via fog) hides any sky.
- Aesthetic target (chosen): **flesh/organic hell** — sinew, muscle, bone,
  pulsing growths, wet/visceral, crimson + bone-white, oppressive and grotesque.
- Build method (chosen): **hybrid** — AI-generated equirectangular hell panorama
  as the skybox; the playable world built in Godot around it.

## Components

Each is small and independently testable.

### 1. Skybox
- Input: an AI-generated **equirectangular (2:1) flesh-hell panorama** at
  `assets/generation/references/hell_skybox.png` (user-generated).
- Godot: a `Sky` resource with `PanoramaSkyMaterial` using that texture; set
  `WorldEnvironment.environment.background_mode = Sky`.
- Open the world so the sky is visible: **no ceiling**, and the perimeter walls
  are lowered/broken/pushed out (see Component 5) so the horizon shows.
- Fallback if the panorama is absent: a procedural/gradient sky so the scene
  still loads (the AI panorama swaps in when present).

### 2. Flesh shader (`flesh_hell.gdshader`)
- A **procedural** spatial shader (no external texture dependency):
  - Fractal/simplex noise drives sinew/vein patterns across the surface.
  - Slow `TIME`-based emissive **pulse** (a breathing/alive glow along the veins).
  - Wet, glossy specular (high roughness contrast); crimson base with
    bone-white highlights.
- Delivered as a `ShaderMaterial` applied as a **material override** to the floor
  tiles and walls (KayKit geometry kept; only materials change).
- Exposed uniforms: pulse speed, vein density, base color, emission color/energy
  (so the look is tunable without editing the shader).

### 3. Atmosphere (`WorldEnvironment`)
- Volumetric fog pushed toward deep crimson/visceral; tuned to the new skybox.
- `glow` (bloom) enabled so the emissive veins bloom.
- Tonemap (e.g. ACES/Filmic) + `adjustment` (contrast/saturation) for a sickly,
  oppressive mood.
- Directional light recolored to a low, blood-red key so forms read against the sky.

### 4. Particles
- A `GPUParticles3D` scene (`scenes/fx/embers.tscn`) of drifting embers / ash /
  spores covering the play area; additive, emissive, slow upward/lateral drift.
- Instanced once in `main.tscn`.

### 5. Space
- In `main.gd`: enlarge the floor extent and push the boundary outward so there
  is visible depth; **remove the ceiling**; lower or open the perimeter walls (or
  replace with a distant low boundary) so the skybox horizon is seen.
- Keep invisible collision so the player still can't leave the intended area
  (collision boundary can stay even if the visible walls are lowered/open).

## Architecture / Files

- `scenes/main.tscn` — updated `WorldEnvironment` (sky, fog, glow, adjustments,
  light), add `Embers` particle instance.
- `assets/shaders/flesh_hell.gdshader` (new) — procedural flesh shader.
- `assets/shaders/flesh_hell_material.tres` (new) — `ShaderMaterial` using it.
- `scenes/fx/embers.tscn` (new) — ember/spore `GPUParticles3D`.
- `scripts/main.gd` — larger/opened layout; apply the flesh material override to
  floor + walls.
- `assets/generation/references/hell_skybox.png` (user-generated input).

Each unit is isolated: the shader/material has no scene deps; the particles scene
is self-contained; the skybox is a swappable texture; `main.gd`'s layout math is
the only logic touched and stays additive.

## Risks & Fallbacks

| Risk | Fallback |
|------|----------|
| Skybox panorama not yet provided | Procedural gradient sky; swap panorama in later. |
| Flesh shader too noisy/garish at gameplay distance | Tunable uniforms; dial vein density / emission down. |
| Opening walls lets player see "edge of world" emptiness | Distant fog + skybox hide the boundary; keep collision in. |
| Perf drop from volumetric fog + glow + particles on the larger space | Cap particle count; tune fog density; these are all adjustable. |
| Panorama seams visible | Re-generate with stronger "seamless equirectangular" prompt; or rotate seam behind the player start. |

## Success Criteria

- Booting `main.tscn` shows a large, **breathing** flesh-hell expanse: hellish
  sky horizon, glowing veined floor/walls, drifting embers, visceral fog/glow.
- The hero and skeletons are unchanged and the game remains playable.
- The look is tunable via shader/material uniforms and `WorldEnvironment` values.
- Change is contained to environment/visual files; no gameplay logic altered.

## Out of Scope (future sub-projects)

Procedural layout generation; bespoke flesh props/meshes; weapons (cane-sword);
additional player moves; demon enemy redesign.

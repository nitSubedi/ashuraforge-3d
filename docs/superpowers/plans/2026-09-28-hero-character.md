# Hero Character Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Alucard × Arno hero in Blender (MPFB2 body + scripted outfit/hair/tattoos) and swap it in for X Bot with every clip, the cane-sword and combat still working.

**Architecture:** `tools/gen/make_hero.py` (Blender headless) produces `assets/characters/hero_mpfb/hero.glb` (body + garments + hair, one Mixamo-named armature incl. extra coat/hair chain bones). `tools/build_hero.gd` switches its base to that GLB and passes every X Bot clip through `tools/retarget.gd` (proven in the spike). Godot `SpringBoneSimulator3D` drives coat/hair chains.

**Tech Stack:** Blender 5.0.1 + MPFB2 (+ MakeHuman system assets CC0, installed), Cycles bake, Godot 4.7.

**Spec:** `docs/superpowers/specs/2026-09-28-hero-character-design.md`

## Global Constraints

- Palette: near-black / deep crimson / antique silver. Platinum hair. Amber-gold eyes. Pale skin.
- Original design — no Assassin's Creed / Castlevania insignia.
- Budget ~50–60k tris; 2K textures per material group.
- Bone names stay `mixamorig:*` (→ `mixamorig_*` in Godot); extra bones prefixed `coat_` / `hair_`.
- Clips must go through `tools/retarget.gd` (raw X Bot clips break feet/arms on MPFB).
- Verification renders go to `assets/generation/out/` and are reviewed before moving on.

## Tasks

### Task 1: Body stage (`make_hero.py` part A) + turntable renderer
- Body: `create_human` macro (male, lean: muscle ~0.65, weight ~0.3, height → ~1.83 m), face targets (cheek bones up, narrow jaw, slight hollow cheeks), eyes (high-poly, amber-gold material), eyebrows (pale), eyelashes, teeth, `young_caucasian_male` skin lightened; Mixamo rig; shape keys + helper mask baked.
- `tools/render_hero.gd`: front / side / back / face close-up of a GLB (idle pose via retarget).
- Verify: renders show a lean aristocratic male, eyes/brows present. Commit script + renderer.

### Task 2: Outfit (`make_hero.py` part B)
- Garments generated from the body: greatcoat (sleeves, stand collar, hood down, open front, skirt to mid-calf, crimson lining), breeches, riding boots, gloves + bracers, crossed belts with silver buckles, crimson sash.
- Weights via Data Transfer from the body; coat skirt → 4 `coat_*` chains × 3 bones.
- Verify turntable: silhouette reads (open chest, hood down, tails), no body poke-through in idle/attack poses.

### Task 3: Hair + tattoos (`make_hero.py` part C)
- Hair: MakeHuman `long01` mesh re-materialised platinum (anisotropic strand texture), 3 `hair_*` chains.
- Tattoos: procedural blackwork (chest/arms/neck) composited into the skin albedo bake.
- Verify close-up renders.

### Task 4: Bake + export, swap into the game
- Cycles bake per material group (base/ORM/normal 2K), export `hero.glb`.
- `build_hero.gd`: base = hero.glb; clips via `retarget.gd`; strip root motion; cane-sword mounts; re-tune grips with `render_grip.gd` (hand axes differ from X Bot).
- `SpringBoneSimulator3D` for `coat_*` / `hair_*` in hero.tscn.
- Verify: `sim_combo.gd` suites PASS (`qhhhhq`→cane, `qhhh`→sword, `hhhh`→cane, `qhkh`→sword, `hhhhffff`→cane); in-game screenshot; user playtest.

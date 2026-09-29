# Hero Character — Design

**Date:** 2026-09-28
**Status:** Approved (design)
**Part of:** Blender asset program — sub-project 1 of 4 (hero → demons → weapons/props → environment kit).

## Goal

Replace the X Bot placeholder with the real hero: an original character that
blends **Alucard (Castlevania, Netflix)** and **Arno (Assassin's Creed Unity)** —
no copied insignia/emblems. Must keep every existing Mixamo clip, the cane-sword
mounts and grips working.

## Look

- **Body (MPFB2):** male, ~1.83 m, lean/wiry (low fat, defined not bulky).
  Aristocratic face: high cheekbones, narrow jaw, straight nose, slight hollow
  cheeks. Pale skin, **amber-gold eyes**.
- **Outfit — hooded greatcoat, open chest.** Palette **near-black / deep crimson /
  antique silver** (matches the cane-sword).
  - Greatcoat: knee-to-calf, high stand collar, hood worn **down**, crimson
    lining; hangs **open over the bare chest**.
  - Crossed leather belts with silver buckles, crimson waist sash.
  - Leather bracers + gloves; fitted dark breeches; tall riding boots.
- **Hair:** long loose **platinum** hair past the shoulders, as alpha hair cards
  with a baked strand texture.
- **Tattoos:** blackwork (ornamental / gothic / sacred-geometry) on chest, arms,
  neck — procedural, baked into the skin albedo.

## Motion

Extra bones on coat tails + hair, driven in Godot by `SpringBoneSimulator3D`
(no cloth sim).

## Pipeline

- `tools/gen/make_hero.py` (Blender 5, headless): MPFB2 body + **Mixamo rig** →
  garments fitted to the body (shrinkwrap/solidify, weights via Data Transfer) →
  hair cards → tattoo + material bakes (Cycles, 2K per material group) → export.
- `tools/build_hero.gd`: base mesh/skeleton switches from X Bot to the new hero;
  clip merge, root-motion strip, cane-sword mounts unchanged.
- Budget: ~50–60k tris; 2K textures per material group.

## Risk / gate

MPFB2 must be installed as a Blender extension, and its Mixamo rig's bone names
must match our clips (`mixamorig_*` after Godot import). **Verify first** (spike);
fallback = Godot retargeting (BoneMap → SkeletonProfileHumanoid).

## Verification

1. Turntable renders (front/side/back/face close-up) for user review.
2. In-game: `sim_combo.gd` stance suites PASS; grip renders re-checked.
3. User playtest.

# AshuraForge — Combat System Design

**Date:** 2026-06-29
**Status:** Approved (design); pending spec review

## BLUF / Overview

Replace the current stiff, two-clip combat (single melee swing + magic projectile,
driven by raw `AnimationPlayer.play()`) with a **smooth, flexible, multi-stance
combat system** inspired by Tekken's Eddy Gordo (flowing capoeira) — but extended
so the hero fluidly switches between **Unarmed (capoeira)**, **Weapon (sword &
shield / greatsword)**, and **Magic** stances.

The defining quality is **smoothness**: attacks flow into combo *strings* via
cancel windows, movement blends instead of snapping, and dodge cancels anything.
Built on Godot's **AnimationTree** with a **data-driven combo graph** per stance.

## Goals

- Smooth, fluid attack chains (combo strings with cancel windows + cross-fade blends).
- Three switchable stances, each with its own moveset, sharing one controller.
- Dodge with i-frames that cancels any attack (the core "flexibility" escape).
- Weighty feedback: hit-stop on impact, enemy hit-reaction animations.
- Data-driven and extensible: a new stance = one new resource, no controller surgery.
- Realistic, mature character (cacB Mixamo human) replacing the KayKit "bobble-head".

## Non-Goals

- Frame-perfect Tekken fidelity. Mixamo clips are separate recordings, not authored
  to interconnect; we target "fluid indie action," not AAA fighting-game frame data.
- Networked/versus play. Single-player PvE only.
- Stamina/poise economy (may add later; not in this slice).

## Character Pipeline

- **Player model:** `cacB.glb` — rigged 1.82 m Mixamo human (65-bone rig), realistic
  proportions. Replaces the KayKit Knight. Imported at scale 0.01 (Mixamo cm → m).
- **Rig source of truth:** standard Mixamo skeleton, so any Mixamo clip retargets onto it.
- **Acquisition automation:** the `v1xel/mixamo-mcp` MCP server (Playwright, user's
  saved Adobe session). Upload `cacB` via `mixamo_upload_character`, then
  `mixamo_download(with_skin=false, format=gltf)` each curated clip onto the shared rig.
- **Output:** glTF into `assets/animations/mixamo/`, imported by Godot natively.

## Input Scheme

| Action | Binding | Notes |
|---|---|---|
| Move | WASD | Locomotion = idle↔walk↔run **blend tree** (no snap) |
| Camera | Mouse | Over-shoulder (existing) |
| Light attack | Left-click | Advances the light combo string in active stance |
| Heavy attack | Right-click | Heavier hit / launcher |
| Dodge | Ctrl | i-frames; **cancels any attack**; primary defense in every stance |
| Block | Hold F | Weapon stance only (shield raise) |
| Switch stance | Q cycles; 1/2/3 direct | Unarmed / Weapon / Magic |
| Sprint | Shift | Existing |
| Jump | Space | Existing |

## Architecture

- **`CombatController`** (on Player): owns the active stance, current combo node,
  input handling, hitbox activation, hit-stop, and the AnimationTree playback.
- **`Stance` (Resource)**: data-defining one style. Fields:
  - `id` (Unarmed / Weapon / Magic)
  - `locomotion` set (idle/walk/run clip names for the blend tree)
  - `light_chain`, `heavy_chain`: ordered lists of combo nodes
  - `dodge_clip`, `block_clip` (optional)
- **`ComboNode`** (struct/Resource): one attack in a chain. Fields:
  - `clip` (animation name)
  - `cancel_window` (start, end) — normalized time during which input advances the chain
  - `hit_frames` (start, end) — when the hitbox is live
  - `damage`
  - `next_on_light`, `next_on_heavy` — index/ref to the next node (enables branching strings)
  - `root_motion` (bool) — whether the clip drives movement
- **`AnimationTree`** (Godot): a state machine with a locomotion **blend space** plus
  one-shot attack states; cross-fade time ~0.12 s for smoothness. Replaces all raw
  `anim.play()` calls in `player.gd`.

### Combo flow (the smoothness engine)

1. Press Light → play `light_chain[0]`, hitbox live during its `hit_frames`.
2. If Light pressed again **within `cancel_window`** → advance to `next_on_light`
   (cross-faded). Press Heavy in-window → branch to `next_on_heavy`.
3. Outside the window → chain resets to node 0.
4. **Dodge (Ctrl) cancels any node immediately**, grants i-frames, plays the stance's
   dodge clip (capoeira *au* / weapon roll / magic backstep).
5. **Hit-stop:** on a confirmed hit, freeze both actors a few frames for impact weight.

## The Three Stances (initial movesets)

Clip names are the curated Mixamo targets; exact names resolved via `mixamo_search`.

| Stance | Light string | Heavy / launcher | Dodge | Block |
|---|---|---|---|---|
| **Unarmed (Capoeira/Eddy)** | ginga → martelo → queixada → meia-lua de compasso | chapa giratória / armada spin | *au* cartwheel | esquiva lean |
| **Weapon (Sword & Shield / Greatsword)** | sword slash ×4 | greatsword overhead / jump-attack | roll | shield raise |
| **Magic** | cast bolt (reuse Fire/Magic projectile) | charged "power-up" cast | backstep | — |

## Hit Detection & Reactions

- Attack hitboxes are `Area3D` regions enabled only during a node's `hit_frames`
  (extends the existing `MeleeHitbox` pattern).
- On hit: apply `damage`, trigger hit-stop, play the target's **hit-reaction** clip
  (impact). Enemies use Mixamo impact clips retargeted onto their rig.
- Magic light attack spawns the existing projectile from the muzzle.

## Animation Acquisition List (curated, via MCP)

Locomotion: idle, walk, run (in-place). Per stance: the light-string clips, heavy/
launcher, dodge, block (weapon). Plus shared: hit-reaction (light/heavy), death.
Fetched one at a time as glTF — no bulk scrape, no rate-limit storm.

## Build Order (all three stances; sequence to first-playable)

1. Swap player to `cacB`, scale/ground, hero fill-light; AnimationTree skeleton.
2. Locomotion blend tree (idle/walk/run) — proves smoothness immediately.
3. `CombatController` + `Stance`/`ComboNode` data model; Unarmed stance first.
4. Weapon stance, then Magic stance (reuses existing projectile).
5. Stance switching (Q / 1-2-3), dodge-cancel, hit-stop, enemy hit-reactions.
6. Enemy (skeleton) realistic swap + reactions for consistency (follow-up).

## Risks & Open Questions

- **Smoothness ceiling:** Mixamo clips aren't built to interconnect; cancel windows +
  blend times will need hand-tuning per clip. Expect iteration.
- **Root motion:** decide per clip whether motion is code-driven (in-place) or clip-driven.
  Default to in-place for locomotion/attacks so the controller owns position.
- **Clip naming:** Mixamo names vary; `mixamo_search` resolves exact names before download.
- **Auto-rig quality:** if cacB upload/retarget deforms poorly, fall back to a Mixamo
  built-in character as the base.
- **Stance-switch readability:** instant switch vs. a brief flourish — tune in playtest.

## Testing

- Logic tests (extend `tools/test_logic.gd`): combo advance/reset on cancel-window
  timing, dodge i-frame window, damage application, stance switching.
- Visual verification: screenshot/again-driven checks of each stance's combo flow.

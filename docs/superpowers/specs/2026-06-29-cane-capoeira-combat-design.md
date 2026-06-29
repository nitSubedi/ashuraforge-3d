# Cane + Capoeira Melee — Combat Slice 1

**Date:** 2026-06-29
**Status:** Design (approved; build-heavy, iterate visually)
**Refines:** `2026-06-29-combat-system-design.md` — collapses the 3 switchable
stances into ONE always-on moveset (cane = hands, capoeira = feet), Tekken-style.

## Goal

A diverse, flowing melee system for the hero: the cane-sword is **always
equipped**; **LMB = cane/hand strikes, RMB = capoeira kicks**, freely mixed into
branching combo strings, with dodge-cancel for flow. No enemies yet — the
deliverable is **combo feel + movement**, not damage.

## Controls (rebind)

| Action | Binding | Notes |
|---|---|---|
| Move | WASD | idle↔walk↔run crossfade blend |
| Camera | Mouse | over-shoulder (existing) |
| Hand attack (cane) | **LMB** | advances the hand combo string |
| Foot attack (kick) | **RMB** | advances the foot combo string |
| Dodge | Ctrl | i-frames; cancels any attack |
| Sprint | Shift | existing |
| Jump | Space | existing |

Magic moves off RMB and is deferred (later secondary).

## Combat engine (code-driven, in `player.gd`)

- **Combo graph** — each node:
  `{ clip:String, cancel_window:Vector2(start,end normalized 0..1),
     hit_window:Vector2, damage:float, next_on_hand:int, next_on_foot:int }`
  (`-1` = no branch). Inline GDScript data for v1; may become Resources later.
- **Flow:**
  1. Hand/Foot from neutral → play that string's node 0 (cross-fade ~0.12 s).
  2. Hand/Foot again **within `cancel_window`** → advance to
     `next_on_hand` / `next_on_foot` (branching across cane↔kick = diversity).
  3. Outside the window or clip ends → reset to neutral.
  4. **Dodge cancels any node immediately**, grants i-frames, plays dodge clip.
  5. **Hit-stop:** brief freeze on confirmed hit (dormant without enemies).
- Drives the existing `AnimationPlayer` (crossfade), not a full AnimationTree
  (lighter for v1; AnimationTree migration is a possible later upgrade).

## Moveset v1 (mix cane + kicks)

- **Hand string (cane):** Cane Slash → Cane Backslash → Cane Thrust (finisher);
  branch to a kick mid-string.
- **Foot string (capoeira):** Roundhouse (martelo) → Hook/Spinning Kick →
  Axe Kick / Sweep (finisher); branch to a cane strike.
- Cross-branches both directions so e.g. *cane, cane, spin-kick, sweep* flows.

## Animations (download from Mixamo onto X Bot)

Have: idle, run, attack_slash, dodge. Need:
- **walk** (locomotion blend).
- **cane #2** — a second sword/cane swing (e.g. "Sword And Shield Attack").
- **kicks** — roundhouse, hook/spinning kick, axe kick, low sweep
  (capoeira/kick clips).
- Optional: capoeira **au** cartwheel as the dodge (else keep the roll).
Downloaded via the established standalone script (character already X Bot;
animation IDs are global), then re-merged into `hero.tscn` by `build_hero.gd`.

## Cane-sword prop

- A **simple built cane**: thin cylinder shaft + handle/knob (a couple of
  `MeshInstance3D` primitives, dark material).
- Mounted on a `BoneAttachment3D` bound to the **right-hand bone** of the hero's
  `Skeleton3D`, added in `build_hero.gd` so it's part of `hero.tscn` and always
  held. Bone name resolved from the skeleton at build time.
- Deferred: sword-unsheathe animation/logic; a nicer/generated cane mesh.

## Hit detection

- Per-node **hit windows** activate the existing `MeleeHitbox` (`Area3D`);
  damage taken from the node. Wired but **dormant** (no enemies). Re-enables
  cleanly when enemy targets return.

## Files

- `scripts/player.gd` — combo-graph data + hand/foot input + cancel-window state
  machine + dodge-cancel; replaces the current single-swing melee/cast.
- `scripts/game_manager.gd` — rebind LMB=hand, RMB=foot; free RMB from magic.
- `tools/build_hero.gd` — add the cane `BoneAttachment3D` + mesh to `hero.tscn`.
- `tools/download_combat_clips.py` — fetch walk + cane#2 + kicks (X Bot).
- `assets/animations/mixamo/*.fbx` (+ re-merge) — new clips into `hero.tscn`.

## Risks & Fallbacks

| Risk | Fallback |
|------|----------|
| Mixamo clips don't interconnect smoothly | Tune cancel windows + crossfade per node; expect iteration. |
| Right-hand bone name differs on X Bot rig | Resolve by searching bone names containing "RightHand"/"Hand_R". |
| Kick clips have root translation | Download in-place; or zero out root motion in code. |
| Combo feel hard to judge without enemies | Screenshot attack poses + logic-test the combo state machine; add a training dummy later if needed. |
| Cane clips into the leg/body on kicks | Acceptable for v1 (placeholder cane); refine attach offset later. |

## Success Criteria

- LMB chains a cane string, RMB chains a kick string, and they **cross-branch**
  within cancel windows into varied combos; dodge cancels any of it.
- The cane is visibly **held in the right hand** at all times.
- Locomotion blends idle↔walk↔run smoothly; no animation snapping.
- Combo state machine covered by logic tests (advance/reset/branch/dodge-cancel).

## Out of scope (later)

Magic secondary, sword-unsheathe, parry/block, enemies + damage application,
generated cane mesh, AnimationTree migration.

# Cane-Sword Stance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the prop cane into a production-grade cane-sword the hero can draw (sword stance), sheathe, and flash out for an iai quick-draw.

**Architecture:** A Blender script builds a 3-part GLB (Sheath / Hilt / Blade). `build_hero.gd` mounts the parts on hand bones and merges new Mixamo sword clips. `player.gd` gains a `_stance` on top of the existing phase-timed combo graph; weapon reparenting is centralised in `_set_drawn()`.

**Tech Stack:** Blender 4.x (bpy, Cycles bake), Godot 4.7 GDScript, Mixamo via Playwright (`~/Projects/mixamo-mcp/tools`).

**Spec:** `docs/superpowers/specs/2026-09-27-cane-sword-stance-design.md`

## Global Constraints

- Blade: slim Victorian **estoc** — straight, narrow, triangular section, steel, engraved fuller, ~0.75 m, fits inside the shaft.
- Clips: FBX, "Without Skin", 30 fps, X Bot rig; root motion stripped (keep hips Y) by `build_hero.gd`.
- The **mixamo MCP must be disconnected** while download scripts run (shared `browser_profile/`).
- Keys: Q = draw/sheathe. J/K unchanged. Dodge may cancel draw/sheathe only before `swap`.
- No childish/placeholder SFX; no new sounds.
- Headless tests: `godot --headless --path . -s res://tools/<x>.gd`. Renders: same without `--headless`.

## File map

| File | Change |
|---|---|
| `tools/gen/make_cane_sword.py` | **new** — production cane-sword model → `assets/weapons/cane_sword.glb` + baked textures |
| `tools/render_cane.gd` | point at the new GLB, render sheathed + drawn turntable shots |
| `~/Projects/mixamo-mcp/tools/download_sword_clips.py` | **new** — JOBS for sword clips (copy of `download_combat_clips.py`) |
| `tools/build_hero.gd` | add sword clips; replace `_add_cane` with GLB parts on `RightHandMount`/`LeftHandMount` |
| `tools/measure_strikes.gd` | CLIPS from env/arg; add `swap` (right hand → left hip closest approach) |
| `scripts/game_manager.gd` | bind `stance` → KEY_Q |
| `scripts/player.gd` | stance, sword/iai/draw/sheathe nodes, `_set_drawn()` |
| `tools/sim_combo.gd` | `q` in SIM_INPUT; PASS/FAIL assertions |

---

### Task 1: Production-grade cane-sword model

**Files:** Create `tools/gen/make_cane_sword.py`; modify `tools/render_cane.gd`.

**Produces:** `assets/weapons/cane_sword.glb` with three root objects named exactly `Sheath`, `Hilt`, `Blade`. Units metres, Y-up in Godot. **Origin of every part = the grip point** (centre of the hand on the hilt, just below the collar), so sheathed assembly = all three at identity.

Modelling requirements (production grade):
- **Hilt:** crook from a Bezier sweep with a *varying* profile (slightly oval, thicker at the crown), silver collar with two beaded rims and an engraved band, silver pommel cap on the curl tip. Blade tang hidden inside.
- **Sheath:** lacquered shaft tapering 13→11 mm radius, silver throat ring at the top (where blade enters), silver ferrule with a worn rubber-black tip. Interior bore (open top) so the blade visibly slides in.
- **Blade:** estoc, 0.74 m, triangular (3-face) cross-section with slightly hollow-ground faces, a short square ricasso, a fuller engraved along the first third of each face, needle point. Edge bevel ~0.3 mm so highlights catch.
- Topology: quads, bevel modifiers applied (2 segments on hard edges), weighted normals, no n-gons on curved surfaces; total ≤ 12k tris.
- UVs: smart-project per part with 0.01 margin; one 2048² texture set per material.
- Materials (Principled, glTF-exportable): `Lacquer` (near-black, clearcoat, roughness 0.12 with subtle baked roughness variation), `Silver` (metallic 1, roughness 0.22, baked engraving **normal map** + cavity darkening in base colour), `Steel` (metallic 1, roughness 0.18, baked fuller-etch normal + faint brushed-streak roughness).
- Procedural detail (noise, engraving pattern) is authored in node trees then **Cycles-baked** to image textures (base colour / roughness / normal) — glTF can't export procedural nodes.

- [ ] **Step 1:** Write the script (sections: clean scene → materials → hilt → sheath → blade → UV → bake → export with `export_image_format="AUTO"`, textures embedded).
- [ ] **Step 2:** Run `/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/gen/make_cane_sword.py`. Expected: `CANE_SWORD_EXPORTED …/cane_sword.glb`, per-part tri counts printed, total ≤ 12000.
- [ ] **Step 3:** `godot --headless --import --path .`, then update `tools/render_cane.gd` to render (a) sheathed, (b) blade drawn 60% out, (c) close-up of collar + ricasso. Run non-headless; inspect PNGs. Iterate the script until it reads as a real antique cane-sword (no gaps at the throat, blade fits the bore, engraving visible).
- [ ] **Step 4:** Commit `tools/gen/make_cane_sword.py tools/render_cane.gd assets/weapons/cane_sword.glb*`.

### Task 2: Download the sword clips

**Files:** Create `~/Projects/mixamo-mcp/tools/download_sword_clips.py` (copy of `download_combat_clips.py`, only `JOBS` changes).

```python
JOBS = [
	("sword_draw",    "draw sword",                 True),
	("sword_sheathe", "sheath sword",               True),
	("sword_1",       "stable sword inward slash",  True),
	("sword_2",       "stable sword outward slash", True),
	("sword_3",       "sword and shield slash",     True),
	("sword_4",       "standing melee attack downward", True),
	("iai",           "sword and shield attack",    True),
	("sword_idle",    "sword and shield idle",      True),
]
```

- [ ] **Step 1:** Ask user to disconnect the mixamo MCP; confirm.
- [ ] **Step 2:** Run `.venv/bin/python tools/download_sword_clips.py /Users/maauri/Projects/ashuraforge-3d/assets/animations/mixamo`. Expected: 8 FBX files; the script prints the Mixamo name it picked for each — check each is a one-handed sword motion; re-query any mismatch.
- [ ] **Step 3:** Tell user they can reconnect the MCP.

### Task 3: Merge clips + mount the weapon on the rig

**Files:** Modify `tools/build_hero.gd`.

**Produces (in `hero.tscn`):** `Skeleton3D/RightHandMount` (BoneAttachment3D, `mixamorig_RightHand`) → child `CaneSword` (grip transform) → children `Hilt`, `Blade`, `Sheath`. `Skeleton3D/LeftHandMount` (BoneAttachment3D, `mixamorig_LeftHand`) → empty `SheathGrip` (Node3D, left-hand grip transform). Player finds these by name.

- [ ] **Step 1:** Add to `CLIPS`: `"sword_draw", "sword_sheathe", "sword_1".."sword_4", "iai", "sword_idle"` (→ `<name>.fbx`); add `"sword_idle"` to `LOOPED`.
- [ ] **Step 2:** Replace `_add_cane` / `_make_cane` / `_make_crook` with `_add_cane_sword(root)`: load `res://assets/weapons/cane_sword.glb`, instantiate, move its `Hilt`/`Blade`/`Sheath` under a `CaneSword` Node3D with `_cane_grip_middle()`, create both mounts as above.
- [ ] **Step 3:** Run `godot --headless --path . -s res://tools/build_hero.gd`. Expected: `added clip 'sword_draw' …` ×8 and `SAVED res://assets/characters/hero.tscn`.
- [ ] **Step 4:** Run `godot --headless --path . -s res://tools/sim_combo.gd` — existing cane combat still hits (regression check; `player.gd` finds `Cane` → update its `find_child("Cane")` to `find_child("CaneSword")` in this task).
- [ ] **Step 5:** Commit.

### Task 4: Measure timing incl. `swap`

**Files:** Modify `tools/measure_strikes.gd`.

- [ ] **Step 1:** Read clip list from `MEASURE_CLIPS` env (comma list), default = current list. For clips containing `draw`/`sheathe`/`iai`, also print `swap` = time of minimum distance between `mixamorig_RightHand` and `mixamorig_LeftUpLeg` (the hip, where a sheathed cane rests) — for `iai` the first such minimum before the strike.
- [ ] **Step 2:** Run with `MEASURE_CLIPS=sword_draw,sword_sheathe,sword_1,sword_2,sword_3,sword_4,iai`. Record the table in the commit message.
- [ ] **Step 3:** Commit.

### Task 5: Stance system in `player.gd`

**Files:** Modify `scripts/game_manager.gd` (add `_bind_key(&"stance", KEY_Q)`), `scripts/player.gd`.

**Interfaces produced:** `_stance: String` (`"cane"`/`"sword"`), `_set_drawn(drawn: bool)`, `_do_stance()`, node keys `s1..s4`, `iai`, `draw`, `sheathe`.

Core code (timings from Task 4 replace the `<m>` values):

```gdscript
const NEUTRAL := {"cane": {"hand": "h1", "foot": "f1"}, "sword": {"hand": "s1", "foot": "f1"}}
var _stance := "cane"
var _swapped := false          # this move's swap already fired
# node additions (same schema; "swap" = clip s where the blade changes place)
#   "h3": ... "hand": "iai"
#   "iai":     {"clip": "iai", "lead": <m>, "swap": <m>, "hits": [[<m>, <m>]], "end": <m>, "wind": 0.18,
#               "hand": "", "foot": "", "dmg": 90.0, "heavy": true, "resheathe": true}
#   "s1".."s4": sword string, "hand" → next, "foot" → "f1".."f3"; s4 "hand": ""
#   "draw":    {"clip": "sword_draw", "lead": <m>, "swap": <m>, "hits": [], "end": <m>, "wind": 0.15, "stance_to": "sword"}
#   "sheathe": {"clip": "sword_sheathe", ..., "stance_to": "cane"}
# kick nodes: "hand": "@hand"  → resolved to NEUTRAL[_stance]["hand"]

func _set_drawn(drawn: bool) -> void:
	# Sheathed: sheath rides on the hilt (reads as one cane). Drawn: sheath to left hand.
	var parent := _sheath_grip if drawn else _cane_sword
	_sheath.reparent(parent, false)
	_sheath.transform = Transform3D.IDENTITY
```

- `_update_attack`: generalise `hits` to allow empty arrays (draw/sheathe: `last_hit = swap`); when `t >= node.swap and not _swapped`: `_swapped = true`; draw → `_set_drawn(true)`, sheathe → `_set_drawn(false)`, iai → `_set_drawn(true)`; on `_end_attack`/cut for iai (`resheathe`) → `_set_drawn(false)`; on reaching end of draw/sheathe → `_stance = node.stance_to`.
- `_do_dodge`: reject if current node has `swap` and `_swapped` (committed).
- `_do_stance()` on `stance` action: if idle → `_play_combo("draw" if _stance == "cane" else "sheathe")`; if attacking → queue `"stance"` in `_buffered` (chains after the strike).
- Loco idle: `_play_loco("sword_idle")` in sword stance. Walking-stick grip only in cane stance.
- Dodge/hit reaction mid-iai must re-sheathe (`_clear_attack` → if node had `resheathe` and `_swapped`, `_set_drawn(false)`).

- [ ] **Step 1:** Extend `tools/sim_combo.gd` first: `q` → `_pl._do_stance()`; at the end print `PASS`/`FAIL` for: every started attack node with hits registered ≥1 HIT, and final `_stance` equals `SIM_EXPECT_STANCE` (env, default `cane`).
- [ ] **Step 2:** Run `SIM_INPUT=qhhhq SIM_EXPECT_STANCE=cane` → FAIL (no `_do_stance`).
- [ ] **Step 3:** Implement the above.
- [ ] **Step 4:** Run and require PASS for: `qhhhq` (→cane), `q hhh` (`SIM_INPUT=qhhh SIM_EXPECT_STANCE=sword`), `hhhh` (iai, →cane, blade sheathed at end), `qhkh` (cross-branch, →sword), `hhhhffff` (regression).
- [ ] **Step 5:** Commit.

### Task 6: Visual verification + playtest

- [ ] **Step 1:** `SIM_SHOT=1` renders (non-headless) for `qhhh` and `hhhh`; add a shot at the `swap` frame. Check: blade leaves/enters the throat, sheath sits in left hand while drawn, grips don't clip through fingers. Tune `_cane_grip_middle()` and `SheathGrip` transform in `build_hero.gd`, rebuild.
- [ ] **Step 2:** Launch the game for the user's playtest; tune from feedback.
- [ ] **Step 3:** Update memory (`ashuraforge-combat.md`); commit.

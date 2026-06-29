# AI-Generated Characters → Headless Mixamo Rig → AshuraForge

**Date:** 2026-06-29
**Status:** Design (awaiting implementation plan)
**Supersedes (in part):** the "CC0 / free-assets only" constraint in
`2026-06-23-ashuraforge-3d-slice-design.md` and the `cacB.glb` player-model
choice in `2026-06-29-combat-system-design.md`. The Mixamo *acquisition* and
*retarget* machinery from the combat spec still applies.

## Goal

Replace placeholder art (KayKit Knight player, horned-skeleton enemies) with
high-quality, AI-generated characters that are rigged and animated through a
**fully headless** Mixamo flow, then imported into the Godot 4.7 game.

## Character Bible

- **Hero** — an *ordinary* man, ~6'4", ripped/muscular, full-body tattoos,
  Viking hair, dressed as a blend of Viking and British aristocrat. One hero
  model for this cycle.
- **Demon (first)** — a **Rakshasa** (Hindu mythology), fanged and grotesque,
  "as demonic and disgusting as possible." Chosen because it fits the
  *AshuraForge* name. **Rigging constraint:** Mixamo auto-rigs only standard
  bipeds (2 arms, 2 legs), so the first Rakshasa is authored **two-armed** for a
  clean rig. Multi-armed depictions are future work (extra limbs added as
  non-skinned/secondary geometry or hand-boned later). Replaces the horned
  skeleton enemy.

Design draws references from biblical, Greek, Norse, and Hindu sources;
additional demons (Pazuzu, etc.) are out of scope for this cycle but the
pipeline is built to make them cheap to add.

## Scope

**This cycle:** Hero **and** the first Rakshasa demon, taken end-to-end
(generate → rig → animate → in-game).

**Explicitly out of scope this cycle:** additional demons, environment/world
generation (HY-World 2.0 is a separate future effort — it is CUDA-only and
scene-oriented, not for characters), multi-armed rigging, frame-perfect combat
tuning.

## Two Work Tracks

This effort produces two deliverables in **two repos** with **two PRs**.

### Track 1 — Upstream contribution to `v1xel/mixamo-mcp`

Add a **headless auto-rig** capability so a freshly uploaded character can be
rigged without a human placing markers. Today `screens/upload.py` detects the
marker screen and dead-ends with
`{"state": "markers", "text": "Marker placement required — not supported."}`.

- **PR workflow:** fork `v1xel/mixamo-mcp`, work on a feature branch, push to the
  fork, open a PR upstream.
- **Conventions:** repo has **no** `CONTRIBUTING.md` and **no** `LICENSE`.
  Match the existing README and commit style (capitalized, imperative subject,
  e.g. *"Add upload auto-confirm, marker detection, list/select commands"*).
- ⚠️ **License risk (flag, do not resolve silently):** the repo ships no
  license. Contributing/redistributing modified code is legally ambiguous. Raise
  with the maintainer (e.g. ask them to add a license) before/with the PR. User
  decides how to proceed.

### Track 2 — AshuraForge integration

The generate→rig→animate→import pipeline and the actual hero + Rakshasa assets
land in `ashuraforge-3d`.

**Dependency:** Track 2's *automated* rig step depends on Track 1. If Track 1
stalls, Track 2 falls back to the semi-manual rig (visible browser, user places
markers once per character) — the rest of the pipeline is unchanged.

## Pipeline (Track 2)

```
[A] Reference  Find internet reference images (hero; Rakshasa). Prefer
               front-facing, roughly A-pose (arms slightly out), single figure,
               clean background. User approves refs before meshing.

[B] Generate   Hunyuan3D image→3D  ⇒  OBJ + texture.
               Host strategy: try the HuggingFace Space first via gradio_client
               (automatable, no login; needs `pip install gradio_client`).
               Fallback: Hunyuan3D Studio web (https://3d.hunyuan.tencent.com),
               manual generate + download.

[C] Prep       Package for Mixamo. Mixamo accepts FBX/OBJ/ZIP (NOT GLB), so zip
               OBJ+MTL+texture → upload-ready. Blender (/Applications/Blender.app)
               only if a mesh needs cleanup, scale, or an A-pose fix.

[D] Rig        mixamo-mcp (headless): upload_character → NEW auto-rig tool →
               character saved to Mixamo "My Assets".

[E] Animate    mixamo-mcp: download the clip set (Without Skin), per the existing
               assets/animations/mixamo/_DOWNLOAD_THESE.md list
               (idle, run, attack_slash, attack_cast, hit, death, dodge; +jump
               optional). Format FBX (or Collada) at 30fps, In-Place ON.
               Repeat per character.

[F] Import     Godot 4.7: import the skinned base mesh + retarget the clips onto
               its rig; wire hero into the player scene and Rakshasa into the
               enemy scene, replacing Knight.glb and the skeleton.
```

Outputs: clips in `assets/animations/mixamo/`; hero/demon models replace
`assets/characters/Knight.glb` and the skeleton enemy. Every generated asset and
every reference-image source is recorded in `CREDITS.md` with license info.

## Track 1 Detail — the auto-rig tool

New tool (working name `complete_autorig`; final name to match repo
conventions), added to `screens/upload.py` and exposed in `mcp_server.py`.

1. **Spike (implementation step 1):** trigger a real test upload and dump the
   **live** auto-rigger modal DOM. We do not yet have an accurate capture
   (`page_dump.html` turned out to be the main page). Learn: are markers
   pre-placed as draggable handles, or placed via canvas coordinates? What are
   the Next/Done/Back controls and the processing/review states?
2. **Primary path — accept auto-estimate:** Mixamo pre-places markers with an
   estimate. For clean A-pose humanoids (which we control via input images),
   accept the estimate and advance: Next → processing → review → confirm. This
   avoids brittle blind coordinate math.
3. **Fallback path — coordinate drag:** if markers are *not* pre-placed, drag the
   named handles (chin, L/R wrist, L/R elbow, L/R knee, groin) to positions
   derived from the mesh bounding box / silhouette.
4. Replace the current "markers not supported" dead-end with this driven flow,
   surfacing clear states (uploading / rigging / review / done / error).

## Risks & Fallbacks

| Risk | Fallback |
|------|----------|
| Auto-accept of markers fails | Coordinate-drag fallback → ultimately Approach A (visible browser, user places markers once). |
| Headless vs visible browser fight over `browser_profile/` | Known issue (resolved earlier this session): only one Chromium may own the profile; sequence stop→swap→relaunch. |
| Generated mesh not A-pose / fused limbs | Reject at ref stage; pick better refs; Blender touch-up. |
| HF Space queue/quality poor | Hunyuan3D Studio web (manual). |
| Mixamo rig deforms a grotesque/non-standard demon body | Keep Rakshasa silhouette humanoid; or use a Mixamo built-in base (per combat-spec fallback). |
| Godot FBX import quirks | Export Collada from Mixamo, or Blender FBX→glTF. |
| Rakshasa multi-arm | Two-armed for this cycle; extra arms as non-skinned geometry / future work. |
| mixamo-mcp has no LICENSE | Flag to maintainer before PR; user decides. |

## Success Criteria

- Track 1: the new tool rigs a fresh upload **headlessly, end-to-end** on at
  least the hero mesh, and is PR-ready (feature branch on a fork, upstream PR
  opened, conventions matched).
- Track 2: hero **and** Rakshasa appear in-game with idle / run / attack / hit /
  death / dodge clips playing.
- All generated assets and reference-image sources credited/licensed in
  `CREDITS.md`.

## Dependencies / Environment

- Apple Silicon (darwin). Local Hunyuan3D is impractical (~16GB VRAM, CUDA-
  oriented) → hosted generation.
- `gradio_client` not installed (one `pip install` if we automate the HF Space).
- Blender at `/Applications/Blender.app`; Godot 4.7 at `/opt/homebrew/bin/godot`.
- mixamo-mcp must be the **sole** owner of `browser_profile/` when running.
```

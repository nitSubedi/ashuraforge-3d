# AshuraForge — Game Design Document

**Date:** 2026-09-28 · **Status:** Approved (core design) · Genre: third-person melee action **descent roguelite**, power fantasy.

## Premise

A half-demon aristocrat (Alucard × Arno look — see `2026-09-28-hero-character-design.md`) once sealed the
underworld beneath New York with his own blood. The seal broke; demons swallowed the city. Every death he is
dragged back to the **Ashura Forge** — a hellish smithy under a ruined Manhattan cathedral — and **reforged**,
stronger. The death loop *is* the story. His demon father waits at the Throne.

## Loop

Forge (hub: spend Souls, skill tree, allies/dialogue) → **Descent** through 5 layers → each layer = connected
combat **arenas**; pick the next door by its reward icon; clear; take reward (Infernal Pact, Ichor, Souls,
heal, shop) → **layer boss** → next layer. Death → reforged in the Forge. Target run length 30–40 min.

| Layer | Biome | Boss |
|---|---|---|
| 1 | Hell-City streets (streamed OSM city) | The Avenue Butcher — hook-armed flesh demon |
| 2 | Subway tunnels | The Train-Wyrm — Jörmungandr-like tunnel serpent |
| 3 | Flooded sewers & catacombs | The Bone Saint — fallen biblical saint |
| 4 | Underworld flesh halls | The Rakshasa King |
| 5 | The Throne | His father, an Asura lord (multi-phase) |

## Currencies

- **Blood** — in-run combat meter (0–100), filled by hits/kills, spent on signature powers.
- **Ichor** — in-run shop currency.
- **Souls** — permanent; spent on the Forge skill tree.

## Signature powers (4 slots; Blood cost + short cooldown; mutated by in-run Infernal Pacts)

1. **Phantom Blade** — the sword leaves the cane and orbits him, striking nearby demons on its own; he keeps
   fighting with the cane. Pacts: split into 3 spectral blades · lunge at marked target · ricochet.
2. **Hellfire Rain** — mark an area; staggered volleys of burning meteors fall; knockdown + burning ground.
   Pacts: splitting meteors · gravity well · homing.
3. **Wraithwing** — dissolve into black smoke and fly fast in any direction (up onto rooftops), damaging demons
   passed through, invulnerable; land with a shockwave. Pacts: choking trail · longer flight · landing crater.
4. **Slot 4** — TBD (e.g. Crimson Reaping execution that refills Blood, or a chain-pull).

## Broad moveset

Cane stance + sword stance (built), capoeira kicks (built), launcher → air combos, parry → counter, executions
on staggered demons, dash-cancel out of anything.

## Enemies

Fodder ghouls, ranged pyre-spitters, shielded brutes, flying harpies, elite variants. Built via the Blender
pipeline (Hunyuan3D concept meshes for grotesque bodies). AI: LimboAI behaviour trees (rank & file) + state
machines (boss phases). Crowds: animation LOD for distant demons, pooling.

## Tooling decisions

Researched 2026-09-28: **Dialogue Manager** (story/dialogue), **Questify** (quests), **LimboAI** (AI) — adopt
when their sub-project starts. **GodotGAS** evaluated for abilities; sub-project 1 uses a small in-house ability
component shaped like GAS (slots, costs, cooldowns, tags) to avoid an unverified dependency for four abilities —
revisit when status effects/attributes grow.

## Sub-projects (each: spec → plan → build → playtest)

1. Ability system + Phantom Blade, Hellfire Rain, Wraithwing, Blood meter, HUD  ← **next**
2. Run structure (arenas, doors, rewards, layers)
3. Enemy roster + AI
4. Bosses
5. Forge hub + meta progression (skill tree, Souls)
6. Narrative / dialogue

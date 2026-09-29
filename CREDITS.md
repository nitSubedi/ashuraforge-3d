# Credits & Asset Licenses

All third-party assets in this project are free to use. Each entry records the
source and license. **CC0** = public domain, no attribution required (we credit
anyway out of courtesy).

## Audio (SFX)

Reused from the original [AshuraForge](https://github.com/nitSubedi/AshuraForge)
repository (`assets/audio/`). Typical retro-game SFX (jsfxr-style generated tones
+ short clips). Files: `bgm.wav`, `Fire.mp3`, `Magic3.mp3`, `Punch.mp3`,
`Scream.mp3`, `hitHurt.wav`, `Jump.*`, `powerUp.wav`, `click.wav`.

## 3D Models — all CC0, by Kay Lousberg (www.kaylousberg.com)

In active use. CC0 (public domain) — free for commercial use and redistribution,
no attribution required. Verified against each pack's `LICENSE.txt`
(`assets/dungeon/LICENSE.txt` kept in-repo).

| File | Role | Pack | Animations |
| --- | --- | --- | --- |
| `assets/characters/Knight.glb` | Player hero | KayKit Character Pack: Adventurers 1.0 | 76 (Idle, Running_A, 1H_Melee_Attack_*, Hit_A, Death_A, …) |
| `assets/enemies/Skeleton_Warrior.glb` | Skeleton enemy | KayKit Character Pack: Skeletons 1.0 | 95 (Idle, Running_A, 1H_Melee_Attack_Chop, Hit_A, Death_A, …) |
| `assets/dungeon/*.glb` | Floors, walls, pillars, torches, barrels, chest | KayKit Dungeon Remastered 1.0 | — |

Source repos (CC0):
- https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
- https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0
- https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0
- Author's page: https://kaylousberg.itch.io/ (CC0)

## City — OpenStreetMap (ODbL)

`assets/city/manhattan.glb` is built from OpenStreetMap building footprints,
© [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors, available
under the Open Database License (ODbL). Exported with
[map3d](https://github.com/cartesiancs/map3d) (MIT).

## Hero base mesh — MPFB2 / MakeHuman (CC0)

The hero body is generated with [MPFB2](https://github.com/makehumancommunity/mpfb2)
using the MakeHuman system assets (CC0). Outfit, hair styling, tattoos and textures
are produced by this project's own Blender scripts (`tools/gen/`).

## Animations — Mixamo (Adobe)

Character animations come from [Mixamo](https://www.mixamo.com). Raw Mixamo files
are not redistributed in this repository; only the built game scenes that use them
are included. The placeholder enemy uses Mixamo's X Bot character.

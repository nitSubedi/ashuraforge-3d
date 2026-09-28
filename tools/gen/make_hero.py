"""AshuraForge hero — Alucard (Castlevania) x Arno (AC Unity), an original blend.

Stage A (this file so far): MPFB2 body — lean wiry male ~1.83 m, aristocratic
face, amber-gold eyes, pale skin, brows/lashes/teeth — on MPFB's Mixamo rig.
Later stages add the outfit, hair, tattoos, bakes and the GLB export.

Needs: MPFB2 extension + MakeHuman system assets (CC0) installed.
Run:   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/gen/make_hero.py
       HERO_RENDER=1 also renders preview shots to assets/generation/out/hero_*.png
"""
import math
import os

import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_outfit  # noqa: E402

from bl_ext.blender_org.mpfb.services.assetservice import AssetService
from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "generation", "out")

# Lean, wiry, compact — not bulky. height 0.55 -> ~1.83 m on MPFB's scale.
MACRO = {"gender": 1.0, "age": 0.45, "muscle": 0.8, "weight": 0.2, "proportions": 0.9,
         "height": 0.62, "cupsize": 0.5, "firmness": 0.5,
         "race": {"asian": 0.05, "caucasian": 0.95, "african": 0.0}}

# Aristocratic face: high cheekbones, narrow tapered jaw, straight narrow nose,
# slightly hollow cheeks, defined chin.
FACE = {
    "l-cheek-bones-incr": 0.7, "r-cheek-bones-incr": 0.7,
    "l-cheek-volume-decr": 0.25, "r-cheek-volume-decr": 0.25,
    "chin-width-decr": 0.35, "chin-prominent-incr": 0.3, "chin-triangle": 0.25,
    "nose-scale-horiz-decr": 0.35, "nose-point-width-decr": 0.3,
    "nose-greek-incr": 0.2, "nose-hump-decr": 0.3,
}

BODYPARTS = {  # asset subdir -> asset name
    "eyes": "high-poly",
    "eyebrows": "eyebrow010",
    "eyelashes": "eyelashes02",
    "teeth": "teeth_base",
    "tongue": "tongue01",
    "hair": "long01",
}
PLATINUM = (0.93, 0.9, 0.82)


def asset(subdir, name, ext=".mhclo"):
    path = AssetService.find_asset_absolute_path(name + ext, asset_subdir=subdir)
    if path is None:  # fall back to any asset of that kind
        for cand in AssetService.get_asset_list(subdir, ext) if hasattr(AssetService, "get_asset_list") else []:
            return cand
    return path


def build_body():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    body = HumanService.create_human(macro_detail_dict=MACRO)
    body.name = "HeroBody"
    TargetService.bulk_load_targets(body, [{"target": k, "value": v} for k, v in FACE.items()])
    rig = HumanService.add_builtin_rig(body, "mixamo")
    rig.name = rig.data.name = "HeroRig"
    skin = asset("skins", "young_caucasian_male/young_caucasian_male", ".mhmat") \
        or AssetService.find_asset_absolute_path("young_caucasian_male.mhmat", asset_subdir="skins")
    HumanService.set_character_skin(skin, body, skin_type="MAKESKIN")
    parts = {}
    for sub, name in BODYPARTS.items():
        path = AssetService.find_asset_absolute_path(name + ".mhclo", asset_subdir=sub)
        if path is None:
            print(f"WARN missing {sub}/{name}")
            continue
        parts[sub] = HumanService.add_mhclo_asset(path, body, asset_type=sub, material_type="MAKESKIN")
    _platinum(parts)
    _finalize_body(body)
    return body, rig, parts


def _platinum(parts):
    """Recolour hair + brows platinum: keep the strand texture's luminance/alpha,
    remap its colour to pale platinum blond."""
    for key in ("hair", "eyebrows"):
        ob = parts.get(key)
        if ob is None:
            continue
        for slot in ob.material_slots:
            nt = slot.material.node_tree
            tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if tex is None or bsdf is None:
                continue
            bw = nt.nodes.new("ShaderNodeRGBToBW")
            ramp = nt.nodes.new("ShaderNodeValToRGB")
            ramp.color_ramp.elements[0].color = (0.45, 0.42, 0.36, 1)
            ramp.color_ramp.elements[1].color = (*PLATINUM, 1)
            nt.links.new(tex.outputs["Color"], bw.inputs[0])
            nt.links.new(bw.outputs[0], ramp.inputs["Fac"])
            nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
            bsdf.inputs["Roughness"].default_value = 0.42


def _finalize_body(body):
    """Bake MPFB shape keys (macro + face targets) and drop helper geometry, so
    garments are generated from the real, final surface."""
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    if body.data.shape_keys:
        body.shape_key_add(name="final", from_mix=True)
        keys = body.data.shape_keys.key_blocks
        for kb in [k for k in keys if k.name != "final"]:
            body.shape_key_remove(kb)
        body.shape_key_remove(body.data.shape_keys.key_blocks["final"])
    for m in list(body.modifiers):
        if m.type == "MASK":
            bpy.ops.object.modifier_apply(modifier=m.name)


# ------------------------------------------------------------------ preview --

def preview(body):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 720, 960
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.23, 0.23, 0.25, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.world = world

    def light(name, rot, energy, color=(1, 1, 1), size=2.0, loc=(0, 0, 0)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy, ld.color, ld.size = energy, color, size
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = [math.radians(a) for a in rot]
        scene.collection.objects.link(ob)

    h = body.dimensions.z
    light("Key", (60, 0, 35), 900, (1.0, 0.95, 0.9), 2.5, (2.2, -2.6, h * 1.3))
    light("Fill", (70, 0, -50), 250, (0.8, 0.85, 1.0), 3.0, (-2.8, -2.0, h))
    light("Rim", (-60, 0, 180), 700, (1.0, 0.9, 0.85), 2.0, (0.0, 2.8, h * 1.2))

    cam_d = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam

    def look(pos, target, lens):
        cam.location = pos
        d = Vector(target) - Vector(pos)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        cam_d.lens = lens

    shots = {
        "front": ((0.0, -4.6, h * 0.55), (0.0, 0.0, h * 0.52), 50),
        "side": ((-4.6, 0.0, h * 0.55), (0.0, 0.0, h * 0.52), 50),
        "back": ((0.0, 4.6, h * 0.55), (0.0, 0.0, h * 0.52), 50),
        "face": ((0.35, -1.05, h * 0.93), (0.0, 0.0, h * 0.925), 85),
        "hero": ((1.9, -3.1, h * 0.62), (0.0, 0.0, h * 0.55), 58),   # 3/4 beauty shot
    }
    for name, (pos, target, lens) in shots.items():
        look(pos, target, lens)
        scene.render.filepath = os.path.join(OUT_DIR, f"hero_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)


if __name__ == "__main__":
    body, rig, parts = build_body()
    print("BODY", body.dimensions, "PARTS", sorted(parts))
    outfit = hero_outfit.build(body, rig)
    print("OUTFIT", sorted(outfit))
    if os.environ.get("HERO_RENDER") == "1":
        preview(body)

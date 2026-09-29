"""Headless Blender: join + decimate a generated mesh and export a single OBJ
suitable for Mixamo auto-rigging (geometry only, no rig).
Usage: blender --background --python decimate_for_mixamo.py -- in.glb out.obj [target_faces]
"""
import bpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
inp, outp = argv[0], argv[1]
target = int(argv[2]) if len(argv) > 2 else 60000

bpy.ops.wm.read_factory_settings(use_empty=True)
if inp.lower().endswith((".glb", ".gltf")):
    bpy.ops.import_scene.gltf(filepath=inp)
else:
    bpy.ops.wm.obj_import(filepath=inp)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(False)
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active

before = len(obj.data.polygons)
ratio = min(1.0, target / before) if before else 1.0
mod = obj.modifiers.new("dec", type="DECIMATE")
mod.ratio = ratio
bpy.ops.object.modifier_apply(modifier="dec")
after = len(obj.data.polygons)

bpy.ops.wm.obj_export(
    filepath=outp,
    export_selected_objects=False,
    export_materials=False,
    export_triangulated_mesh=True,
)
print(f"DECIMATED {before} -> {after} faces (ratio {ratio:.3f}); WROTE {outp}")

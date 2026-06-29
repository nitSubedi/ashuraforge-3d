"""Headless Blender: render front + 3/4 preview of a mesh to a PNG.
Usage: blender --background --python render_preview.py -- input.glb output.png
"""
import bpy
import sys
import math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
inp, outp = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
if inp.lower().endswith(".glb") or inp.lower().endswith(".gltf"):
    bpy.ops.import_scene.gltf(filepath=inp)
else:
    bpy.ops.wm.obj_import(filepath=inp)

# Compute combined bounding box of all meshes.
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
coords = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
mn = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
mx = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
center = (mn + mx) / 2
size = (mx - mn)
height = max(size.x, size.y, size.z)

# Neutral material so the untextured mesh reads clearly.
mat = bpy.data.materials.new("preview")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.7, 0.7, 0.72, 1)
bsdf.inputs["Roughness"].default_value = 0.5
for o in objs:
    o.data.materials.clear()
    o.data.materials.append(mat)

# Sun light.
light_data = bpy.data.lights.new("sun", type="SUN")
light_data.energy = 3.0
light = bpy.data.objects.new("sun", light_data)
bpy.context.collection.objects.link(light)
light.rotation_euler = (math.radians(55), 0, math.radians(30))

# Camera, framed on the model from the front, slightly elevated.
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
bpy.context.collection.objects.link(cam)
bpy.context.scene.camera = cam
dist = height * 1.6
cam.location = center + Vector((0, -dist, size.z * 0.1))
# Point camera at center.
direction = center - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
cam_data.lens = 50

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scene.render.resolution_x = 768
scene.render.resolution_y = 1024
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("w")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.06, 1)
scene.render.filepath = outp
bpy.ops.render.render(write_still=True)
print(f"RENDERED {outp}  (model height={height:.3f})")

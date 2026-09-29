"""Model an elegant black walking cane with a hooked (crook) handle.
Glossy-black lacquer shaft + crook, silver ferrule (tip cap) and collar band.
NOT a staff, no magic. Blender Z-up; exports GLB (Godot gets Y-up).

Run: /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/gen/make_cane.py
"""
import bpy
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "weapons", "cane.glb")
OUT = os.path.abspath(OUT)
os.makedirs(os.path.dirname(OUT), exist_ok=True)

# --- clean scene ---
bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, base, rough, metal, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    inp = bsdf.inputs
    inp["Base Color"].default_value = (*base, 1.0)
    inp["Roughness"].default_value = rough
    inp["Metallic"].default_value = metal
    for key, val in (("Coat Weight", coat), ("Coat Roughness", 0.08),
                     ("Specular IOR Level", 0.6)):
        if key in inp:
            inp[key].default_value = val
    return m


black = mat("CaneLacquer", (0.018, 0.018, 0.021), 0.14, 0.0, coat=1.0)
silver = mat("CaneSilver", (0.86, 0.86, 0.90), 0.24, 1.0)

# --- main body: shaft + crook as one bevelled curve ---
# (x, z, radius) in the vertical XZ plane; the crook curls forward in +X.
PTS = [
    (0.000, 0.000, 0.72),  # ferrule tip
    (0.000, 0.780, 0.95),  # up the straight shaft
    (0.000, 0.885, 1.00),  # crook begins
    (0.045, 0.958, 1.02),  # curving forward
    (0.118, 0.975, 1.02),  # over the crown
    (0.170, 0.930, 1.00),  # down the front
    (0.162, 0.862, 0.98),  # hooking back under
    (0.104, 0.845, 0.92),  # curl tip
]

cur = bpy.data.curves.new("CaneCurve", type="CURVE")
cur.dimensions = "3D"
cur.bevel_depth = 0.0135
cur.bevel_resolution = 8
cur.use_fill_caps = True
sp = cur.splines.new("BEZIER")
sp.bezier_points.add(len(PTS) - 1)
for i, (x, z, r) in enumerate(PTS):
    bp = sp.bezier_points[i]
    bp.co = (x, 0.0, z)
    bp.handle_left_type = "AUTO"
    bp.handle_right_type = "AUTO"
    bp.radius = r
cane = bpy.data.objects.new("Cane", cur)
bpy.context.collection.objects.link(cane)
bpy.context.view_layer.objects.active = cane
cane.select_set(True)
bpy.ops.object.convert(target="MESH")
cane = bpy.context.active_object
cane.data.materials.append(black)
bpy.ops.object.shade_smooth()


def add_cylinder(name, radius, depth, z, material, cone_ratio=1.0):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth,
                                        location=(0, 0, z), vertices=32)
    ob = bpy.context.active_object
    ob.name = name
    if cone_ratio != 1.0:  # taper the bottom (ferrule point)
        for v in ob.data.vertices:
            if v.co.z < 0:
                v.co.x *= cone_ratio
                v.co.y *= cone_ratio
    ob.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return ob


# Silver ferrule (worn metal cap at the very bottom, slightly tapered).
add_cylinder("Ferrule", 0.017, 0.06, 0.03, silver, cone_ratio=0.55)
# Silver collar band where the crook meets the shaft.
add_cylinder("Collar", 0.019, 0.035, 0.80, silver)

# --- export ---
for ob in bpy.data.objects:
    ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB",
                          use_selection=True)
print("CANE_EXPORTED", OUT)

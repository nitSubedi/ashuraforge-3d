"""Production cane-sword: a Victorian sword-cane with a hidden estoc blade.

Three parts, exported to one GLB (assets/weapons/cane_sword.glb):
  Hilt   – lacquered crook handle + engraved silver collar + silver end cap
  Sheath – lacquered tapered shaft with a real bore, silver throat ring,
           silver ferrule, worn rubber tip
  Blade  – slim triangular-section estoc, hollow-ground faces, square ricasso,
           acid-etched fuller along the first third, needle point

Every part's origin is the GRIP POINT (hand on the hilt neck), so the sheathed
cane is simply all three parts at identity. Blender is Z-up; Godot gets Y-up.
Detail is authored procedurally, then Cycles-baked to 2K PBR textures
(base colour / ORM / tangent normal) because glTF can't carry node trees.

Run: /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/gen/make_cane_sword.py
"""
import math
import os

import bmesh
import bpy
import numpy as np

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                   "assets", "weapons", "cane_sword.glb"))
TEX = 2048
SEG = 40  # radial segments for turned parts

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ---------------------------------------------------------------- geometry --

def new_obj(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    return ob


def lathe(name, prof, closed=False, seg=SEG):
    """Turn an (r, z) profile around Z. r == 0 points become poles."""
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        if r < 1e-7:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / seg),
                                        r * math.sin(2 * math.pi * i / seg), z))
                          for i in range(seg)])
    pairs = list(zip(rings, rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    return new_obj(name, bm)


def bead(zc, r, h, amp, n=6):
    """Half-round bead (top to bottom) for turned silverwork."""
    return [(r + amp * math.sin(math.pi * k / n), zc + h / 2 - h * k / n)
            for k in range(n + 1)]


def blade():
    """Triangular estoc, hollow-ground faces, with an 'etch' mask attribute."""
    z0, z1 = -0.068, -0.785           # shoulder -> needle point
    length = z0 - z1
    k = 6                             # segments across each face
    n = 72                            # stations along the blade
    bm = bmesh.new()
    etch_vals = []
    rings = []
    for i in range(n):
        s = (i / n) ** 1.15           # denser toward the point
        z = z0 - s * length
        rad = 0.0060 * (1.0 - s) ** 0.85 + 0.00025 * (1.0 - s)
        hollow = 0.00085 * (1.0 - s) ** 1.2
        corners = [(rad * math.cos(a), rad * math.sin(a))
                   for a in (0.0, 2 * math.pi / 3, 4 * math.pi / 3)]
        ring = []
        for f in range(3):
            (ax, ay), (bx, by) = corners[f], corners[(f + 1) % 3]
            for t_i in range(k):
                t = t_i / k
                px, py = ax + (bx - ax) * t, ay + (by - ay) * t
                push = hollow * math.sin(math.pi * t)
                ln = math.hypot(px, py) or 1.0
                px -= px / ln * push
                py -= py / ln * push
                ring.append(bm.verts.new((px, py, z)))
                # Etched fuller: middle third of each face, first third of blade.
                across = max(0.0, 1.0 - abs(t - 0.5) / 0.22)
                along = max(0.0, min(1.0, (0.34 - s) / 0.05)) * min(1.0, s / 0.02)
                etch_vals.append(min(1.0, across * 1.4) * along)
        rings.append(ring)
    tip = bm.verts.new((0.0, 0.0, z1))
    etch_vals.append(0.0)
    m = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for j in range(m):
            bm.faces.new((a[j], a[(j + 1) % m], b[(j + 1) % m], b[j]))
    for j in range(m):
        bm.faces.new((rings[-1][j], rings[-1][(j + 1) % m], tip))
    bm.faces.new(list(reversed(rings[0])))   # cap (hidden in the ricasso)
    ob = new_obj("BladeLoft", bm)
    attr = ob.data.color_attributes.new("etch", "FLOAT_COLOR", "POINT")
    for idx, v in enumerate(etch_vals):
        attr.data[idx].color = (v, v, v, 1.0)
    return ob


def ricasso():
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 0.0074
        v.co.y *= 0.0074
        v.co.z = v.co.z * 0.024 - 0.0565
    ob = new_obj("Ricasso", bm)
    ob.rotation_euler.z = math.radians(45)
    bev = ob.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.0006
    bev.segments = 2
    return ob


def crook():
    """Neck + crook as a swept curve with a thicker crown."""
    pts = [  # (x, z, radius factor)
        (0.000, -0.016, 1.00),
        (0.000, 0.045, 1.00),
        (0.045, 0.118, 1.06),
        (0.118, 0.135, 1.08),
        (0.170, 0.090, 1.04),
        (0.162, 0.022, 0.98),
        (0.104, 0.005, 0.92),
    ]
    cu = bpy.data.curves.new("CrookCurve", "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 14
    cu.bevel_depth = 0.0135
    cu.bevel_resolution = 6
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, (x, z, r) in zip(sp.bezier_points, pts):
        bp.co = (x, 0.0, z)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        bp.radius = r
    ob = bpy.data.objects.new("Crook", cu)
    scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob.select_set(False)
    end = (0.104, 0.005)
    return ob, end, (pts[-2][0], pts[-2][1])


# --------------------------------------------------------------- materials --

CH = {}  # material name -> {"base": socket, "rough": socket, "metal": socket}


def node(nt, kind, **props):
    n = nt.nodes.new(kind)
    for k, v in props.items():
        setattr(n, k, v)
    return n


def math_node(nt, op, a, b=None, c=None):
    n = node(nt, "ShaderNodeMath", operation=op)
    for i, v in enumerate((a, b, c)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def mix_rgb(nt, fac, a, b):
    n = node(nt, "ShaderNodeMix", data_type="RGBA")
    nt.links.new(fac, n.inputs[0])
    n.inputs[6].default_value = (*a, 1.0)
    n.inputs[7].default_value = (*b, 1.0)
    return n.outputs[2]


def value(nt, v):
    n = node(nt, "ShaderNodeValue")
    n.outputs[0].default_value = v
    return n.outputs[0]


def rgb(nt, c):
    n = node(nt, "ShaderNodeRGB")
    n.outputs[0].default_value = (*c, 1.0)
    return n.outputs[0]


def material(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    obj_co = node(nt, "ShaderNodeTexCoord").outputs["Object"]
    base, rough, metal, height, coat = build(nt, obj_co)
    nt.links.new(base, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    nt.links.new(metal, bsdf.inputs["Metallic"])
    bump = node(nt, "ShaderNodeBump", invert=True)
    bump.inputs["Strength"].default_value = height[1]
    bump.inputs["Distance"].default_value = height[2]
    nt.links.new(height[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Coat Weight"].default_value = coat
    CH[name] = {"base": base, "rough": rough, "metal": metal, "coat": coat}
    return m


def noise(nt, co, scale, detail=4.0, stretch=None):
    n = node(nt, "ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    if stretch:
        mp = node(nt, "ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        nt.links.new(co, mp.inputs["Vector"])
        co = mp.outputs[0]
    nt.links.new(co, n.inputs["Vector"])
    return n.outputs["Fac"]


def engraving(nt, co, scale, lo=0.47, hi=0.53, distortion=3.5):
    """Flowing scrollwork: gently distorted rings, thresholded to thin cuts."""
    # Warp the ring field with low-frequency noise so lines curl into scrolls
    # instead of running as straight bands around the axis.
    warp = node(nt, "ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = scale * 0.45
    warp.inputs["Detail"].default_value = 1.0
    nt.links.new(co, warp.inputs["Vector"])
    centred = node(nt, "ShaderNodeVectorMath", operation="SUBTRACT")
    nt.links.new(warp.outputs["Color"], centred.inputs[0])
    centred.inputs[1].default_value = (0.5, 0.5, 0.5)
    amt = node(nt, "ShaderNodeVectorMath", operation="SCALE")
    nt.links.new(centred.outputs[0], amt.inputs[0])
    amt.inputs["Scale"].default_value = 2.2 / scale
    warped = node(nt, "ShaderNodeVectorMath", operation="ADD")
    nt.links.new(co, warped.inputs[0])
    nt.links.new(amt.outputs[0], warped.inputs[1])
    co = warped.outputs[0]
    w = node(nt, "ShaderNodeTexWave", wave_type="RINGS")
    w.inputs["Scale"].default_value = scale
    w.inputs["Distortion"].default_value = distortion
    w.inputs["Detail"].default_value = 1.0
    w.inputs["Detail Scale"].default_value = 1.2
    nt.links.new(co, w.inputs["Vector"])
    ramp = node(nt, "ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = lo - 0.03, (0, 0, 0, 1)
    els[1].position, els[1].color = lo, (1, 1, 1, 1)
    e2 = els.new(hi)
    e2.color = (1, 1, 1, 1)
    e3 = els.new(hi + 0.03)
    e3.color = (0, 0, 0, 1)
    nt.links.new(w.outputs["Fac"], ramp.inputs["Fac"])
    return ramp.outputs["Color"]


def build_lacquer(nt, co):
    depth = noise(nt, co, 14.0)
    base = mix_rgb(nt, depth, (0.009, 0.009, 0.010), (0.018, 0.016, 0.015))
    rough = math_node(nt, "MULTIPLY_ADD", noise(nt, co, 22.0), 0.07, 0.05)
    peel = noise(nt, co, 900.0, 2.0)                    # orange-peel lacquer
    return base, rough, value(nt, 0.0), (peel, 0.035, 0.0002), 1.0


def build_silver(nt, co):
    # Mask: only faces whose normal is near-horizontal (the flat bands), so the
    # beaded rims and end caps stay mirror-polished.
    nrm = node(nt, "ShaderNodeNewGeometry").outputs["Normal"]
    sep = node(nt, "ShaderNodeSeparateXYZ")
    nt.links.new(nrm, sep.inputs[0])
    flat = math_node(nt, "LESS_THAN", math_node(nt, "ABSOLUTE", sep.outputs["Z"]), 0.25)
    eng_raw = node(nt, "ShaderNodeRGBToBW")
    nt.links.new(engraving(nt, co, 60.0), eng_raw.inputs[0])
    eng = math_node(nt, "MULTIPLY", eng_raw.outputs[0], flat)
    tarnish = noise(nt, co, 60.0, 6.0)
    bright = mix_rgb(nt, tarnish, (0.86, 0.85, 0.83), (0.66, 0.63, 0.58))
    base_n = node(nt, "ShaderNodeMix", data_type="RGBA")
    nt.links.new(eng, base_n.inputs[0])
    nt.links.new(bright, base_n.inputs[6])
    base_n.inputs[7].default_value = (0.09, 0.08, 0.07, 1.0)   # dark cavity fill
    rough = math_node(nt, "MULTIPLY_ADD", eng, 0.38, 0.18)
    rough = math_node(nt, "ADD", rough, math_node(nt, "MULTIPLY", tarnish, 0.08))
    metal = math_node(nt, "MULTIPLY_ADD", eng, -0.35, 1.0)
    return base_n.outputs[2], rough, metal, (eng, 0.55, 0.0004), 0.0


def build_steel(nt, co):
    streak = noise(nt, co, 3.0, 8.0, stretch=(420.0, 420.0, 2.0))  # brushed along the blade
    attr = node(nt, "ShaderNodeAttribute", attribute_name="etch").outputs["Fac"]
    vines = node(nt, "ShaderNodeRGBToBW")
    nt.links.new(engraving(nt, co, 140.0, 0.44, 0.56, 5.0), vines.inputs[0])
    frost = noise(nt, co, 700.0, 3.0)
    etched = math_node(nt, "MULTIPLY", attr,
                       math_node(nt, "MULTIPLY_ADD", vines.outputs[0], 0.55, 0.45))
    etched = math_node(nt, "MULTIPLY", etched, math_node(nt, "MULTIPLY_ADD", frost, 0.4, 0.8))
    base_n = node(nt, "ShaderNodeMix", data_type="RGBA")
    nt.links.new(etched, base_n.inputs[0])
    base_n.inputs[6].default_value = (0.72, 0.73, 0.76, 1.0)
    base_n.inputs[7].default_value = (0.24, 0.24, 0.26, 1.0)
    rough = math_node(nt, "MULTIPLY_ADD", streak, 0.08, 0.10)
    rough = math_node(nt, "ADD", rough, math_node(nt, "MULTIPLY", etched, 0.38))
    height = math_node(nt, "ADD", math_node(nt, "MULTIPLY", streak, 0.08), etched)
    return base_n.outputs[2], rough, value(nt, 1.0), (height, 0.45, 0.0003), 0.0


def build_rubber(nt, co):
    grit = noise(nt, co, 320.0, 4.0)
    base = mix_rgb(nt, grit, (0.018, 0.017, 0.016), (0.045, 0.041, 0.038))
    rough = math_node(nt, "MULTIPLY_ADD", grit, 0.15, 0.72)
    return base, rough, value(nt, 0.0), (grit, 0.25, 0.0004), 0.0


LACQUER = material("Lacquer", build_lacquer)
SILVER = material("Silver", build_silver)
STEEL = material("Steel", build_steel)
RUBBER = material("Rubber", build_rubber)


def assign(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)


# ------------------------------------------------------------------- parts --

def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        o.select_set(False)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        o.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
    wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=wn.name)
    ob.select_set(False)
    return ob


# Hilt: crook + engraved collar + end cap on the curl.
crook_ob, end, prev = crook()
assign(crook_ob, LACQUER)
collar = lathe("Collar",
               [(0.0, -0.045), (0.0138, -0.045), (0.0146, -0.0447)]
               + bead(-0.0418, 0.0147, 0.0046, 0.0011)
               + [(0.0148, -0.0392), (0.0148, -0.0196)]
               + bead(-0.0170, 0.0147, 0.0046, 0.0011)
               + [(0.0141, -0.0146), (0.0136, -0.0120), (0.0, -0.0120)])
assign(collar, SILVER)
cap = lathe("Cap", [(0.0, -0.002), (0.0134, -0.002), (0.0146, 0.001), (0.0142, 0.004)]
            + bead(0.0065, 0.0132, 0.004, 0.0008, 4)
            + [(0.0105, 0.0095), (0.0060, 0.0118), (0.0, 0.0124)])
assign(cap, SILVER)
tx, tz = end[0] - prev[0], end[1] - prev[1]
cap.rotation_euler = (0.0, math.atan2(tx, tz), 0.0)   # local +Z along the curl
cap.location = (end[0], 0.0, end[1])
hilt = join("Hilt", [crook_ob, collar, cap])

# Sheath: tube with a bore, throat ring, ferrule, rubber tip.
tube = lathe("Tube", [(0.0, -0.790), (0.0063, -0.790), (0.0063, -0.066), (0.0136, -0.066),
                      (0.0131, -0.200), (0.0124, -0.420), (0.0117, -0.640), (0.0112, -0.795),
                      (0.0, -0.795)])
assign(tube, LACQUER)
throat = lathe("Throat", [(0.0063, -0.0452), (0.0141, -0.0452), (0.0148, -0.0458)]
               + bead(-0.0490, 0.0148, 0.0050, 0.0010)
               + [(0.0146, -0.0525), (0.0143, -0.0640), (0.0139, -0.0685), (0.0063, -0.0685)],
               closed=True)
assign(throat, SILVER)
ferrule = lathe("Ferrule", [(0.0, -0.7825), (0.0117, -0.7825), (0.0122, -0.7855)]
                + bead(-0.7890, 0.0122, 0.004, 0.0007, 4)
                + [(0.0119, -0.800), (0.0100, -0.8255), (0.0093, -0.8290), (0.0, -0.8290)])
assign(ferrule, SILVER)
tip = lathe("Tip", [(0.0, -0.8280), (0.0089, -0.8280), (0.0091, -0.8320), (0.0085, -0.8370),
                    (0.0060, -0.8392), (0.0, -0.8395)])
assign(tip, RUBBER)
sheath = join("Sheath", [tube, throat, ferrule, tip])

# Blade: ricasso + triangular estoc.
loft = blade()
assign(loft, STEEL)
bev = loft.modifiers.new("Bevel", "BEVEL")
bev.limit_method = "ANGLE"
bev.angle_limit = math.radians(40)
bev.width = 0.00022
bev.segments = 2
ric = ricasso()
assign(ric, STEEL)
blade_ob = join("Blade", [loft, ric])

PARTS = [hilt, sheath, blade_ob]


# -------------------------------------------------------------------- bake --

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.render.bake.margin = 16


def only(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def unwrap(ob):
    only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


def image(name, non_color, fill=(0, 0, 0, 1)):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False)
    img.generated_color = fill
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def set_target(mats, img):
    for m in mats:
        nt = m.node_tree
        n = nt.nodes.get("BakeTarget") or node(nt, "ShaderNodeTexImage", name="BakeTarget")
        n.image = img
        nt.nodes.active = n


def bake_channel(ob, mats, ch, img):
    set_target(mats, img)
    saved = []
    for m in mats:
        nt = m.node_tree
        out = nt.nodes["Material Output"]
        em = node(nt, "ShaderNodeEmission")
        src = CH[m.name][ch]
        # Scalars feed the emission colour as grey.
        nt.links.new(src, em.inputs["Color"])
        saved.append((nt, out, em))
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    only(ob)
    bpy.ops.object.bake(type="EMIT")
    for nt, out, em in saved:
        nt.links.new(nt.nodes["Principled BSDF"].outputs[0], out.inputs["Surface"])
        nt.nodes.remove(em)


def pixels(img):
    a = np.empty(TEX * TEX * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(-1, 4)


def bake_part(ob):
    unwrap(ob)
    mats = [s.material for s in ob.material_slots]
    base = image(f"{ob.name}_BaseColor", False)
    rough = image(f"{ob.name}_r", True)
    metal = image(f"{ob.name}_m", True)
    orm = image(f"{ob.name}_ORM", True)
    nrm = image(f"{ob.name}_Normal", True, (0.5, 0.5, 1.0, 1.0))
    bake_channel(ob, mats, "base", base)
    bake_channel(ob, mats, "rough", rough)
    bake_channel(ob, mats, "metal", metal)
    set_target(mats, nrm)
    only(ob)
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
    # Pack glTF ORM: R = occlusion (1), G = roughness, B = metallic.
    packed = np.ones((TEX * TEX, 4), dtype=np.float32)
    packed[:, 1] = pixels(rough)[:, 0]
    packed[:, 2] = pixels(metal)[:, 0]
    orm.pixels.foreach_set(packed.ravel())
    for img in (base, orm, nrm):
        img.pack()
    bpy.data.images.remove(rough)
    bpy.data.images.remove(metal)
    # Swap every slot to a baked material (same atlas; lacquer keeps its clear coat).
    for slot in ob.material_slots:
        src = slot.material
        m = bpy.data.materials.new(f"{ob.name}_{src.name}")
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tb = node(nt, "ShaderNodeTexImage", image=base)
        to = node(nt, "ShaderNodeTexImage", image=orm)
        tn = node(nt, "ShaderNodeTexImage", image=nrm)
        sep = node(nt, "ShaderNodeSeparateColor")
        nm = node(nt, "ShaderNodeNormalMap")
        nt.links.new(tb.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(to.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Coat Weight"].default_value = CH[src.name]["coat"]
        bsdf.inputs["Coat Roughness"].default_value = 0.04
        slot.material = m
    if "etch" in ob.data.color_attributes:
        ob.data.color_attributes.remove(ob.data.color_attributes["etch"])


for part in PARTS:
    bake_part(part)
    print(f"BAKED {part.name}")

# ------------------------------------------------------------------ export --

total = 0
dg = bpy.context.evaluated_depsgraph_get()
for part in PARTS:
    me = part.evaluated_get(dg).to_mesh()
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    total += tris
    print(f"PART {part.name}: {tris} tris")
    part.evaluated_get(dg).to_mesh_clear()
print(f"TOTAL_TRIS {total}")

bpy.ops.object.select_all(action="DESELECT")
for part in PARTS:
    part.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
                          export_apply=True, export_image_format="AUTO")
print("CANE_SWORD_EXPORTED", OUT)

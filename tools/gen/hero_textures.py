"""Hero texture pass: procedural surface detail, tattoos, eye/hair tweaks, then
Cycles bakes of everything into glTF-ready PBR maps.

  detail()   – wool twill + heather, leather grain + worn edges, lining sheen,
               silver tarnish (procedural, node-based)
  tattoos()  – blackwork sacred-geometry mandala over the sternum (the coat
               hangs open over the chest)
  eyes()     – iris hue-shifted to amber-gold
  bake_all() – per object: base colour (+alpha), ORM, tangent normal ->
               a simple Principled material the glTF exporter understands.
"""
import math
import os

import bpy
import numpy as np
from mathutils import Vector


# ------------------------------------------------------------- node helpers --

def _n(nt, kind, **props):
    node = nt.nodes.new(kind)
    for k, v in props.items():
        setattr(node, k, v)
    return node


def _link(nt, a, b):
    nt.links.new(a, b)


def _math(nt, op, a, b=None, c=None):
    m = _n(nt, "ShaderNodeMath", operation=op)
    for i, v in enumerate((a, b, c)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            m.inputs[i].default_value = v
        else:
            _link(nt, v, m.inputs[i])
    return m.outputs[0]


def _noise(nt, co, scale, detail=4.0, stretch=None):
    n = _n(nt, "ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    if stretch:
        mp = _n(nt, "ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        _link(nt, co, mp.inputs["Vector"])
        co = mp.outputs[0]
    _link(nt, co, n.inputs["Vector"])
    return n.outputs["Fac"]


def _bsdf(mat):
    return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def _bump(nt, bsdf, height, strength, distance):
    b = _n(nt, "ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    b.inputs["Distance"].default_value = distance
    _link(nt, height, b.inputs["Height"])
    _link(nt, b.outputs["Normal"], bsdf.inputs["Normal"])


def _mix_col(nt, fac, a, b):
    m = _n(nt, "ShaderNodeMix", data_type="RGBA")
    _link(nt, fac, m.inputs[0])
    for idx, v in ((6, a), (7, b)):
        if isinstance(v, tuple):
            m.inputs[idx].default_value = (*v, 1.0)
        else:
            _link(nt, v, m.inputs[idx])
    return m.outputs[2]


# ---------------------------------------------------------------- detail --

def detail():
    """Upgrade the flat outfit materials with woven / grained surface detail."""
    def upgrade(name, fn):
        m = bpy.data.materials.get(name)
        if m:
            nt = m.node_tree
            co = _n(nt, "ShaderNodeTexCoord").outputs["Object"]
            fn(nt, _bsdf(m), co, tuple(_bsdf(m).inputs["Base Color"].default_value)[:3])

    def wool(nt, bsdf, co, base):
        # Twill: diagonal ribs + fine heather fibres + large-scale tone drift.
        ribs = _n(nt, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL")
        ribs.inputs["Scale"].default_value = 900.0
        ribs.inputs["Distortion"].default_value = 1.5
        _link(nt, co, ribs.inputs["Vector"])
        heather = _noise(nt, co, 1400.0, 2.0)
        drift = _noise(nt, co, 6.0, 3.0)
        dark = tuple(c * 0.55 for c in base)
        light = tuple(min(1.0, c * 2.4 + 0.012) for c in base)
        col = _mix_col(nt, _math(nt, "MULTIPLY", heather, drift), dark, light)
        _link(nt, col, bsdf.inputs["Base Color"])
        _link(nt, _math(nt, "MULTIPLY_ADD", ribs.outputs["Fac"], 0.12, 0.6), bsdf.inputs["Roughness"])
        _bump(nt, bsdf, _math(nt, "ADD", ribs.outputs["Fac"], _math(nt, "MULTIPLY", heather, 0.5)), 0.35, 0.0006)

    def leather(nt, bsdf, co, base):
        grain = _n(nt, "ShaderNodeTexVoronoi", feature="SMOOTH_F1")
        grain.inputs["Scale"].default_value = 480.0
        _link(nt, co, grain.inputs["Vector"])
        wear = _noise(nt, co, 14.0, 6.0)
        edge = _n(nt, "ShaderNodeNewGeometry").outputs["Pointiness"]
        worn = _math(nt, "MULTIPLY", _math(nt, "GREATER_THAN", edge, 0.6),
                     _math(nt, "GREATER_THAN", wear, 0.62))
        col = _mix_col(nt, _math(nt, "MULTIPLY", worn, 0.45), base, (0.07, 0.055, 0.045))  # edge scuffs only
        _link(nt, col, bsdf.inputs["Base Color"])
        _link(nt, _math(nt, "MULTIPLY_ADD", grain.outputs["Distance"], 0.25, 0.32), bsdf.inputs["Roughness"])
        _bump(nt, bsdf, grain.outputs["Distance"], 0.4, 0.0004)

    def silk(nt, bsdf, co, base):
        weave = _noise(nt, co, 2000.0, 1.0, stretch=(1.0, 1.0, 12.0))
        _link(nt, _mix_col(nt, weave, base, tuple(c * 1.6 for c in base)), bsdf.inputs["Base Color"])
        _link(nt, _math(nt, "MULTIPLY_ADD", weave, 0.1, 0.3), bsdf.inputs["Roughness"])

    def cloth(nt, bsdf, co, base):
        fib = _noise(nt, co, 1100.0, 2.0)
        _link(nt, _mix_col(nt, fib, tuple(c * 0.7 for c in base), tuple(c * 1.5 for c in base)), bsdf.inputs["Base Color"])
        _bump(nt, bsdf, fib, 0.25, 0.0004)

    def silver(nt, bsdf, co, base):
        tarnish = _noise(nt, co, 90.0, 5.0)
        _link(nt, _mix_col(nt, tarnish, base, (0.33, 0.3, 0.26)), bsdf.inputs["Base Color"])
        _link(nt, _math(nt, "MULTIPLY_ADD", tarnish, 0.3, 0.18), bsdf.inputs["Roughness"])

    upgrade("CoatWool", wool)
    upgrade("CharcoalBreeches", cloth)
    upgrade("CrimsonSash", cloth)
    upgrade("CrimsonLining", silk)
    upgrade("BlackLeather", leather)
    upgrade("AntiqueSilver", silver)


# --------------------------------------------------------------- tattoos --

def tattoos(body, sternum, neck_z):
    """Blackwork ink mixed into the skin's base colour (object-space pattern)."""
    for slot in body.material_slots:
        mat = slot.material
        nt = mat.node_tree
        bsdf = _bsdf(mat)
        src = bsdf.inputs["Base Color"].links[0].from_socket if bsdf.inputs["Base Color"].is_linked else None
        co = _n(nt, "ShaderNodeTexCoord").outputs["Object"]
        # Offset from the sternum (x right, z up), on the chest's front.
        sep = _n(nt, "ShaderNodeSeparateXYZ")
        _link(nt, co, sep.inputs[0])
        dx = _math(nt, "SUBTRACT", sep.outputs["X"], sternum.x)
        dz = _math(nt, "SUBTRACT", sep.outputs["Z"], sternum.z)
        front = _math(nt, "LESS_THAN", sep.outputs["Y"], sternum.y + 0.05)
        r = _math(nt, "SQRT", _math(nt, "ADD", _math(nt, "MULTIPLY", dx, dx), _math(nt, "MULTIPLY", dz, dz)))
        ang = _math(nt, "ARCTAN2", dz, dx)
        # Mandala: thin rings + 16 spokes + a petal ring, inside r < 0.11.
        rings = _math(nt, "LESS_THAN", _math(nt, "ABSOLUTE", _math(nt, "SINE", _math(nt, "MULTIPLY", r, 150.0))), 0.2)
        spokes = _math(nt, "LESS_THAN", _math(nt, "ABSOLUTE", _math(nt, "SINE", _math(nt, "MULTIPLY", ang, 8.0))), 0.09)
        petal_r = _math(nt, "MULTIPLY_ADD", _math(nt, "ABSOLUTE", _math(nt, "SINE", _math(nt, "MULTIPLY", ang, 6.0))), 0.03, 0.045)
        petals = _math(nt, "LESS_THAN", _math(nt, "ABSOLUTE", _math(nt, "SUBTRACT", r, petal_r)), 0.004)
        core = _math(nt, "LESS_THAN", r, 0.012)
        mandala = _math(nt, "MAXIMUM", _math(nt, "MAXIMUM", _math(nt, "MULTIPLY", rings, _math(nt, "LESS_THAN", r, 0.11)),
                                                  _math(nt, "MULTIPLY", spokes, _math(nt, "LESS_THAN", r, 0.075))),
                        _math(nt, "MAXIMUM", petals, core))
        # Filigree across the pecs + up the neck: warped ring lines (like the cane).
        warp = _n(nt, "ShaderNodeTexNoise")
        warp.inputs["Scale"].default_value = 18.0
        _link(nt, co, warp.inputs["Vector"])
        wv = _n(nt, "ShaderNodeVectorMath", operation="ADD")
        _link(nt, co, wv.inputs[0])
        sc = _n(nt, "ShaderNodeVectorMath", operation="SCALE")
        _link(nt, warp.outputs["Color"], sc.inputs[0])
        sc.inputs["Scale"].default_value = 0.05
        _link(nt, sc.outputs[0], wv.inputs[1])
        wave = _n(nt, "ShaderNodeTexWave", wave_type="RINGS")
        wave.inputs["Scale"].default_value = 14.0            # bolder, sparser blackwork
        wave.inputs["Distortion"].default_value = 3.0
        _link(nt, wv.outputs[0], wave.inputs["Vector"])
        fil = _math(nt, "LESS_THAN", _math(nt, "ABSOLUTE", _math(nt, "SUBTRACT", wave.outputs["Fac"], 0.5)), 0.07)
        pec_zone = _math(nt, "MULTIPLY", _math(nt, "LESS_THAN", r, 0.24), _math(nt, "GREATER_THAN", r, 0.12))
        # Neck: collarbones up to mid-neck only — never onto the jaw/face.
        neck_zone = _math(nt, "MULTIPLY", _math(nt, "GREATER_THAN", sep.outputs["Z"], neck_z - 0.07),
                          _math(nt, "LESS_THAN", sep.outputs["Z"], neck_z + 0.015))
        filigree = _math(nt, "MULTIPLY", fil, _math(nt, "MAXIMUM", pec_zone, neck_zone))
        # Filigree read as skin wrinkles at game scale — mandala only for now.
        ink = _math(nt, "MULTIPLY", mandala, front)
        ink = _math(nt, "MINIMUM", ink, 1.0)
        base = src if src is not None else _n(nt, "ShaderNodeRGB").outputs[0]
        col = _mix_col(nt, _math(nt, "MULTIPLY", ink, 0.88), base, (0.025, 0.03, 0.04))   # faded blue-black ink
        _link(nt, col, bsdf.inputs["Base Color"])


# -------------------------------------------------------------- eyes/hair --

def eyes(eye_ob):
    for slot in eye_ob.material_slots:
        nt = slot.material.node_tree
        bsdf = _bsdf(slot.material)
        if not bsdf.inputs["Base Color"].is_linked:
            continue
        src = bsdf.inputs["Base Color"].links[0].from_socket
        hsv = _n(nt, "ShaderNodeHueSaturation")
        hsv.inputs["Hue"].default_value = 0.56      # brown -> amber-gold
        hsv.inputs["Saturation"].default_value = 1.5
        hsv.inputs["Value"].default_value = 1.25
        _link(nt, src, hsv.inputs["Color"])
        _link(nt, hsv.outputs["Color"], bsdf.inputs["Base Color"])


# ------------------------------------------------------------------ bake --

def _only(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def join(objs, name):
    _only(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    return ob


def _image(name, size, non_color, alpha=False, fill=(0, 0, 0, 1)):
    img = bpy.data.images.new(name, size, size, alpha=alpha)
    img.generated_color = fill
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def _px(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(-1, 4)


def _src(bsdf, name, default):
    s = bsdf.inputs[name]
    return s.links[0].from_socket if s.is_linked else default


def bake_object(ob, size, out_dir, unwrap=False, alpha=False):
    """Bake every material on ob into one texture set; swap to glTF materials."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 8
    scene.render.bake.margin = 12
    _only(ob)
    for m in list(ob.modifiers):
        if m.type in ("SOLIDIFY", "SUBSURF", "BEVEL"):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError:          # no-op/disabled (e.g. MPFB's level-0 subdiv)
                ob.modifiers.remove(m)
    if unwrap or not ob.data.uv_layers:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(62), island_margin=0.003)
        bpy.ops.object.mode_set(mode="OBJECT")
    mats = [s.material for s in ob.material_slots if s.material]
    if not mats:
        return
    imgs = {k: _image(f"{ob.name}_{k}", size, k != "base", fill=(0.5, 0.5, 1, 1) if k == "normal" else (0, 0, 0, 1))
            for k in ("base", "alpha", "rough", "metal", "normal")}
    # Only cards (hair/brows/lashes) get alpha; MPFB links alpha on skin too.
    has_alpha = alpha and any(_bsdf(m).inputs["Alpha"].is_linked for m in mats)

    def target(img):
        for m in mats:
            nt = m.node_tree
            t = nt.nodes.get("BakeTarget") or _n(nt, "ShaderNodeTexImage", name="BakeTarget")
            t.image = img
            nt.nodes.active = t

    def emit(channel, img):
        target(img)
        saved = []
        for m in mats:
            nt = m.node_tree
            bsdf = _bsdf(m)
            out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
            prev = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].is_linked else None
            em = _n(nt, "ShaderNodeEmission")
            inp = bsdf.inputs[channel]
            if inp.is_linked:
                _link(nt, inp.links[0].from_socket, em.inputs["Color"])
            else:
                v = inp.default_value
                em.inputs["Color"].default_value = (*v[:3], 1) if hasattr(v, "__len__") else (v, v, v, 1)
            _link(nt, em.outputs[0], out.inputs["Surface"])
            saved.append((nt, out, em, prev))
        _only(ob)
        bpy.ops.object.bake(type="EMIT")
        for nt, out, em, prev in saved:
            if prev is not None:
                _link(nt, prev, out.inputs["Surface"])
            nt.nodes.remove(em)

    emit("Base Color", imgs["base"])
    emit("Roughness", imgs["rough"])
    emit("Metallic", imgs["metal"])
    if has_alpha:
        emit("Alpha", imgs["alpha"])
    target(imgs["normal"])
    _only(ob)
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")

    base = _px(imgs["base"])
    if has_alpha:
        base[:, 3] = _px(imgs["alpha"])[:, 0]
        imgs["base"].alpha_mode = "STRAIGHT"
    imgs["base"].pixels.foreach_set(base.ravel())
    orm = np.ones_like(base)
    orm[:, 1] = _px(imgs["rough"])[:, 0]
    orm[:, 2] = _px(imgs["metal"])[:, 0]
    imgs["rough"].pixels.foreach_set(orm.ravel())   # reuse as ORM
    orm_img = imgs["rough"]
    orm_img.name = f"{ob.name}_ORM"
    for k in ("base", "normal"):
        imgs[k].name = f"{ob.name}_{'BaseColor' if k == 'base' else 'Normal'}"
    for img in (imgs["base"], orm_img, imgs["normal"]):
        img.filepath_raw = os.path.join(out_dir, img.name + ".png")
        img.file_format = "PNG"
        img.save()
    for k in ("alpha", "metal"):
        bpy.data.images.remove(imgs[k])

    m = bpy.data.materials.new(f"{ob.name}_Baked")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = _bsdf(m)
    tb = _n(nt, "ShaderNodeTexImage", image=imgs["base"])
    to = _n(nt, "ShaderNodeTexImage", image=orm_img)
    tn = _n(nt, "ShaderNodeTexImage", image=imgs["normal"])
    sepc = _n(nt, "ShaderNodeSeparateColor")
    nm = _n(nt, "ShaderNodeNormalMap")
    _link(nt, tb.outputs["Color"], bsdf.inputs["Base Color"])
    _link(nt, to.outputs["Color"], sepc.inputs["Color"])
    _link(nt, sepc.outputs["Green"], bsdf.inputs["Roughness"])
    _link(nt, sepc.outputs["Blue"], bsdf.inputs["Metallic"])
    _link(nt, tn.outputs["Color"], nm.inputs["Color"])
    _link(nt, nm.outputs["Normal"], bsdf.inputs["Normal"])
    if has_alpha:   # alpha clip -> glTF MASK (hair cards, brows, lashes)
        _link(nt, _math(nt, "ROUND", tb.outputs["Alpha"]), bsdf.inputs["Alpha"])
    ob.data.materials.clear()
    ob.data.materials.append(m)
    print(f"BAKED {ob.name} ({size}px, alpha={has_alpha})")

"""Hero outfit, generated from the MPFB body so everything fits by construction.

  greatcoat  – torso + sleeves pushed off the body, open V front, crimson
               lining (solidify inner shell), crimson turned cuffs; flared
               skirt from waist to mid-calf, split front, on coat_* bone chains
  collar     – high stand collar, open at the throat
  hood       – worn down, bunched on the upper back
  breeches, riding boots (smoothed toes, heel, fold-over cuff), gloves,
  bracers, two crossed hip belts with silver buckles, crimson waist sash.

Body faces hidden under tight garments are deleted (no poke-through).
Blender Z-up; the MPFB human faces -Y (his left is +X).
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector

WAIST_PAD = 0.03


# ------------------------------------------------------------- materials --

def _mat(name, color, rough, metal=0.0, sheen=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Sheen Weight" in b.inputs:
        b.inputs["Sheen Weight"].default_value = sheen
    return m


def materials():
    return {
        "coat": _mat("CoatWool", (0.008, 0.0075, 0.009), 0.66, sheen=0.05),
        "lining": _mat("CrimsonLining", (0.11, 0.004, 0.009), 0.38),
        "leather": _mat("BlackLeather", (0.022, 0.019, 0.018), 0.42),
        "breeches": _mat("CharcoalBreeches", (0.045, 0.044, 0.05), 0.82, sheen=0.2),
        "sash": _mat("CrimsonSash", (0.12, 0.006, 0.011), 0.62),
        "silver": _mat("AntiqueSilver", (0.72, 0.70, 0.66), 0.26, metal=1.0),
    }


# ----------------------------------------------------------------- helpers --

class Body:
    """Evaluated body mesh + per-vertex bone weights + rig landmarks."""

    def __init__(self, body, rig):
        self.obj, self.rig = body, rig
        me = body.data
        self.co = np.array([v.co[:] for v in me.vertices])
        self.no = np.array([v.normal[:] for v in me.vertices])
        self.groups = {g.index: g.name for g in body.vertex_groups}
        self.w = {}
        for v in me.vertices:
            for g in v.groups:
                name = self.groups[g.group]
                if name.startswith("mixamorig:"):
                    self.w.setdefault(name[10:], np.zeros(len(me.vertices)))[v.index] = g.weight

    def weight(self, *bones):
        out = np.zeros(len(self.co))
        for b in bones:
            for side in ("", "Left", "Right"):
                if side + b in self.w:
                    out += self.w[side + b]
        return out

    def z(self, bone):
        return self.rig.data.bones["mixamorig:" + bone].head_local.z

    def head(self, bone):
        return Vector(self.rig.data.bones["mixamorig:" + bone].head_local)

    def contour(self, mask, z0, bins=64, band=0.012, center=None):
        """Outer radius per angle of the masked body slice at height z0."""
        sel = mask & (np.abs(self.co[:, 2] - z0) < band)
        pts = self.co[sel]
        if center is None:
            center = pts[:, :2].mean(axis=0) if len(pts) else np.zeros(2)
        r = np.full(bins, np.nan)
        if len(pts):
            d = pts[:, :2] - center
            ang = (np.arctan2(d[:, 1], d[:, 0]) % (2 * math.pi)) / (2 * math.pi) * bins
            rad = np.hypot(d[:, 0], d[:, 1])
            for a, rr in zip(ang.astype(int) % bins, rad):
                if np.isnan(r[a]) or rr > r[a]:
                    r[a] = rr
        good = ~np.isnan(r)
        if good.sum() < 3:
            return center, np.full(bins, 0.15)
        idx = np.arange(bins)
        r = np.interp(idx, idx[good], r[good], period=bins)
        for _ in range(3):  # circular smoothing
            r = (np.roll(r, 1) + 2 * r + np.roll(r, -1)) / 4
        return center, r


def _new_obj(name, bm, mat_list):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mat_list:
        ob.data.materials.append(m)
    return ob


def _region_shell(B, name, vmask, offset, mats):
    """Copy the body faces whose verts are all in vmask, pushed out by offset."""
    bm = bmesh.new()
    bm.from_mesh(B.obj.data)
    bm.verts.ensure_lookup_table()
    keep = set(i for i in np.nonzero(vmask)[0])
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not all(v.index in keep for v in f.verts)],
                     context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for v in bm.verts:
        v.co += v.normal * offset
    for f in bm.faces:
        f.material_index = 0
    return _new_obj(name, bm, mats)


def _solidify(ob, thickness, inner_mat_offset=0, rim_mat_offset=0, even=True):
    """Thickness grows inward (normals point out), so the new inner shell takes
    the lining material and the outer surface keeps the garment material."""
    m = ob.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = thickness
    m.offset = -1.0
    m.use_even_offset = even   # off for tiny faces (fingers), else it spikes
    m.material_offset = inner_mat_offset
    m.material_offset_rim = rim_mat_offset
    return m


def _ring_band(B, name, mask, z_of_theta, height, pad, mats, bins=64, gap=None, center=None):
    """A ribbon (belt/sash/collar) hugging a body contour; z may vary with angle."""
    bm = bmesh.new()
    rows = []
    for k in (0, 1):
        row = []
        for i in range(bins + (0 if gap is None else 1)):
            th = 2 * math.pi * i / bins
            if gap is not None and _in_gap(th, gap):
                row.append(None)
                continue
            z = z_of_theta(th) + (height if k else 0.0)
            c, r = B.contour(mask, z, bins, center=center)
            rr = r[i % bins] + pad
            row.append(bm.verts.new((c[0] + rr * math.cos(th), c[1] + rr * math.sin(th), z)))
        rows.append(row)
    n = len(rows[0])
    for i in range(n if gap is None else n - 1):
        a, b = rows[0][i], rows[0][(i + 1) % n]
        c, d = rows[1][(i + 1) % n], rows[1][i]
        if None not in (a, b, c, d):
            bm.faces.new((a, b, c, d))
    return _new_obj(name, bm, mats)


FRONT = -math.pi / 2  # the body faces -Y


def _in_gap(theta, half):
    d = (theta - FRONT + math.pi) % (2 * math.pi) - math.pi
    return abs(d) < half


def _transfer_weights(ob, B):
    for g in B.obj.vertex_groups:
        if g.name.startswith("mixamorig:") and g.name not in ob.vertex_groups:
            ob.vertex_groups.new(name=g.name)
    dt = ob.modifiers.new("Weights", "DATA_TRANSFER")
    dt.object = B.obj
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    _apply_all(ob)


def _apply_all(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        if m.type != "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=m.name)


def _bind(ob, rig):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    ob.select_set(False)
    ob.parent = rig
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rig


# ------------------------------------------------------------------ pieces --

def build(body, rig):
    """Create every garment, bind to the rig, hide covered body. Returns objects."""
    M = materials()
    B = Body(body, rig)
    waist = B.z("Spine") + 0.02
    knee = B.z("LeftLeg")
    hem = knee - 0.2
    neck = B.z("Neck")
    torso_bones = B.weight("Spine", "Spine1", "Spine2", "Shoulder", "Arm", "ForeArm", "Neck")
    hand_w = B.weight("Hand", "HandThumb1", "HandThumb2", "HandThumb3", "HandIndex1", "HandIndex2",
                      "HandIndex3", "HandMiddle1", "HandMiddle2", "HandMiddle3", "HandRing1",
                      "HandRing2", "HandRing3", "HandPinky1", "HandPinky2", "HandPinky3")
    leg_w = B.weight("UpLeg", "Leg", "Hips")
    shin_w = B.weight("Leg", "Foot", "ToeBase")
    torso_mask = B.weight("Spine", "Spine1", "Spine2", "Hips") > 0.3
    out = {}

    # --- greatcoat: torso + sleeves -------------------------------------
    coat_mask = (torso_bones > 0.45) & (B.co[:, 2] > waist - WAIST_PAD) & (B.co[:, 2] < neck + 0.01) \
        & (hand_w < 0.2)
    coat = _region_shell(B, "CoatUpper", coat_mask, 0.016, [M["coat"], M["lining"]])
    _open_front(coat, waist, neck)
    _cuffs(coat, B)
    _solidify(coat, 0.006, inner_mat_offset=1, rim_mat_offset=1)
    out["coat_upper"] = coat

    # --- skirt ------------------------------------------------------------
    skirt, chains = _skirt(B, waist, hem, [M["coat"], M["lining"]], rig)
    out["coat_skirt"] = skirt

    # --- collar + hood ----------------------------------------------------
    neck_mask = B.weight("Neck", "Spine2") > 0.25
    collar = _ring_band(B, "Collar", neck_mask, lambda th: neck - 0.03, 0.085, 0.022,
                        [M["coat"], M["lining"]], gap=math.radians(38))
    _flare(collar, neck - 0.03, 0.018)
    _solidify(collar, 0.005, inner_mat_offset=1, rim_mat_offset=1)
    out["collar"] = collar
    out["hood"] = _hood(B, neck, [M["coat"], M["lining"]])

    # --- breeches, boots, gloves, bracers ---------------------------------
    breech_mask = (leg_w > 0.3) & (B.co[:, 2] < waist + 0.01) & (B.co[:, 2] > knee - 0.12)
    br = _region_shell(B, "Breeches", breech_mask, 0.005, [M["breeches"]])
    _solidify(br, 0.003)
    out["breeches"] = br

    boot_mask = (shin_w > 0.3) & (B.co[:, 2] < knee + 0.05)
    out["boots"] = _boots(B, knee, [M["leather"]])

    gloves = _region_shell(B, "Gloves", hand_w > 0.4, 0.0028, [M["leather"]])
    _solidify(gloves, 0.0015, even=False)
    out["gloves"] = gloves

    out["bracers"] = _bracers(B, [M["leather"], M["silver"]])

    # --- sash + crossed belts ---------------------------------------------
    out["sash"] = _ring_band(B, "Sash", torso_mask, lambda th: waist - 0.055, 0.095, 0.034,
                             [M["sash"]])
    _solidify(out["sash"], 0.004)
    for side, tilt in (("L", 1), ("R", -1)):
        phase = FRONT + tilt * math.radians(55)
        belt = _ring_band(B, f"Belt{side}", B.weight("Hips", "UpLeg", "Spine") > 0.3,
                          lambda th, p=phase: waist - 0.11 - 0.055 * (1 + math.cos(th - p)) / 2,
                          0.038, 0.05 + (0.006 if side == "R" else 0.0), [M["leather"]])
        _solidify(belt, 0.005)
        out[f"belt_{side}"] = belt
        out[f"buckle_{side}"] = _buckle(B, belt, phase, M["silver"])

    # --- bind everything --------------------------------------------------
    for key, ob in out.items():
        if key == "coat_skirt":
            _apply_all(ob)
        else:
            _transfer_weights(ob, B)
        _bind(ob, rig)

    below_boot_tops = B.co[:, 2] < knee + 0.04   # only legs/feet are this low
    _hide_covered_body(B, breech_mask | boot_mask | below_boot_tops | (hand_w > 0.4))
    return out


def _open_front(coat, waist, neck):
    """Cut a clean V opening (bare chest shows): two slanted planes, narrow at the
    waist (belted), wide at the collar."""
    lo, hi = 0.035, 0.125
    bm = bmesh.new()
    bm.from_mesh(coat.data)
    for sgn in (1, -1):
        p0 = Vector((sgn * lo, 0.0, waist))
        p1 = Vector((sgn * hi, 0.0, neck))
        edge = (p1 - p0).normalized()
        no = edge.cross(Vector((0.0, 1.0, 0.0))).normalized()
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p0, plane_no=no)
    def inside(c):
        t = min(max((c.z - waist) / max(neck - waist, 1e-3), 0.0), 1.0)
        return c.y < 0 and abs(c.x) < lo + (hi - lo) * t - 1e-4
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if inside(f.calc_center_median())], context="FACES")
    bm.to_mesh(coat.data)
    bm.free()


def _cuffs(coat, B):
    """Crimson turned-back cuffs: outer faces within 7 cm of each wrist."""
    wrists = [B.head("LeftHand"), B.head("RightHand")]
    for f in coat.data.polygons:
        c = Vector(f.center)
        if min((c - w).length for w in wrists) < 0.07:
            f.material_index = 1


def _flare(ob, z0, amount):
    for v in ob.data.vertices:
        t = max(0.0, v.co.z - z0) / 0.085
        d = Vector((v.co.x, v.co.y, 0.0))
        if d.length > 1e-4:
            v.co += d.normalized() * amount * t * t


def _skirt(B, waist, hem, mats, rig, bins=64, rows=20):
    """Flared, front-split coat skirt + 4 bone chains (coat_<side>_<n>)."""
    hips_mask = B.weight("Hips", "UpLeg", "Spine") > 0.2
    c_top, _ = B.contour(hips_mask, waist)
    bm = bmesh.new()
    grid = []
    z_top = waist + WAIST_PAD * 0.5
    zs = [z_top + (hem - z_top) * j / rows for j in range(rows + 1)]
    raw = [B.contour(hips_mask, max(z, B.z("LeftLeg")), bins, band=0.02, center=c_top)[1] for z in zs]
    radii, prev = [], None
    for j, r in enumerate(raw):
        r = np.maximum(r, prev) if prev is not None else r   # never cling between legs
        prev = r
        radii.append(r)
    radii = np.array(radii)
    for _ in range(6):                                        # smooth down the length
        radii[1:-1] = (radii[:-2] + 2 * radii[1:-1] + radii[2:]) / 4
    for j in range(rows + 1):
        t = j / rows
        z = zs[j]
        r = radii[j] + 0.02 + 0.075 * t ** 1.3                # ease + gentle flare
        gap = math.radians(8 + 14 * t)
        row = []
        for i in range(bins + 1):
            th = FRONT + gap + (2 * math.pi - 2 * gap) * i / bins
            k = int(round(((th % (2 * math.pi)) / (2 * math.pi)) * bins)) % bins
            row.append(bm.verts.new((c_top[0] + r[k] * math.cos(th), c_top[1] + r[k] * math.sin(th), z)))
        grid.append(row)
    for j in range(rows):
        for i in range(bins):   # wound so normals face outward
            bm.faces.new((grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1]))
    ob = _new_obj("CoatSkirt", bm, mats)
    _solidify(ob, 0.006, inner_mat_offset=1, rim_mat_offset=1)

    # Bone chains: 4 around the skirt, 3 segments each, parented to Hips.
    chain_angles = {"L_front": FRONT + math.radians(40), "R_front": FRONT - math.radians(40),
                    "L_back": FRONT + math.radians(140), "R_back": FRONT - math.radians(140)}
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    hips = eb["mixamorig:Hips"]
    zs = [z_top, z_top + (hem - z_top) / 3, z_top + 2 * (hem - z_top) / 3, hem]
    for key, th in chain_angles.items():
        parent = hips
        for n in range(3):
            pts = []
            for z in (zs[n], zs[n + 1]):
                t = (z_top - z) / (z_top - hem)
                _, r = B.contour(hips_mask, max(z, B.z("LeftLeg")), bins, band=0.02, center=c_top)
                k = int(round(((th % (2 * math.pi)) / (2 * math.pi)) * bins)) % bins
                rr = r[k] + 0.02 + 0.075 * t ** 1.3
                pts.append(Vector((c_top[0] + rr * math.cos(th), c_top[1] + rr * math.sin(th), z)))
            b = eb.new(f"coat_{key}_{n + 1}")
            b.head, b.tail = pts[0], pts[1]
            b.parent = parent
            b.use_connect = n > 0
            parent = b
    bpy.ops.object.mode_set(mode="OBJECT")

    # Weights: angular blend between the two nearest chains x vertical segments;
    # the top quarter blends into Hips so the waist stays put.
    names = list(chain_angles)
    groups = {f"coat_{k}_{n}": ob.vertex_groups.new(name=f"coat_{k}_{n}") for k in names for n in (1, 2, 3)}
    hips_g = ob.vertex_groups.new(name="mixamorig:Hips")
    for v in ob.data.vertices:
        co = v.co
        th = math.atan2(co.y - c_top[1], co.x - c_top[0])
        t = min(max((z_top - co.z) / (z_top - hem), 0.0), 1.0)
        ang = []
        for k in names:
            d = abs((th - chain_angles[k] + math.pi) % (2 * math.pi) - math.pi)
            ang.append((d, k))
        ang.sort()
        (d0, k0), (d1, k1) = ang[0], ang[1]
        s = d0 + d1
        wa, wb = (d1 / s, d0 / s) if s > 1e-6 else (1.0, 0.0)
        seg = min(t * 3, 2.999)
        n = int(seg)
        f = seg - n
        hip = max(0.0, 1.0 - t / 0.25)
        body = 1.0 - hip
        for k, wk in ((k0, wa), (k1, wb)):
            groups[f"coat_{k}_{n + 1}"].add([v.index], body * wk * (1 - f), "ADD")
            if n < 2:
                groups[f"coat_{k}_{n + 2}"].add([v.index], body * wk * f, "ADD")
        if hip > 0:
            hips_g.add([v.index], hip, "ADD")
    return ob, chain_angles


def _hood(B, neck, mats):
    """Hood worn down: a head-sized hood (dome + face opening), squashed and
    laid back so it drapes on the upper back below the collar, with soft folds."""
    R = 0.135
    bm = bmesh.new()
    rows, segs = 12, 24
    grid = []
    for j in range(rows + 1):
        v = j / rows                        # 0 = opening rim .. 1 = crown/back
        row = []
        for i in range(segs + 1):
            u = math.pi * i / segs          # around the face opening
            a = v * math.pi * 0.62
            x = R * math.cos(u) * math.cos(a * 0.35)
            y = R * math.sin(a) * 1.1
            z = R * math.sin(u) * math.cos(a * 0.35) * (1 - 0.25 * v)
            fold = 0.01 * math.sin(u * 7 + v * 4) * math.sin(math.pi * v)
            p = Vector((x, y + fold, z))
            # Lay it down: rotate about X so the opening faces up, squash depth.
            p = Vector((p.x, p.y * 0.45, p.z)).to_3d()
            c, s_ = math.cos(math.radians(-72)), math.sin(math.radians(-72))
            p = Vector((p.x, p.y * c - p.z * s_, p.y * s_ + p.z * c))
            row.append(bm.verts.new(p))
        grid.append(row)
    for j in range(rows):
        for i in range(segs):
            bm.faces.new((grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = _new_obj("Hood", bm, mats)
    ob.location = B.head("Neck") + Vector((0.0, 0.1, -0.06))
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=True)
    ob.select_set(False)
    _solidify(ob, 0.006, inner_mat_offset=1, rim_mat_offset=1)
    return ob


def _boots(B, knee, mats):
    """Tall riding boots, modelled per leg from its measurements: a shaft lofted
    along the shin contour (fold-over cuff at the knee), then a foot built as a
    rounded last from heel to toe, with a raised heel block."""
    bm = bmesh.new()
    segs = 28
    for side in ("Left", "Right"):
        ankle = B.head(side + "Foot")
        leg_mask = (B.weight(side + "Leg", side + "Foot") > 0.35)
        rings = []
        zs = list(np.linspace(knee + 0.06, ankle.z + 0.02, 9))
        for k, z in enumerate(zs):
            c, r = B.contour(leg_mask, z, segs, band=0.015)   # centre per slice: the shin angles out
            pad = 0.014 + (0.012 if k == 0 else 0.0)           # cuff lip
            ring = [bm.verts.new((c[0] + (r[i] + pad) * math.cos(2 * math.pi * i / segs),
                                  c[1] + (r[i] + pad) * math.sin(2 * math.pi * i / segs), z))
                    for i in range(segs)]
            rings.append(ring)
        # Foot: measure the body foot, then loft rounded cross-sections heel->toe.
        fm = (B.weight(side + "Foot", side + "ToeBase") > 0.3) & (B.co[:, 2] < ankle.z + 0.02)
        fp = B.co[fm]
        y_heel, y_toe = fp[:, 1].max() + 0.012, fp[:, 1].min() - 0.018   # toe is -Y
        fx = float(np.median(fp[:, 0]))
        half_w = (np.percentile(fp[:, 0], 97) - np.percentile(fp[:, 0], 3)) / 2 + 0.012
        top = ankle.z + 0.02
        last = rings[-1]
        steps = 10
        for k in range(1, steps + 1):
            t = k / steps
            y = y_heel + (y_toe - y_heel) * t
            height = (top - 0.0) * (1 - 0.72 * t ** 1.2)      # instep slopes to the toe
            width = half_w * (0.8 + 0.25 * math.sin(math.pi * min(t * 1.3, 1.0))) * (1 - 0.45 * t ** 3)
            ring = []
            for i in range(segs):
                a = 2 * math.pi * i / segs
                cx, sy = math.cos(a), math.sin(a)
                z = 0.5 * height + 0.5 * height * sy
                ring.append(bm.verts.new((fx + width * cx, y, max(z, 0.0))))
            rings.append(ring)
        for a, b in zip(rings, rings[1:]):
            for i in range(segs):
                bm.faces.new((a[i], b[i], b[(i + 1) % segs], a[(i + 1) % segs]))
        bm.faces.new(rings[-1][::-1])                            # toe cap
        # Heel block.
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((fx + v.co.x * half_w * 1.4, y_heel - 0.03 + v.co.y * 0.06, v.co.z * 0.025 - 0.0125))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = _new_obj("Boots", bm, mats)
    sub = ob.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 1
    return ob


def _bracers(B, mats):
    bm = bmesh.new()
    for side in ("Left", "Right"):
        wrist, elbow = B.head(side + "Hand"), B.head(side + "ForeArm")
        axis = (elbow - wrist).normalized()
        mask = (B.weight("ForeArm") > 0.3)
        pts = B.co[mask]
        # Radius of the forearm near the wrist, plus sleeve + leather clearance.
        rel = pts - np.array(wrist[:])
        along = rel @ np.array(axis[:])
        near = pts[(along > 0.0) & (along < 0.14)]
        radial = np.linalg.norm((near - np.array(wrist[:])) - np.outer((near - np.array(wrist[:])) @ np.array(axis[:]), axis[:]), axis=1)
        r = float(np.percentile(radial, 90)) + 0.03 if len(radial) else 0.05
        u = axis.orthogonal().normalized()
        w = axis.cross(u)
        rings = []
        for k, (d, rr) in enumerate(((0.015, r), (0.14, r * 1.12))):
            ring = [bm.verts.new(wrist + axis * d + (u * math.cos(a) + w * math.sin(a)) * rr)
                    for a in [2 * math.pi * i / 24 for i in range(24)]]
            rings.append(ring)
        for i in range(24):
            bm.faces.new((rings[0][i], rings[0][(i + 1) % 24], rings[1][(i + 1) % 24], rings[1][i]))
    ob = _new_obj("Bracers", bm, mats)
    _solidify(ob, 0.005)
    return ob


def _buckle(B, belt, phase, silver):
    """Silver frame buckle at the belt's front point."""
    me = belt.data
    best = max(me.vertices, key=lambda v: math.cos(math.atan2(v.co.y, v.co.x) - phase))
    zs = [v.co.z for v in me.vertices if (v.co - best.co).length < 0.03]
    p = Vector((best.co.x, best.co.y, (min(zs) + max(zs)) / 2))
    out = Vector((p.x, p.y, 0)).normalized()
    bm = bmesh.new()
    W, H, T, D = 0.05, 0.05, 0.007, 0.006
    for (cx, cz, sx, sz) in ((0, H / 2 - T / 2, W, T), (0, -H / 2 + T / 2, W, T),
                             (-W / 2 + T / 2, 0, T, H), (W / 2 - T / 2, 0, T, H), (0, 0, T * 0.6, H)):
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((v.co.x * sx + cx, v.co.y * D, v.co.z * sz + cz))
    ob = _new_obj(belt.name + "Buckle", bm, [silver])
    ob.location = p + out * 0.008
    ob.rotation_euler = (0, 0, math.atan2(out.y, out.x) + math.pi / 2)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.select_set(False)
    bev = ob.modifiers.new("Bevel", "BEVEL")
    bev.width, bev.segments = 0.0012, 2
    return ob


def _hide_covered_body(B, covered):
    """Delete body faces fully under tight garments (legs, feet, hands)."""
    me = B.obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    kill = [f for f in bm.faces if all(covered[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(me)
    bm.free()

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
# Pieces bound rigidly to one bone (belts ride the hips, the hood the upper back).
RIGID = {"belt": "Hips", "buckle": "Hips", "sash": "Hips", "hood": "Spine2"}


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
        "breeches": _mat("CharcoalBreeches", (0.02, 0.019, 0.022), 0.8),
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
    ob = _new_obj(name, bm, mats)
    # bmesh kept each vertex's deform weights (by group index): recreate the
    # body's groups in the same order so they line up exactly — no nearest-
    # surface guessing (which mixed neighbouring fingers into spiky claws).
    for g in B.obj.vertex_groups:
        ob.vertex_groups.new(name=g.name)
    ob["exact_weights"] = True
    return ob


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
    shoulder_top = (B.weight("Shoulder") > 0.3) & (np.abs(B.co[:, 0]) > 0.07)   # cover the trapezius
    coat_mask = (torso_bones > 0.45) & (B.co[:, 2] > waist - WAIST_PAD) \
        & ((B.co[:, 2] < neck + 0.01) | shoulder_top) & (hand_w < 0.2)
    coat = _region_shell(B, "CoatUpper", coat_mask, 0.016, [M["coat"], M["lining"]])
    _open_front(coat, waist, neck)
    _cuffs(coat, B)
    _sleeve_folds(coat, B)
    out["lapels"] = _lapels(coat, waist, neck, [M["lining"]])
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
    # Hood omitted: a static hood reads as a slab from behind; revisit with cloth sim.

    # --- breeches, boots, gloves, bracers ---------------------------------
    breech_mask = (leg_w > 0.3) & (B.co[:, 2] < waist + 0.01) & (B.co[:, 2] > knee - 0.12)
    br = _region_shell(B, "Breeches", breech_mask, 0.005, [M["breeches"]])
    _solidify(br, 0.003)
    out["breeches"] = br

    boot_mask = (shin_w > 0.3) & (B.co[:, 2] < knee - 0.03)
    out["boots"] = _boots(B, knee, [M["leather"]])

    wrist_band = np.zeros(len(B.co), dtype=bool)
    for side in ("Left", "Right"):
        w = np.array(B.head(side + "Hand")[:])
        wrist_band |= (np.linalg.norm(B.co - w, axis=1) < 0.075) & (B.weight("ForeArm", "Hand") > 0.2)
    glove_mask = (hand_w > 0.15) | wrist_band
    gloves = _region_shell(B, "Gloves", glove_mask, 0.0016, [M["leather"]])
    _solidify(gloves, 0.0012, even=False)
    gsub = gloves.modifiers.new("Subsurf", "SUBSURF")
    gsub.levels = 1
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
        rigid = RIGID.get(key.rstrip("_LR") if key.startswith(("belt", "buckle")) else key)
        if rigid:
            # Free-floating pieces: nearest-surface weights would grab the thighs.
            _apply_all(ob)
            g = ob.vertex_groups.new(name="mixamorig:" + rigid)
            g.add([v.index for v in ob.data.vertices], 1.0, "REPLACE")
        elif key == "coat_skirt" or ob.get("exact_weights"):
            _apply_all(ob)
        else:
            _transfer_weights(ob, B)
        _bind(ob, rig)

    below_boot_tops = B.co[:, 2] < knee - 0.04   # only legs/feet are this low
    _hide_covered_body(B, breech_mask | boot_mask | below_boot_tops | glove_mask)
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
        if c.y < 0 and c.z < waist and abs(c.x) < 0.14:
            return True   # below the sash the skirt takes over (no stray front panel)
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
        k_idx = np.arange(bins)
        r = r + 0.011 * t ** 1.2 * (np.sin(k_idx * 2 * math.pi / bins * 9 + 0.7) * 0.7
                                     + np.sin(k_idx * 2 * math.pi / bins * 17 + 2.1) * 0.3)
        gap = math.radians(max(0.5, -6 + 28 * t))   # closed under the sash, opens lower
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
            p = Vector((p.x, p.y * 0.6, p.z)).to_3d()
            c, s_ = math.cos(math.radians(-118)), math.sin(math.radians(-118))  # opening tucked to the neck
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


def _superellipse(cx, w, z0, h, n=2.6, segs=28):
    """Boot cross-section: flat sole line, rounded-square upper."""
    pts = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s_ = math.cos(a), math.sin(a)
        x = cx + w * math.copysign(abs(c) ** (2 / n), c)
        z = z0 + h * max(0.0, math.copysign(abs(s_) ** (2 / n), s_))
        pts.append((x, z))
    return pts


def _boots(B, knee, mats):
    """Victorian riding boots per leg: shaft lofted on the shin (fold-over cuff),
    a foot measured slice-by-slice from the real foot (rounded-square toe box,
    instep), a separate welted sole and a stacked heel."""
    bm = bmesh.new()
    segs = 28
    SOLE = 0.012
    for side in ("Left", "Right"):
        ankle = B.head(side + "Foot")
        leg_mask = (B.weight(side + "Leg", side + "Foot") > 0.35)
        rings = []
        # Top just below the knee (above it, the cuff pokes through the skirt
        # whenever the knee comes forward).
        knee_h = B.head(side + "Leg")
        for k, z in enumerate(np.linspace(knee - 0.03, ankle.z + 0.035, 9)):
            # Centre on the shin bone line (knee -> ankle); an empty body slice
            # must never fall back to a ring around the origin (between the legs).
            f = (knee_h.z - z) / max(knee_h.z - ankle.z, 1e-3)
            ctr = np.array([knee_h.x + (ankle.x - knee_h.x) * f, knee_h.y + (ankle.y - knee_h.y) * f])
            c, r = B.contour(leg_mask, z, segs, band=0.02, center=ctr)
            r = np.minimum(r, 0.09)                             # a shin is never wider than this
            pad = 0.011 + (0.005 if k == 0 else 0.0)
            rings.append([bm.verts.new((c[0] + (r[i] + pad) * math.cos(2 * math.pi * i / segs),
                                        c[1] + (r[i] + pad) * math.sin(2 * math.pi * i / segs), z))
                          for i in range(segs)])
        for a, b in zip(rings, rings[1:]):
            for i in range(segs):
                bm.faces.new((a[i], b[i], b[(i + 1) % segs], a[(i + 1) % segs]))

        # Foot measured from the body: width and top per slice along Y (toe = -Y).
        # Whole foot incl. the heel (the heel is weighted to the shin, not Foot).
        fm = (B.co[:, 2] < ankle.z + 0.03) & (np.sign(B.co[:, 0]) == math.copysign(1, ankle.x))
        fp = B.co[fm]
        y_heel, y_toe = fp[:, 1].max() + 0.01, fp[:, 1].min() - 0.016
        slices = 14
        foot = []
        prev_w = None
        for k in range(slices + 1):
            t = k / slices
            y = y_heel + (y_toe - y_heel) * t
            near = fp[np.abs(fp[:, 1] - y) < 0.02]
            if len(near) < 4:
                near = fp
            cx = float((near[:, 0].max() + near[:, 0].min()) / 2)
            w = float((near[:, 0].max() - near[:, 0].min()) / 2) + 0.01
            top = float(near[:, 2].max()) + 0.01
            top = max(top, 0.05 + 0.02 * (1 - t))            # roomy toe box
            if t > 0.85:                                      # round the toe off
                q = (t - 0.85) / 0.15
                w *= math.sqrt(max(1 - q * q, 0.05))
                top = SOLE + (top - SOLE) * math.sqrt(max(1 - q * q, 0.1))
            w = w if prev_w is None else 0.6 * w + 0.4 * prev_w
            prev_w = w
            sec = _superellipse(cx, w, SOLE, top - SOLE, segs=segs)
            foot.append([bm.verts.new((x, y, z)) for x, z in sec])
        for a, b in zip(foot, foot[1:]):
            for i in range(segs):
                bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
        bm.faces.new(foot[0])                                  # heel cap
        bm.faces.new(foot[-1][::-1])                           # toe cap

        # Welted sole: the foot outline, 5 mm proud, SOLE thick; stacked heel.
        outline_l, outline_r = [], []
        for k in range(slices + 1):
            ring = foot[k]
            xs = [v.co.x for v in ring]
            outline_l.append((min(xs) - 0.005, ring[0].co.y))
            outline_r.append((max(xs) + 0.005, ring[0].co.y))
        outline = outline_r + outline_l[::-1]
        top_v = [bm.verts.new((x, y, SOLE)) for x, y in outline]
        bot_v = [bm.verts.new((x, y, 0.0)) for x, y in outline]
        n = len(outline)
        for i in range(n):
            bm.faces.new((bot_v[i], bot_v[(i + 1) % n], top_v[(i + 1) % n], top_v[i]))
        bm.faces.new(top_v)
        bm.faces.new(bot_v[::-1])
        hw = (outline_r[0][0] - outline_l[0][0]) / 2
        hc = (outline_r[0][0] + outline_l[0][0]) / 2
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((hc + v.co.x * hw * 1.9, y_heel - 0.035 + v.co.y * 0.065, v.co.z * 0.028 - 0.014))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = _new_obj("Boots", bm, mats)
    bev = ob.modifiers.new("Bevel", "BEVEL")
    bev.width, bev.segments, bev.limit_method = 0.002, 2, "ANGLE"
    return ob


def _sleeve_folds(coat, B):
    """Soft compression folds around each elbow (rings along the arm)."""
    for side in ("Left", "Right"):
        elbow = B.head(side + "ForeArm")
        arm_dir = (B.head(side + "Hand") - elbow).normalized()
        for v in coat.data.vertices:
            d = v.co - elbow
            along = d.dot(arm_dir)
            radial = (d - arm_dir * along).length
            if abs(along) < 0.09 and radial < 0.09:
                fade = 1 - abs(along) / 0.09
                v.co += v.normal * 0.004 * math.sin(along * 110) * fade


def _lapels(coat, waist, neck, mats):
    """Crimson lapels turned back along the V opening: wide at the chest,
    tapering to nothing at the belted waist."""
    me = coat.data
    bm = bmesh.new()
    bm.from_mesh(me)
    edge_v = [v for v in bm.verts if v.is_boundary and v.co.y < 0 and waist - 0.01 < v.co.z < neck - 0.02
              and abs(v.co.x) < 0.2]
    out = bmesh.new()
    for sgn in (1, -1):
        side = sorted([v for v in edge_v if math.copysign(1, v.co.x) == sgn], key=lambda v: v.co.z)
        if len(side) < 3:
            continue
        # resample to an even strip
        zs = np.linspace(side[0].co.z, side[-1].co.z, 18)
        prev = None
        for z in zs:
            v = min(side, key=lambda q: abs(q.co.z - z))
            t = (z - waist) / max(neck - waist, 1e-3)
            width = 0.075 * math.sin(math.pi * min(max(t, 0.0), 1.0) * 0.8)
            base = Vector((v.co.x, v.co.y - 0.004, z))
            tip = base + Vector((sgn * width, -0.004 - 0.01 * width / 0.075, 0.0))
            pair = (out.verts.new(base), out.verts.new(tip))
            if prev:
                out.faces.new((prev[0], prev[1], pair[1], pair[0]) if sgn > 0 else (prev[0], pair[0], pair[1], prev[1]))
            prev = pair
    bm.free()
    ob = _new_obj("Lapels", out, mats)
    _solidify(ob, 0.004)
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

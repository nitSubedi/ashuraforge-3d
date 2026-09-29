extends RefCounted
## Build-time Mixamo clip retargeter (same-named bones, different rest poses).
##
## Clips authored on X Bot store LOCAL bone rotations relative to X Bot's rest
## orientation; played raw on another rig whose rest axes differ (e.g. MPFB's
## feet), limbs twist. This converts each frame through world space:
##     D   = W_src(bone) * G_src(bone)^-1     (world-space delta from rest)
##     W_dst(bone) = D * G_dst(bone)
##     q_dst = W_dst(parent)^-1 * W_dst(bone) (back to dst local)
## G = global rest rotation (incl. the skeleton node's own basis).
## Rest POSE differences (X Bot T-pose arms vs an A-pose rig) are cancelled for
## the arm/finger chains: their dst rest is first swung so the bone points the
## same way as the src rest bone (A), i.e. W_dst = D * A * G_dst — the limb then
## follows the src limb's direction. Other bones (feet, spine…) keep pure
## rest-relative deltas, which respects each rig's own bone-vs-mesh placement.
## Hips position
## is carried as a rest-relative offset scaled by the hip-height ratio.
## Usage: preload("res://tools/retarget.gd").retarget(anim, src_skel, dst_skel, dst_path)

const FPS := 30.0

static func _order(sk: Skeleton3D) -> PackedInt32Array:
	# Parents before children.
	var out := PackedInt32Array()
	var depth := {}
	for i in sk.get_bone_count():
		var d := 0
		var p := sk.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = sk.get_bone_parent(p)
		depth[i] = d
	var ids := range(sk.get_bone_count())
	ids.sort_custom(func(a, b): return depth[a] < depth[b])
	for i in ids:
		out.append(i)
	return out

static func _global_rest(sk: Skeleton3D) -> Dictionary:
	var base := sk.transform.basis.get_rotation_quaternion()
	var g := {}
	for i in _order(sk):
		var p := sk.get_bone_parent(i)
		var parent_q: Quaternion = g[p] if p >= 0 else base
		g[i] = parent_q * sk.get_bone_rest(i).basis.get_rotation_quaternion()
	return g

const ALIGN_PARTS := ["Shoulder", "Arm", "ForeArm", "Hand"]

static func _rest_pos(sk: Skeleton3D, i: int) -> Vector3:
	return sk.transform.basis * sk.get_bone_global_rest(i).origin

## World rest direction of bone i -> its chain child (or null if leaf).
static func _rest_dir(sk: Skeleton3D, i: int) -> Variant:
	var kids := sk.get_bone_children(i)
	if kids.is_empty():
		return null
	var best := kids[0]
	var name := sk.get_bone_name(i)
	for k in kids:   # prefer the middle finger / next segment of the chain
		if "Middle1" in sk.get_bone_name(k) or name.trim_suffix("1").trim_suffix("2") in sk.get_bone_name(k):
			best = k
	var d := _rest_pos(sk, best) - _rest_pos(sk, i)
	return d.normalized() if d.length() > 1e-6 else null

static func _needs_align(name: String) -> bool:
	var n := name.trim_prefix("mixamorig_").trim_prefix("Left").trim_prefix("Right")
	return n in ALIGN_PARTS or n.begins_with("Hand")   # arms + fingers

static func retarget(anim: Animation, src: Skeleton3D, dst: Skeleton3D, dst_path: String) -> Animation:
	var g_src := _global_rest(src)
	var g_dst := _global_rest(dst)
	# Swing dst rest onto src rest direction for arm/finger chains.
	var swing := {}
	for i in _order(dst):
		var name := dst.get_bone_name(i)
		var si := src.find_bone(name)
		if si < 0 or not _needs_align(name):
			continue
		var dd: Variant = _rest_dir(dst, i)
		var ds: Variant = _rest_dir(src, si)
		var a := Quaternion.IDENTITY
		if dd != null and ds != null:
			a = Quaternion(dd as Vector3, ds as Vector3)
		else:
			a = swing.get(dst.get_bone_parent(i), Quaternion.IDENTITY)   # leaf: parent's swing
		swing[i] = a
		g_dst[i] = a * (g_dst[i] as Quaternion)
	var src_base := src.transform.basis.get_rotation_quaternion()
	var dst_base := dst.transform.basis.get_rotation_quaternion()
	# Track lookup by bone name.
	var rot_tr := {}
	var pos_tr := {}
	for ti in anim.get_track_count():
		var bone := String(anim.track_get_path(ti).get_concatenated_subnames())
		match anim.track_get_type(ti):
			Animation.TYPE_ROTATION_3D:
				rot_tr[bone] = ti
			Animation.TYPE_POSITION_3D:
				pos_tr[bone] = ti
	var src_order := _order(src)
	var dst_order := _order(dst)
	var hips_s := src.find_bone("mixamorig_Hips")
	var hips_d := dst.find_bone("mixamorig_Hips")
	var ratio := 1.0
	if hips_s >= 0 and hips_d >= 0:
		var hs := (src.get_bone_global_rest(hips_s).origin * src.transform.basis.get_scale()).y
		var hd := (dst.get_bone_global_rest(hips_d).origin * dst.transform.basis.get_scale()).y
		ratio = hd / hs if absf(hs) > 1e-5 else 1.0

	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	var out_tr := {}
	for i in dst_order:
		var name := dst.get_bone_name(i)
		if src.find_bone(name) < 0:
			continue
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath(dst_path + ":" + name))
		out_tr[i] = t
	var hips_out := -1
	if hips_d >= 0 and pos_tr.has("mixamorig_Hips"):
		hips_out = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_out, NodePath(dst_path + ":mixamorig_Hips"))

	var frames := int(ceil(anim.length * FPS))
	for f in frames + 1:
		var time := minf(f / FPS, anim.length)
		var w_src := {}
		for i in src_order:
			var name := src.get_bone_name(i)
			var q: Quaternion = anim.rotation_track_interpolate(rot_tr[name], time) \
				if rot_tr.has(name) else src.get_bone_rest(i).basis.get_rotation_quaternion()
			var p := src.get_bone_parent(i)
			var wp_s: Quaternion = w_src[p] if p >= 0 else src_base
			w_src[i] = wp_s * q
		var w_dst := {}
		for i in dst_order:
			var p := dst.get_bone_parent(i)
			var wp: Quaternion = w_dst[p] if p >= 0 else dst_base
			var si := src.find_bone(dst.get_bone_name(i))
			if si >= 0:
				var delta: Quaternion = (w_src[si] as Quaternion) * (g_src[si] as Quaternion).inverse()
				w_dst[i] = delta * g_dst[i]
				var local: Quaternion = (wp.inverse() * (w_dst[i] as Quaternion)).normalized()
				out.rotation_track_insert_key(out_tr[i], time, local)
			else:
				w_dst[i] = wp * dst.get_bone_rest(i).basis.get_rotation_quaternion()
		if hips_out >= 0:
			var p_src: Vector3 = anim.position_track_interpolate(pos_tr["mixamorig_Hips"], time)
			var off := src.transform.basis * (p_src - src.get_bone_rest(hips_s).origin)
			var p_dst := dst.get_bone_rest(hips_d).origin + dst.transform.basis.inverse() * off * ratio
			out.position_track_insert_key(hips_out, time, p_dst)
	return out

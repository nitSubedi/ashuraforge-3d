extends SceneTree
## Build res://assets/enemies/enemy.tscn from the rigged, region-split X Bot GLB:
## merge idle/hit/death clips onto its skeleton (rewriting track paths to match
## the GLB's Armature/Skeleton3D), tint red. Run: godot --headless -s res://tools/build_enemy.gd

const SRC := "res://assets/enemies/xbot_rigged.glb"
const DIR := "res://assets/animations/mixamo/"
const CLIPS := {"idle": "idle.fbx", "hit": "hit.fbx", "death": "death.fbx"}
const LOOPED := ["idle"]
const OUT := "res://assets/enemies/enemy.tscn"

func _initialize() -> void:
	var root := (load(SRC) as PackedScene).instantiate()
	root.name = "Enemy"
	var ap := _find_anim(root)
	var skel := _find_skel(root)
	var ap_root := ap.get_node(ap.root_node)
	var skel_rel := str(ap_root.get_path_to(skel))
	print("skel_rel=", skel_rel)

	var lib := ap.get_animation_library(&"")
	if lib == null:
		lib = AnimationLibrary.new()
		ap.add_animation_library(&"", lib)
	for junk in ["Take 001", "mixamo_com"]:
		if lib.has_animation(junk):
			lib.remove_animation(junk)

	for clip_name in CLIPS:
		var ps := load(DIR + CLIPS[clip_name]) as PackedScene
		if ps == null:
			push_error("missing " + CLIPS[clip_name]); continue
		var inst := ps.instantiate()
		var src_ap := _find_anim(inst)
		var src_name := "mixamo_com" if src_ap.has_animation("mixamo_com") else src_ap.get_animation_list()[0]
		var a := (src_ap.get_animation(src_name) as Animation).duplicate(true) as Animation
		# Retarget track paths onto this GLB's skeleton.
		for ti in a.get_track_count():
			var sub := a.track_get_path(ti).get_concatenated_subnames()
			a.track_set_path(ti, NodePath(skel_rel + ":" + sub) if sub != "" else NodePath(skel_rel))
		if clip_name in LOOPED:
			a.loop_mode = Animation.LOOP_LINEAR
		_strip_root(a)
		lib.add_animation(clip_name, a)
		print("  added ", clip_name, " len=", a.length)
		inst.free()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.09, 0.10)
	mat.roughness = 0.6
	for m in _all_meshes(root):
		m.material_override = mat

	root.scene_file_path = ""
	_set_owner(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT)
	print("SAVED ", OUT, " err=", err, " clips=", ap.get_animation_list())
	quit()

func _strip_root(a: Animation) -> void:
	for ti in a.get_track_count():
		if a.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		if "Hips" not in str(a.track_get_path(ti)):
			continue
		for ki in a.track_get_key_count(ti):
			var v: Vector3 = a.track_get_key_value(ti, ki)
			a.track_set_key_value(ti, ki, Vector3(0.0, v.y, 0.0))

func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out

func _set_owner(n: Node, owner_root: Node) -> void:
	for c in n.get_children():
		c.owner = owner_root
		_set_owner(c, owner_root)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

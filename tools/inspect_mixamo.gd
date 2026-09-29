extends SceneTree
## Inspect imported Mixamo FBX: node tree + AnimationPlayer clip names + skeleton.
## Run: godot --headless -s res://tools/inspect_mixamo.gd

func _initialize() -> void:
	for path in [
		"res://assets/animations/mixamo/hero_base.fbx",
		"res://assets/animations/mixamo/idle.fbx",
		"res://assets/animations/mixamo/run.fbx",
	]:
		print("\n==== ", path)
		var ps := load(path) as PackedScene
		if ps == null:
			print("  FAILED to load")
			continue
		var inst := ps.instantiate()
		_dump(inst, 0)
		var ap := _find_anim(inst)
		if ap != null:
			print("  ANIM LIBS: ", ap.get_animation_library_list())
			print("  ANIMATIONS: ", ap.get_animation_list())
		var sk := _find_skel(inst)
		if sk != null:
			print("  SKELETON bones: ", sk.get_bone_count(), "  root: ", sk.get_bone_name(0) if sk.get_bone_count() > 0 else "-")
		inst.free()
	quit()

func _dump(n: Node, d: int) -> void:
	if d <= 3:
		print("  ".repeat(d + 1), n.name, " [", n.get_class(), "]")
	for c in n.get_children():
		_dump(c, d + 1)

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

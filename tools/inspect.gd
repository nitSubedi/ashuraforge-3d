extends SceneTree
## One-off introspection: dumps node tree, AnimationPlayer clips, and rough AABB
## for the imported character GLBs. Run: godot --headless -s res://tools/inspect.gd

func _initialize() -> void:
	for path in [
		"res://assets/characters/Knight.glb",
		"res://assets/enemies/Skeleton_Warrior.glb",
		"res://assets/dungeon/floor_tile_large.gltf.glb",
		"res://assets/dungeon/wall.gltf.glb",
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
			var names := ap.get_animation_list()
			print("  ANIMATIONS (", names.size(), "):")
			for a in names:
				if a.to_lower().contains("idle") or a.to_lower().contains("run") \
				or a.to_lower().contains("walk") or a.to_lower().contains("attack") \
				or a.to_lower().contains("hit") or a.to_lower().contains("death") \
				or a.to_lower().contains("die"):
					print("    * ", a)
		print("  AABB: ", _aabb(inst))
		inst.free()
	quit()

func _dump(n: Node, d: int) -> void:
	if d <= 2:
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

func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is VisualInstance3D:
			var a: AABB = cur.get_aabb()
			if first:
				box = a
				first = false
			else:
				box = box.merge(a)
		for c in cur.get_children():
			stack.append(c)
	return box

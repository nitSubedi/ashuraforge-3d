extends SceneTree
func _initialize() -> void:
	var inst := (load("res://assets/enemies/xbot_parts.glb") as PackedScene).instantiate()
	get_root().add_child(inst)
	var box := AABB(); var first := true
	var stack: Array = [inst]
	while not stack.is_empty():
		var c = stack.pop_back()
		if c is VisualInstance3D:
			var a: AABB = (c as VisualInstance3D).get_aabb()
			a = (c as Node3D).global_transform * a
			if first: box = a; first = false
			else: box = box.merge(a)
		for ch in c.get_children(): stack.push_back(ch)
	print("PARTS_AABB size=", box.size, " pos=", box.position)
	quit()

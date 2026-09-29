extends SceneTree
func _initialize() -> void:
	var inst := (load("res://assets/enemies/xbot_rigged.glb") as PackedScene).instantiate()
	get_root().add_child(inst)
	_dump(inst, 0)
	var box := AABB(); var first := true
	var st: Array = [inst]
	while not st.is_empty():
		var c = st.pop_back()
		if c is VisualInstance3D:
			var a: AABB = (c as VisualInstance3D).get_aabb(); a = (c as Node3D).global_transform * a
			if first: box=a; first=false
			else: box=box.merge(a)
		for ch in c.get_children(): st.push_back(ch)
	print("RIG AABB size=", box.size.snapped(Vector3(0.01,0.01,0.01)))
	quit()
func _dump(n,d):
	if d<=2: print("  ".repeat(d), n.name, " [", n.get_class(), "]")
	for c in n.get_children(): _dump(c,d+1)

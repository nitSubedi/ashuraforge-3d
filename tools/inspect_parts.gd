extends SceneTree
func _initialize() -> void:
	var inst := (load("res://assets/enemies/xbot_parts.glb") as PackedScene).instantiate()
	get_root().add_child(inst)
	_dump(inst, 0)
	quit()
func _dump(n: Node, d: int) -> void:
	var info := ""
	if n is MeshInstance3D:
		var a: AABB = (n as MeshInstance3D).get_aabb()
		info = "  pos=%s  meshsize=%s" % [(n as Node3D).global_position.snapped(Vector3(0.1,0.1,0.1)), a.size.snapped(Vector3(0.1,0.1,0.1))]
	print("  ".repeat(d), n.name, " [", n.get_class(), "]", info)
	for c in n.get_children(): _dump(c, d+1)

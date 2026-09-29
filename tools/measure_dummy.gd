extends SceneTree
var _f := 0
var _d
func _initialize() -> void:
	_d = Node3D.new()
	_d.set_script(load("res://scripts/dummy.gd"))
	get_root().add_child(_d)
func _process(_dt: float) -> bool:
	_f += 1
	if _f < 3: return false
	var box := AABB(); var first := true
	for p in _d.get_children():
		var m = p.get_node_or_null("Mesh")
		if m:
			var a: AABB = p.global_transform * (m as MeshInstance3D).get_aabb()
			if first: box = a; first = false
			else: box = box.merge(a)
	print("DUMMY size=", box.size.snapped(Vector3(0.01,0.01,0.01)), " min=", box.position.snapped(Vector3(0.01,0.01,0.01)))
	return true

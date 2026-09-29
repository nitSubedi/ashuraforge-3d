extends SceneTree

## Boot the REAL game scene and audit every building's world-space base Y using
## valid global_transform (nodes are under a proper Node3D scene here, unlike the
## measure tool that parented under the Window root). Ground truth for floating.
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	if _f < 30:
		return false
	var city := get_root().get_node_or_null("Main/FleshCity")
	if city == null:
		print("NO FleshCity")
		return true
	var meshes: Array[MeshInstance3D] = []
	_collect(city, meshes)
	var bases: Array[float] = []
	for m in meshes:
		var wa := m.global_transform * m.mesh.get_aabb()
		bases.append(wa.position.y)
	bases.sort()
	var n := bases.size()
	var floaters := 0
	for b in bases:
		if b > 2.0:
			floaters += 1
	print("REAL-SCENE buildings=", n)
	print("base_y min=", bases[0], " p50=", bases[n/2], " p90=", bases[n*9/10], " max=", bases[n-1])
	print("floaters (base>2u): ", floaters, " (", 100.0*floaters/n, "%)")
	return true

func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect(c, out)

extends SceneTree
var _f := 0
var _e
func _initialize() -> void:
	_e = (load("res://assets/enemies/enemy.tscn") as PackedScene).instantiate()
	get_root().add_child(_e)
func _process(_d): 
	_f += 1
	if _f < 3: return false
	var box := AABB(); var first := true
	var st: Array = [_e]
	while not st.is_empty():
		var c = st.pop_back()
		if c is VisualInstance3D:
			var a: AABB = (c as VisualInstance3D).get_aabb(); a = (c as Node3D).global_transform * a
			if first: box=a; first=false
			else: box=box.merge(a)
		for ch in c.get_children(): st.push_back(ch)
	print("ENEMY size=", box.size.snapped(Vector3(0.01,0.01,0.01)), " min=", box.position.snapped(Vector3(0.01,0.01,0.01)))
	return true

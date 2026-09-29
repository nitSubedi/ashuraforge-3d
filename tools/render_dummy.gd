extends SceneTree
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var pl = get_root().get_node_or_null("Main/Player")
	if _f == 25 and pl: pl.global_position = Vector3(0,1.0,5.5)  # stand back, look at dummy(z=3)
	if _f == 45:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/dummy.png")
		print("DUMMY_SAVED parts=", get_nodes_in_group("enemy_part").size())
		return true
	return false

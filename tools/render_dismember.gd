extends SceneTree
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var pl = get_root().get_node_or_null("Main/Player")
	if _f == 20 and pl: pl.global_position = Vector3(0,0.05,4.6)
	if pl and _f >= 30 and _f <= 90 and _f % 10 == 0: pl._do_attack("foot")
	# screenshot later so gibs have time to fall
	if _f == 220:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/dismember.png")
		var gibs := 0
		for n in get_root().get_node("Main").get_children():
			if n is RigidBody3D: gibs += 1
		print("DISMEMBER_SAVED parts_left=", get_nodes_in_group("enemy_part").size(), " gibs=", gibs)
		return true
	return false

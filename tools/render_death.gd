extends SceneTree
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var pl = get_root().get_node_or_null("Main/Player")
	if _f == 20 and pl: pl.global_position = Vector3(0,0.05,4.6)
	if _f == 30:
		var en = get_nodes_in_group("enemies")[0]
		en.take_damage(999.0, 4242, Vector3(0,0,-1))   # force the kill -> death anim + explosion
		print("forced kill on ", en.name)
	if _f == 160:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/death.png")
		var gibs := 0
		for n in get_root().get_node("Main").get_children():
			if n is RigidBody3D: gibs += 1
		print("DEATH_SAVED gibs=", gibs)
		return true
	return false

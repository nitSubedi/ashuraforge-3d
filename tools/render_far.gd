extends SceneTree
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var pl = get_root().get_node_or_null("Main/Player")
	if _f == 20 and pl: pl.global_position = Vector3(160, 1.0, -160)  # far from origin
	if _f == 70:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/far_render.png")
		print("FAR_RENDER_SAVED  player_y=", pl.global_position.y if pl else -999)
		return true
	return false

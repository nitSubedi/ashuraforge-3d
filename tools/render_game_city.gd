extends SceneTree

## Boots the ACTUAL game scene (main.tscn) and screenshots from the player's
## camera, to confirm the city now shows up in-game.
## Run: godot --path . -s res://tools/render_game_city.gd
var _f := 0
func _initialize() -> void:
	get_root().size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/main.tscn")
var _cam: Camera3D
func _process(_d: float) -> bool:
	_f += 1
	var pl = get_root().get_node_or_null("Main/Player") as Node3D
	if _f == 15 and pl:
		pl.global_position = Vector3(0.0, 1.0, -18.0)
	if _f == 30 and _cam == null:
		# Low side-on inspection camera framing where buildings meet the ground.
		_cam = Camera3D.new()
		_cam.fov = 55.0
		_cam.far = 6000.0
		get_root().get_node("Main").add_child(_cam)
		_cam.look_at_from_position(Vector3(35, 14, 30), Vector3(5, 0, -120), Vector3.UP)
		_cam.make_current()
	if _f == 120:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/game_city.png")
		print("GAME_CITY_SAVED player_pos=", pl.global_position if pl else "?")
		return true
	return false

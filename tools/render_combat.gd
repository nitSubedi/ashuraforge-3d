extends SceneTree
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var pl = get_root().get_node_or_null("Main/Player")
	if _f == 36 and pl: pl._do_attack("hand")   # h1 attack_slash
	if _f == 50 and pl: pl._do_attack("hand")    # -> h2 cane2
	if _f == 64 and pl: pl._do_attack("foot")    # -> f2 roundhouse (cross-branch)
	if _f == 72:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/combat_render.png")
		print("COMBAT_RENDER_SAVED")
		return true
	return false

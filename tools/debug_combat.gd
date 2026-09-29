extends SceneTree
var _f := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var pl = get_root().get_node_or_null("Main/Player")
	if _f == 25 and pl: pl.global_position = Vector3(0,0.05,4.6)
	if pl and _f in [40,55,70,85,100,115]: pl._do_attack("hand")
	if _f == 130:
		var parts = get_nodes_in_group("enemy_part")
		print("parts_left=", parts.size())
		for p in parts: print("  ", p.name, " hp=", p.hp)
		print("attack_id=", pl._attack_id, " attacking=", pl._attacking, " buffered=", pl._buffered)
		return true
	return false

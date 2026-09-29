extends SceneTree
## Headless check of the signature powers: fills Blood, fires each power in turn
## near the demon pack, and reports damage dealt, Blood flow and any errors.
var _f := 0
var _pl
var _hp0 := 0.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _hp() -> float:
	var t := 0.0
	for e in get_nodes_in_group(&"enemies"):
		t += e.hp
	return t
func _physics_process(_d: float) -> bool:
	_f += 1
	_pl = get_root().get_node_or_null("Main/Player")
	if _pl == null or _f < 30:
		return false
	if _f == 30:
		_pl.global_position = Vector3(0, 0.05, -2.0)
		_pl._yaw = PI   # face the pack (+Z)
		_pl.camera_pivot.rotation.y = PI
		_pl.abilities.gain_blood(100)
		_hp0 = _hp()
	var names := {60: 0, 400: 1, 700: 2}
	if names.has(_f):
		_pl.abilities.gain_blood(100)
		var h := _hp()
		var ok: bool = _pl.abilities.try_activate(names[_f])
		print("CAST %s ok=%s blood_after=%.0f" % [_pl.abilities.slots[names[_f]].display_name, ok, _pl.abilities.blood])
	if _f in [390, 690, 990]:
		print("  pack hp lost so far=%.0f  flying=%s  pos=%s" % [_hp0 - _hp(), _pl.flying, _pl.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
	# Non-headless: grab frames mid-power (blade orbit/strike, meteor impacts, smoke flight).
	if _f == 250:   # force a kill to check the final dismemberment + blood
		var es := get_nodes_in_group(&"enemies")
		es.sort_custom(func(a, b): return a.global_position.distance_to(_pl.global_position) < b.global_position.distance_to(_pl.global_position))
		es[0].take_damage(9999.0, 999999, Vector3(0, 2, 3))
	if DisplayServer.get_name() != "headless" and _f in [120, 300, 318, 470, 505, 720]:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/power_%d.png" % _f)
	return _f > 1000

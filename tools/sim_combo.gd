extends SceneTree
## Boots the real game, stands the hero ~3 m from an enemy and mashes a combo
## string, logging each move start, strike window, hit (with hitstop) and the
## gap to the target — a headless check of combat timing, lunge and chaining.
## Run: godot --headless --path . -s res://tools/sim_combo.gd  [SIM_INPUT=hhhff]
## SIM_SHOT=1 without --headless saves a frame at each impact (hit_N.png).
## Input chars: h = hand (J), f = foot (K), q = stance (Q). Ends with PASS/FAIL:
## every started striking move landed >= 1 hit, and the final stance equals
## SIM_EXPECT_STANCE (default "cane") with the blade in the matching place.

var _f := 0
var _pl: Node3D
var _en: Node3D
var _seq := "hhhhfffff"
var _next := 0
var _last := {}
var _t0 := 0
var _shots := 0
var _moves := {}   # move key -> hits landed (striking moves only)
var _cur := ""

func _initialize() -> void:
	if OS.has_environment("SIM_INPUT"):
		_seq = OS.get_environment("SIM_INPUT")
	change_scene_to_file("res://scenes/main.tscn")

func _physics_process(_d: float) -> bool:
	_f += 1
	if _pl == null:
		_pl = get_root().get_node_or_null("Main/Player") as Node3D
		return false
	if _en == null:
		var es := get_nodes_in_group(&"enemies")
		if es.is_empty():
			return _f > 600
		_en = es[0]
		_pl.global_position = _en.global_position + Vector3(0, 0.05, 3.0)
		_t0 = Time.get_ticks_msec()
		return false
	# Press the next button every ~0.18 s (a player mashing a string).
	if _f % 11 == 0 and _next < _seq.length():
		match _seq[_next]:
			"q": _pl._do_stance()
			"h": _pl._do_attack("hand")
			_: _pl._do_attack("foot")
		_next += 1
	var state := {"combo": _pl._combo, "win": _pl._hit_window, "stop": _pl._hitstop > 0.0}
	var ms: int = Time.get_ticks_msec() - _t0
	var gap: float = _pl.global_position.distance_to(_en.global_position)
	if state["combo"] != "" and state["combo"] != _cur and not _pl._nodes[state["combo"]]["hits"].is_empty():
		_moves[state["combo"]] = _moves.get(state["combo"], 0)
	_cur = state["combo"]
	if state["combo"] != _last.get("combo"):
		print("%5d ms  %-6s clip=%-12s wind_speed=%.2f gap=%.2f" % [ms, state["combo"], _pl._combo_clip, _pl._wind_speed, gap])
	elif state["win"] != _last.get("win") and state["win"] >= 0:
		print("%5d ms    strike #%d at clip t=%.2f  gap=%.2f" % [ms, state["win"], _pl.driver.action_time, gap])
	if state["stop"] and not _last.get("stop", false):
		print("%5d ms    HIT  hitstop=%.2fs  enemy hp=%.0f" % [ms, _pl._hitstop, _en.hp])
		if _moves.has(state["combo"]):
			_moves[state["combo"]] += 1
		if OS.has_environment("SIM_SHOT") and _shots < 4:   # non-headless only
			get_root().get_texture().get_image().save_png("res://assets/generation/out/hit_%d.png" % _shots)
			_shots += 1
	_last = state
	var done: bool = _f > 1200 or (_next >= _seq.length() and state["combo"] == "" and _f > 200)
	if done:
		_report()
	return done

func _report() -> void:
	var want := OS.get_environment("SIM_EXPECT_STANCE") if OS.has_environment("SIM_EXPECT_STANCE") else "cane"
	var drawn: bool = _pl._sheath.get_parent() == _pl._sheath_grip
	var ok := true
	for k in _moves:
		if _moves[k] == 0:
			print("FAIL: move ", k, " landed no hit")
			ok = false
	if _pl._stance != want or drawn != (want == "sword"):
		print("FAIL: stance=", _pl._stance, " blade drawn=", drawn, " (want ", want, ")")
		ok = false
	print("moves=", _moves, " stance=", _pl._stance, " drawn=", drawn)
	print("PASS" if ok else "FAIL")

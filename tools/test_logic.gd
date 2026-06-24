extends SceneTree
## Lightweight logic tests for the slice's non-visual systems (Health + round
## win/lose). Run: godot --headless --path . -s res://tools/test_logic.gd
## Exits 0 only if all assertions pass.

var _fail := 0

func _initialize() -> void:
	_test_health()
	_test_win()
	_test_lose()
	if _fail == 0:
		print("ALL TESTS PASSED")
	else:
		print("TESTS FAILED: ", _fail)
	quit(_fail)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  - ", label)
	else:
		_fail += 1
		print("  FAIL- ", label)

func _test_health() -> void:
	print("[Health]")
	var HealthScript := load("res://scripts/health.gd")
	var h = HealthScript.new()
	h.max_health = 10.0
	h._ready()
	var died := [false]
	h.died.connect(func() -> void: died[0] = true)
	h.take_damage(4.0)
	_check(is_equal_approx(h.current, 6.0), "damage reduces health (6 left)")
	_check(not died[0], "not dead at 6 hp")
	h.take_damage(10.0)
	_check(is_equal_approx(h.current, 0.0), "health floors at 0")
	_check(died[0], "died fires at 0 hp")
	h.heal(5.0)
	_check(is_equal_approx(h.current, 0.0), "no heal after death")
	h.free()

func _test_win() -> void:
	print("[Win condition]")
	var game := root.get_node_or_null(^"Game")
	_check(game != null, "Game autoload present")
	if game == null:
		return
	var result := [99]
	var cb := func(won: bool) -> void: result[0] = 1 if won else 0
	game.game_over.connect(cb)
	game.start_round(2)
	game.report_enemy_died()
	_check(result[0] == 99, "no game over with 1/2 enemies down")
	game.report_enemy_died()
	_check(result[0] == 1, "victory when all enemies down")
	game.game_over.disconnect(cb)

func _test_lose() -> void:
	print("[Lose condition]")
	var game := root.get_node_or_null(^"Game")
	if game == null:
		return
	var result := [99]
	var cb := func(won: bool) -> void: result[0] = 1 if won else 0
	game.game_over.connect(cb)
	game.start_round(1)  # resets the over-latch
	game.report_player_died()
	_check(result[0] == 0, "defeat when player dies")
	game.game_over.disconnect(cb)

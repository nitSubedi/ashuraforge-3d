extends SceneTree
## First-contact hitch check: boots the game, walks to the enemy and attacks
## (first hits = first blood particles), logging any frame > 25 ms.
var _f := 0
var _last := 0
var _worst := 0.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var now := Time.get_ticks_usec()
	var pl = get_root().get_node_or_null("Main/Player")
	if _f > 90 and pl:
		var dt := (now - _last) / 1000.0
		_worst = maxf(_worst, dt)
		if dt > 25.0:
			print("HITCH frame=%d %.0fms attacking=%s" % [_f, dt, pl._attacking])
		if _f % 20 == 0 and _f < 400:
			pl._do_attack("hand" if (_f / 20) % 2 == 0 else "foot")
	_last = now
	if _f == 420:
		print("COMBAT_WORST %.1fms" % _worst)
		return true
	return false

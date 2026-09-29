extends SceneTree
func _initialize() -> void:
	var inst := (load("res://assets/characters/hero.tscn") as PackedScene).instantiate()
	var ap := _find(inst)
	for clip in ["idle","walk","run","kick_hook"]:
		var a := ap.get_animation(clip)
		if a == null: continue
		for ti in a.get_track_count():
			var path := str(a.track_get_path(ti))
			if a.track_get_type(ti) == Animation.TYPE_POSITION_3D and ("Hips" in path or path.ends_with(":Hips")):
				var p0: Vector3 = a.position_track_interpolate(ti, 0.0)
				var p1: Vector3 = a.position_track_interpolate(ti, a.length)
				print(clip, "  hips Δ = ", (p1-p0).snapped(Vector3(0.001,0.001,0.001)), "  (len ", a.length, ")")
	quit()
func _find(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find(c)
		if r: return r
	return null

extends SceneTree
## Popping probe: stands still, spins the camera 1 deg/frame through 360 deg and
## records objects/primitives drawn per frame. Smooth rotation should change
## these smoothly; culling or streaming pops show up as big frame-to-frame jumps.
## Run NON-headless: godot --path . -s res://tools/pop_probe.gd
var _f := 0
var _pl
var _objs := []
var _prims := []
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	_pl = get_root().get_node_or_null("Main/Player")
	if _pl == null or _f < 150:
		return false
	var start := 150
	if OS.has_environment("POP_CENTER"):
		start = 260   # 110 frames to settle after the teleport
		if _f == 150:
			var st = get_root().find_child("CityStreamer", true, false)
			_pl.set_physics_process(false)
			_pl.global_position = Vector3(0, 60.0, float(st.floor_layout["cz"]))   # above rooftops, mid-city
		if _f < start:
			return false
	var k := _f - start
	if k <= 360:
		_pl._yaw = deg_to_rad(k)
		_pl.camera_pivot.rotation.y = _pl._yaw
		if k % 45 == 0:
			var st = get_root().find_child("CityStreamer", true, false)
			if st:
				print("  yaw=%d chunks_loaded=%d" % [k, st.loaded_count()])
		if k > 2:
			_objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		return false
	var jumps := 0
	var worst := 0.0
	for i in range(1, _prims.size()):
		var a: float = _prims[i - 1]
		var b: float = _prims[i]
		var rel := absf(b - a) / maxf(maxf(a, b), 1.0)
		worst = maxf(worst, rel)
		if rel > 0.25:
			jumps += 1
	print("POP frames=%d big_jumps(>25%%)=%d worst_jump=%.0f%% objs[min=%d max=%d] occlusion=%s" % [
		_prims.size(), jumps, worst * 100.0, _objs.min(), _objs.max(),
		ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling")])
	return true

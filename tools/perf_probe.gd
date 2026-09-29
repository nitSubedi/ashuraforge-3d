extends SceneTree
## Boots the real game, walks the hero forward and logs frame-time stats:
## avg / p95 / worst frame, FPS, draw calls, physics tick rate vs display rate.
## Run NON-headless: godot --path . -s res://tools/perf_probe.gd
var _f := 0
var _times := []
var _last := 0
var _calls := 0
var _cpu := 0.0
var _gpu := 0.0
var _phys := 0.0
var _n := 0
var _proc := 0.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_f += 1
	var vp := get_root().get_viewport_rid()
	if _f == 5:
		RenderingServer.viewport_set_measure_render_time(vp, true)
	if _f > 120:
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_n += 1
	var now := Time.get_ticks_usec()
	if _f > 120:   # skip load hitches
		var dt := (now - _last) / 1000.0
		_times.append(dt)
		if dt > 50.0:
			print("HITCH frame=%d %.0fms t=%.1fs" % [_f, dt, now / 1e6])
		_calls = maxi(_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		Input.action_press(&"move_forward")
	_last = now
	if _f == 600:
		_times.sort()
		var n := _times.size()
		var avg := 0.0
		for t in _times: avg += t
		avg /= n
		print("PERF frames=%d avg=%.2fms p95=%.2fms worst=%.2fms fps=%.0f draw_calls_max=%d refresh=%.0fHz physics=%dHz" % [
			n, avg, _times[int(n * 0.95)], _times[n - 1], 1000.0 / avg, _calls,
			DisplayServer.screen_get_refresh_rate(), Engine.physics_ticks_per_second])
		print("SPLIT render_cpu=%.2fms gpu=%.2fms physics=%.2fms process=%.2fms enemies=%d" % [_cpu / _n, _gpu / _n, _phys / _n, _proc / _n, get_nodes_in_group(&"enemies").size()])
		return true
	return false

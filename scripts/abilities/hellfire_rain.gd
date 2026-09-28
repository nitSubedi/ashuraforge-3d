extends "res://scripts/abilities/ability.gd"
## Hellfire Rain: marks the ground (nearest demon ahead, else the spot the camera
## looks at), then staggered volleys of burning meteors fall on it — each impact
## knocks demons down and leaves burning ground that keeps damaging.

const VOLLEYS := 3
const PER_VOLLEY := 4
const VOLLEY_GAP := 0.35
const SPREAD := 3.6
const FALL_TIME := 0.55
const IMPACT_R := 2.8
const IMPACT_DMG := 38.0
const BURN_TIME := 3.0
const BURN_R := 2.0
const BURN_DMG := 7.0

var _target := Vector3.ZERO
var _queue: Array = []        # [spawn_time, offset]
var _meteors: Array = []      # [node, start, end, t]
var _burns: Array = []        # [node, pos, time_left, tick]
var _clock := 0.0
var _marker: MeshInstance3D

func _init() -> void:
	display_name = "Hellfire Rain"
	cost = 50.0
	cooldown = 12.0

func _activate() -> void:
	_target = _pick_target()
	_clock = 0.0
	_queue.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for v in VOLLEYS:
		for i in PER_VOLLEY:
			var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).limit_length(1.0) * SPREAD
			_queue.append([0.45 + v * VOLLEY_GAP + i * 0.05, off])
	# Ground mark: a glowing ring that warns where fire will fall.
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = SPREAD + 0.6
	ring.outer_radius = SPREAD + 0.9
	_marker.mesh = ring
	_marker.material_override = glow_mat(Color(1.0, 0.25, 0.05), 4.0)
	world().add_child(_marker)
	_marker.global_position = _target + Vector3(0, 0.05, 0)

func _pick_target() -> Vector3:
	var cam := player.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best: Node3D = null
	var bd := 20.0
	for e in enemies_near(player.global_position, 20.0):
		var to: Vector3 = (e as Node3D).global_position - player.global_position
		to.y = 0.0
		if to.normalized().dot(fwd) > 0.3 and to.length() < bd:
			bd = to.length()
			best = e
	if best:
		return Vector3(best.global_position.x, 0.0, best.global_position.z)
	var p := player.global_position + fwd * 9.0
	return Vector3(p.x, 0.0, p.z)

func _process(delta: float) -> void:
	if not active:
		_tick_burns(delta)
		return
	_clock += delta
	for q in _queue.duplicate():
		if _clock >= q[0]:
			_queue.erase(q)
			_spawn_meteor(_target + q[1])
	for m in _meteors.duplicate():
		m[3] += delta / FALL_TIME
		var node: Node3D = m[0]
		node.global_position = (m[1] as Vector3).lerp(m[2], minf(m[3], 1.0))
		if m[3] >= 1.0:
			_meteors.erase(m)
			_impact(m[2])
			node.queue_free()
	_tick_burns(delta)
	if _queue.is_empty() and _meteors.is_empty():
		if _marker:
			_marker.queue_free()
			_marker = null
		end()

func _spawn_meteor(ground: Vector3) -> void:
	var node := Node3D.new()
	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.45
	sph.height = 0.9
	core.mesh = sph
	core.material_override = glow_mat(Color(1.0, 0.45, 0.1), 6.0)
	node.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.1)
	light.light_energy = 3.0
	light.omni_range = 6.0
	node.add_child(light)
	var trail := GPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 0.8, 0.4, 1))
	fade.set_color(1, Color(0.6, 0.1, 0.02, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	trail.process_material = pm
	var q := QuadMesh.new()
	q.material = particle_mat(Color(1.0, 0.35, 0.06), true, 1.6)
	trail.draw_pass_1 = q
	node.add_child(trail)
	world().add_child(node)
	var start := ground + Vector3(randf_range(-4, 4), 28.0, randf_range(-4, 4))
	node.global_position = start
	_meteors.append([node, start, ground + Vector3(0, 0.3, 0), 0.0])

func _impact(p: Vector3) -> void:
	burst(p, Color(1.0, 0.45, 0.08), 36, 9.0, 0.7, 0.3, 1.0)
	burst(p, Color(0.12, 0.09, 0.09, 0.6), 16, 3.0, 1.2, 1.2, 0.1, false)   # smoke
	for e in enemies_near(p, IMPACT_R):
		var away: Vector3 = (e as Node3D).global_position - p
		away.y = 0.0
		hit(e, IMPACT_DMG, away.normalized() * 5.0 + Vector3.UP * 4.0, 0.07)
	player.add_trauma(0.25)
	# Burning ground patch.
	var patch := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = BURN_R
	disc.bottom_radius = BURN_R
	disc.height = 0.04
	patch.mesh = disc
	patch.material_override = glow_mat(Color(0.9, 0.18, 0.02), 2.5)
	world().add_child(patch)
	patch.global_position = Vector3(p.x, 0.03, p.z)
	_burns.append([patch, p, BURN_TIME, 0.0])

func _tick_burns(delta: float) -> void:
	for b in _burns.duplicate():
		b[2] -= delta
		b[3] -= delta
		var patch: MeshInstance3D = b[0]
		var mat := patch.material_override as StandardMaterial3D
		mat.emission_energy_multiplier = 1.5 + sin(Time.get_ticks_msec() * 0.02 + b[1].x) * 0.8
		if b[3] <= 0.0:
			b[3] = 0.5
			for e in enemies_near(b[1], BURN_R):
				hit(e, BURN_DMG, Vector3.UP * 0.5, 0.0)
		if b[2] <= 0.0:
			patch.queue_free()
			_burns.erase(b)

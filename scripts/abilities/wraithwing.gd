extends "res://scripts/abilities/ability.gd"
## Wraithwing: the hero dissolves into a streak of black smoke and flies where
## the camera looks (up onto rooftops too), steerable with WASD, invulnerable,
## tearing through demons he passes; he lands with a shockwave. Press again to
## land early.

const DURATION := 2.8
const SPEED := 15.0
const PASS_R := 1.6
const PASS_DMG := 22.0
const LAND_R := 4.5
const LAND_DMG := 34.0

var _t := 0.0
var _smoke: GPUParticles3D
var _passed := {}
var _mask := 0

func _init() -> void:
	display_name = "Wraithwing"
	cost = 25.0
	cooldown = 6.0

func reactivate() -> void:
	_t = 0.0   # land now

func _activate() -> void:
	_t = DURATION
	_passed.clear()
	_mask = player.collision_mask
	player.collision_mask = 1            # through demons, not through buildings
	player.set_flying(true)
	burst(player.global_position + Vector3(0, 1, 0), Color(0.02, 0.02, 0.03, 0.7), 40, 4.0, 0.8, 0.9, 0.0, false)
	_smoke = GPUParticles3D.new()
	_smoke.amount = 220
	_smoke.lifetime = 0.9
	_smoke.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.35
	pm.scale_max = 0.85
	var fade := Gradient.new()      # dense black core, thinning to a crimson-tinged wisp
	fade.set_color(0, Color(0.0, 0.0, 0.0, 0.7))
	fade.add_point(0.5, Color(0.04, 0.0, 0.01, 0.4))
	fade.set_color(fade.get_point_count() - 1, Color(0.12, 0.01, 0.02, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_smoke.process_material = pm
	var q := QuadMesh.new()
	q.material = particle_mat(Color.BLACK, false)
	_smoke.draw_pass_1 = q
	player.add_child(_smoke)
	_smoke.position = Vector3(0, 1.0, 0)

func _physics_process(delta: float) -> void:
	if not active:
		return
	_t -= delta
	# Fly where the camera looks, bent by WASD.
	var cam := player.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else Vector3.FORWARD
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := fwd * maxf(0.35, -input.y) + cam.global_basis.x * input.x if cam else fwd
	player.flight_velocity = player.flight_velocity.lerp(dir.normalized() * SPEED, 1.0 - exp(-6.0 * delta))
	for e in enemies_near(player.global_position + Vector3(0, 1, 0), PASS_R):
		if not _passed.has(e):
			_passed[e] = true
			var v: Vector3 = player.flight_velocity
			hit(e, PASS_DMG, v.normalized() * 4.0 + Vector3.UP * 2.0, 0.04)
	if _t <= 0.0:
		end()

func _end() -> void:
	player.set_flying(false)
	player.collision_mask = _mask
	if _smoke:
		_smoke.emitting = false
		var s := _smoke
		get_tree().create_timer(1.0).timeout.connect(s.queue_free)
		_smoke = null
	# Landing shockwave.
	var p := player.global_position
	burst(p + Vector3(0, 0.3, 0), Color(0.03, 0.03, 0.04, 0.7), 50, 8.0, 0.7, 0.9, 0.0, false)
	for e in enemies_near(p, LAND_R):
		var away: Vector3 = (e as Node3D).global_position - p
		away.y = 0.0
		hit(e, LAND_DMG, away.normalized() * 6.0 + Vector3.UP * 3.0, 0.08)
	player.add_trauma(0.45)

extends StaticBody3D
## Rigged enemy built on the working X Bot rig (idle / hurt / death animations),
## tinted red. Takes damage from melee (one hit per swing) with a real hurt
## reaction; on death it plays the death anim then bursts into bloody physics
## gibs (dismemberment), and respawns after a few seconds.

const BODY := preload("res://assets/enemies/xbot_enemy.tscn")  # X Bot rig (hero.tscn is now the real hero)
const PARTS := preload("res://assets/enemies/xbot_parts.glb")
const MAX_HP := 320.0
const PARTS_SCALE := 0.01
const PARTS_ROT := Vector3(90.0, 0.0, 0.0)

var hp := MAX_HP
var _last_attack := -1
var _dead := false
var _anim: AnimationPlayer
var _body: Node3D
var _mat: StandardMaterial3D
var _stop := 0.0   # remaining hitstop (s): animation frozen in the hit pose

func _ready() -> void:
	add_to_group(&"enemies")
	collision_layer = 4   # detected by the player's MeleeHitbox (mask 4)
	collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.5, 0.09, 0.10)
	_mat.roughness = 0.6
	_spawn_body()

func _spawn_body() -> void:
	_dead = false
	hp = MAX_HP
	_body = BODY.instantiate()
	add_child(_body)
	for m in _meshes(_body):
		m.material_override = _mat
		m.material_overlay = _rim()
	_anim = _body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null and _anim.has_animation("idle"):
		_anim.play("idle")
		if not _anim.animation_finished.is_connected(_on_anim_finished):
			_anim.animation_finished.connect(_on_anim_finished)

func take_damage(amount: float, attack_id: int, impulse: Vector3) -> void:
	if _dead or attack_id == _last_attack:
		return
	_last_attack = attack_id
	hp -= amount
	_blood(global_position + Vector3(0, 1.0, 0), impulse.normalized(), 34, 1.0, 4.5)
	if hp <= 0.0:
		_die(impulse)
	elif _anim != null and _anim.has_animation("hit"):
		# Restart the reaction on every hit (play() alone is a no-op mid-"hit").
		_anim.play("hit", 0.05)
		_anim.seek(0.0, true)
	# Knockback: a short shove away from the attacker, bigger for heavier hits.
	var shove := impulse
	shove.y = 0.0
	if shove.length() > 0.01:
		var tw := create_tween()
		tw.tween_property(self, "position", position + shove.normalized() * clampf(amount / 120.0, 0.12, 0.6), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Freeze the animation on the hit pose for `secs` (the attacker calls this on
## contact so both bodies lock together for a beat — the GoW hitstop).
func hitstop(secs: float) -> void:
	if _anim == null or _dead:
		return
	_stop = maxf(_stop, secs)
	_anim.speed_scale = 0.04

func _process(delta: float) -> void:
	if _stop > 0.0:
		_stop -= delta
		if _stop <= 0.0 and _anim != null:
			_anim.speed_scale = 1.0

func _on_anim_finished(which: StringName) -> void:
	if not _dead and _anim != null and String(which) == "hit":
		_anim.play("idle", 0.15)

func _die(impulse: Vector3) -> void:
	_dead = true
	if _anim != null and _anim.has_animation("death"):
		_anim.play("death", 0.1)
	_after(0.7, func(): _explode(impulse))

func _explode(impulse: Vector3) -> void:
	if _body != null:
		_body.queue_free()
		_body = null
	# The final burst: a heavy spray + mist, and a spreading pool underneath.
	var chest := global_position + Vector3(0, 1.1, 0)
	_blood(chest, Vector3.UP + impulse.normalized() * 0.4, 130, 1.1, 8.0)
	_blood(chest, impulse.normalized(), 70, 0.9, 10.0)
	_blood(chest + Vector3(0, -0.4, 0), Vector3.UP, 60, 0.7, 5.0)
	_blood_pool(global_position, 1.3)
	var src := PARTS.instantiate()
	src.scale = Vector3(PARTS_SCALE, PARTS_SCALE, PARTS_SCALE)
	src.rotation_degrees = PARTS_ROT
	add_child(src)
	for mi in _meshes(src):
		_make_gib(mi, impulse)
	src.queue_free()
	_after(4.0, _spawn_body)

# Robust delayed call via a one-shot child Timer (await timers were unreliable here).
func _after(secs: float, fn: Callable) -> void:
	var t := Timer.new()
	t.wait_time = secs
	t.one_shot = true
	t.autostart = true
	add_child(t)
	t.timeout.connect(fn)
	t.timeout.connect(t.queue_free)

func _make_gib(mi: MeshInstance3D, impulse: Vector3) -> void:
	if mi.mesh == null:
		return
	var s := mi.global_transform.basis.get_scale()
	var gib := RigidBody3D.new()
	gib.collision_layer = 8
	gib.collision_mask = 1
	gib.gravity_scale = 1.6
	var vis := MeshInstance3D.new()
	vis.mesh = mi.mesh
	vis.scale = s
	vis.material_override = _mat
	gib.add_child(vis)
	var aabb := mi.mesh.get_aabb()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(aabb.size.x * s.x, 0.05), maxf(aabb.size.y * s.y, 0.05), maxf(aabb.size.z * s.z, 0.05))
	col.shape = box
	col.position = (aabb.position + aabb.size * 0.5) * s
	gib.add_child(col)
	get_tree().current_scene.add_child(gib)
	gib.global_transform = Transform3D(mi.global_transform.basis.orthonormalized(), mi.global_position)
	var outward := (gib.global_position - (global_position + Vector3(0, 1, 0)))
	outward.y = 0.0
	outward = outward.normalized() if outward.length() > 0.05 else impulse.normalized()
	# Violent and immediate: the parts are cut in the rest pose, so the burst
	# must break that silhouette apart within a frame or two.
	gib.apply_central_impulse(outward * 7.5 + Vector3.UP * 4.5 + impulse * 0.4)
	gib.angular_velocity = Vector3(randf_range(-16, 16), randf_range(-16, 16), randf_range(-16, 16))
	_blood(gib.global_position, outward, 45, 1.0, 5.0)
	_gib_trail(gib)
	var t := Timer.new()
	t.wait_time = 10.0
	t.one_shot = true
	t.autostart = true
	gib.add_child(t)
	t.timeout.connect(gib.queue_free)

static var _rim_mat: ShaderMaterial

## Hot red rim so demons separate from the red world.
static func _rim() -> ShaderMaterial:
	if _rim_mat == null:
		_rim_mat = ShaderMaterial.new()
		_rim_mat.shader = preload("res://assets/shaders/rim.gdshader")
		_rim_mat.set_shader_parameter("rim_color", Color(1.0, 0.38, 0.22))
		_rim_mat.set_shader_parameter("strength", 0.45)
	return _rim_mat

func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

## --- blood ------------------------------------------------------------------
## Real-looking blood, not glowing magic: dark, glossy, LIT (catches the scene
## light), velocity-stretched droplets under gravity + a thin mist; big events
## also stain the ground. Shared textures/materials are built once.

static var _soft_tex: GradientTexture2D
static var _drop_mat: StandardMaterial3D
static var _mist_mat: StandardMaterial3D
static var _pool_tex: GradientTexture2D

static func _blood_assets() -> void:
	if _drop_mat != null:
		return
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.55, Color(1, 1, 1, 0.8))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_soft_tex = GradientTexture2D.new()
	_soft_tex.gradient = g
	_soft_tex.fill = GradientTexture2D.FILL_RADIAL
	_soft_tex.fill_from = Vector2(0.5, 0.5)
	_soft_tex.fill_to = Vector2(1.0, 0.5)
	_drop_mat = StandardMaterial3D.new()                 # wet, lit droplets
	_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_drop_mat.billboard_keep_scale = true
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.albedo_texture = _soft_tex
	_drop_mat.vertex_color_use_as_albedo = true
	_drop_mat.roughness = 0.15
	_drop_mat.metallic_specular = 0.9
	_mist_mat = _drop_mat.duplicate() as StandardMaterial3D
	_mist_mat.roughness = 0.6
	var pg := Gradient.new()                             # ground pool: dark core, soft rim
	pg.set_color(0, Color(0.16, 0.0, 0.005, 0.95))
	pg.add_point(0.6, Color(0.22, 0.0, 0.01, 0.85))
	pg.set_color(pg.get_point_count() - 1, Color(0.25, 0.0, 0.01, 0.0))
	_pool_tex = GradientTexture2D.new()
	_pool_tex.gradient = pg
	_pool_tex.fill = GradientTexture2D.FILL_RADIAL
	_pool_tex.fill_from = Vector2(0.5, 0.5)
	_pool_tex.fill_to = Vector2(1.0, 0.5)
	_pool_tex.width = 128
	_pool_tex.height = 128

func _blood(pos: Vector3, dir: Vector3, amount: int, life: float, speed: float) -> void:
	_blood_assets()
	var d := dir.normalized() if dir.length() > 0.1 else Vector3.UP
	# Droplets: small quads stretched along their velocity.
	var p := _blood_emitter(amount, life, false)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = d
	pm.spread = 50.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed * 1.1
	pm.gravity = Vector3(0, -16.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.particle_flag_align_y = true
	pm.color = Color(0.3, 0.0, 0.012)
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.16)
	q.material = _drop_mat
	p.draw_pass_1 = q
	_place(p, pos)
	# Mist puff.
	var m := _blood_emitter(maxi(4, amount / 5), life * 0.6, false)
	var mm := m.process_material as ParticleProcessMaterial
	mm.direction = d
	mm.spread = 70.0
	mm.initial_velocity_min = speed * 0.1
	mm.initial_velocity_max = speed * 0.3
	mm.gravity = Vector3(0, -1.0, 0)
	mm.scale_min = 0.8
	mm.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(0.25, 0.0, 0.01, 0.45))
	fade.set_color(1, Color(0.18, 0.0, 0.01, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	mm.color_ramp = ramp
	var mq := QuadMesh.new()
	mq.size = Vector2(0.35, 0.35)
	mq.material = _mist_mat
	m.draw_pass_1 = mq
	_place(m, pos)

func _blood_emitter(amount: int, life: float, continuous: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = not continuous
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.0 if continuous else 0.9
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	p.process_material = pm
	return p

func _place(p: GPUParticles3D, pos: Vector3) -> void:
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## A blood pool projected on the ground (Decal), spreading then drying out.
func _blood_pool(pos: Vector3, radius: float) -> void:
	_blood_assets()
	var dcl := Decal.new()
	dcl.texture_albedo = _pool_tex
	dcl.size = Vector3(radius * 0.3, 1.0, radius * 0.3)
	dcl.cull_mask = 1
	get_tree().current_scene.add_child(dcl)
	dcl.global_position = Vector3(pos.x, 0.2, pos.z)
	dcl.rotation.y = randf() * TAU
	var tw := dcl.create_tween()
	tw.tween_property(dcl, "size", Vector3(radius * 2.0, 1.0, radius * 2.0 * randf_range(0.7, 1.0)), 0.9) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(8.0)
	tw.tween_property(dcl, "modulate:a", 0.0, 3.0)
	tw.tween_callback(dcl.queue_free)

## Blood streaming from a severed piece while it flies.
func _gib_trail(gib: Node3D) -> void:
	_blood_assets()
	var p := _blood_emitter(60, 0.7, true)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3.DOWN
	pm.spread = 30.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -14.0, 0)
	pm.particle_flag_align_y = true
	pm.color = Color(0.28, 0.0, 0.01)
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.09)
	q.material = _drop_mat
	p.draw_pass_1 = q
	gib.add_child(p)
	p.emitting = true
	var t := Timer.new()          # stop bleeding after a moment (child timer: freed with the gib)
	t.wait_time = 1.4
	t.one_shot = true
	t.autostart = true
	gib.add_child(t)
	t.timeout.connect(func(): p.emitting = false)

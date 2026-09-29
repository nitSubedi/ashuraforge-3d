extends RefCounted
## Shared VFX helpers (static): soft particle sprite, particle materials, bursts.
## Used by abilities and combat so every effect shares one look.

static var _soft: GradientTexture2D

## Soft round sprite (white core -> transparent edge); without it particle quads
## render as hard squares.
static func soft_tex() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft

## Particle material: soft sprite, vertex colour, billboard. Additive for
## fire/embers/sparks (glows and stacks), alpha blend for smoke/ash.
static func particle_mat(color: Color, additive := true, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex()
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0) if additive else Color(1, 1, 1, 1)
	m.disable_receive_shadows = true
	# Fade particles out right in front of the lens (otherwise a near spark,
	# ember or ash fleck fills the screen as a blurry disc).
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.6
	m.distance_fade_max_distance = 2.0
	return m

## One-shot burst of soft particles at p.
static func burst(parent: Node, p: Vector3, color: Color, amount: int, speed: float, life := 0.6,
		size := 0.12, up := 0.4, additive := true) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.explosiveness = 0.95
	gp.amount = amount
	gp.lifetime = life
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -6.0 * up, 0)
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.4
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = particle_mat(color, additive)
	gp.draw_pass_1 = q
	parent.add_child(gp)
	gp.global_position = p
	gp.emitting = true
	gp.finished.connect(gp.queue_free)

## Short, stretched, fast steel sparks (weapon contact). Dim on purpose: the
## HDR bloom inflates bright sparks into glowing orbs.
static func sparks(parent: Node, p: Vector3, dir: Vector3, amount := 10) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.explosiveness = 1.0
	gp.amount = amount
	gp.lifetime = 0.22
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -12, 0)
	pm.particle_flag_align_y = true
	var fade := Gradient.new()
	fade.set_color(0, Color(0.55, 0.45, 0.32, 1))
	fade.set_color(1, Color(0.4, 0.12, 0.05, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.16)
	var m := particle_mat(Color(1, 0.8, 0.55), true, 1.0)
	m.billboard_keep_scale = true
	q.material = m
	gp.draw_pass_1 = q
	parent.add_child(gp)
	gp.global_position = p
	gp.emitting = true
	gp.finished.connect(gp.queue_free)

extends Node
## Base signature power. Subclasses override _activate() / _tick() and call
## end() when done. The AbilitySystem owns Blood cost and cooldown.

var player: CharacterBody3D
var display_name := "Power"
var cost := 30.0
var cooldown := 8.0
var cooldown_left := 0.0
var active := false

func can_activate() -> bool:
	return not active

func activate() -> void:
	active = true
	_activate()

## Pressing the key while active (e.g. land Wraithwing early). Default: no-op.
func reactivate() -> void:
	pass

func end() -> void:
	active = false
	_end()

func _activate() -> void:
	pass

func _end() -> void:
	pass

# --- shared helpers --------------------------------------------------------

func enemies_near(p: Vector3, radius: float) -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e is Node3D and not e.get(&"_dead") and (e as Node3D).global_position.distance_to(p) <= radius:
			out.append(e)
	return out

func nearest_enemy(p: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for e in enemies_near(p, radius):
		var d: float = (e as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best

## Deal damage through the enemy's normal path (blood, reactions, gibs) and
## feed the player's Blood meter.
func hit(e: Node, dmg: float, impulse: Vector3, stop := 0.05) -> void:
	if not is_instance_valid(e) or not e.has_method(&"take_damage"):
		return
	e.take_damage(dmg, player.next_attack_id(), impulse)
	if e.has_method(&"hitstop"):
		e.hitstop(stop)
	player.on_ability_hit(e)

func world() -> Node:
	return player.get_tree().current_scene

static var _soft: GradientTexture2D

## Soft round sprite (white core -> transparent edge): every particle uses it,
## otherwise quads render as hard squares.
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

## Particle material: soft sprite, vertex colour, billboard. `additive` for
## fire/embers/energy (glows and stacks), alpha blend for smoke.
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
	return m

## Simple emissive unshaded material.
static func glow_mat(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

## One-shot burst of particles at p (embers, smoke, shockwave dust).
func burst(p: Vector3, color: Color, amount: int, speed: float, life := 0.6, size := 0.12, up := 0.4, additive := true) -> void:
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
	world().add_child(gp)
	gp.global_position = p
	gp.emitting = true
	gp.finished.connect(gp.queue_free)

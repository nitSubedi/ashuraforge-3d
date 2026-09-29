extends "res://scripts/abilities/ability.gd"
## Phantom Blade: the sword leaves the cane and hunts on its own — orbiting the
## hero, then lunging through the nearest demon and returning — while he keeps
## fighting with the cane. The real hilt+blade are hidden while it flies.

const DURATION := 8.0
const ORBIT_R := 1.7
const ORBIT_H := 1.35
const SEEK_RANGE := 8.0
const DASH_SPEED := 24.0
const STRIKE_GAP := 0.4
const DAMAGE := 28.0

var _blade: Node3D
var _t := 0.0
var _angle := 0.0
var _state := "orbit"
var _target: Node3D
var _gap := 0.0
var _hidden: Array = []
var _trail: MeshInstance3D
var _samples: Array = []      # recent [base, tip] world positions for the glint ribbon
const TRAIL_LEN := 12

func _init() -> void:
	display_name = "Phantom Blade"
	cost = 40.0
	cooldown = 10.0

func _activate() -> void:
	_t = DURATION
	_state = "orbit"
	_gap = 0.2
	_blade = Node3D.new()
	_blade.name = "PhantomBlade"
	world().add_child(_blade)
	# Copy the cane-sword's real hilt + blade meshes so it's the same weapon.
	for part in ["Hilt", "Blade"]:
		var src := player.find_child(part, true, false) as Node3D
		if src:
			var cp := src.duplicate() as Node3D
			cp.transform = Transform3D.IDENTITY
			_blade.add_child(cp)
			src.visible = false
			_hidden.append(src)
	# Readable at gameplay distance: thicker, with a spectral steel glint on top.
	_blade.scale = Vector3(2.4, 1.15, 2.4)
	var glint := StandardMaterial3D.new()
	glint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint.albedo_color = Color(0.55, 0.62, 0.8, 0.55)
	for mi in _blade.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).name.begins_with("Blade"):   # the steel only, not the crook
			(mi as MeshInstance3D).material_overlay = glint
	_trail = MeshInstance3D.new()
	_trail.top_level = true
	_trail.mesh = ImmediateMesh.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.vertex_color_use_as_albedo = true
	_trail.material_override = tm
	world().add_child(_trail)
	_samples.clear()
	_blade.global_position = player.global_position + Vector3(0, ORBIT_H, 0)

func _process(delta: float) -> void:
	if not active or _blade == null:
		return
	_t -= delta
	if _t <= 0.0:
		end()
		return
	var home := player.global_position + Vector3(0, ORBIT_H, 0)
	_gap -= delta
	match _state:
		"orbit":
			_angle += delta * 3.4
			var goal := home + Vector3(cos(_angle), 0.15 * sin(_angle * 2.0), sin(_angle)) * ORBIT_R
			_blade.global_position = _blade.global_position.lerp(goal, 1.0 - exp(-10.0 * delta))
			_point(Vector3(-sin(_angle), 0, cos(_angle)))
			if _gap <= 0.0:
				_target = nearest_enemy(player.global_position, SEEK_RANGE)
				if _target:
					_state = "dash"
		"dash":
			if not is_instance_valid(_target) or _target.get(&"_dead"):
				_state = "return"
			else:
				var aim := _target.global_position + Vector3(0, 1.1, 0)
				var to := aim - _blade.global_position
				_point(to)
				var step := DASH_SPEED * delta
				if to.length() <= step:
					var away := (aim - player.global_position)
					away.y = 0.0
					hit(_target, DAMAGE, away.normalized() * 3.0 + Vector3.UP * 1.5, 0.06)
					burst(aim, Color(0.32, 0.34, 0.42), 6, 5.0, 0.15, 0.04)   # steel spark (dim: bloom inflates bright sparks into orbs)
					_blade.global_position = aim + to.normalized() * 0.6   # follow through
					_state = "return"
					_gap = STRIKE_GAP
				else:
					_blade.global_position += to.normalized() * step
		"return":
			pass
	_update_trail()
	match _state:
		"return":
			var goal := home + Vector3(cos(_angle), 0, sin(_angle)) * ORBIT_R
			var to := goal - _blade.global_position
			_point(to)
			if to.length() < 0.4:
				_state = "orbit"
			else:
				_blade.global_position += to.normalized() * minf(DASH_SPEED * delta, to.length())

## Blade tip (local -Y of the cane-sword parts) points along dir.
func _point(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	var y := -dir.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	_blade.global_basis = Basis(x, y, x.cross(y)).orthonormalized()

## Glint ribbon: a strip between the blade's base and tip over the last few
## frames, bright at the blade and fading to nothing behind it.
func _update_trail() -> void:
	if _trail == null or _blade == null:
		return
	var base := _blade.global_transform * Vector3(0, -0.12, 0)
	var tip := _blade.global_transform * Vector3(0, -0.78, 0)
	_samples.push_front([base, tip])
	if _samples.size() > TRAIL_LEN:
		_samples.pop_back()
	var im := _trail.mesh as ImmediateMesh
	im.clear_surfaces()
	# Hold the ribbon until the blade has left his hands (it would smear across him).
	if _samples.size() < 2 or _t > DURATION - 0.35:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	# Full glint only when the blade is travelling fast (lunge/return); while it
	# circles close to the hero a long ribbon would overlap into a glowing disc.
	var strength := 1.0 if _state != "orbit" else 0.25
	var n := _samples.size() if _state != "orbit" else mini(_samples.size(), 5)
	for i in n:
		var a := (1.0 - float(i) / float(n - 1)) * strength
		var c := Color(0.75, 0.82, 1.0, 0.6 * a * a)
		im.surface_set_color(c)
		im.surface_add_vertex(_samples[i][0])
		im.surface_set_color(Color(1, 1, 1, 0.85 * a * a))
		im.surface_add_vertex(_samples[i][1])
	im.surface_end()

func _end() -> void:
	if _trail:
		_trail.queue_free()
		_trail = null
	if _blade:
		burst(_blade.global_position, Color(0.3, 0.32, 0.4), 6, 2.0, 0.2, 0.04)
		_blade.queue_free()
		_blade = null
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()

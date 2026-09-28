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
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.18, 0.12)
	light.light_energy = 2.5
	light.omni_range = 3.0
	_blade.add_child(light)
	_blade.global_position = player.global_position + Vector3(0, ORBIT_H, 0)
	burst(_blade.global_position, Color(1.0, 0.2, 0.1), 24, 3.0)

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
					burst(aim, Color(0.9, 0.05, 0.05), 14, 4.0, 0.4)
					_blade.global_position = aim + to.normalized() * 0.6   # follow through
					_state = "return"
					_gap = STRIKE_GAP
				else:
					_blade.global_position += to.normalized() * step
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

func _end() -> void:
	if _blade:
		burst(_blade.global_position, Color(1.0, 0.2, 0.1), 18, 2.5)
		_blade.queue_free()
		_blade = null
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()

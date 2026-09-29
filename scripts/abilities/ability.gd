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

const FX := preload("res://scripts/fx/fx.gd")

static func soft_tex() -> GradientTexture2D:
	return FX.soft_tex()

static func particle_mat(color: Color, additive := true, energy := 2.0) -> StandardMaterial3D:
	return FX.particle_mat(color, additive, energy)

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
	FX.burst(world(), p, color, amount, speed, life, size, up, additive)

extends CharacterBody3D
## Skeleton enemy with a small state machine: IDLE -> CHASE -> ATTACK.
## Direct-steering chase (no navmesh) is fine for a single open room; navigation
## arrives with the procedural-dungeon sub-project.

signal died

enum State { IDLE, CHASE, ATTACK, DEAD }

@export var move_speed: float = 3.0
@export var gravity: float = 18.0
@export var aggro_range: float = 14.0
@export var attack_range: float = 2.0
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 1.2

@onready var model: Node3D = $Model
@onready var health: Health = $Health

var _state: State = State.IDLE
var _player: Node3D = null
var _attack_ready: bool = true

const SFX_SCREAM := preload("res://audio/Scream.mp3")

func _ready() -> void:
	add_to_group(&"enemies")
	health.died.connect(_on_died)

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")

	if _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()

		if dist <= attack_range:
			_state = State.ATTACK
			velocity.x = 0.0
			velocity.z = 0.0
			_try_attack()
		elif dist <= aggro_range:
			_state = State.CHASE
			var dir := to_player.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
		else:
			_state = State.IDLE
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()

func _try_attack() -> void:
	if not _attack_ready or _player == null:
		return
	_attack_ready = false
	if _player.has_method(&"take_hit"):
		_player.take_hit(attack_damage)
	await get_tree().create_timer(attack_cooldown).timeout
	_attack_ready = true

## Called by player melee / projectile.
func take_hit(amount: float) -> void:
	if _state == State.DEAD:
		return
	health.take_damage(amount)
	_flash()

func _on_died() -> void:
	_state = State.DEAD
	_play(SFX_SCREAM)
	set_physics_process(false)
	died.emit()
	Game.report_enemy_died()
	# brief death fade then remove
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tween.tween_callback(queue_free)

func _flash() -> void:
	var mesh := model.get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		var orig: Color = mat.albedo_color
		mat.albedo_color = Color(1, 1, 1)
		await get_tree().create_timer(0.08).timeout
		if is_instance_valid(mesh) and mat is StandardMaterial3D:
			mat.albedo_color = orig

func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	add_child(p)
	p.stream = stream
	p.play()
	p.finished.connect(p.queue_free)

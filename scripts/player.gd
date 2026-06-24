extends CharacterBody3D
## Third-person over-shoulder player controller.
## Movement is camera-relative. Mouse drives the camera pivot (yaw) and spring arm
## (pitch); the visual model turns to face movement. Combat: melee swing + magic
## projectile, mapping to AshuraForge's Fire/Magic.

@export var speed: float = 5.0
@export var sprint_multiplier: float = 1.7
@export var jump_velocity: float = 5.0
@export var gravity: float = 18.0
@export var mouse_sensitivity: float = 0.0025
@export var turn_speed: float = 12.0

@export var melee_damage: float = 35.0
@export var magic_damage: float = 45.0
@export var dodge_speed: float = 12.0
@export var dodge_time: float = 0.35
@export var dodge_cooldown: float = 0.6

const PITCH_MIN := -1.2
const PITCH_MAX := 0.5

@onready var model: Node3D = $Model
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var muzzle: Marker3D = $Muzzle
@onready var melee_hitbox: Area3D = $MeleeHitbox
@onready var health: Health = $Health
@onready var sfx: AudioStreamPlayer = $Sfx

var _yaw: float = 0.0
var _pitch: float = -0.3
var _attacking: bool = false
var _dodging: bool = false
var _can_dodge: bool = true
var _invulnerable: bool = false

const SFX_PUNCH := preload("res://audio/Punch.mp3")
const SFX_FIRE := preload("res://audio/Fire.mp3")
const SFX_MAGIC := preload("res://audio/Magic3.mp3")
const SFX_HURT := preload("res://audio/hitHurt.wav")
const SFX_JUMP := preload("res://audio/jump.wav")
const PROJECTILE := preload("res://scenes/projectile.tscn")

func _ready() -> void:
	add_to_group(&"player")
	melee_hitbox.monitoring = false
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	Game.player_health_changed.emit(health.current, health.max_health)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)
		camera_pivot.rotation.y = _yaw
		spring_arm.rotation.x = _pitch
	elif event.is_action_pressed(&"attack"):
		_do_melee()
	elif event.is_action_pressed(&"cast"):
		_do_cast()
	elif event.is_action_pressed(&"dodge"):
		_do_dodge()
	elif Input.is_key_pressed(KEY_ESCAPE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed(&"jump") and not _dodging:
		velocity.y = jump_velocity
		_play(SFX_JUMP)

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := Vector3.ZERO
	dir += camera_pivot.global_basis.x * input.x
	dir += camera_pivot.global_basis.z * input.y
	dir.y = 0.0
	dir = dir.normalized()

	if _dodging:
		# Lock horizontal velocity to the dodge direction; keep gravity on y.
		velocity.x = velocity.x
		velocity.z = velocity.z
	else:
		var cur_speed := speed
		if Input.is_action_pressed(&"sprint"):
			cur_speed *= sprint_multiplier
		velocity.x = dir.x * cur_speed
		velocity.z = dir.z * cur_speed
		if dir.length() > 0.1:
			var target := atan2(dir.x, dir.z)
			model.rotation.y = lerp_angle(model.rotation.y, target, turn_speed * delta)

	move_and_slide()

func _do_melee() -> void:
	if _attacking or _dodging:
		return
	_attacking = true
	_play(SFX_PUNCH)
	melee_hitbox.monitoring = true
	await get_tree().create_timer(0.15).timeout
	for body in melee_hitbox.get_overlapping_bodies():
		if body.is_in_group(&"enemies") and body.has_method(&"take_hit"):
			body.take_hit(melee_damage)
	melee_hitbox.monitoring = false
	await get_tree().create_timer(0.25).timeout
	_attacking = false

func _do_cast() -> void:
	if _dodging:
		return
	_play(SFX_FIRE)
	var p := PROJECTILE.instantiate()
	get_tree().current_scene.add_child(p)
	var cam: Node3D = $CameraPivot/SpringArm3D/Camera3D
	var aim_dir := -cam.global_transform.basis.z
	p.global_position = muzzle.global_position
	if p.has_method(&"launch"):
		p.launch(aim_dir, magic_damage)

func _do_dodge() -> void:
	if _dodging or not _can_dodge:
		return
	_dodging = true
	_can_dodge = false
	_invulnerable = true
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := (camera_pivot.global_basis.x * input.x) + (camera_pivot.global_basis.z * input.y)
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = -model.global_basis.z  # dodge backward-relative-to-facing if no input
	dir = dir.normalized()
	velocity.x = dir.x * dodge_speed
	velocity.z = dir.z * dodge_speed
	await get_tree().create_timer(dodge_time).timeout
	_dodging = false
	_invulnerable = false
	await get_tree().create_timer(dodge_cooldown).timeout
	_can_dodge = true

func take_hit(amount: float) -> void:
	if _invulnerable:
		return
	health.take_damage(amount)

func _on_damaged(_amount: float, current: float) -> void:
	_play(SFX_HURT)
	Game.player_health_changed.emit(current, health.max_health)
	_flash()

func _on_died() -> void:
	Game.report_player_died()
	set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _flash() -> void:
	var mesh := model.get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		var orig: Color = mat.albedo_color
		mat.albedo_color = Color(1, 0.4, 0.4)
		await get_tree().create_timer(0.1).timeout
		mat.albedo_color = orig

func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()

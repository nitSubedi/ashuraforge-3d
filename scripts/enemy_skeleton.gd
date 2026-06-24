extends CharacterBody3D
## Skeleton enemy with a small state machine: IDLE -> CHASE -> ATTACK.
## Direct-steering chase (no navmesh) is fine for a single open room; navigation
## arrives with the procedural-dungeon sub-project. Drives the KayKit Skeleton rig.

signal died

enum State { IDLE, CHASE, ATTACK, DEAD }

@export var move_speed: float = 3.0
@export var gravity: float = 18.0
@export var aggro_range: float = 14.0
@export var attack_range: float = 2.0
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 1.5
@export var model_yaw_offset: float = 0.0

const ANIM_IDLE := "Idle"
const ANIM_RUN := "Running_A"
const ANIM_ATTACK := "1H_Melee_Attack_Chop"
const ANIM_HIT := "Hit_A"
const ANIM_DEATH := "Death_A"

@onready var model: Node3D = $Model
@onready var health: Health = $Health
@onready var anim: AnimationPlayer = $Model/Skeleton_Warrior/AnimationPlayer

var _state: State = State.IDLE
var _player: Node3D = null
var _attack_ready: bool = true
var _oneshot: bool = false
var _locomotion: String = ANIM_IDLE

const SFX_SCREAM := preload("res://audio/Scream.mp3")

func _ready() -> void:
	add_to_group(&"enemies")
	health.died.connect(_on_died)
	for clip in [ANIM_IDLE, ANIM_RUN]:
		var a := anim.get_animation(clip)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_on_anim_finished)
	_play_loco(ANIM_IDLE)

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
			_face(to_player, delta)
			_play_loco(ANIM_IDLE)
			_try_attack()
		elif dist <= aggro_range:
			_state = State.CHASE
			var dir := to_player.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			_face(to_player, delta)
			_play_loco(ANIM_RUN)
		else:
			_state = State.IDLE
			velocity.x = 0.0
			velocity.z = 0.0
			_play_loco(ANIM_IDLE)

	move_and_slide()

func _face(to_player: Vector3, delta: float) -> void:
	var dir := to_player.normalized()
	if dir.length() > 0.1:
		var target := atan2(dir.x, dir.z) + model_yaw_offset
		model.rotation.y = lerp_angle(model.rotation.y, target, 10.0 * delta)

func _try_attack() -> void:
	if not _attack_ready or _player == null:
		return
	_attack_ready = false
	_play_oneshot(ANIM_ATTACK)
	await get_tree().create_timer(0.4).timeout
	# Damage lands mid-swing, only if still in range and both alive.
	if _state != State.DEAD and _player != null and is_instance_valid(_player) \
	and _player.has_method(&"take_hit"):
		if global_position.distance_to(_player.global_position) <= attack_range + 0.6:
			_player.take_hit(attack_damage)
	await get_tree().create_timer(attack_cooldown).timeout
	_attack_ready = true

## Called by player melee / projectile.
func take_hit(amount: float) -> void:
	if _state == State.DEAD:
		return
	health.take_damage(amount)
	if _state != State.DEAD:
		_play_oneshot(ANIM_HIT)

func _on_died() -> void:
	_state = State.DEAD
	_play(SFX_SCREAM)
	_oneshot = true
	if anim.has_animation(ANIM_DEATH):
		anim.play(ANIM_DEATH, 0.1)
	set_physics_process(false)
	died.emit()
	Game.report_enemy_died()
	await get_tree().create_timer(2.0).timeout
	queue_free()

## --- animation helpers -----------------------------------------------------

func _play_loco(clip: String) -> void:
	_locomotion = clip
	if not _oneshot and _state != State.DEAD and anim.current_animation != clip:
		anim.play(clip, 0.15)

func _play_oneshot(clip: String) -> void:
	if not anim.has_animation(clip) or _state == State.DEAD:
		return
	_oneshot = true
	anim.play(clip, 0.1)

func _on_anim_finished(finished: String) -> void:
	if _state == State.DEAD or finished == _locomotion:
		return
	_oneshot = false
	anim.play(_locomotion, 0.15)

func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.stream = stream
	p.play()
	p.finished.connect(p.queue_free)

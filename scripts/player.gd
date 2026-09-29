extends CharacterBody3D
## Third-person over-shoulder player controller.
## Movement is camera-relative. Mouse drives the camera pivot (yaw) and spring arm
## (pitch); the visual model turns to face movement. Combat: melee swing + magic
## projectile, mapping to AshuraForge's Fire/Magic. Drives the KayKit Knight rig.

@export var speed: float = 2.6           # walk speed (m/s)
@export var sprint_multiplier: float = 2.3  # -> run ~6 m/s, matches the run clip stride
# Natural ground speed baked into each clip's stride (m/s), used to scale playback
# so the feet match the body (no sliding).
const WALK_STRIDE := 1.35
const RUN_STRIDE := 5.92
const STEP_DISTANCE := 1.6  # metres travelled per footstep sound
@export var jump_velocity: float = 7.0
@export var gravity: float = 18.0
@export var mouse_sensitivity: float = 0.0025
@export var turn_speed: float = 12.0
## If the hero runs facing backwards, flip this to PI in the inspector.
@export var model_yaw_offset: float = 0.0

@export var melee_damage: float = 35.0
@export var magic_damage: float = 45.0
@export var dodge_speed: float = 12.0
@export var dodge_time: float = 0.35
@export var dodge_cooldown: float = 0.6

const PITCH_MIN := -1.2
const PITCH_MAX := 0.5

const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"
const ANIM_RUN := "run"
const ANIM_MELEE := "attack_slash"
const ANIM_CAST := "attack_cast"
const ANIM_HIT := "hit"
const ANIM_DEATH := "death"
const ANIM_DODGE := "dodge"
const ANIM_JUMP := "jump"          # standing: squat + vertical
const ANIM_JUMP_RUN := "jump_run"  # moving: forward leap

# Combo graph. LMB = hand (cane), RMB = foot (kick); strings cross-branch.
# "" = string ends (next press restarts from neutral).
#
# Each move is split into phases by its REAL strike timing, measured from the
# mocap with tools/measure_strikes.gd (peak hand/foot speed), in clip seconds:
#   lead   – idle lead-in skipped entirely (clip starts here)
#   hits   – active windows [a0, a1]; hitbox is live ONLY inside these
#   end    – recovery is cut here and blends back to locomotion
#   wind   – target real-time wind-up (lead -> first a0): the startup plays
#            faster to hit it; strike plays at 1x; recovery at RECOVERY_SPEED
#   heavy  – finisher: bigger hitstop/shake, no dodge-cancel in its wind-up
#   swap   – (draw/sheathe/iai) clip s where the blade changes hands
#   then   – auto-chain into this node when `end` is reached (iai reach -> cut)
#   stance_to – stance entered at `swap` (draw -> sword, sheathe -> cane)
# Moves with no `hits` (draw/sheathe/iai reach) play their whole lead..end
# span in `wind` real seconds.
const NEUTRAL := {"cane": {"hand": "h1", "foot": "f1"}, "sword": {"hand": "s1", "foot": "f1"}}
# Hand-string nodes a kick branches into, per stance (kicks are shared).
const STANCE_HAND := {"sword": {"h1": "s1", "h2": "s2", "h3": "s3"}}
const CHAIN_BLEND := 0.1       # blend into a chained move (short = snappy)
const RECOVER_BLEND := 0.25    # blend from a cut recovery back to locomotion
const RECOVERY_SPEED := 1.35
const MAX_WIND_SPEED := 2.2    # never fast-forward mocap wind-ups harder than this
const MOVE_CANCEL_AFTER := 0.12  # clip s after the last hit when stick input cancels
const BUFFER_TIME := 0.45      # a queued press expires this long after an attack ends
const BUFFER_DEPTH := 2        # presses remembered while a move plays (mash-friendly)
const LUNGE_RANGE := 3.5       # m: close the gap to targets within this
const LUNGE_STOP := 1.2        # m: stop this far from the target's centre
const LUNGE_MAX_SPEED := 9.0
const LOCK_RANGE := 8.0        # m: attacks turn toward the nearest enemy in range
const ATTACK_TURN_SPEED := 18.0  # rad/s tracking — during the wind-up only
var _nodes := {
	# Hand (cane) string
	"h1":    {"clip": "attack_slash", "lead": 0.08, "hits": [[0.74, 0.90]], "end": 1.25, "wind": 0.22,
		"hand": "h2", "foot": "f1",    "dmg": 35.0},
	"h2":    {"clip": "cane2",        "lead": 0.12, "hits": [[0.50, 0.72]], "end": 1.00, "wind": 0.20,
		"hand": "h3", "foot": "f2",    "dmg": 38.0},
	"h3":    {"clip": "punch1",       "lead": 0.42, "hits": [[0.86, 1.04]], "end": 1.40, "wind": 0.22,
		"hand": "iai", "foot": "fspin", "dmg": 42.0},
	# Iai quick-draw (cane stance): hand to the hilt at the hip, blade flashes
	# out into an outward draw-cut, then goes home (stance stays "cane").
	"iai":     {"clip": "sword_draw", "lead": 0.02, "hits": [], "swap": 0.44, "end": 0.47, "wind": 0.16,
		"then": "iai_cut", "hand": "", "foot": ""},
	"iai_cut": {"clip": "sword_2",    "lead": 0.42, "hits": [[0.76, 0.92]], "end": 1.30, "wind": 0.12,
		"hand": "", "foot": "", "dmg": 90.0, "heavy": true, "keep_drawn": true},
	# Foot (capoeira) string
	"f1":    {"clip": "kick_hook",    "lead": 0.18, "hits": [[0.43, 0.69]], "end": 1.05, "wind": 0.20,
		"hand": "h1", "foot": "f2",    "dmg": 45.0},
	"f2":    {"clip": "roundhouse",   "lead": 0.32, "hits": [[0.50, 0.66]], "end": 1.00, "wind": 0.16,
		"hand": "h2", "foot": "f3",    "dmg": 48.0},
	"f3":    {"clip": "kick_axe",     "lead": 0.37, "hits": [[0.50, 0.70]], "end": 1.00, "wind": 0.16,
		"hand": "h3", "foot": "f4",    "dmg": 50.0},
	"f4":    {"clip": "spin_kick",    "lead": 0.35, "hits": [[1.73, 1.95], [2.45, 2.60]], "end": 2.95, "wind": 0.62,
		"hand": "",   "foot": "ffin",  "dmg": 55.0},
	# Finishers (big hits — these are what send a part flying)
	"ffin":  {"clip": "flykick",      "lead": 0.02, "hits": [[0.52, 0.66]], "end": 0.67, "wind": 0.30,
		"hand": "",   "foot": "",      "dmg": 85.0, "heavy": true},
	"fspin": {"clip": "capoeira",     "lead": 0.02, "hits": [[1.85, 2.03], [3.05, 3.22], [3.78, 3.98]], "end": 4.30, "wind": 0.85,
		"hand": "",   "foot": "",      "dmg": 60.0, "heavy": true},
	# Sword stance (blade drawn, sheath in the off hand)
	"s1":    {"clip": "sword_1",      "lead": 0.55, "hits": [[1.10, 1.32]], "end": 1.65, "wind": 0.26,
		"hand": "s2", "foot": "f1",    "dmg": 40.0},
	"s2":    {"clip": "sword_2",      "lead": 0.42, "hits": [[0.76, 0.92]], "end": 1.30, "wind": 0.18,
		"hand": "s3", "foot": "f2",    "dmg": 42.0},
	"s3":    {"clip": "sword_3",      "lead": 0.10, "hits": [[0.56, 0.85], [1.18, 1.32]], "end": 1.75, "wind": 0.22,
		"hand": "s4", "foot": "f3",    "dmg": 38.0},
	"s4":    {"clip": "sword_4",      "lead": 0.30, "hits": [[0.70, 0.92]], "end": 1.30, "wind": 0.24,
		"hand": "",   "foot": "",      "dmg": 80.0, "heavy": true},
	# Stance changes (Q). Draw = reach to the hilt; the blend into the sword idle
	# sweeps the hand out as the pull.
	"draw":    {"clip": "sword_draw",    "lead": 0.02, "hits": [], "swap": 0.44, "end": 0.48, "wind": 0.20,
		"stance_to": "sword", "hand": "s1", "foot": "f1"},
	"sheathe": {"clip": "sword_sheathe", "lead": 0.08, "hits": [], "swap": 1.27, "end": 1.45, "wind": 0.70,
		"stance_to": "cane", "hand": "h1", "foot": "f1"},
}
var _attack_id := 0   # increments per active window; a target takes one hit per window
var _buffered: Array[String] = []   # queued attack presses ("hand"/"foot"), FIFO
var _buffer_age := 0.0
var _wind_speed := 1.0         # playback speed for the current move's wind-up
var _hit_window := -1          # index of the active window we're inside (-1 = none)
var _hit_bodies := {}          # bodies already struck in the current window
var _target: Node3D = null     # enemy this move lunges/turns toward
var _hitstop := 0.0            # remaining hitstop (real s): hero anim frozen
var _trauma := 0.0             # camera shake energy 0..1 (decays; shake = trauma^2)
var _stance := "cane"          # "cane" | "sword" (blade drawn)
var _swapped := false          # the current move's weapon swap has fired
var _sheath: Node3D            # Sheath part (rides the hilt, or the off hand when drawn)
var _sheath_grip: Node3D       # left-hand mount for the drawn sheath

@onready var model: Node3D = $Model
@onready var camera_pivot: Node3D = $CameraPivot
# Camera follow: the pivot is detached (top_level) and eases toward the body's
# INTERPOLATED position every rendered frame — smooth at any refresh rate, with
# a touch of lag so motion reads as weight rather than a rigid attachment.
const CAM_FOLLOW := 14.0          # higher = tighter follow
const CAM_HEIGHT := Vector3(0.0, 1.5, 0.0)
# Ground movement has weight: speed ramps up/down instead of snapping.
const ACCEL := 22.0               # m/s^2 speeding up
const DECEL := 30.0               # m/s^2 slowing down / stopping
const AnimDriver := preload("res://scripts/anim_driver.gd")
var driver: AnimDriver
const AbilitySystem := preload("res://scripts/abilities/ability_system.gd")
var abilities: AbilitySystem
var flying := false               # Wraithwing: the ability steers flight_velocity
const FX := preload("res://scripts/fx/fx.gd")
const PostFX := preload("res://scripts/fx/post_fx.gd")
const WeaponTrail := preload("res://scripts/fx/weapon_trail.gd")
const RIM := preload("res://assets/shaders/rim.gdshader")
const BASE_FOV := 68.0
var _trail_weapon: WeaponTrail
var _trail_feet: Array = []
var flight_velocity := Vector3.ZERO
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var muzzle: Marker3D = $Muzzle
@onready var melee_hitbox: Area3D = $MeleeHitbox
@onready var health: Health = $Health
@onready var sfx: AudioStreamPlayer = $Sfx
@onready var anim: AnimationPlayer = $Model/Hero/AnimationPlayer
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var _yaw: float = 0.0
var _pitch: float = -0.3
var _attacking: bool = false
var _dodging: bool = false
var _can_dodge: bool = true
var _invulnerable: bool = false
var _oneshot: bool = false
var _dead: bool = false
var _combo: String = ""        # current combo node key; "" = neutral
var _combo_clip: String = ""   # clip name of the current combo node
var _combo_len: float = 0.0    # length of the current combo clip (for cancel window)
var _cane: Node3D              # CaneSword: Hilt + Blade (+ Sheath while sheathed)
var _grip_mid: Transform3D     # hilt in the fist, shaft/blade out of the thumb side (combat / run / jump)
var _grip_walk: Transform3D    # walking-stick grip (crook above the fist, tip down)

const PROJECTILE := preload("res://scenes/projectile.tscn")

# High-quality SFX, loaded by name from res://audio/sfx/<name>.ogg|wav|mp3 if present.
# Drop real sound files there; until then these are silent (no childish placeholders).
const SFX_DIR := "res://audio/sfx/"
const SFX_NAMES := ["cane_swing", "kick", "footstep", "hit", "jump", "dodge", "cast"]
var _sfx := {}
var _step_accum := 0.0

func _ready() -> void:
	add_to_group(&"player")
	camera_pivot.top_level = true
	camera_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_pivot.global_position = global_position + CAM_HEIGHT
	spring_arm.add_excluded_object(get_rid())   # detached pivot: don't collide with our own capsule
	_load_sfx()
	_cane = find_child("CaneSword", true, false) as Node3D
	_sheath = find_child("Sheath", true, false) as Node3D
	_sheath_grip = find_child("SheathGrip", true, false) as Node3D
	# Grips tuned with tools/render_grip.gd; the cane-sword's origin is the hilt neck.
	_grip_mid = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90), 0.0, 0.0)), Vector3(0.0, 0.08, 0.0))
	_grip_walk = Transform3D(Basis.from_euler(Vector3(deg_to_rad(180), 0.0, 0.0)), Vector3(0.0, 0.08, 0.02))
	melee_hitbox.monitoring = true   # damage is gated by the active window, not monitoring
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	Game.player_health_changed.emit(health.current, health.max_health)
	for clip in [ANIM_IDLE, ANIM_WALK, ANIM_RUN]:
		var a := anim.get_animation(clip)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	driver = AnimDriver.new()
	driver.name = "AnimDriver"
	add_child(driver)
	driver.setup(anim)
	driver.action_finished.connect(_on_anim_finished)
	abilities = AbilitySystem.new()
	abilities.name = "Abilities"
	add_child(abilities)
	abilities.setup(self)
	_setup_fx()
	model.rotation.y = PI + model_yaw_offset  # face into the room, away from the camera
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var target := get_global_transform_interpolated().origin + CAM_HEIGHT
	camera_pivot.global_position = camera_pivot.global_position.lerp(target, 1.0 - exp(-CAM_FOLLOW * delta))
	# FOV push sells speed: a little on lunges, more in Wraithwing flight.
	var want_fov := BASE_FOV
	if flying:
		want_fov += 12.0
	elif _attacking and _target != null and _in_wind_up():
		want_fov += 5.0
	camera.fov = lerpf(camera.fov, want_fov, 1.0 - exp(-8.0 * delta))

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)
		camera_pivot.rotation.y = _yaw
		spring_arm.rotation.x = _pitch
	elif event.is_action_pressed(&"attack"):
		_do_attack("hand")
	elif event.is_action_pressed(&"kick"):
		_do_attack("foot")
	elif event.is_action_pressed(&"cast"):
		_do_cast()
	elif event.is_action_pressed(&"dodge"):
		_do_dodge()
	elif event.is_action_pressed(&"stance"):
		_do_stance()
	elif Input.is_key_pressed(KEY_ESCAPE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	_update_camera_shake(delta)
	if _hitstop > 0.0:
		# Both bodies lock on the impact pose; physics/particles/camera keep running.
		_hitstop -= delta
		if _hitstop > 0.0:
			velocity = Vector3.ZERO
			return
		driver.time_scale = 1.0
	_update_attack(delta)
	_update_trails()
	if flying:
		velocity = flight_velocity
		move_and_slide()
		var hv := Vector2(velocity.x, velocity.z)
		if hv.length() > 0.5:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(hv.x, hv.y) + model_yaw_offset, 10.0 * delta)
		driver.set_locomotion(0.0, _stance == "sword")
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed(&"jump") and not _dodging:
		velocity.y = jump_velocity
		_sfx_play("jump")
		var mv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		if mv.length() > 0.1 and Input.is_action_pressed(&"sprint"):
			_play_oneshot(ANIM_JUMP_RUN)   # forward leap (air control carries it forward)
		else:
			_play_oneshot(ANIM_JUMP)        # standing squat-jump

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := Vector3.ZERO
	dir += camera_pivot.global_basis.x * input.x
	dir += camera_pivot.global_basis.z * input.y
	dir.y = 0.0
	dir = dir.normalized()

	if _attacking and is_on_floor():
		# Wind-up: track + lunge toward the target (motion warp). Active/recovery:
		# rooted, so the strike lands where the wind-up aimed it.
		var lunge := _lunge_velocity(delta)
		velocity.x = lunge.x
		velocity.z = lunge.z
	elif not _dodging:
		var sprinting := Input.is_action_pressed(&"sprint")
		var cur_speed := speed * (sprint_multiplier if sprinting else 1.0)
		# Accelerate toward the wanted velocity (weight), brake a bit harder.
		var hv := Vector2(velocity.x, velocity.z)
		var want := Vector2(dir.x, dir.z) * cur_speed
		hv = hv.move_toward(want, (ACCEL if want.length() > hv.length() else DECEL) * delta)
		velocity.x = hv.x
		velocity.z = hv.y
		if dir.length() > 0.1:
			var target := atan2(dir.x, dir.z) + model_yaw_offset
			model.rotation.y = lerp_angle(model.rotation.y, target, turn_speed * delta)
			# Footstep on distance travelled (a step every STEP_DISTANCE metres).
			if is_on_floor():
				_step_accum += hv.length() * delta
				if _step_accum >= STEP_DISTANCE:
					_step_accum = 0.0
					_sfx_play("footstep")
		else:
			_step_accum = STEP_DISTANCE  # next move triggers a step promptly

	move_and_slide()
	# Locomotion blends continuously from the real ground speed.
	var ground_speed := Vector2(velocity.x, velocity.z).length() if is_on_floor() and not _attacking else 0.0
	driver.set_locomotion(ground_speed, _stance == "sword")

	# Cane grip: walking-stick while walking; middle grip otherwise (combat/run/jump).
	if _cane != null:
		var walking := _stance == "cane" and is_on_floor() and not _attacking and not _dodging \
			and dir.length() > 0.1 and not Input.is_action_pressed(&"sprint")
		_cane.transform = _grip_walk if walking else _grip_mid

	# Keep the melee hitbox in front of wherever the hero is facing.
	var face := Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))
	melee_hitbox.position = Vector3(0.0, 1.0, 0.0) + face * 1.2

	# Damage only inside the move's active window: one hit per body per window;
	# a part is severed (flies off, gory) only when its HP runs out.
	if _attacking and _hit_window >= 0:
		var node: Dictionary = _nodes[_combo]
		var dmg: float = float(node["dmg"])
		var landed := false
		var fresh := []
		for b in melee_hitbox.get_overlapping_bodies():
			if b.has_method(&"take_damage") and not _hit_bodies.has(b):
				_hit_bodies[b] = true
				fresh.append(b)
				var away := b.global_position - global_position
				away.y = 0.0
				away = away.normalized() if away.length() > 0.01 else face
				b.take_damage(dmg, _attack_id, away * 4.0 + Vector3.UP * 2.5)
				landed = true
		if landed:
			_on_hit_landed(node)
			for b in fresh:
				on_ability_hit(b)   # melee feeds Blood exactly like power hits

## --- ability hooks ---------------------------------------------------------

func next_attack_id() -> int:
	_attack_id += 1
	return _attack_id

## Any hit that landed (melee or power): feed the Blood meter.
func on_ability_hit(e: Node) -> void:
	abilities.gain_blood(AbilitySystem.BLOOD_PER_HIT)
	if e.get(&"_dead"):
		abilities.gain_blood(AbilitySystem.BLOOD_PER_KILL)

func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)
	var pf := PostFX.get_instance(get_tree())
	if pf:
		pf.pulse(amount * 1.4)

## --- presentation (trails, rim) ---------------------------------------------

func _setup_fx() -> void:
	# Weapon trail between markers on the cane-sword (grip area -> tip).
	if _cane:
		var base := Node3D.new()
		base.position = Vector3(0, -0.12, 0)
		_cane.add_child(base)
		var tip := Node3D.new()
		tip.position = Vector3(0, -0.8, 0)
		_cane.add_child(tip)
		_trail_weapon = WeaponTrail.new()
		_trail_weapon.base = base
		_trail_weapon.tip = tip
		add_child(_trail_weapon)
	# Kick arcs: ankle -> toe on each foot.
	var skel := model.find_children("*", "Skeleton3D", true, false)
	if not skel.is_empty():
		for side in ["Left", "Right"]:
			var pts := []
			for bone in ["Foot", "ToeBase"]:
				var at := BoneAttachment3D.new()
				at.bone_name = "mixamorig_%s%s" % [side, bone]
				skel[0].add_child(at)
				pts.append(at)
			var tr := WeaponTrail.new()
			tr.base = pts[0]
			tr.tip = pts[1]
			tr.color = Color(1.0, 0.55, 0.4)
			tr.intensity = 0.35
			tr.length = 8
			add_child(tr)
			_trail_feet.append(tr)
	# Rim light on skin/clothes (not the alpha-card hair/brows/lashes or eyes).
	var rim := ShaderMaterial.new()
	rim.shader = RIM
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.contains("long01") or n.contains("eyebrow") or n.contains("eyelash") or n.contains("high-poly") \
				or (_cane != null and _cane.is_ancestor_of(mi)):
			continue
		(mi as MeshInstance3D).material_overlay = rim

## Trails show only around each move's strike window.
func _update_trails() -> void:
	var live := false
	if _attacking and _combo != "":
		var t := driver.action_time
		for h in _nodes[_combo]["hits"]:
			if t >= float(h[0]) - 0.1 and t <= float(h[1]) + 0.04:
				live = true
	var kick := live and _is_kick(_combo_clip)
	if _trail_weapon:
		_trail_weapon.emitting = live and not kick
	for tr in _trail_feet:
		tr.emitting = kick

## Wraithwing: hide the body inside the smoke, i-frames, no gravity/attacks.
func set_flying(on: bool) -> void:
	flying = on
	_invulnerable = on
	model.visible = not on
	if on:
		_clear_attack()
		_buffered.clear()
		driver.stop_action(0.05)
		flight_velocity = velocity + Vector3.UP * 2.0
	else:
		velocity = flight_velocity * 0.3

## --- combat ------------------------------------------------------------------

func _do_attack(kind: String) -> void:
	# kind: "hand" (cane / LMB) or "foot" (kick / RMB).
	if _dodging or _dead:
		return
	if not _attacking:
		_play_combo(NEUTRAL[_stance][kind])
	else:
		# Queue the press; it fires the moment the current strike has landed.
		if _buffered.size() < BUFFER_DEPTH:
			_buffered.append(kind)
		_buffer_age = 0.0

## Per-frame attack driver: phase-based playback speed, active windows, chaining
## a buffered press after the strike, and cutting the recovery short.
func _update_attack(delta: float) -> void:
	# Queued presses wait as long as a move is playing; they only go stale
	# once out of an attack (e.g. after a dodge), so nothing fires out of context.
	if not _buffered.is_empty() and not _attacking:
		_buffer_age += delta
		if _buffer_age > BUFFER_TIME:
			_buffered.clear()
	if not _attacking:
		return
	if driver.action_clip != StringName(_combo_clip):
		_clear_attack()   # something else (hit reaction) took over the rig
		return
	var node: Dictionary = _nodes[_combo]
	var hits: Array = node["hits"]
	var t := driver.action_time
	driver.action_speed = _phase_speed()

	# Weapon handoff at the measured swap frame (hand at the hilt on the hip).
	if node.has("swap") and not _swapped and t >= float(node["swap"]):
		_swapped = true
		if node.has("stance_to"):
			_stance = node["stance_to"]
		_set_drawn(_stance == "sword" or _combo == "iai")

	# Active window tracking: each window is a separate hit (new attack id).
	var win := -1
	for i in hits.size():
		if t >= hits[i][0] and t <= hits[i][1]:
			win = i
	if win != _hit_window:
		_hit_window = win
		if win >= 0:
			_attack_id += 1
			_hit_bodies.clear()
			_sfx_play("kick" if _is_kick(_combo_clip) else "cane_swing")

	var last_hit := _last_hit(node)
	if t < last_hit:
		return
	# Iai reach flows straight into its cut.
	if node.has("then") and t >= float(node["end"]):
		_play_combo(node["then"], 0.06)
		return
	# Strike has landed: a buffered press chains straight into the next move.
	if not _buffered.is_empty():
		var kind: String = _buffered.pop_front()
		var nxt: String
		if kind == "stance":
			nxt = "draw" if _stance == "cane" else "sheathe"
		else:
			nxt = _resolve(node[kind])
			if nxt == "":
				nxt = NEUTRAL[_stance][kind]
		_play_combo(nxt, CHAIN_BLEND)
		return
	# Late recovery: moving (or reaching the cut point) hands control back.
	var moving := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back").length() > 0.2
	if t >= float(node["end"]) or (moving and t >= last_hit + MOVE_CANCEL_AFTER):
		_end_attack()

## Playback speed for the current phase: fast wind-up, 1x strike, brisk recovery.
func _phase_speed() -> float:
	if not _attacking or _combo == "":
		return 1.0
	var node: Dictionary = _nodes[_combo]
	var t := driver.action_time
	if t < _first_strike(node):
		return _wind_speed
	if node["hits"].is_empty() or t > node["hits"][-1][1]:
		return RECOVERY_SPEED if not node["hits"].is_empty() else _wind_speed
	return 1.0

## First active frame (or `end` for strike-less moves like draw/sheathe).
func _first_strike(node: Dictionary) -> float:
	return float(node["hits"][0][0]) if not node["hits"].is_empty() else float(node["end"])

## When the move may chain: after its last strike (or at `end` with no strikes).
func _last_hit(node: Dictionary) -> float:
	return float(node["hits"][-1][1]) if not node["hits"].is_empty() else float(node["end"])

## Map a kick's hand-branch onto the current stance's hand string.
func _resolve(key: String) -> String:
	if key == "" or not _nodes.has(key):
		return ""
	return STANCE_HAND.get(_stance, {}).get(key, key)

func _idle_clip() -> String:
	return "sword_idle" if _stance == "sword" and anim.has_animation("sword_idle") else ANIM_IDLE

func _in_wind_up() -> bool:
	return _attacking and _combo != "" \
		and driver.action_time < _first_strike(_nodes[_combo])

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := LOCK_RANGE * LOCK_RANGE
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e is Node3D and not e.get(&"_dead"):
			var d := global_position.distance_squared_to((e as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = e
	return best

## Motion warp during the wind-up: turn toward the target and close the gap so
## the strike connects at LUNGE_STOP, arriving exactly as the active frames open.
func _lunge_velocity(delta: float) -> Vector3:
	var wind := _in_wind_up()
	if not (wind or _hit_window >= 0) or _target == null or not is_instance_valid(_target):
		return Vector3.ZERO
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.05:
		return Vector3.ZERO
	if wind:
		var want := atan2(to.x, to.z) + model_yaw_offset
		model.rotation.y = lerp_angle(model.rotation.y, want, minf(1.0, ATTACK_TURN_SPEED * delta))
	var gap := dist - LUNGE_STOP
	if gap <= 0.0 or dist > LUNGE_RANGE:
		return Vector3.ZERO
	# Arrive as the first strike opens; if the strike is already live, close at full speed.
	var real_left: float = (_first_strike(_nodes[_combo]) - driver.action_time) / _wind_speed if wind else 0.0
	var spd := minf(gap / maxf(real_left, delta), LUNGE_MAX_SPEED)
	return to / dist * spd

func _play_combo(key: String, blend: float = CHAIN_BLEND) -> void:
	var node: Dictionary = _nodes[key]
	var clip: String = node["clip"]
	if not anim.has_animation(clip):
		return
	_combo = key
	_combo_clip = clip
	_combo_len = anim.get_animation(clip).length
	_attacking = true
	_oneshot = true
	_hit_window = -1
	_hit_bodies.clear()
	_swapped = false
	if not node.get("keep_drawn", false):
		_set_drawn(_stance == "sword")   # e.g. a cane move chained after the iai
	_target = _nearest_enemy() if not node["hits"].is_empty() else null
	# Wind-up plays fast enough to reach the first strike in `wind` real seconds.
	var lead: float = node["lead"]
	_wind_speed = clampf((_first_strike(node) - lead) / float(node["wind"]), 1.0, MAX_WIND_SPEED)
	# Crossfade from whatever was playing, starting past the idle lead-in.
	driver.play_action(StringName(clip), blend, lead, _wind_speed)

## Contact: hitstop on both bodies, camera trauma. Heavier moves hold longer.
func _on_hit_landed(node: Dictionary) -> void:
	var heavy: bool = node.get("heavy", false)
	var stop := 0.13 if heavy else clampf(0.05 + float(node["dmg"]) / 1000.0, 0.06, 0.1)
	_hitstop = stop
	driver.time_scale = 0.04
	_trauma = minf(1.0, _trauma + (0.7 if heavy else 0.35))
	_sfx_play("hit")
	for b in _hit_bodies:
		if is_instance_valid(b) and b.has_method(&"hitstop"):
			b.hitstop(stop)
	# Contact feedback: steel sparks at the hit point + a chromatic pulse
	# (a warm flash too on finishers).
	for b in _hit_bodies:
		if is_instance_valid(b):
			var to_me: Vector3 = global_position - b.global_position
			to_me.y = 0.0
			FX.sparks(get_tree().current_scene, b.global_position + Vector3(0, 1.15, 0) + to_me.normalized() * 0.35, to_me + Vector3.UP * 0.5)
	var pf := PostFX.get_instance(get_tree())
	if pf:
		pf.pulse(0.7 if heavy else 0.22)
		if heavy:
			pf.flash(Color(1.0, 0.82, 0.68), 0.1)

func _update_camera_shake(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - 2.2 * delta)
	var s := _trauma * _trauma
	var tt := Time.get_ticks_msec() * 0.001
	camera.h_offset = 0.14 * s * sin(tt * 61.0)
	camera.v_offset = 0.10 * s * sin(tt * 47.0 + 1.3)

## Recovery cut: blend straight back into locomotion.
func _end_attack() -> void:
	_clear_attack()
	_oneshot = false
	driver.stop_action(RECOVER_BLEND)

func _clear_attack() -> void:
	_attacking = false
	_combo = ""
	_combo_clip = ""
	_hit_window = -1
	_target = null
	_set_drawn(_stance == "sword")   # iai / interrupted draw: blade goes home

## Blade out: the sheath moves to the off hand. Sheathed: it rides the hilt so
## the three parts read as one cane (every part's origin is the grip point).
func _set_drawn(drawn: bool) -> void:
	if _sheath == null or _sheath_grip == null:
		return
	var parent: Node3D = _sheath_grip if drawn else _cane
	if _sheath.get_parent() != parent:
		_sheath.reparent(parent, false)
		_sheath.transform = Transform3D.IDENTITY

## Q: draw the blade (cane -> sword stance) or sheathe it. Mid-move it queues and
## fires once the current strike lands, like any other press.
func _do_stance() -> void:
	if _dodging or _dead:
		return
	if not _attacking:
		_play_combo("draw" if _stance == "cane" else "sheathe")
	elif _buffered.size() < BUFFER_DEPTH:
		_buffered.append("stance")
		_buffer_age = 0.0

func _apply_melee_hit() -> void:
	for body in melee_hitbox.get_overlapping_bodies():
		if body.is_in_group(&"enemies") and body.has_method(&"take_hit"):
			body.take_hit(melee_damage)

func _do_cast() -> void:
	if _dodging:
		return
	_sfx_play("cast")
	_play_oneshot(ANIM_CAST)
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
	if _attacking:
		# Cancel rules: never mid-strike; finishers commit through their wind-up.
		if _hit_window >= 0:
			return
		if _in_wind_up() and _nodes[_combo].get("heavy", false):
			return
		if _swapped and _nodes[_combo].has("stance_to"):
			return   # committed: the blade has already changed hands
	_dodging = true
	_can_dodge = false
	_invulnerable = true
	_clear_attack()
	_buffered.clear()
	_hitstop = 0.0
	_sfx_play("dodge")
	_play_oneshot(ANIM_DODGE)
	driver.action_speed = 1.6  # snappier roll so it doesn't slide upright first
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := (camera_pivot.global_basis.x * input.x) + (camera_pivot.global_basis.z * input.y)
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = -model.global_basis.z
	dir = dir.normalized()
	velocity.x = dir.x * dodge_speed
	velocity.z = dir.z * dodge_speed
	await get_tree().create_timer(dodge_time).timeout
	_dodging = false
	_invulnerable = false
	await get_tree().create_timer(dodge_cooldown).timeout
	_can_dodge = true

func take_hit(amount: float) -> void:
	if _invulnerable or _dead:
		return
	health.take_damage(amount)

func _on_damaged(_amount: float, current: float) -> void:
	_sfx_play("hit")
	Game.player_health_changed.emit(current, health.max_health)
	if not _dead:
		_play_oneshot(ANIM_HIT)

func _on_died() -> void:
	_dead = true
	_play_oneshot(ANIM_DEATH)
	Game.report_player_died()
	set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## --- animation helpers -----------------------------------------------------

func _play_oneshot(clip: String) -> void:
	if not anim.has_animation(clip):
		return
	_oneshot = true
	driver.play_action(StringName(clip), 0.1)

func _on_anim_finished(_finished: StringName) -> void:
	if _dead:
		return   # hold the death pose
	_oneshot = false
	_clear_attack()
	_buffered.clear()
	driver.stop_action(0.15)

func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()

func _load_sfx() -> void:
	for n in SFX_NAMES:
		for ext in [".ogg", ".wav", ".mp3"]:
			var path: String = SFX_DIR + n + ext
			if ResourceLoader.exists(path):
				_sfx[n] = load(path)
				break

func _sfx_play(sound: String) -> void:
	if _sfx.has(sound):
		_play(_sfx[sound])

func _is_kick(clip: String) -> bool:
	for k in ["kick", "capoeira", "round", "spin", "fly"]:
		if k in clip:
			return true
	return false

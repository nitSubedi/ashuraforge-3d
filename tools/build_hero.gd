extends SceneTree
## Build res://assets/characters/hero.tscn: the real hero (MPFB2 body + outfit,
## tools/gen/make_hero.py -> hero.glb) with every Mixamo clip merged in.
## Clips were authored on X Bot, so each one is root-motion stripped on the X Bot
## skeleton, then retargeted onto the hero's rest pose (tools/retarget.gd).
## Run: godot --headless -s res://tools/build_hero.gd

const BASE := "res://assets/characters/hero_mpfb/hero.glb"
const SRC_RIG := "res://assets/animations/mixamo/hero_base.fbx"   # X Bot: the clips' source rig
const RETARGET := preload("res://tools/retarget.gd")
const COAT_CHAINS := ["L_front", "R_front", "L_back", "R_back"]
const DIR := "res://assets/animations/mixamo/"
const CLIPS := {
	"idle": "idle.fbx",
	"walk": "walk.fbx",
	"run": "run.fbx",
	"attack_slash": "attack_slash.fbx",
	"cane2": "cane2.fbx",
	"kick_hook": "kick_hook.fbx",
	"kick_axe": "kick_axe.fbx",
	"kick_sweep": "kick_sweep.fbx",
	"capoeira": "capoeira.fbx",
	"roundhouse": "roundhouse.fbx",
	"spin_kick": "spin_kick.fbx",
	"flykick": "flykick.fbx",
	"punch1": "punch1.fbx",
	"jump": "jump.fbx",
	"jump_run": "jump_run.fbx",
	"attack_cast": "attack_cast.fbx",
	"hit": "hit.fbx",
	"death": "death.fbx",
	"dodge": "dodge.fbx",
	# Cane-sword stance
	"sword_draw": "sword_draw.fbx",
	"sword_sheathe": "sword_sheathe.fbx",
	"sword_1": "sword_1.fbx",
	"sword_2": "sword_2.fbx",
	"sword_3": "sword_3.fbx",
	"sword_4": "sword_4.fbx",
	"sword_idle": "sword_idle.fbx",
}
const LOOPED := ["idle", "run", "walk", "sword_idle"]
const OUT := "res://assets/characters/hero.tscn"

const CANE_SWORD := "res://assets/weapons/cane_sword.glb"
const HAND_BONE := "mixamorig_RightHand"
const OFF_HAND_BONE := "mixamorig_LeftHand"

func _initialize() -> void:
	var base_ps := load(BASE) as PackedScene
	var root := base_ps.instantiate()
	root.name = "Hero"
	var skel := _find_skel(root)
	var src_root := (load(SRC_RIG) as PackedScene).instantiate()
	var src_skel := _find_skel(src_root)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	ap.add_animation_library(&"", lib)
	var skel_path := String(root.get_path_to(skel))

	for clip_name in CLIPS:
		var ps := load(DIR + CLIPS[clip_name]) as PackedScene
		if ps == null:
			push_error("Failed to load " + CLIPS[clip_name]); continue
		var inst := ps.instantiate()
		var src := _find_anim(inst)
		var src_name := "mixamo_com" if src.has_animation("mixamo_com") else src.get_animation_list()[0]
		var anim := (src.get_animation(src_name) as Animation).duplicate(true) as Animation
		if clip_name in LOOPED:
			anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion(anim, clip_name)  # controller owns movement
		anim = RETARGET.retarget(anim, src_skel, skel, skel_path)
		if clip_name in LOOPED:
			anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(clip_name, anim)
		print("  added clip '", clip_name, "'  length=", anim.length)
		inst.free()

	_add_cane_sword(root)
	# _add_coat_springs(skel)  # off until leg colliders exist: springs alone bunch the hem
	src_root.free()

	# Flatten to a self-contained scene (not an FBX instance) so edits persist.
	root.scene_file_path = ""
	_set_owner(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed: " + str(err)); quit(1); return
	err = ResourceSaver.save(packed, OUT)
	print("SAVED ", OUT, " err=", err, "  clips=", ap.get_animation_list())
	quit()

## Coat tails swing on spring bones (4 chains of 3 bones, parented to Hips).
func _add_coat_springs(skel: Skeleton3D) -> void:
	var sb := SpringBoneSimulator3D.new()
	sb.name = "CoatSprings"
	skel.add_child(sb)
	sb.set_setting_count(COAT_CHAINS.size())
	for i in COAT_CHAINS.size():
		var key: String = COAT_CHAINS[i]
		sb.set_root_bone_name(i, "coat_%s_1" % key)
		sb.set_end_bone_name(i, "coat_%s_3" % key)
		sb.set_extend_end_bone(i, true)
		sb.set_end_bone_length(i, 0.12)
		sb.set_stiffness(i, 4.0)   # sway, not reshape (no leg colliders yet)
		sb.set_drag(i, 0.6)
		sb.set_gravity(i, 0.1)
		sb.set_radius(i, 0.03)

func _set_owner(n: Node, owner_root: Node) -> void:
	for c in n.get_children():
		c.owner = owner_root
		_set_owner(c, owner_root)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null

func _strip_root_motion(anim: Animation, clip_name: String) -> void:
	# Kill HORIZONTAL (X/Z) hips drift so the controller owns position; KEEP Y —
	# it holds the standing height (zeroing it sinks the body). For jump clips,
	# FLATTEN Y to the standing baseline too, so the code-driven jump isn't
	# doubled by the clip's own vertical rise (which looked exaggerated).
	var is_jump := clip_name == "jump" or clip_name == "jump_run"
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		var path := str(anim.track_get_path(ti))
		if "Hips" not in path:
			continue
		var key_n := anim.track_get_key_count(ti)
		var base_y := (anim.track_get_key_value(ti, 0) as Vector3).y if key_n > 0 else 0.0
		for ki in key_n:
			var v: Vector3 = anim.track_get_key_value(ti, ki)
			var y := base_y if is_jump else v.y
			anim.track_set_key_value(ti, ki, Vector3(0.0, y, 0.0))

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

## Cane-sword rig: RightHandMount/CaneSword holds Hilt + Blade + Sheath (the
## sheathed cane — every part's origin is the grip point, so all sit at
## identity). LeftHandMount/SheathGrip is where the sheath goes when drawn.
## player.gd owns the grip transforms and reparenting at runtime.
func _add_cane_sword(root: Node) -> void:
	var skel := _find_skel(root)
	if skel == null:
		push_warning("No skeleton; cane-sword not attached")
		return
	var right := BoneAttachment3D.new()
	right.name = "RightHandMount"
	skel.add_child(right)
	right.bone_name = HAND_BONE
	var left := BoneAttachment3D.new()
	left.name = "LeftHandMount"
	skel.add_child(left)
	left.bone_name = OFF_HAND_BONE
	var grip := Node3D.new()
	grip.name = "SheathGrip"
	# Left fist holds the sheath ~12 cm below its throat, ferrule down/back.
	# Tuned with tools/render_grip.gd (sword_idle) on the MPFB hero's hand axes.
	grip.transform = Transform3D(Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(-90.0))),
		Vector3(0.12, 0.08, 0.0))
	left.add_child(grip)

	var cane := Node3D.new()
	cane.name = "CaneSword"
	right.add_child(cane)
	var glb := (load(CANE_SWORD) as PackedScene).instantiate()
	for part in ["Hilt", "Blade", "Sheath"]:
		var n := glb.find_child(part, true, false) as Node3D
		if n == null:
			push_error("cane_sword.glb missing part " + part)
			continue
		n.owner = null
		n.get_parent().remove_child(n)
		n.transform = Transform3D.IDENTITY
		cane.add_child(n)
	glb.free()


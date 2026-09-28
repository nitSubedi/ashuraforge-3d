extends Node
## Animation driver: an AnimationTree with AAA-style "slots" so nothing ever
## hard-cuts.
##
##   loco  : BlendSpace1D idle -> walk -> run by real ground speed (m/s), played
##           at stride-matched rate (no foot sliding); idle blends cane/sword.
##   A / B : two action slots (clip -> TimeSeek -> TimeScale), ping-ponged so
##           every new action CROSSFADES from the previous one; the start offset
##           is applied inside the tree (no seek pop).
##   ab    : Blend2 between the slots;  act : Blend2 locomotion <-> action.
##
## The driver tracks action time itself (it owns the speeds), which is what
## combat code reads for phase timing. `time_scale` multiplies everything
## (hitstop). Emits action_finished(clip) when a non-looping action ends.

signal action_finished(clip: StringName)

const WALK_STRIDE := 1.35   # clip-native ground speeds (m/s) of the X Bot locomotion
const RUN_STRIDE := 5.92

var tree: AnimationTree
var player: AnimationPlayer
var time_scale := 1.0

var action_clip := &""
var action_time := 0.0
var action_speed := 1.0
var action_length := 0.0
var _slot := 0               # active slot: 0 = A, 1 = B
var _ab := 0.0
var _ab_target := 0.0
var _act := 0.0
var _act_target := 0.0
var _ab_rate := 10.0
var _act_rate := 10.0
var _finished_sent := true
var _loco_speed := 0.0
var _sword := 0.0
var _sword_target := 0.0

func setup(anim_player: AnimationPlayer) -> void:
	player = anim_player
	tree = AnimationTree.new()
	tree.name = "AnimTree"
	anim_player.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.tree_root = _build()
	tree.active = true

func _build() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	# Idle point: cane idle <-> sword idle.
	var idle_bt := AnimationNodeBlendTree.new()
	idle_bt.add_node(&"cane", _anim(&"idle"))
	idle_bt.add_node(&"sword", _anim(&"sword_idle" if player.has_animation(&"sword_idle") else &"idle"))
	idle_bt.add_node(&"stance", AnimationNodeBlend2.new())
	idle_bt.connect_node(&"stance", 0, &"cane")
	idle_bt.connect_node(&"stance", 1, &"sword")
	idle_bt.connect_node(&"output", 0, &"stance")
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = RUN_STRIDE
	bs.add_blend_point(idle_bt, 0.0, -1, &"idle")
	bs.add_blend_point(_anim(&"walk"), WALK_STRIDE, -1, &"walk")
	bs.add_blend_point(_anim(&"run"), RUN_STRIDE, -1, &"run")
	bs.sync = true
	bt.add_node(&"loco", bs)
	bt.add_node(&"loco_rate", AnimationNodeTimeScale.new())
	bt.connect_node(&"loco_rate", 0, &"loco")
	for s in ["A", "B"]:
		bt.add_node(StringName("clip" + s), _anim(&"idle"))
		bt.add_node(StringName("seek" + s), AnimationNodeTimeSeek.new())
		bt.add_node(StringName("rate" + s), AnimationNodeTimeScale.new())
		bt.connect_node(StringName("seek" + s), 0, StringName("clip" + s))
		bt.connect_node(StringName("rate" + s), 0, StringName("seek" + s))
	bt.add_node(&"ab", AnimationNodeBlend2.new())
	bt.connect_node(&"ab", 0, &"rateA")
	bt.connect_node(&"ab", 1, &"rateB")
	bt.add_node(&"act", AnimationNodeBlend2.new())
	bt.connect_node(&"act", 0, &"loco_rate")
	bt.connect_node(&"act", 1, &"ab")
	bt.connect_node(&"output", 0, &"act")
	return bt

func _anim(clip: StringName) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a

## Crossfade into an action clip, starting `start` seconds in.
func play_action(clip: StringName, fade := 0.1, start := 0.0, speed := 1.0) -> void:
	if not player.has_animation(clip):
		return
	_slot = 1 - _slot
	var s := "A" if _slot == 0 else "B"
	var root := tree.tree_root as AnimationNodeBlendTree
	(root.get_node(StringName("clip" + s)) as AnimationNodeAnimation).animation = clip
	tree.set("parameters/seek%s/seek_request" % s, start)
	action_clip = clip
	action_time = start
	action_speed = speed
	action_length = player.get_animation(clip).length
	_finished_sent = false
	_ab_target = float(_slot)
	_ab_rate = 1.0 / maxf(fade, 0.001)
	_act_target = 1.0
	_act_rate = 1.0 / maxf(fade, 0.001)

## Blend back to locomotion.
func stop_action(fade := 0.2) -> void:
	_act_target = 0.0
	_act_rate = 1.0 / maxf(fade, 0.001)
	action_clip = &""
	_finished_sent = true

func is_acting() -> bool:
	return action_clip != &""

## Ground speed (m/s) drives the locomotion blend; stance picks the idle.
func set_locomotion(speed: float, sword_stance: bool) -> void:
	_loco_speed = speed
	_sword_target = 1.0 if sword_stance else 0.0

func _process(delta: float) -> void:
	if tree == null:
		return
	var d := delta * time_scale
	# Locomotion: blend position = speed, rate = speed / blended stride.
	var sp := clampf(_loco_speed, 0.0, RUN_STRIDE * 1.6)
	tree.set("parameters/loco/blend_position", minf(sp, RUN_STRIDE))
	var stride := lerpf(WALK_STRIDE, RUN_STRIDE, clampf((sp - WALK_STRIDE) / (RUN_STRIDE - WALK_STRIDE), 0.0, 1.0))
	var rate := 1.0 if sp < WALK_STRIDE * 0.5 else clampf(sp / stride, 0.6, 1.8)
	tree.set("parameters/loco_rate/scale", rate * time_scale)
	_sword = move_toward(_sword, _sword_target, delta * 5.0)
	tree.set("parameters/loco/idle/stance/blend_amount", _sword)
	# Slot rates (inactive slot keeps its last rate while it fades out).
	var s := "A" if _slot == 0 else "B"
	tree.set("parameters/rate%s/scale" % s, action_speed * time_scale)
	# Fades.
	_ab = move_toward(_ab, _ab_target, delta * _ab_rate)
	_act = move_toward(_act, _act_target, delta * _act_rate)
	tree.set("parameters/ab/blend_amount", _ab)
	tree.set("parameters/act/blend_amount", _act)
	# Action clock + end-of-clip notification.
	if action_clip != &"":
		action_time += d * action_speed
		if not _finished_sent and action_time >= action_length:
			_finished_sent = true
			action_time = action_length
			action_finished.emit(action_clip)

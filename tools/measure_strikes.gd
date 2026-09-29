extends SceneTree
## Measures each combat clip's real timing from the motion itself: samples the
## hand/foot bones every frame and finds the strike (peak limb speed), the
## active window (speed above ACTIVE_FRAC of peak around the strike), and the
## lead-in (first frame the limbs actually start moving).
## For draw/sheathe/iai-style clips it also reports `swap`: the moment the right
## hand is closest to the left hip (where the hand meets the cane to draw or
## re-sheathe the blade).
## Run: godot --headless --path . -s res://tools/measure_strikes.gd
##      MEASURE_CLIPS=sword_draw,sword_1 ... to measure specific clips

const CLIPS := ["attack_slash", "cane2", "punch1", "kick_hook", "roundhouse",
	"kick_axe", "spin_kick", "flykick", "capoeira"]
const EFFECTORS := ["mixamorig_RightHand", "mixamorig_LeftHand",
	"mixamorig_RightFoot", "mixamorig_LeftFoot"]
const DT := 1.0 / 60.0
const ACTIVE_FRAC := 0.6   # active window = limb speed >= 60% of the peak
const MOVE_FRAC := 0.15    # lead-in ends when limbs pass 15% of the peak

func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	var hero := (load("res://assets/characters/hero.tscn") as PackedScene).instantiate()
	root.add_child(hero)
	var ap := hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := hero.find_child("*Skeleton*", true, false) as Skeleton3D
	if ap == null or sk == null:
		push_error("hero rig not found")
		quit(1)
		return
	var ids := []
	for b in EFFECTORS:
		var i := sk.find_bone(b)
		if i < 0:
			i = sk.find_bone(b.replace("mixamorig_", "mixamorig:"))
		ids.append(i)
	var clips: Array = CLIPS
	if OS.has_environment("MEASURE_CLIPS"):
		clips = Array(OS.get_environment("MEASURE_CLIPS").split(","))
	var hand := sk.find_bone("mixamorig_RightHand")
	var hip := sk.find_bone("mixamorig_LeftUpLeg")
	print("clip          len    lead  strike  active         limb      swap")
	for clip in clips:
		if not ap.has_animation(clip):
			print(clip, "  MISSING")
			continue
		var length := ap.get_animation(clip).length
		ap.play(clip)
		var speeds := []   # max effector speed per frame
		var which := []
		var prev := []
		var t := 0.0
		var hip_d := []   # right hand -> left hip distance per frame
		while t <= length:
			ap.seek(t, true)
			hip_d.append(sk.get_bone_global_pose(hand).origin.distance_to(sk.get_bone_global_pose(hip).origin))
			var cur := []
			for i in ids:
				cur.append(sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO)
			var best := 0.0
			var best_i := 0
			var kick := _is_kick(clip)
			if not prev.is_empty():
				for k in cur.size():
					if kick != (k >= 2):   # kicks: feet only; hand moves: hands only
						continue
					var v: float = (cur[k] - prev[k]).length() / DT
					if v > best:
						best = v
						best_i = k
			speeds.append(best)
			which.append(best_i)
			prev = cur
			t += DT
		var peak := 0.0
		var pi := 0
		for f in speeds.size():
			if speeds[f] > peak:
				peak = speeds[f]
				pi = f
		var a0 := pi
		while a0 > 0 and speeds[a0 - 1] >= peak * ACTIVE_FRAC:
			a0 -= 1
		var a1 := pi
		while a1 < speeds.size() - 1 and speeds[a1 + 1] >= peak * ACTIVE_FRAC:
			a1 += 1
		var lead := 0
		while lead < pi and speeds[lead] < peak * MOVE_FRAC:
			lead += 1
		# Swap: closest hand->hip approach (before the strike for strike clips).
		var sw := 0
		var lim: int = hip_d.size() if clip.contains("draw") or clip.contains("sheathe") else pi
		for f in lim:
			if hip_d[f] < hip_d[sw]:
				sw = f
		print("%-12s %5.2f  %5.2f  %5.2f   %5.2f-%5.2f  %-9s %5.2f (%.2fm)" % [clip, length,
			lead * DT, pi * DT, a0 * DT, a1 * DT, EFFECTORS[which[pi]].replace("mixamorig_", ""),
			sw * DT, hip_d[sw]])
		# Other strong local peaks (multi-hit moves), at least 0.25 s apart.
		var extra := []
		for f in range(1, speeds.size() - 1):
			if speeds[f] >= peak * 0.7 and speeds[f] >= speeds[f - 1] and speeds[f] > speeds[f + 1] \
					and absf((f - pi) * DT) > 0.25:
				if extra.is_empty() or f * DT - extra[-1] > 0.25:
					extra.append(f * DT)
		if not extra.is_empty():
			print("             other peaks: ", extra.map(func(x): return snappedf(x, 0.01)))
	quit()

func _is_kick(clip: String) -> bool:
	for k in ["kick", "capoeira", "round", "spin", "fly"]:
		if k in clip:
			return true
	return false

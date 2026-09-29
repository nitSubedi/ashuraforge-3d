extends SceneTree
## Plays the hero's Mixamo clips (from hero.tscn, X Bot rest) on another
## Mixamo-rigged character and renders frames — checks rest-pose compatibility.
## RT_RETARGET=1 converts clips through tools/retarget.gd first.
## Run NON-headless: RT_SCENE=res://...glb RT_CLIPS=idle:0.5,attack_slash:0.8 \
##   godot --path . -s res://tools/render_retarget.gd

const RETARGET := preload("res://tools/retarget.gd")
var _f := 0
var _i := 0
var _shots: Array = []
var _ap: AnimationPlayer
var _cam: Camera3D

func _initialize() -> void:
	var root := get_root()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.light_energy = 1.8
	root.add_child(key)

	var ch := (load(OS.get_environment("RT_SCENE")) as PackedScene).instantiate() as Node3D
	root.add_child(ch)
	var sk := ch.find_child("*", true, false) as Node
	sk = _find_skel(ch)
	var src := (load("res://assets/characters/hero.tscn") as PackedScene).instantiate()
	var src_ap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_ap = AnimationPlayer.new()
	ch.add_child(_ap)
	var lib := AnimationLibrary.new()
	var skel_path := String(_ap.get_node(_ap.root_node).get_path_to(sk))
	for spec in OS.get_environment("RT_CLIPS").split(","):
		var parts := spec.split(":")
		var a := (src_ap.get_animation(parts[0]) as Animation).duplicate(true) as Animation
		if OS.get_environment("RT_RETARGET") == "1":
			a = RETARGET.retarget(a, src.find_children("*", "Skeleton3D", true, false)[0], sk, skel_path)
		else:
			for ti in a.get_track_count():
				var p := String(a.track_get_path(ti))
				var bone := p.substr(p.find(":") + 1)
				a.track_set_path(ti, NodePath(skel_path + ":" + bone))
		lib.add_animation(parts[0], a)
		_shots.append([parts[0], float(parts[1])])
	_ap.add_animation_library("", lib)
	src.free()
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.make_current()
	_cam.look_at_from_position(Vector3(1.6, 1.3, 2.6), Vector3(0.0, 0.95, 0.0), Vector3.UP)
	_pose()

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _pose() -> void:
	_ap.play(_shots[_i][0])
	_ap.seek(_shots[_i][1], true)
	_ap.speed_scale = 0.0

func _process(_d: float) -> bool:
	_f += 1
	if _f % 20 == 0:
		var path := "res://assets/generation/out/retarget_%d.png" % _i
		get_root().get_texture().get_image().save_png(path)
		print("SAVED ", path)
		_i += 1
		if _i >= _shots.size():
			return true
		_pose()
	return false

extends SceneTree
## Grip tuning: poses the hero on a clip frame and renders the cane-sword with
## candidate grip transforms (one image each). Run NON-headless:
##   GRIP_CLIP=sword_idle GRIP_T=0.5 GRIP_MODE=drawn \
##   GRIPS="rx,ry,rz,px,py,pz;..." godot --path . -s res://tools/render_grip.gd
## GRIP_MODE: sheathed (sheath rides on the hilt) | drawn (sheath to SheathGrip,
## whose transform is SHEATH_GRIP="rx,ry,rz,px,py,pz"). Degrees / metres.

var _f := 0
var _i := 0
var _grips: Array = []
var _hero: Node3D
var _cane: Node3D
var _cam: Camera3D
var _out := "res://assets/generation/out/grip_%d.png"

func _parse(s: String) -> Transform3D:
	var v := s.split(",")
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(float(v[0])), deg_to_rad(float(v[1])),
		deg_to_rad(float(v[2])))), Vector3(float(v[3]), float(v[4]), float(v[5])))

func _initialize() -> void:
	for g in OS.get_environment("GRIPS").split(";"):
		if g.strip_edges() != "":
			_grips.append(_parse(g))
	var root := get_root()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
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
	_hero = (load("res://assets/characters/hero.tscn") as PackedScene).instantiate()
	root.add_child(_hero)
	var ap := _hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	ap.play(OS.get_environment("GRIP_CLIP") if OS.has_environment("GRIP_CLIP") else "idle")
	ap.seek(float(OS.get_environment("GRIP_T")) if OS.has_environment("GRIP_T") else 0.3, true)
	ap.speed_scale = 0.0
	_cane = _hero.find_child("CaneSword", true, false) as Node3D
	if OS.get_environment("GRIP_MODE") == "drawn":
		var sg := _hero.find_child("SheathGrip", true, false) as Node3D
		if OS.has_environment("SHEATH_GRIP"):
			sg.transform = _parse(OS.get_environment("SHEATH_GRIP"))
		_cane.find_child("Sheath", true, false).reparent(sg, false)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.make_current()
	# Frame the upper body from the front-right.
	_cam.look_at_from_position(Vector3(1.2, 1.4, 2.2), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	_apply()

func _apply() -> void:
	if _grips.is_empty():
		return
	_cane.transform = _grips[_i]

func _process(_d: float) -> bool:
	_f += 1
	if _f % 20 == 0:
		var path := _out % _i
		get_root().get_texture().get_image().save_png(path)
		print("SAVED ", path)
		_i += 1
		if _i >= maxi(1, _grips.size()):
			return true
		_apply()
	return false

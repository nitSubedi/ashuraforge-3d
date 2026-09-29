extends SceneTree
## Full-body review renders of the built hero.tscn (as the game uses it).
## Run NON-headless: HR_CLIP=idle HR_T=0.5 HR_SPRINGS=0 godot --path . -s res://tools/render_hero.gd
## Saves front / side / back / 3-4 shots to assets/generation/out/ingame_*.png.
## HR_HIDE=HeroCloth,HeroCoat hides meshes by name prefix.
## HR_SPRINGS=0 removes the coat spring bones (to isolate deformation issues).

const SHOTS := [
	["front", Vector3(0.0, 1.1, 3.4)],
	["side", Vector3(3.4, 1.1, 0.0)],
	["back", Vector3(0.0, 1.1, -3.4)],
	["q34", Vector3(2.2, 1.4, 2.8)],
]
var _f := 0
var _i := 0
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
	key.rotation_degrees = Vector3(-40, 30, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	root.add_child(key)
	var hero := (load("res://assets/characters/hero.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(hero)
	if OS.get_environment("HR_SPRINGS") == "0":
		var sb := hero.find_child("CoatSprings", true, false)
		if sb:
			sb.free()
	for hide in OS.get_environment("HR_HIDE").split(",", false):   # isolate meshes
		for mi in hero.find_children(hide + "*", "MeshInstance3D", true, false):
			mi.visible = false
	var ap := hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if OS.get_environment("HR_CLIP") == "rest":
		ap = AnimationPlayer.new()   # leave the skeleton in its rest pose
		hero.add_child(ap)
		ap.add_animation_library("", AnimationLibrary.new())
		ap.get_animation_library("").add_animation("rest", Animation.new())
	ap.play(OS.get_environment("HR_CLIP") if OS.has_environment("HR_CLIP") else "idle")
	ap.seek(float(OS.get_environment("HR_T")) if OS.has_environment("HR_T") else 0.5, true)
	ap.speed_scale = 0.0
	_cam = Camera3D.new()
	_cam.fov = 38.0
	root.add_child(_cam)
	_cam.make_current()
	_aim()

func _aim() -> void:
	_cam.look_at_from_position(SHOTS[_i][1], Vector3(0.0, 0.95, 0.0), Vector3.UP)

func _process(_d: float) -> bool:
	_f += 1
	if _f % 25 == 0:
		var path := "res://assets/generation/out/ingame_%s.png" % SHOTS[_i][0]
		get_root().get_texture().get_image().save_png(path)
		print("SAVED ", path)
		_i += 1
		if _i >= SHOTS.size():
			return true
		_aim()
	return false

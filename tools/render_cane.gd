extends SceneTree

## Studio preview of the cane-sword. Run NON-headless:
##   godot --path . -s res://tools/render_cane.gd
## Saves three shots to assets/generation/out/: sheathed, blade 60% drawn,
## and a close-up of the collar / throat / ricasso.
const CANE := preload("res://assets/weapons/cane_sword.glb")
const OUT := "res://assets/generation/out/cane_sword_%s.png"
# name, blade drawn fraction (0..1 of 0.74 m), camera pos, look-at, fov
# The cane lies diagonally (product shot); look-at points are in cane-local space.
const SHOTS := [
	["sheathed", 0.0, Vector3(0, -0.35, 0), 1.45, 30.0],
	["drawn", 0.6, Vector3(0, -0.15, 0), 1.75, 30.0],
	["closeup", 0.12, Vector3(0, 0.03, 0), 0.30, 30.0],
]
var _f := 0
var _shot := 0
var _cane: Node3D
var _cam: Camera3D

func _initialize() -> void:
	var root := get_root()
	root.size = Vector2i(900, 1200)
	var env := Environment.new()
	# A studio sky gives polished steel/silver something to reflect.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.32, 0.36)
	sky_mat.sky_horizon_color = Color(0.75, 0.76, 0.78)
	sky_mat.ground_horizon_color = Color(0.45, 0.45, 0.47)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.13)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -50, 0)
	key.light_energy = 2.4
	key.shadow_enabled = true
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 140, 0)
	rim.light_color = Color(0.85, 0.9, 1.0)
	rim.light_energy = 1.4
	root.add_child(rim)
	_cane = CANE.instantiate() as Node3D
	_cane.rotation_degrees = Vector3(0, 0, -68)   # lay it diagonally across frame
	root.add_child(_cane)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()
	_setup(0)

func _setup(i: int) -> void:
	var s: Array = SHOTS[i]
	var drawn: float = s[1]
	# Draw the hilt+blade up out of the sheath (the sheath stays put).
	for part in ["Hilt", "Blade"]:
		var n := _cane.find_child(part, true, false) as Node3D
		if n:
			n.position = Vector3(0, drawn * 0.74, 0)
	_cam.fov = s[4]
	var target: Vector3 = _cane.transform * (s[2] as Vector3)
	_cam.look_at_from_position(target + Vector3(0.0, 0.05, s[3]), target, Vector3.UP)

func _process(_d: float) -> bool:
	_f += 1
	if _f % 30 == 0:
		var s: Array = SHOTS[_shot]
		var path: String = OUT % s[0]
		get_root().get_texture().get_image().save_png(path)
		print("SAVED ", path)
		_shot += 1
		if _shot >= SHOTS.size():
			return true
		_setup(_shot)
	return false

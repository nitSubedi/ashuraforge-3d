extends SceneTree

## Experiment: import a real Manhattan chunk (exported from map3d / OSM) and
## corrupt it into the flesh-hell aesthetic — flesh shader on every building,
## crimson skybox + fog + glow — then screenshot it. Run:
##   godot --path . -s res://tools/render_city.gd
## (NON-headless so WebGL/atmosphere renders.)

const CITY_GLB := "res://assets/city/manhattan.glb"
const FLESH_MAT := preload("res://assets/shaders/flesh_hell_material.tres")
const SKYBOX := "res://assets/generation/references/hell_skybox.png"
var OUT := "res://assets/generation/out/city_hell.png"

var _f := 0
var _city_aabb: AABB

func _initialize() -> void:
	var root := get_root()
	root.size = Vector2i(1600, 900)

	# --- Atmosphere (mirrors scripts/main.gd _setup_environment) ---
	var env := Environment.new()
	var tex := load(SKYBOX) as Texture2D
	if tex != null:
		var sky := Sky.new()
		var psm := PanoramaSkyMaterial.new()
		psm.panorama = tex
		sky.sky_material = psm
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.7
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.06, 0.01, 0.015)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.1
	# Thin fog: tuned for a wide skyline shot (hundreds of units deep), not a
	# player standing inside it — heavy density would bury the whole city.
	env.fog_enabled = true
	env.fog_light_color = Color(0.20, 0.05, 0.045)
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.3
	if "volumetric_fog_enabled" in env:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0016
		env.volumetric_fog_emission = Color(0.2, 0.03, 0.02)
		env.volumetric_fog_emission_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 130, 0)
	sun.light_color = Color(1.0, 0.5, 0.42)
	sun.light_energy = 0.9
	root.add_child(sun)

	# --- The city ---
	if OS.has_environment("CITY_SHOT") and OS.get_environment("CITY_SHOT") == "2":
		OUT = "res://assets/generation/out/city_hell_street.png"
	var packed := load(CITY_GLB) as PackedScene
	if packed == null:
		push_error("City GLB failed to load: " + CITY_GLB)
		quit(1)
		return
	var city := packed.instantiate() as Node3D
	root.add_child(city)

	# Tuned flesh material for city scale: larger organic vein blobs + vertex
	# displacement so buildings bulge/sag instead of reading as crisp boxes.
	var city_mat := (FLESH_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	city_mat.set_shader_parameter("vein_scale", 0.06)
	city_mat.set_shader_parameter("displace", 6.0)
	city_mat.set_shader_parameter("emission_energy", 0.7)
	city_mat.set_shader_parameter("bump", 0.9)

	var count := _apply_flesh(city, city_mat)
	_city_aabb = _compute_aabb(city, Transform3D.IDENTITY)
	print("CITY loaded. flesh-applied meshes=", count)
	print("CITY aabb pos=", _city_aabb.position, " size=", _city_aabb.size)

	# Flesh ground so the city sits on tissue instead of floating over the sky.
	var ground := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	var gsize: float = max(_city_aabb.size.x, _city_aabb.size.z) * 2.0
	gp.size = Vector2(gsize, gsize)
	gp.subdivide_width = 120
	gp.subdivide_depth = 120
	ground.mesh = gp
	var ground_mat := (FLESH_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	ground_mat.set_shader_parameter("vein_scale", 0.05)
	ground_mat.set_shader_parameter("displace", 3.0)
	ground.material_override = ground_mat
	var gc := _city_aabb.get_center()
	ground.position = Vector3(gc.x, _city_aabb.position.y, gc.z)
	root.add_child(ground)

	# --- Camera: 3/4 skyline shot framed on the city bounds ---
	var c := _city_aabb.get_center()
	var s := _city_aabb.size
	var reach: float = max(s.x, s.z)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 8000.0
	var shot := 1
	if OS.has_environment("CITY_SHOT"):
		shot = OS.get_environment("CITY_SHOT").to_int()
	var eye: Vector3
	var target: Vector3
	if shot == 2:
		# Low, near street level — closer to the in-game fighting POV.
		eye = Vector3(c.x - reach * 0.30, _city_aabb.position.y + 7.0, c.z - reach * 0.30)
		target = Vector3(c.x, c.y + s.y * 0.4, c.z)
		cam.fov = 65.0
	else:
		eye = Vector3(c.x + reach * 0.42, c.y + s.y * 0.95, c.z + reach * 0.42)
		target = Vector3(c.x, c.y + s.y * 0.25, c.z)
	root.add_child(cam)
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.make_current()

func _process(_d: float) -> bool:
	_f += 1
	if _f == 60:
		var img: Image = get_root().get_texture().get_image()
		img.save_png(OUT)
		print("CITY_RENDER_SAVED -> ", OUT)
		return true
	return false

func _apply_flesh(n: Node, mat: Material) -> int:
	var count := 0
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
		count += 1
	for ch in n.get_children():
		count += _apply_flesh(ch, mat)
	return count

func _compute_aabb(n: Node, xform: Transform3D) -> AABB:
	var acc := AABB()
	var has := false
	if n is Node3D:
		xform = xform * (n as Node3D).transform
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		if m.mesh != null:
			var local := m.mesh.get_aabb()
			var world := xform * local
			acc = world
			has = true
	for ch in n.get_children():
		var sub := _compute_aabb(ch, xform)
		if sub.size != Vector3.ZERO:
			if has:
				acc = acc.merge(sub)
			else:
				acc = sub
				has = true
	return acc

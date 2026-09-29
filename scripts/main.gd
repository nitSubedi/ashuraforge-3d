extends Node3D
## Flesh-hell dimension orchestrator. Configures the visceral environment (AI
## skybox, crimson fog, glow), builds an organic flesh expanse (large veined
## ground + sparse sinew pillars), drifting embers, then starts the round.
##
## Sub-project 2 (procedural layout) will replace _build_world() with a generator
## that emits zones into this same aesthetic.

const PILLAR := preload("res://assets/dungeon/pillar.gltf.glb")
const FLESH_MAT := preload("res://assets/shaders/flesh_hell_material.tres")
const SKYBOX := "res://assets/generation/references/hell_skybox.png"
const CITY := preload("res://assets/city/manhattan.glb")
const BUILDING_SHADER := preload("res://assets/shaders/building_hell.gdshader")
const ROAD_SHADER := preload("res://assets/shaders/road_blood.gdshader")
const CityStreamer := preload("res://scripts/city_streamer.gd")
const PostFX := preload("res://scripts/fx/post_fx.gd")
const FX := preload("res://scripts/fx/fx.gd")

const GROUND_HALF := 120.0  # ground radius that follows the player (feels infinite)
const CITY_MODE := true      # spawn inside the corrupted OSM city instead of the empty expanse
const CITY_SCALE := 2.4      # scale the OSM city up so streets are walkable/fight-able

var _ground: Node3D
var _ground_col: Node3D
var _embers: Node3D
var _ash: Node3D
var _player: Node3D
var _city_mesh_count := 0
var _growth_count := 0

func _ready() -> void:
	_setup_environment()
	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-32, -40, 0)
		sun.light_color = Color(0.85, 0.15, 0.12)
		sun.light_energy = 1.4
	if CITY_MODE:
		_build_city_world()
	else:
		_build_world()
	_spawn_embers()
	_spawn_ash()
	_apply_grade()
	add_child(PostFX.new())
	_spawn_dummy()
	_warmup_and_fade_in()
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	Game.start_round(enemies.size())

## Polished start: a short fade from black that hides first-use shader/pipeline
## compiles. Everything that would otherwise compile on first use (blood
## particles on the first hit, the hero/enemy/city materials) renders once
## underneath it, so gameplay never hitches.
func _warmup_and_fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	add_child(layer)
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e.has_method(&"_blood"):   # compile the blood particle pipeline now
			e._blood(e.global_position + Vector3(0, 1, 0), Vector3.UP, 4, 0.2, 0.5)
			break
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(black, "color:a", 0.0, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_callback(layer.queue_free)

func _spawn_dummy() -> void:
	# A small pack to test powers on (placeholder until the arena spawner).
	for pos in [Vector3(0, 0, 3), Vector3(-2.5, 0, 6), Vector3(2.5, 0, 6), Vector3(-4, 0, 9.5),
			Vector3(0, 0, 10), Vector3(4, 0, 9.5)]:
		var enemy := StaticBody3D.new()
		enemy.set_script(preload("res://scripts/enemy.gd"))
		enemy.position = pos
		add_child(enemy)

func _setup_environment() -> void:
	var we := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment

	# AI flesh-hell skybox (fall back to a crimson gradient if it's missing).
	var tex := load(SKYBOX) as Texture2D
	if tex != null:
		var sky := Sky.new()
		var psm := PanoramaSkyMaterial.new()
		psm.panorama = tex
		sky.sky_material = psm
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.8
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.06, 0.01, 0.015)

	# Visceral grade: bloom on the emissive veins, contrast/saturation, filmic.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08

	# Keep crimson fog but thin it so the skybox horizon reads.
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.045, 0.04)
	env.fog_density = 0.008
	if "volumetric_fog_enabled" in env:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.008
		env.volumetric_fog_emission = Color(0.2, 0.03, 0.02)
		env.volumetric_fog_emission_energy = 0.4

func _build_world() -> void:
	var world := Node3D.new()
	world.name = "FleshHell"
	add_child(world)

	# Large veined flesh ground that follows the player (_process), so it reads
	# as an endless expanse — the flesh shader is world-space, so sliding the
	# plane just reveals more of the same infinite pattern. No boundary walls.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_HALF * 2.0, GROUND_HALF * 2.0)
	plane.subdivide_width = 100
	plane.subdivide_depth = 100
	ground.mesh = plane
	ground.material_override = FLESH_MAT
	world.add_child(ground)
	_ground = ground

	# Flat collision (also follows the player) so there's always ground underfoot.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_HALF * 2.0 + 40.0, 1.0, GROUND_HALF * 2.0 + 40.0)
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(0, -0.5, 0)
	world.add_child(body)
	_ground_col = body

func _build_city_world() -> void:
	var world := Node3D.new()
	world.name = "FleshCity"
	add_child(world)
	_tune_city_lighting()

	# Preferred path: stream the baked chunks (tools/bake_city.gd) — merged
	# meshes, occluders, background loading ahead of the player/camera.
	var streamer := CityStreamer.new()
	streamer.name = "CityStreamer"
	if streamer.load_index():
		world.add_child(streamer)
		var fl: Dictionary = streamer.floor_layout
		_add_city_floor(world, float(fl["cx"]), float(fl["cz"]), float(fl["span"]))
		streamer.prime(Vector3.ZERO)
		print("FleshCity streaming. chunks loaded at spawn=", streamer.loaded_count())
		return
	streamer.free()

	# Fallback: build the whole city in one go (no baked chunks present).
	var city := CITY.instantiate() as Node3D
	city.scale = Vector3(CITY_SCALE, CITY_SCALE, CITY_SCALE)
	world.add_child(city)

	# Buildings keep their building-ness: concrete facades with a grid of windows
	# (dark / hell-lit / broken) and blood streaks — "New York, but damned".
	var city_mat := ShaderMaterial.new()
	city_mat.shader = BUILDING_SHADER
	city_mat.set_shader_parameter("floor_height", 3.5)   # local units/storey (pre-scale)
	city_mat.set_shader_parameter("window_span", 4.0)
	city_mat.set_shader_parameter("lit_ratio", 0.28)
	city_mat.set_shader_parameter("window_energy", 2.2)
	city_mat.set_shader_parameter("blood_amount", 0.7)
	_skin_city(city, city_mat)

	# Offset so the player (spawns near origin, facing -Z) stands just outside
	# the near edge looking in — not buried in the middle of the block.
	var aabb := _compute_aabb(city, Transform3D.IDENTITY)
	var center := aabb.get_center()
	# Ground the HIGHEST building base at y=0. The GLB has buildings on two base
	# levels; grounding to the global MIN (aabb.position.y) left the higher group
	# floating 2.4u ("walk under a building"). Grounding to the max base instead
	# plants that group and lets the few lower ones sink harmlessly below the floor.
	var max_base := _max_building_base(city, Transform3D.IDENTITY)
	city.position = Vector3(-center.x, -max_base, -40.0 - aabb.end.z)

	_add_city_floor(world, 0.0, -40.0 - aabb.size.z * 0.5, max(aabb.size.x, aabb.size.z) + 800.0)

	# Gross organic growths clustered on the buildings (final transforms are set,
	# so per-building world AABBs are valid).
	_grow_organics(city, world)

	print("FleshCity built. buildings=", _city_mesh_count, " growths=", _growth_count,
		" offset=", city.position)

## Wet bloody asphalt floor + one flat collider under the whole city.
func _add_city_floor(world: Node3D, world_cx: float, world_cz: float, floor_span: float) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(floor_span, floor_span)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	ground.mesh = plane
	# Ground = wet asphalt with blood puddles. The gaps between building blocks
	# then read as bloody streets (the road grid comes free from negative space).
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = ROAD_SHADER
	ground_mat.set_shader_parameter("puddle_scale", 0.02)
	ground_mat.set_shader_parameter("puddle_amount", 0.55)
	ground_mat.set_shader_parameter("glow", 0.3)
	ground.material_override = ground_mat
	ground.position = Vector3(world_cx, 0.0, world_cz)
	world.add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(floor_span, 1.0, floor_span)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(world_cx, -0.5, world_cz)
	world.add_child(floor_body)


## Re-light the world for the city: a red key/fog washes everything to flat
## crimson, so warm-but-not-red key + a cool fill create form and hue contrast,
## and the fog is thinned + desaturated so the pale towers survive at distance.
func _tune_city_lighting() -> void:
	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-38, -52, 0)
		sun.light_color = Color(1.0, 0.72, 0.55)   # warm amber, NOT pure red
		sun.light_energy = 2.2
		sun.shadow_enabled = true

	# Cool fill from the opposite side so shadowed faces don't go pure black/red
	# — the value split between warm-lit and cool-shadowed faces gives form.
	var fill := DirectionalLight3D.new()
	fill.name = "CityFill"
	fill.rotation_degrees = Vector3(-24, 128, 0)
	fill.light_color = Color(0.35, 0.42, 0.62)
	fill.light_energy = 0.55
	fill.shadow_enabled = false
	add_child(fill)

	var we := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.ambient_light_energy = 0.45
		# Thin, desaturated fog: the city is huge, so the old dense red fog buried
		# everything in crimson haze. Keep just enough for depth.
		env.fog_enabled = true
		env.fog_light_color = Color(0.14, 0.07, 0.08)
		env.fog_density = 0.0015
		if "fog_sky_affect" in env:
			env.fog_sky_affect = 0.2
		if "volumetric_fog_enabled" in env:
			env.volumetric_fog_density = 0.002
		env.glow_hdr_threshold = 1.3

## Scatter lumpy flesh tumors on/around every building via MultiMesh (one draw
## call). Uses the flesh shader WITH displacement — fine here, these are
## decorative, nothing stands on them.
func _grow_organics(city: Node, world: Node3D) -> void:
	var buildings: Array[MeshInstance3D] = []
	_collect_meshes(city, buildings)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260705

	var xforms: Array[Transform3D] = []
	for m in buildings:
		var wa := m.global_transform * m.mesh.get_aabb()  # world-space AABB
		var cx := wa.position.x + wa.size.x * 0.5
		var cz := wa.position.z + wa.size.z * 0.5
		var base_y := wa.position.y
		var top_y := wa.end.y
		var radius: float = max(wa.size.x, wa.size.z) * 0.5
		var blob: float = clamp(radius * 0.14, 2.0, 8.0)

		# Sparse flesh growth seeping up ONLY at the street-level base, so the
		# building facades stay readable. Skip most buildings entirely.
		if rng.randf() > 0.45:
			continue
		var n_base := 1 + rng.randi_range(0, 2)
		for i in n_base:
			var a := rng.randf() * TAU
			var r := radius * rng.randf_range(0.82, 1.02)
			var p := Vector3(cx + cos(a) * r, base_y + blob * 0.25, cz + sin(a) * r)
			xforms.append(_blob_xform(p, blob * rng.randf_range(0.7, 1.2), rng))

	var blob_mesh := SphereMesh.new()
	blob_mesh.radius = 1.0
	blob_mesh.height = 2.0
	blob_mesh.radial_segments = 12
	blob_mesh.rings = 8

	var growth_mat := (FLESH_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	growth_mat.set_shader_parameter("base_color", Color(0.42, 0.06, 0.05))
	growth_mat.set_shader_parameter("vein_color", Color(0.95, 0.30, 0.28))
	growth_mat.set_shader_parameter("emission_color", Color(0.95, 0.12, 0.06))
	growth_mat.set_shader_parameter("emission_energy", 1.3)
	growth_mat.set_shader_parameter("vein_scale", 0.5)
	growth_mat.set_shader_parameter("wetness", 0.98)
	growth_mat.set_shader_parameter("bump", 1.0)
	growth_mat.set_shader_parameter("displace", 0.45)  # lumpy, gross
	growth_mat.set_shader_parameter("pulse_speed", 1.6)
	blob_mesh.material = growth_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blob_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Growths"
	mmi.multimesh = mm
	world.add_child(mmi)
	_growth_count = xforms.size()

func _blob_xform(pos: Vector3, s: float, rng: RandomNumberGenerator) -> Transform3D:
	# Squashed, randomly-oriented ellipsoid so clumps read as fleshy sacs.
	var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
	basis = basis.scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.75, 1.15)))
	return Transform3D(basis, pos)

func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c, out)

func _skin_city(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		m.material_override = mat
		_city_mesh_count += 1
		# Box collider matching the building footprint (children inherit the
		# mesh's world transform, so it lines up with the rotated geometry).
		if m.mesh != null:
			var box_aabb := m.mesh.get_aabb()
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = box_aabb.size
			col.shape = box
			col.position = box_aabb.get_center()
			body.add_child(col)
			m.add_child(body)
	for c in n.get_children():
		_skin_city(c, mat)

## Highest per-building base Y (each building's own AABB minimum), so we can
## ground the dominant/upper group instead of the single lowest outlier.
func _max_building_base(n: Node, xform: Transform3D) -> float:
	var m := -INF
	if n is Node3D:
		xform = xform * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var wa := xform * (n as MeshInstance3D).mesh.get_aabb()
		m = max(m, wa.position.y)
	for c in n.get_children():
		m = max(m, _max_building_base(c, xform))
	return m

func _compute_aabb(n: Node, xform: Transform3D) -> AABB:
	var acc := AABB()
	var has := false
	if n is Node3D:
		xform = xform * (n as Node3D).transform
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		if m.mesh != null:
			acc = xform * m.mesh.get_aabb()
			has = true
	for c in n.get_children():
		var sub := _compute_aabb(c, xform)
		if sub.size != Vector3.ZERO:
			acc = sub if not has else acc.merge(sub)
			has = true
	return acc

func _process(_delta: float) -> void:
	if _player == null:
		_player = get_node_or_null(^"Player") as Node3D
		if _player == null:
			return
	var p := _player.global_position
	if _ground:
		_ground.global_position = Vector3(p.x, 0.0, p.z)
	if _ground_col:
		_ground_col.global_position = Vector3(p.x, -0.5, p.z)
	if _embers:
		_embers.global_position = Vector3(p.x, 4.0, p.z)
	if _ash:
		_ash.global_position = Vector3(p.x, 14.0, p.z)

## Cinematic grade on top of the lighting: a baked 3D colour LUT (deep crimson
## lifted shadows, warm amber highlights, slightly calmer mids, gentle S-curve),
## screen-space reflections for the wet bloody streets, AgX tonemapping.
func _apply_grade() -> void:
	var we := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_color_correction = _grade_lut()
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.0
	env.ssao_power = 1.4

func _grade_lut() -> ImageTexture3D:
	const N := 17
	var layers: Array[Image] = []
	for bz in N:
		var img := Image.create(N, N, false, Image.FORMAT_RGB8)
		for gy in N:
			for rx in N:
				var c := Color(rx / float(N - 1), gy / float(N - 1), bz / float(N - 1))
				img.set_pixel(rx, gy, _grade(c))
		layers.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, N, N, N, false, layers)
	return tex

static func _grade(c: Color) -> Color:
	var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var v := Vector3(c.r, c.g, c.b)
	v = Vector3(l, l, l).lerp(v, 0.9)                           # calmer mids
	var sh := pow(1.0 - l, 2.0)
	v += Vector3(0.035, 0.0, 0.018) * sh                          # crimson-violet shadow lift
	var hi := smoothstep(0.55, 1.0, l)
	v = v.lerp(v * Vector3(1.04, 0.93, 0.8), hi * 0.6)            # warm amber highlights
	for i in 3:                                                   # gentle S-curve
		var x: float = clampf(v[i], 0.0, 1.0)
		v[i] = lerpf(x, x * x * (3.0 - 2.0 * x), 0.22)
	return Color(clampf(v.x, 0, 1), clampf(v.y, 0, 1), clampf(v.z, 0, 1))

## Grey ash drifting down through the air around the player.
func _spawn_ash() -> void:
	var ash := GPUParticles3D.new()
	ash.name = "Ash"
	ash.amount = 700
	ash.lifetime = 9.0
	ash.preprocess = 6.0
	ash.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 2, 30)
	pm.direction = Vector3(0.2, -1, 0.1)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.15, -0.25, 0.05)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.012     # fine flecks — large quads read as snow/bokeh near the camera
	pm.scale_max = 0.028
	var fade := Gradient.new()
	fade.set_color(0, Color(0.35, 0.33, 0.32, 0.0))
	fade.add_point(0.15, Color(0.3, 0.28, 0.27, 0.45))
	fade.set_color(fade.get_point_count() - 1, Color(0.3, 0.28, 0.27, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	ash.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var am := FX.particle_mat(Color.WHITE, false)
	am.distance_fade_min_distance = 2.5     # ash only reads at a distance
	am.distance_fade_max_distance = 6.0
	q.material = am
	ash.draw_pass_1 = q
	add_child(ash)
	_ash = ash

func _spawn_embers() -> void:
	var emb := GPUParticles3D.new()
	emb.name = "Embers"
	emb.amount = 500
	emb.lifetime = 7.0
	emb.preprocess = 4.0
	emb.position = Vector3(0, 4, 0)
	emb.visibility_aabb = AABB(Vector3(-50, -4, -50), Vector3(100, 60, 100))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 8, 40)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.2, 0.4, 0.0)
	pm.scale_min = 0.02
	pm.scale_max = 0.07
	pm.color = Color(1.0, 0.45, 0.18)
	emb.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.2)
	mat.emission_energy_multiplier = 5.0
	mat.albedo_color = Color(1.0, 0.5, 0.2)
	quad.material = mat
	emb.draw_pass_1 = quad
	add_child(emb)
	_embers = emb

func _apply_flesh(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = FLESH_MAT
	for c in n.get_children():
		_apply_flesh(c)

func _static_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	parent.add_child(body)

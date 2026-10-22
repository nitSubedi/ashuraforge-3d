extends SceneTree
## Bake the OSM hell-city into streamable chunks (AAA-style world partition).
##
## Per CHUNK x CHUNK metre cell, one scene with:
##   Buildings  – ONE merged mesh (one draw call instead of ~16); every vertex
##                carries its building-local position/normal in CUSTOM0/1 so the
##                per-building window grid of building_hell_merged still works
##   Occluder   – the building boxes as an ArrayOccluder3D (occlusion culling)
##   Colliders  – one StaticBody3D, an unscaled BoxShape per building
##   Growths    – this cell's flesh tumours as one MultiMesh
## plus index.json (chunk AABBs + world floor layout) for scripts/city_streamer.gd.
## Layout (scale, offset, grounding) and growth placement match main.gd exactly.
## Run: godot --headless --path . -s res://tools/bake_city.gd

const CITY := preload("res://assets/city/manhattan.glb")
const FLESH_MAT := preload("res://assets/shaders/flesh_hell_material.tres")
const MERGED_SHADER := preload("res://assets/shaders/building_hell_merged.gdshader")
const CITY_SCALE := 1.0   # must match main.gd (real-world metres)
const CHUNK := 120.0
const OUT := "res://assets/city/chunks/"

class Cell:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var occ_verts := PackedVector3Array()
	var occ_idx := PackedInt32Array()
	var boxes := []        # [Transform3D, Vector3 size]
	var growths := []      # Transform3D
	var aabb := AABB()
	var has_aabb := false

var _cells := {}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var city := CITY.instantiate() as Node3D
	city.scale = Vector3(CITY_SCALE, CITY_SCALE, CITY_SCALE)
	# Same layout as main.gd:_build_city_world.
	var aabb := _compute_aabb(city, Transform3D.IDENTITY)
	var center := aabb.get_center()
	var max_base := _max_building_base(city, Transform3D.IDENTITY)
	city.position = Vector3(-center.x, -max_base, -40.0 - aabb.end.z)

	var buildings := []   # [MeshInstance3D, world Transform3D] in main.gd's order
	_collect(city, Transform3D.IDENTITY, buildings)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260705   # same seed + order as main.gd:_grow_organics
	for entry in buildings:
		var mi: MeshInstance3D = entry[0]
		var xf: Transform3D = entry[1]
		var wa: AABB = xf * mi.mesh.get_aabb()
		var cell := _cell_for(wa.get_center())
		_add_building(cell, mi.mesh, xf)
		_add_growths(cell, wa, rng)

	var mat := ShaderMaterial.new()
	mat.shader = MERGED_SHADER
	mat.set_shader_parameter("floor_height", 3.5)
	mat.set_shader_parameter("window_span", 4.0)
	mat.set_shader_parameter("lit_ratio", 0.28)
	mat.set_shader_parameter("window_energy", 2.2)
	mat.set_shader_parameter("blood_amount", 0.7)
	ResourceSaver.save(mat, OUT + "building_material.tres")
	var growth := _growth_mesh()
	ResourceSaver.save(growth, OUT + "growth_mesh.tres")
	mat = load(OUT + "building_material.tres")
	growth = load(OUT + "growth_mesh.tres")

	var index := {"chunk": CHUNK, "chunks": [],
		"floor": {"cx": 0.0, "cz": -40.0 - aabb.size.z * 0.5,
			"span": maxf(aabb.size.x, aabb.size.z) + 800.0}}
	for key in _cells:
		var c: Cell = _cells[key]
		var path := OUT + "c_%d_%d.scn" % [key.x, key.y]
		ResourceSaver.save(_pack(c, key, mat, growth), path)
		index["chunks"].append({"file": path, "pos": [c.aabb.position.x, c.aabb.position.y, c.aabb.position.z],
			"size": [c.aabb.size.x, c.aabb.size.y, c.aabb.size.z]})
	var f := FileAccess.open(OUT + "index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(index, "\t"))
	f.close()
	print("CITY_BAKED chunks=%d buildings=%d" % [_cells.size(), buildings.size()])
	city.free()
	quit()

func _cell_for(p: Vector3) -> Cell:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not _cells.has(key):
		_cells[key] = Cell.new()
	return _cells[key]

func _add_building(c: Cell, mesh: Mesh, xf: Transform3D) -> void:
	var nb := xf.basis.inverse().transposed()   # normal matrix
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var order: PackedInt32Array = idx if idx.size() > 0 else PackedInt32Array(range(v.size()))
		for t in range(0, order.size() - 2, 3):   # de-indexed triangles, flat normals (boxes)
			var a := v[order[t]]
			var bb := v[order[t + 1]]
			var cc := v[order[t + 2]]
			var ln := (cc - a).cross(bb - a).normalized()   # Godot winding: clockwise front
			for p in [a, bb, cc]:
				var wv: Vector3 = xf * p
				c.verts.append(wv)
				c.normals.append((nb * ln).normalized())
				c.custom0.append_array([p.x, p.y, p.z, 0.0])
				c.custom1.append_array([ln.x, ln.y, ln.z, 0.0])
				if c.has_aabb:
					c.aabb = c.aabb.expand(wv)
				else:
					c.aabb = AABB(wv, Vector3.ZERO)
					c.has_aabb = true
	# Box occluder + unscaled box collider from the building's local AABB.
	var la := mesh.get_aabb()
	var base := c.occ_verts.size()
	for k in 8:
		c.occ_verts.append(xf * la.get_endpoint(k))
	for tri in [0, 1, 2, 1, 3, 2, 4, 6, 5, 5, 6, 7, 0, 4, 1, 1, 4, 5, 2, 3, 6, 3, 7, 6, 0, 2, 4, 2, 6, 4, 1, 5, 3, 3, 5, 7]:
		c.occ_idx.append(base + tri)
	var sc := xf.basis.get_scale()
	var box_xf := Transform3D(xf.basis.orthonormalized(), xf * la.get_center())
	c.boxes.append([box_xf, la.size * sc])

func _add_growths(c: Cell, wa: AABB, rng: RandomNumberGenerator) -> void:
	# Mirrors main.gd:_grow_organics (same RNG call sequence).
	var cx := wa.position.x + wa.size.x * 0.5
	var cz := wa.position.z + wa.size.z * 0.5
	var radius: float = max(wa.size.x, wa.size.z) * 0.5
	var blob: float = clamp(radius * 0.14, 2.0, 8.0)
	if rng.randf() > 0.45:
		return
	var n_base := 1 + rng.randi_range(0, 2)
	for i in n_base:
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.82, 1.02)
		var p := Vector3(cx + cos(a) * r, wa.position.y + blob * 0.25, cz + sin(a) * r)
		var s := blob * rng.randf_range(0.7, 1.2)
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		b = b.scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.75, 1.15)))
		c.growths.append(Transform3D(b, p))

func _growth_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 12
	m.rings = 8
	var g := (FLESH_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	g.set_shader_parameter("base_color", Color(0.42, 0.06, 0.05))
	g.set_shader_parameter("vein_color", Color(0.95, 0.30, 0.28))
	g.set_shader_parameter("emission_color", Color(0.95, 0.12, 0.06))
	g.set_shader_parameter("emission_energy", 1.3)
	g.set_shader_parameter("vein_scale", 0.5)
	g.set_shader_parameter("wetness", 0.98)
	g.set_shader_parameter("bump", 1.0)
	g.set_shader_parameter("displace", 0.45)
	g.set_shader_parameter("pulse_speed", 1.6)
	m.material = g
	return m

func _pack(c: Cell, key: Vector2i, mat: Material, growth: Mesh) -> PackedScene:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = c.verts
	arrays[Mesh.ARRAY_NORMAL] = c.normals
	arrays[Mesh.ARRAY_CUSTOM0] = c.custom0
	arrays[Mesh.ARRAY_CUSTOM1] = c.custom1
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	am.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = am
	root.add_child(mi)

	var occ := ArrayOccluder3D.new()
	occ.set_arrays(c.occ_verts, c.occ_idx)
	var oi := OccluderInstance3D.new()
	oi.name = "Occluder"
	oi.occluder = occ
	root.add_child(oi)

	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for b in c.boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b[1]
		cs.shape = shape
		cs.transform = b[0]
		body.add_child(cs)

	if not c.growths.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = growth
		# Headless baking uses a dummy renderer that DROPS MultiMesh instance
		# data, so store the transforms as plain data; city_streamer fills the
		# MultiMesh when the chunk is instanced.
		var flat := PackedFloat32Array()
		for t in c.growths:
			flat.append_array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
				t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y,
				t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Growths"
		mmi.multimesh = mm
		mmi.set_meta("xforms", flat)
		root.add_child(mmi)
	for n in root.get_children():
		n.owner = root
		for m in n.get_children():
			m.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps

# --- layout helpers (same maths as main.gd) -------------------------------

func _collect(n: Node, xform: Transform3D, out: Array) -> void:
	if n is Node3D:
		xform = xform * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, xform])
	for c in n.get_children():
		_collect(c, xform, out)

func _max_building_base(n: Node, xform: Transform3D) -> float:
	var m := -INF
	if n is Node3D:
		xform = xform * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		m = max(m, (xform * (n as MeshInstance3D).mesh.get_aabb()).position.y)
	for c in n.get_children():
		m = max(m, _max_building_base(c, xform))
	return m

func _compute_aabb(n: Node, xform: Transform3D) -> AABB:
	var acc := AABB()
	var has := false
	if n is Node3D:
		xform = xform * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		acc = xform * (n as MeshInstance3D).mesh.get_aabb()
		has = true
	for c in n.get_children():
		var sub := _compute_aabb(c, xform)
		if sub.size != Vector3.ZERO:
			acc = sub if not has else acc.merge(sub)
			has = true
	return acc

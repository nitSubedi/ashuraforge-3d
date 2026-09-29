extends SceneTree

## Diagnose the "walk under buildings" bug: report the distribution of each
## building's world-space base Y (after CITY_SCALE), so we know if bases vary.
const CITY := preload("res://assets/city/manhattan.glb")
const CITY_SCALE := 2.4

var _rows: Array = []  # [baseY, size]

func _initialize() -> void:
	var city := CITY.instantiate() as Node3D
	city.scale = Vector3(CITY_SCALE, CITY_SCALE, CITY_SCALE)
	# Manual traversal with accumulated transform (matches main.gd _compute_aabb).
	_walk(city, Transform3D.IDENTITY)
	var bases: Array[float] = []
	var tall := 0
	for i in _rows.size():
		var b: float = _rows[i][0]
		var sz: Vector3 = _rows[i][1]
		bases.append(b)
		if sz.y >= sz.x and sz.y >= sz.z:
			tall += 1
		if i < 8:
			print("  mesh[", i, "] size=", sz, " baseY=", b)
	print("standing(tall)=", tall, " of ", _rows.size())
	bases.sort()
	var n := bases.size()
	var gmin := bases[0]
	var above := 0
	for b in bases:
		if b - gmin > 4.0:
			above += 1
	print("buildings=", n)
	print("base_y min=", gmin, " max=", bases[n - 1])
	print("percentiles: p10=", bases[n/10], " p50=", bases[n/2], " p90=", bases[n*9/10])
	print("count with base >4u above global-min: ", above, " (", 100.0*above/n, "%)")
	quit()

func _walk(node: Node, xform: Transform3D) -> void:
	if node is Node3D:
		xform = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var wa := xform * (node as MeshInstance3D).mesh.get_aabb()
		_rows.append([wa.position.y, wa.size])
	for c in node.get_children():
		_walk(c, xform)

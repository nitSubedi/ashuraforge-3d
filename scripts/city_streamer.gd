extends Node3D
## Streams the baked city chunks (tools/bake_city.gd) around the player, the
## way open-world games partition their worlds:
##   - keep EVERY chunk within FAR of the player loaded, in all directions —
##     loading only what the camera faces made buildings pop in as you turned,
##   - the camera's view cone and the velocity lookahead only set the ORDER:
##     what the player is looking at / heading toward loads first,
##   - load on a background thread (ResourceLoader threaded requests), and
##     instance at most ADD_PER_FRAME chunks per frame so streaming never hitches,
##   - unload with hysteresis (UNLOAD > FAR) so boundary chunks don't thrash.
## Rendering inside loaded chunks is further culled by the engine: frustum
## culling per chunk AABB + occlusion culling via each chunk's box occluder.

const INDEX := "res://assets/city/chunks/index.json"
const NEAR := 260.0
const FAR := 900.0
const UNLOAD := 1000.0
const LOOKAHEAD := 1.5
const VIEW_DOT := 0.25        # cos of the half-angle of the "looking at" cone
const ADD_PER_FRAME := 2
const TICK := 0.1             # re-evaluate wanted chunks 10x/second

var floor_layout := {}
var _chunks: Array = []       # [{file, aabb, center, node, state}]
var _tick := 0.0
var _player: Node3D
var _last_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _ready_queue: Array = []

func load_index() -> bool:
	var f := FileAccess.open(INDEX, FileAccess.READ)
	if f == null:
		return false
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	floor_layout = data["floor"]
	for c in data["chunks"]:
		var aabb := AABB(Vector3(c["pos"][0], c["pos"][1], c["pos"][2]),
			Vector3(c["size"][0], c["size"][1], c["size"][2]))
		_chunks.append({"file": c["file"], "aabb": aabb, "center": aabb.get_center(),
			"node": null, "state": "out"})
	return true

## Synchronously load everything near the spawn so the first frame is complete
## (the "prepare assets before the player sees them" pass behind the loading).
func prime(at: Vector3) -> void:
	for c in _chunks:
		if _flat_dist(c, at) < NEAR:
			_instance(c, load(c["file"]) as PackedScene)

func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
		if _player == null:
			return
		_last_pos = _player.global_position
	# Smoothed velocity estimate for movement prediction.
	var p := _player.global_position
	if delta > 0.0:
		_vel = _vel.lerp((p - _last_pos) / delta, 0.2)
	_last_pos = p

	# Finish background loads, a couple per frame.
	var added := 0
	for c in _chunks:
		if added >= ADD_PER_FRAME:
			break
		if c["state"] == "loading":
			var st := ResourceLoader.load_threaded_get_status(c["file"])
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				_instance(c, ResourceLoader.load_threaded_get(c["file"]) as PackedScene)
				added += 1
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				c["state"] = "out"

	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ahead := p + _vel * LOOKAHEAD
	# Priority: distance, halved for chunks in view or on the predicted path.
	var score := {}
	for i in _chunks.size():
		var c: Dictionary = _chunks[i]
		var d := _flat_dist(c, p)
		var to: Vector3 = c["center"] - p
		to.y = 0.0
		var favoured := to.normalized().dot(fwd) > VIEW_DOT or _flat_dist(c, ahead) < NEAR
		score[i] = d * (0.5 if favoured else 1.0)
	var order := range(_chunks.size())
	order.sort_custom(func(a, b): return score[a] < score[b])
	for i in order:
		var c: Dictionary = _chunks[i]
		var d := _flat_dist(c, p)
		var wanted := d < FAR or _flat_dist(c, ahead) < NEAR
		if wanted and c["state"] == "out":
			ResourceLoader.load_threaded_request(c["file"], "PackedScene", true)
			c["state"] = "loading"
		elif not wanted and c["state"] == "in" and d > UNLOAD:
			c["node"].queue_free()
			c["node"] = null
			c["state"] = "out"

func loaded_count() -> int:
	return _chunks.filter(func(c): return c["state"] == "in").size()

func _instance(c: Dictionary, ps: PackedScene) -> void:
	if ps == null or c["state"] == "in":
		return
	var n := ps.instantiate()
	var g := n.get_node_or_null(^"Growths") as MultiMeshInstance3D
	if g and g.has_meta(&"xforms"):
		var flat: PackedFloat32Array = g.get_meta(&"xforms")
		var mm := g.multimesh.duplicate() as MultiMesh   # per-chunk instance data
		mm.instance_count = flat.size() / 12
		mm.buffer = flat
		g.multimesh = mm
	add_child(n)
	c["node"] = n
	c["state"] = "in"

## Distance from p to the chunk's footprint (0 inside it), ignoring height.
func _flat_dist(c: Dictionary, p: Vector3) -> float:
	var a: AABB = c["aabb"]
	var dx := maxf(maxf(a.position.x - p.x, 0.0), p.x - a.end.x)
	var dz := maxf(maxf(a.position.z - p.z, 0.0), p.z - a.end.z)
	return sqrt(dx * dx + dz * dz)

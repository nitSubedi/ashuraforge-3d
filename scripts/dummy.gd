extends Node3D
## Static training dummy from the SAME Mixamo (X Bot) mesh as the hero, pre-split
## into body-region parts (tools/gen/split_character.py). Doesn't move or attack.
## Each region has HP and is severed (flies off, gory) only when worn down by
## multiple/heavy hits. Respawns whole a few seconds after full dismemberment.

const PART_SCRIPT := preload("res://scripts/dummy_part.gd")
const PARTS_GLB := preload("res://assets/enemies/xbot_parts.glb")

# The Blender->GLB came out ~100x and Z-up; correct it here.
const SRC_SCALE := 0.01
const SRC_ROT := Vector3(90.0, 0.0, 0.0)  # stand upright (head up)

const HP := {"head": 70.0, "torso": 150.0, "hips": 150.0,
	"arm_l": 90.0, "arm_r": 90.0, "leg_l": 110.0, "leg_r": 110.0}

var _alive := 0
var _mat: StandardMaterial3D

func _ready() -> void:
	add_to_group(&"enemies")
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.5, 0.09, 0.10)  # tint red so it reads as the enemy
	_mat.roughness = 0.6
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_alive = 0
	var src := PARTS_GLB.instantiate()
	src.scale = Vector3(SRC_SCALE, SRC_SCALE, SRC_SCALE)
	src.rotation_degrees = SRC_ROT
	add_child(src)
	var meshes: Array = []
	_collect_meshes(src, meshes)
	var min_y := INF
	for mi in meshes:
		min_y = minf(min_y, _wrap_part(mi))
	src.queue_free()
	# Ground-snap: lift all parts so the lowest sits at y=0.
	if min_y != INF:
		for p in get_children():
			p.global_position.y -= min_y

func _collect_meshes(n: Node, arr: Array) -> void:
	if n is MeshInstance3D:
		arr.append(n)
	for c in n.get_children():
		_collect_meshes(c, arr)

# Wraps a mesh in a body with a CLEAN, world-sized collision box (no node scale,
# which physics handles unreliably). Returns the part's world-AABB min Y.
func _wrap_part(mi: MeshInstance3D) -> float:
	var region := str(mi.name)
	var wa := mi.global_transform * mi.get_aabb()  # world-space bounds
	var part := StaticBody3D.new()
	part.set_script(PART_SCRIPT)
	part.name = "part_" + region
	part.collision_layer = 4
	part.collision_mask = 0
	part.add_to_group(&"enemy_part")
	part.hp = HP.get(region, 100.0)
	add_child(part)
	part.global_position = wa.position + wa.size * 0.5  # world centre, identity rot/scale
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(wa.size.x, 0.08), maxf(wa.size.y, 0.08), maxf(wa.size.z, 0.08))
	col.shape = box
	part.add_child(col)
	mi.reparent(part)  # mesh keeps its (scaled/rotated) world transform -> renders right
	mi.name = "Mesh"
	mi.material_override = _mat
	_alive += 1
	return wa.position.y

func on_part_severed() -> void:
	_alive -= 1
	if _alive <= 0:
		await get_tree().create_timer(3.0).timeout
		_build()

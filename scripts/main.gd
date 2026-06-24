extends Node3D
## Slice room orchestrator. Builds a 24x24 dungeon room from KayKit tiles (visuals)
## plus simple invisible static boxes (collision), scatters a few props/torches,
## then starts the round so the Game manager can detect the win condition.
##
## The tiling math here is intentionally reusable: the procedural-dungeon
## sub-project will generalize it to multi-room layouts.

const FLOOR := preload("res://assets/dungeon/floor_tile_large.gltf.glb")
const WALL := preload("res://assets/dungeon/wall.gltf.glb")
const PILLAR := preload("res://assets/dungeon/pillar.gltf.glb")
const TORCH := preload("res://assets/dungeon/torch_lit.gltf.glb")
const BARREL := preload("res://assets/dungeon/barrel_large.gltf.glb")
const CHEST := preload("res://assets/dungeon/chest_gold.glb")

const HALF := 12.0   # room spans -12..12 on X and Z
const TILE := 4.0    # KayKit large floor tile + wall segment length

func _ready() -> void:
	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-55, -35, 0)
	_build_room()
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	Game.start_round(enemies.size())

func _build_room() -> void:
	var room := Node3D.new()
	room.name = "Dungeon"
	add_child(room)

	# Floor tiles (centers at -10,-6,-2,2,6,10 cover -12..12).
	for x in range(-10, 11, int(TILE)):
		for z in range(-10, 11, int(TILE)):
			var t := FLOOR.instantiate()
			t.position = Vector3(x, 0, z)
			room.add_child(t)

	# Visual walls along the four edges.
	for i in range(-10, 11, int(TILE)):
		_wall(room, Vector3(i, 0, -HALF), 0.0)        # north
		_wall(room, Vector3(i, 0, HALF), PI)          # south
		_wall(room, Vector3(-HALF, 0, i), PI / 2.0)   # west
		_wall(room, Vector3(HALF, 0, i), -PI / 2.0)   # east

	# Invisible collision: floor + 4 walls.
	_static_box(room, Vector3(24, 1, 24), Vector3(0, -0.5, 0))
	_static_box(room, Vector3(24, 4, 1), Vector3(0, 2, -HALF))
	_static_box(room, Vector3(24, 4, 1), Vector3(0, 2, HALF))
	_static_box(room, Vector3(1, 4, 24), Vector3(-HALF, 2, 0))
	_static_box(room, Vector3(1, 4, 24), Vector3(HALF, 2, 0))

	# Corner pillars + torches (with warm point lights) for atmosphere.
	for c in [Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(-10, 0, 10), Vector3(10, 0, 10)]:
		var p := PILLAR.instantiate()
		p.position = c
		room.add_child(p)
		var torch := TORCH.instantiate()
		torch.position = c + Vector3(0, 1.4, 0)
		room.add_child(torch)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.25)
		light.light_energy = 4.0
		light.omni_range = 12.0
		light.position = c + Vector3(0, 2.4, 0)
		room.add_child(light)

	# A little loot flavour.
	var chest := CHEST.instantiate()
	chest.position = Vector3(0, 0, -10)
	room.add_child(chest)
	for b in [Vector3(-8, 0, 9), Vector3(8.5, 0, 8)]:
		var barrel := BARREL.instantiate()
		barrel.position = b
		room.add_child(barrel)

func _wall(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var w := WALL.instantiate()
	w.position = pos
	w.rotation.y = yaw
	parent.add_child(w)

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

extends StaticBody3D
## One body part with its own HP. Takes damage from melee hits (one hit per
## swing); when HP runs out it's severed — flies off as a physics gib with a
## gory blood burst. Lighter hits just spray blood and weaken it.

var hp := 100.0
var _severed := false
var _last_attack := -1

func take_damage(amount: float, attack_id: int, impulse: Vector3) -> void:
	if _severed or attack_id == _last_attack:
		return
	_last_attack = attack_id
	hp -= amount
	_flash()
	# blood spurt from the wound, biased along the hit direction
	_blood(global_position, impulse.normalized(), 22, 1.2, 4.0)
	if hp <= 0.0:
		_sever(impulse)

func _flash() -> void:
	var mesh := get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh == null:
		return
	var normal := mesh.material_override
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 1, 1)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.4, 0.4)
	fm.emission_energy_multiplier = 4.0
	mesh.material_override = fm
	var t := Timer.new()
	t.wait_time = 0.09
	t.one_shot = true
	t.autostart = true
	mesh.add_child(t)  # child of mesh: freed together, so no dangling capture
	t.timeout.connect(func(): if is_instance_valid(mesh): mesh.material_override = normal)

func _sever(impulse: Vector3) -> void:
	if _severed:
		return
	_severed = true
	var mesh := get_node_or_null(^"Mesh") as MeshInstance3D
	var pos := mesh.global_position if mesh != null else global_position
	if mesh != null and mesh.mesh != null:
		# RigidBody drops scale from its transform, so BAKE the part's scale into
		# the gib's mesh child + collision (else it renders ~100x and flies away).
		var s := mesh.global_transform.basis.get_scale()
		var gib := RigidBody3D.new()
		gib.collision_layer = 8
		gib.collision_mask = 1
		gib.gravity_scale = 1.6
		gib.mass = 1.0
		var mi := MeshInstance3D.new()
		mi.mesh = mesh.mesh
		mi.scale = s
		mi.material_override = mesh.material_override
		gib.add_child(mi)
		var aabb := mesh.mesh.get_aabb()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(aabb.size.x * s.x, 0.05), maxf(aabb.size.y * s.y, 0.05), maxf(aabb.size.z * s.z, 0.05))
		col.shape = box
		col.position = (aabb.position + aabb.size * 0.5) * s
		gib.add_child(col)
		get_tree().current_scene.add_child(gib)
		gib.global_transform = Transform3D(mesh.global_transform.basis.orthonormalized(), mesh.global_position)
		gib.apply_central_impulse(impulse)
		gib.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		_despawn(gib, 10.0)
	# heavy gore burst on sever
	_blood(pos, impulse.normalized(), 80, 1.6, 7.0)
	var parent := get_parent()
	queue_free()
	if parent != null and parent.has_method(&"on_part_severed"):
		parent.on_part_severed()

func _blood(pos: Vector3, dir: Vector3, amount: int, life: float, speed: float) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.9
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = dir if dir.length() > 0.1 else Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.flatness = 0.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -18.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.015
	pm.scale_max = 0.05
	pm.color = Color(0.32, 0.0, 0.01)  # dark arterial red
	p.process_material = pm

	var drop := SphereMesh.new()
	drop.radius = 0.025
	drop.height = 0.05
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.0, 0.01)
	mat.roughness = 0.3
	mat.metallic = 0.1
	drop.material = mat
	p.draw_pass_1 = drop

	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)  # one-shot: frees itself when done (no dangling capture)

# Self-contained despawn via a child Timer (freed with the node — no dangling lambda).
func _despawn(node: Node, secs: float) -> void:
	var t := Timer.new()
	t.wait_time = secs
	t.one_shot = true
	t.autostart = true
	node.add_child(t)
	t.timeout.connect(node.queue_free)

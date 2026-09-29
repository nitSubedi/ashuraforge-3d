extends SceneTree
var _f := 0
func _initialize() -> void:
	var world := Node3D.new(); get_root().add_child(world)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.1,0.1,0.12)
	e.ambient_light_color = Color(0.7,0.7,0.7); e.ambient_light_energy = 1.0
	env.environment = e; world.add_child(env)
	var en := (load("res://assets/enemies/enemy.tscn") as PackedScene).instantiate()
	world.add_child(en)
	var ap := en.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("ENEMY anims=", ap.get_animation_list() if ap else "none")
	if ap and ap.has_animation("hit"): ap.play("hit"); ap.advance(0.5)
	var l := DirectionalLight3D.new(); world.add_child(l); l.rotation_degrees = Vector3(-50,-35,0)
	var cam := Camera3D.new(); world.add_child(cam); cam.position = Vector3(0,1.0,3.5); cam.look_at(Vector3(0,1.0,0))
func _process(_d): 
	_f += 1
	if _f == 30:
		get_root().get_texture().get_image().save_png("res://assets/generation/out/enemy.png")
		print("ENEMY_SAVED")
		return true
	return false

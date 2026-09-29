extends SceneTree
var _f := 0
var _hero
func _initialize() -> void:
	_hero = (load("res://assets/characters/hero.tscn") as PackedScene).instantiate()
	get_root().add_child(_hero)
func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var box := AABB(); var first := true
	var stack: Array = [_hero]
	while not stack.is_empty():
		var c = stack.pop_back()
		if c is VisualInstance3D:
			var a: AABB = (c as VisualInstance3D).get_aabb()
			a = (c as Node3D).global_transform * a
			if first: box = a; first = false
			else: box = box.merge(a)
		for ch in c.get_children(): stack.push_back(ch)
	print("HERO_HEIGHT=", box.size.y, " AABB=", box)
	return true

extends SceneTree
func _initialize() -> void:
	var inst := (load("res://assets/characters/hero.tscn") as PackedScene).instantiate()
	var sk := _find_skel(inst)
	if sk:
		print("BONE_COUNT ", sk.get_bone_count())
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			if "Hand" in n or "hand" in n:
				print("BONE ", i, " ", n)
	quit()
func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r: return r
	return null

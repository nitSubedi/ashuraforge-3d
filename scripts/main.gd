extends Node3D
## Slice room orchestrator: counts enemies present and starts the round so the
## Game manager can detect the win condition.

func _ready() -> void:
	# Aim the sun downward here rather than encoding a rotation matrix in the scene file.
	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-55, -35, 0)
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	Game.start_round(enemies.size())

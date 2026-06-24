extends Area3D
## Magic projectile (AshuraForge Fire/Magic). Flies straight, damages the first
## enemy or wall it hits, then despawns. Auto-expires after `lifetime`.

@export var speed: float = 18.0
@export var lifetime: float = 3.0

var _velocity: Vector3 = Vector3.ZERO
var _damage: float = 0.0
var _alive: bool = false

func launch(direction: Vector3, damage: float) -> void:
	_velocity = direction.normalized() * speed
	_damage = damage
	_alive = true
	look_at(global_position + direction, Vector3.UP)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_despawn)

func _physics_process(delta: float) -> void:
	if _alive:
		global_position += _velocity * delta

func _on_body_entered(body: Node) -> void:
	if not _alive:
		return
	if body.is_in_group(&"enemies") and body.has_method(&"take_hit"):
		body.take_hit(_damage)
	_despawn()

func _despawn() -> void:
	_alive = false
	queue_free()

extends Node
class_name Health
## Reusable health component. Attach as a child node of any entity.

signal damaged(amount: float, current: float)
signal died

@export var max_health: float = 100.0

var current: float
var _dead: bool = false

func _ready() -> void:
	current = max_health

func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	current = max(0.0, current - amount)
	damaged.emit(amount, current)
	if current <= 0.0:
		_dead = true
		died.emit()

func heal(amount: float) -> void:
	if _dead:
		return
	current = min(max_health, current + amount)

func is_dead() -> bool:
	return _dead

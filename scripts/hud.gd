extends CanvasLayer
## Minimal HUD: HP bar + center message for win/lose, with restart prompt.

@onready var hp_bar: ProgressBar = $HPBar
@onready var message: Label = $Message
@onready var hint: Label = $Hint

func _ready() -> void:
	message.text = ""
	hint.text = ""
	Game.player_health_changed.connect(_on_health_changed)
	Game.game_over.connect(_on_game_over)

func _on_health_changed(current: float, max_health: float) -> void:
	hp_bar.max_value = max_health
	hp_bar.value = current

func _on_game_over(won: bool) -> void:
	message.text = "VICTORY" if won else "YOU DIED"
	message.modulate = Color(0.6, 1, 0.6) if won else Color(1, 0.4, 0.4)
	hint.text = "Press R to restart"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart"):
		Game.restart()

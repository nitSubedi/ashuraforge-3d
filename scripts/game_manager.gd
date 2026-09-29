extends Node
## Global game manager (autoload "Game").
## Registers input actions in code and brokers global signals so HUD / player /
## enemies stay decoupled.

signal player_health_changed(current: float, max_health: float)
signal game_over(won: bool)

var _enemies_alive: int = 0
var _is_over: bool = false

func _ready() -> void:
	_setup_input_map()

func _setup_input_map() -> void:
	_bind_key(&"move_forward", KEY_W)
	_bind_key(&"move_back", KEY_S)
	_bind_key(&"move_left", KEY_A)
	_bind_key(&"move_right", KEY_D)
	_bind_key(&"jump", KEY_SPACE)
	_bind_key(&"sprint", KEY_SHIFT)
	_bind_key(&"dodge", KEY_CTRL)
	_bind_key(&"restart", KEY_R)
	_bind_mouse(&"attack", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"kick", MOUSE_BUTTON_RIGHT)
	_bind_key(&"attack", KEY_J)   # laptop-friendly: J = cane (hand)
	_bind_key(&"kick", KEY_K)     # laptop-friendly: K = kick (foot)
	_bind_key(&"stance", KEY_Q)   # draw / sheathe the cane-sword
	_bind_key(&"ability_1", KEY_1)   # Phantom Blade
	_bind_key(&"ability_2", KEY_2)   # Hellfire Rain
	_bind_key(&"ability_3", KEY_3)   # Wraithwing
	_bind_key(&"cast", KEY_E)  # magic deferred; kept on E for later

func _bind_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

## --- Round lifecycle -------------------------------------------------------

func start_round(enemy_count: int) -> void:
	_enemies_alive = enemy_count
	_is_over = false

func report_enemy_died() -> void:
	if _is_over:
		return
	_enemies_alive = max(0, _enemies_alive - 1)
	if _enemies_alive == 0:
		_is_over = true
		game_over.emit(true)

func report_player_died() -> void:
	if _is_over:
		return
	_is_over = true
	game_over.emit(false)

func restart() -> void:
	get_tree().reload_current_scene()

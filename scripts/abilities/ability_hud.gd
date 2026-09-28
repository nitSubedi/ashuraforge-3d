extends CanvasLayer
## Bottom-centre combat HUD: Blood meter + one slot per signature power
## (key, name, cooldown sweep, dimmed when unaffordable, lit while active).

var system: Node
var _bar: ProgressBar
var _slots: Array = []   # [panel, cooldown_rect, name_label]

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -190
	box.offset_right = 190
	box.offset_top = -118
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for i in system.slots.size():
		var a = system.slots[i]
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(112, 58)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.02, 0.03, 0.82)
		sb.border_color = Color(0.55, 0.06, 0.06)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", sb)
		var cd := ColorRect.new()
		cd.color = Color(0, 0, 0, 0.6)
		cd.anchor_right = 1.0
		cd.anchor_bottom = 1.0
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cd)
		var key := Label.new()
		key.text = str(i + 1)
		key.position = Vector2(8, 4)
		key.add_theme_color_override("font_color", Color(1.0, 0.75, 0.6))
		panel.add_child(key)
		var name_l := Label.new()
		name_l.text = a.display_name
		name_l.position = Vector2(8, 28)
		name_l.add_theme_font_size_override("font_size", 13)
		panel.add_child(name_l)
		var cost_l := Label.new()
		cost_l.text = str(int(a.cost))
		cost_l.position = Vector2(84, 4)
		cost_l.add_theme_font_size_override("font_size", 12)
		cost_l.add_theme_color_override("font_color", Color(0.9, 0.15, 0.12))
		panel.add_child(cost_l)
		row.add_child(panel)
		_slots.append([panel, cd, name_l, sb])

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(380, 14)
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.03, 0.05)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.02, 0.02, 0.85)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_bar)
	system.blood_changed.connect(_on_blood)
	_on_blood(system.blood, system.BLOOD_MAX)

func _on_blood(v: float, m: float) -> void:
	_bar.max_value = m
	_bar.value = v

func _process(_d: float) -> void:
	for i in _slots.size():
		var a = system.slots[i]
		var panel: Panel = _slots[i][0]
		var cd: ColorRect = _slots[i][1]
		var sb: StyleBoxFlat = _slots[i][3]
		var frac: float = a.cooldown_left / a.cooldown if a.cooldown > 0.0 else 0.0
		cd.anchor_top = 1.0 - frac          # sweep drains upward as it recharges
		var ready: bool = a.cooldown_left <= 0.0 and system.blood >= a.cost
		panel.modulate = Color(1, 1, 1, 1) if ready or a.active else Color(0.55, 0.5, 0.5, 1)
		sb.border_color = Color(1.0, 0.35, 0.1) if a.active else (Color(0.85, 0.1, 0.08) if ready else Color(0.35, 0.05, 0.05))

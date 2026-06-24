extends SceneTree
## Boots the main scene in a real window, lets it render, then saves a PNG and
## quits. Run (NOT headless): godot --path . -s res://tools/screenshot.gd

var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 120:
		var img := root.get_texture().get_image()
		img.save_png("res://screenshot.png")
		print("SCREENSHOT_SAVED")
		return true
	return false

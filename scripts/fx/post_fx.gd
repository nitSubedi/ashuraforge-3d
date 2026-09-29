extends CanvasLayer
## Screen-space finishing pass: vignette + film grain always; chromatic
## aberration and a flash pulse on impacts (decay back to zero).
## Usage: PostFX.get_instance(tree).pulse(0.6)  /  .flash(Color.WHITE, 0.3)

const SHADER := preload("res://assets/shaders/post_fx.gdshader")

var _mat: ShaderMaterial
var _aberration := 0.0
var _flash := Color(0, 0, 0, 0)

static func get_instance(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group(&"post_fx")

func _ready() -> void:
	add_to_group(&"post_fx")
	layer = 50   # above the 3D world, below the HUD (100)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	rect.material = _mat
	add_child(rect)

## Chromatic-aberration kick (0..1), e.g. 0.35 on a hit, 0.8 on a finisher.
func pulse(amount: float) -> void:
	_aberration = maxf(_aberration, amount)

## Brief screen flash.
func flash(color: Color, strength: float) -> void:
	_flash = Color(color.r, color.g, color.b, maxf(_flash.a, strength))

func _process(delta: float) -> void:
	_aberration = move_toward(_aberration, 0.0, delta * 3.5)
	_flash.a = move_toward(_flash.a, 0.0, delta * 5.0)
	_mat.set_shader_parameter("aberration", _aberration)
	_mat.set_shader_parameter("flash", Vector4(_flash.r, _flash.g, _flash.b, _flash.a))
	_mat.set_shader_parameter("time_seed", fmod(Time.get_ticks_msec() * 0.001, 100.0))

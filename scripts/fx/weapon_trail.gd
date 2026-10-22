extends MeshInstance3D
## Swing trail: a ribbon between two tracked points (weapon base -> tip, or
## knee -> toe) over the last few frames, bright at the weapon and fading
## behind. Set `emitting` during a move's strike window; the tail fades out on
## its own after it stops.

@export var length := 10            # samples kept (~0.08 s at 120 fps)
@export var color := Color(0.85, 0.88, 1.0)
@export var intensity := 0.7

var base: Node3D
var tip: Node3D
var emitting := false
var _samples: Array = []

func _ready() -> void:
	top_level = true
	mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_d: float) -> void:
	if base == null or tip == null or not is_instance_valid(base) or not is_instance_valid(tip):
		return
	if emitting:
		_samples.push_front([base.global_position, tip.global_position])
		if _samples.size() > length:
			_samples.pop_back()
	elif not _samples.is_empty():
		_samples.pop_back()      # let the tail shrink away
	var im := mesh as ImmediateMesh
	im.clear_surfaces()
	if _samples.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _samples.size()
	for i in n:
		var a := 1.0 - float(i) / float(n - 1)
		a *= a
		im.surface_set_color(Color(color.r, color.g, color.b, 0.25 * a * intensity))
		im.surface_add_vertex(_samples[i][0])
		im.surface_set_color(Color(color.r, color.g, color.b, a * intensity))
		im.surface_add_vertex(_samples[i][1])
	im.surface_end()

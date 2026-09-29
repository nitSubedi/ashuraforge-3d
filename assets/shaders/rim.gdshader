shader_type spatial;
// Character rim light (material_overlay): a thin additive fresnel edge so the
// hero and demons separate from the red world at a glance.
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec3 rim_color : source_color = vec3(1.0, 0.72, 0.55);
uniform float power = 3.5;      // higher = thinner edge
uniform float strength = 0.35;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = rim_color * f * strength;
	ALPHA = f;
}

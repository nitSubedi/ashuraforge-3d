shader_type canvas_item;
// Full-screen finishing pass (drawn under the HUD): vignette, fine film grain,
// and impact-driven chromatic aberration + flash. Drives are set from
// scripts/fx/post_fx.gd.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.38;        // edge darkening strength
uniform float grain = 0.035;          // film grain amount
uniform float aberration = 0.0;       // 0..1 impact pulse (RGB split toward edges)
uniform vec4 flash = vec4(0.0);       // rgb + strength
uniform float time_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + time_seed) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	// Chromatic aberration grows toward the screen edges.
	vec2 off = c * aberration * 0.018 * (0.4 + r2 * 2.0);
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;
	// Impact flash (additive tint that fades quickly).
	col += flash.rgb * flash.a;
	// Vignette: smooth, slightly oval.
	float v = smoothstep(0.85, 0.2, length(c * vec2(1.0, 1.15)) * 1.25);
	col *= mix(1.0 - vignette, 1.0, v);
	// Grain: luminance-weighted so shadows stay clean-ish.
	float n = hash(uv * vec2(1920.0, 1080.0)) - 0.5;
	col += n * grain * (0.35 + dot(col, vec3(0.3, 0.6, 0.1)));
	COLOR = vec4(col, 1.0);
}

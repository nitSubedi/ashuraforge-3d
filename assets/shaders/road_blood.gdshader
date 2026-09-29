shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Detailed wet-asphalt street with blood. Read as an actual road surface up
// close (grain, cracks, tar patches, gravel, faded lane paint) and as bloody
// streets in the gaps between building blocks. World-space so it's continuous.

uniform vec3 asphalt : source_color = vec3(0.075, 0.072, 0.078);
uniform vec3 asphalt_dark : source_color = vec3(0.035, 0.034, 0.038);
uniform vec3 asphalt_patch : source_color = vec3(0.10, 0.095, 0.10);
uniform vec3 blood : source_color = vec3(0.24, 0.014, 0.014);
uniform vec3 blood_bright : source_color = vec3(0.55, 0.03, 0.02);
uniform vec3 paint : source_color = vec3(0.35, 0.30, 0.12);   // faded yellow lane paint
uniform float macro_scale = 0.02;    // puddles / big patches
uniform float detail_scale = 0.6;    // asphalt grain
uniform float puddle_amount = 0.5;
uniform float glow = 0.28;
uniform float lane_span = 26.0;      // world units between lane markings
uniform float paint_amount = 0.35;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			   mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.02 + 7.1;
		a *= 0.5;
	}
	return s;
}

// Ridged noise -> crack network.
float cracks(vec2 p) {
	float n = fbm(p);
	float r = 1.0 - abs(n * 2.0 - 1.0);
	return pow(clamp(r, 0.0, 1.0), 12.0);
}

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = v_world.xz;

	// --- Asphalt base: grain + tar patches + gravel speckle ---
	float grain = vnoise(w * detail_scale);
	float patch = fbm(w * macro_scale * 2.3);
	vec3 base = mix(asphalt_dark, asphalt, grain);
	base = mix(base, asphalt_patch, smoothstep(0.55, 0.8, patch) * 0.7);
	float gravel = hash(floor(w * 6.0));           // tiny aggregate specks
	base += (gravel - 0.5) * 0.03;

	// Cracks darken the surface.
	float crack = cracks(w * 0.25);
	base = mix(base, asphalt_dark * 0.5, crack * 0.8);

	// --- Faded lane paint (only shows in the street gaps; hidden under buildings) ---
	float lane = smoothstep(0.46, 0.48, abs(fract(w.x / lane_span) - 0.5)) *
				 step(0.5, fract(w.x / lane_span + 0.5));
	float dash = step(0.5, fract(w.y / 10.0));      // dashed center line
	lane *= dash * (0.5 + 0.5 * grain);
	base = mix(base, paint, lane * paint_amount);

	// --- Blood: puddles pool in the macro lows, plus finer splatter ---
	float macro = fbm(w * macro_scale);
	float puddle = smoothstep(0.60 - puddle_amount * 0.22, 0.66, macro);
	float splat = smoothstep(0.72, 0.82, vnoise(w * 0.12 + 3.0)) * 0.6;
	float bloodmask = clamp(puddle + splat, 0.0, 1.0);

	vec3 col = mix(base, blood, bloodmask);
	// Bright wet rim where a puddle meets dry asphalt.
	float rim = smoothstep(0.60, 0.66, macro) - smoothstep(0.66, 0.72, macro);
	col = mix(col, blood_bright, clamp(rim, 0.0, 1.0) * 0.5);

	ALBEDO = col;
	// Puddles are glossy/reflective; dry cracked asphalt is rough.
	ROUGHNESS = mix(mix(0.9, 0.75, grain), 0.08, puddle);
	SPECULAR = mix(0.35, 1.0, puddle);
	METALLIC = 0.0;
	EMISSION = blood_bright * puddle * glow;
}

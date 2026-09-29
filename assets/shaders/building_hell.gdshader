shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Corrupted-city building facade: weathered concrete with a grid of windows
// (dark / hellishly-lit / broken) and blood streaks running down the walls, so
// map3d's plain extruded boxes read as real skyscrapers with hell on top.
// Works in OBJECT-LOCAL space so the window grid is per-building. In the source
// mesh, local +Z is the building's up axis (footprint is local X/Y).

uniform vec3 wall_color : source_color = vec3(0.11, 0.10, 0.11);
uniform vec3 wall_color2 : source_color = vec3(0.16, 0.14, 0.13);
uniform vec3 window_dark : source_color = vec3(0.015, 0.015, 0.02);
uniform vec3 window_lit : source_color = vec3(1.0, 0.32, 0.08);   // hellish interior glow
uniform vec3 blood_color : source_color = vec3(0.30, 0.02, 0.02);
uniform float floor_height = 3.5;    // local units per storey
uniform float window_span = 4.0;     // local units per window column
uniform float lit_ratio = 0.30;      // fraction of windows glowing
uniform float window_energy = 2.2;
uniform float blood_amount = 0.6;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1, 0));
	float c = h21(i + vec2(0, 1));
	float d = h21(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

varying vec3 v_local;
varying vec3 v_lnormal;

void vertex() {
	v_local = VERTEX;
	v_lnormal = NORMAL;
}

void fragment() {
	vec3 an = abs(normalize(v_lnormal));
	float height = v_local.z;                 // local up axis

	if (an.z > 0.6) {
		// Roof: dark tar with blood pooling, no windows.
		float pool = smoothstep(0.5, 0.75, vnoise(v_local.xy * 0.25));
		ALBEDO = mix(wall_color * 0.5, blood_color, pool * 0.7);
		ROUGHNESS = mix(0.92, 0.25, pool);
		SPECULAR = mix(0.2, 0.8, pool);
		METALLIC = 0.0;
		EMISSION = vec3(0.0);
	} else {
		// Wall: pick the in-plane horizontal axis by the dominant normal.
		float hcoord = (an.x > an.y) ? v_local.y : v_local.x;
		vec2 cell = vec2(floor(hcoord / window_span), floor(height / floor_height));
		float fx = fract(hcoord / window_span);
		float fy = fract(height / floor_height);

		// Window rectangle inside the cell (rest is mullion/concrete).
		float win = step(0.14, fx) * step(fx, 0.86) * step(0.22, fy) * step(fy, 0.82);

		float r = h21(cell);
		float lit = step(1.0 - lit_ratio, r);          // some windows glow
		float broken = step(0.94, h21(cell + 7.3));    // a few blown-out dark holes
		vec3 wcol = mix(window_dark, window_lit, lit);
		wcol = mix(wcol, vec3(0.0), broken);

		// Concrete with grime variation.
		float grime = vnoise(vec2(hcoord * 0.15, height * 0.15));
		vec3 concrete = mix(wall_color, wall_color2, grime);

		// Blood streaks weeping down from random columns.
		float col_seed = h21(vec2(cell.x, 3.1));
		float streak = smoothstep(0.55, 1.0, col_seed) *
			smoothstep(0.0, 0.4, vnoise(vec2(hcoord * 0.4, height * 0.03)));
		streak *= clamp(1.0 - fy * 0.15, 0.0, 1.0);
		concrete = mix(concrete, blood_color, streak * blood_amount);

		ALBEDO = mix(concrete, wcol, win);
		EMISSION = window_lit * win * lit * (1.0 - broken) * window_energy;
		ROUGHNESS = mix(0.85, 0.25, win);
		SPECULAR = 0.4;
		METALLIC = 0.0;
	}
}

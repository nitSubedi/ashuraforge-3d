shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Procedural flesh / sinew surface: ridged-noise veins, a slow breathing
// emissive pulse, wet specular, and normal perturbation so it reads as living
// tissue without any textures.

uniform vec3 base_color : source_color = vec3(0.28, 0.03, 0.035);
uniform vec3 vein_color : source_color = vec3(0.80, 0.09, 0.10);
uniform vec3 emission_color : source_color = vec3(0.9, 0.06, 0.04);
uniform float emission_energy = 0.55;
uniform float pulse_speed = 1.0;
uniform float vein_scale = 0.22;
uniform float displace = 0.0;
uniform float wetness = 0.8;
uniform float bump = 0.6;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
				   mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
				   mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

float veins_at(vec3 p) {
	float ridged = 1.0 - abs(fbm(p * 1.7) * 2.0 - 1.0);
	return pow(clamp(ridged, 0.0, 1.0), 3.0);
}

varying vec3 v_world;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (displace > 0.001) {
		VERTEX.y += (fbm(wp * vein_scale * 0.5) - 0.5) * displace;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = v_world * vein_scale;
	float n = fbm(p);
	float veins = veins_at(p);

	float pulse = 0.55 + 0.45 * sin(TIME * pulse_speed + n * 6.2831);

	ALBEDO = mix(base_color, vein_color, veins * 0.85) * (0.55 + 0.45 * n);
	ROUGHNESS = mix(0.85, 0.18, wetness * veins);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	EMISSION = emission_color * veins * pulse * emission_energy;

	// Normal perturbation from the vein height field (world space -> view space).
	float e = 0.15;
	float hl = veins_at((v_world - vec3(e, 0, 0)) * vein_scale);
	float hr = veins_at((v_world + vec3(e, 0, 0)) * vein_scale);
	float hd = veins_at((v_world - vec3(0, 0, e)) * vein_scale);
	float hu = veins_at((v_world + vec3(0, 0, e)) * vein_scale);
	vec3 wn = normalize(vec3((hl - hr) * bump, 1.0, (hd - hu) * bump));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

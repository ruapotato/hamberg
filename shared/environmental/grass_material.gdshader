shader_type spatial;
render_mode cull_disabled, shadows_disabled;

// Wind parameters
uniform float wind_strength : hint_range(0.0, 0.5) = 0.08;
uniform float wind_speed : hint_range(0.0, 5.0) = 2.0;

// Color parameters
uniform vec3 base_color : source_color = vec3(0.15, 0.38, 0.1);
uniform vec3 tip_color : source_color = vec3(0.35, 0.6, 0.12);

// Simple hash for per-instance variation
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// Get instance world position from model matrix
	vec3 instance_pos = MODEL_MATRIX[3].xyz;

	// Per-instance color variation
	float variation = hash(floor(instance_pos.xz * 10.0)) * 0.3 - 0.15;

	// Wind displacement - only affects top of blade
	float wind_factor = pow(UV.y, 2.0);
	float wind_phase = TIME * wind_speed + instance_pos.x * 0.7 + instance_pos.z * 0.5;
	float wind = sin(wind_phase) * wind_strength * wind_factor;
	float wind2 = sin(wind_phase * 0.7 + 1.3) * wind_strength * 0.5 * wind_factor;

	VERTEX.x += wind;
	VERTEX.z += wind2;

	// Pass variation to fragment via COLOR
	COLOR.r = variation;
}

void fragment() {
	// Blade shape: taper toward tip using UV
	float blade_width = 1.0 - UV.y; // wider at base, narrow at tip
	float blade_mask = step(abs(UV.x - 0.5) * 2.0, blade_width);

	// Alpha cutout for blade shape
	if (blade_mask < 0.5) {
		discard;
	}

	// Color gradient from base to tip with per-instance variation
	float variation = COLOR.r;
	vec3 color = mix(base_color, tip_color, UV.y);
	color += variation;

	// Slight darkening at base for depth
	color *= mix(0.7, 1.0, UV.y);

	ALBEDO = color;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}

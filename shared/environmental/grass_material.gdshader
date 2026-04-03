shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_disabled;

// Wind parameters
uniform float wind_strength : hint_range(0.0, 0.5) = 0.06;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.5;

// Color parameters
uniform vec3 base_color : source_color = vec3(0.15, 0.38, 0.1);
uniform vec3 tip_color : source_color = vec3(0.4, 0.62, 0.15);

void vertex() {
	// Get instance world position for per-clump variation
	vec3 instance_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Wind - only bends the top of the blade (UV.y = 1 at tip)
	float wind_factor = UV.y * UV.y;
	float phase = TIME * wind_speed + instance_pos.x * 0.7 + instance_pos.z * 0.5;
	VERTEX.x += sin(phase) * wind_strength * wind_factor;
	VERTEX.z += sin(phase * 0.7 + 1.3) * wind_strength * 0.3 * wind_factor;

	// Per-instance color variation via COLOR
	float hash = fract(sin(dot(instance_pos.xz, vec2(127.1, 311.7))) * 43758.5);
	COLOR.r = hash;
}

void fragment() {
	float variation = COLOR.r * 0.2 - 0.1;
	vec3 color = mix(base_color, tip_color, UV.y) + variation;
	color *= mix(0.75, 1.0, UV.y);  // Darker at base

	ALBEDO = color;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	NORMAL = vec3(0.0, 1.0, 0.0);  // Force normals up for natural lighting
}

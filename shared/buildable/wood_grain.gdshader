shader_type spatial;

// Wood grain procedural shader
uniform vec3 wood_color_light : source_color = vec3(0.65, 0.45, 0.25);
uniform vec3 wood_color_dark : source_color = vec3(0.35, 0.22, 0.12);
uniform float grain_scale : hint_range(1.0, 50.0) = 12.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float ring_scale : hint_range(0.5, 10.0) = 3.0;
uniform float noise_scale : hint_range(1.0, 20.0) = 8.0;

// Simple noise functions
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	// Use world position for triplanar-like consistency
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Primary grain direction along Y axis (vertical planks)
	vec2 grain_uv = world_pos.xz * grain_scale;

	// Add noise distortion for natural look
	float distortion = fbm(grain_uv * 0.3) * 2.0;

	// Wood grain rings - elongated along the plank direction
	float grain_y = world_pos.y * ring_scale + distortion;
	float rings = sin(grain_y * 6.28318) * 0.5 + 0.5;
	rings = pow(rings, 2.0); // Sharpen the rings

	// Fine grain detail
	float fine_grain = fbm(vec2(world_pos.y * grain_scale * 2.0, world_pos.x * noise_scale));

	// Combine for final grain pattern
	float grain = mix(rings, fine_grain, 0.4) * grain_strength;

	// Add some random variation for natural wood
	float variation = fbm(world_pos.xz * 2.0) * 0.15;

	// Final color
	vec3 color = mix(wood_color_dark, wood_color_light, grain + variation);

	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}

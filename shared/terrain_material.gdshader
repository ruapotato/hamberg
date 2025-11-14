shader_type spatial;

// Biome colors
const vec3 VALLEY_COLOR = vec3(0.4, 0.7, 0.3);      // Bright green
const vec3 FOREST_COLOR = vec3(0.2, 0.5, 0.2);      // Dark green
const vec3 SWAMP_COLOR = vec3(0.3, 0.4, 0.3);       // Murky green-brown
const vec3 MOUNTAIN_COLOR = vec3(0.6, 0.6, 0.65);   // Gray rock
const vec3 DESERT_COLOR = vec3(0.8, 0.7, 0.4);      // Sandy yellow
const vec3 WIZARDLAND_COLOR = vec3(0.6, 0.4, 0.8);  // Purple/magical
const vec3 HELL_COLOR = vec3(0.7, 0.2, 0.1);        // Red/lava

// Distance thresholds (match BiomeGenerator)
const float VALLEY_RADIUS = 500.0;
const float FOREST_RADIUS = 1000.0;
const float SWAMP_RADIUS = 1500.0;
const float MOUNTAIN_RADIUS = 2000.0;
const float DESERT_RADIUS = 2500.0;
const float WIZARDLAND_RADIUS = 3000.0;

varying vec3 world_pos;

vec3 get_biome_color(float distance) {
	if (distance < VALLEY_RADIUS) {
		return VALLEY_COLOR;
	} else if (distance < FOREST_RADIUS) {
		// Blend between valley and forest
		float t = (distance - VALLEY_RADIUS) / (FOREST_RADIUS - VALLEY_RADIUS);
		return mix(VALLEY_COLOR, FOREST_COLOR, smoothstep(0.0, 1.0, t));
	} else if (distance < SWAMP_RADIUS) {
		float t = (distance - FOREST_RADIUS) / (SWAMP_RADIUS - FOREST_RADIUS);
		return mix(FOREST_COLOR, SWAMP_COLOR, smoothstep(0.0, 1.0, t));
	} else if (distance < MOUNTAIN_RADIUS) {
		float t = (distance - SWAMP_RADIUS) / (MOUNTAIN_RADIUS - SWAMP_RADIUS);
		return mix(SWAMP_COLOR, MOUNTAIN_COLOR, smoothstep(0.0, 1.0, t));
	} else if (distance < DESERT_RADIUS) {
		float t = (distance - MOUNTAIN_RADIUS) / (DESERT_RADIUS - MOUNTAIN_RADIUS);
		return mix(MOUNTAIN_COLOR, DESERT_COLOR, smoothstep(0.0, 1.0, t));
	} else if (distance < WIZARDLAND_RADIUS) {
		float t = (distance - DESERT_RADIUS) / (WIZARDLAND_RADIUS - DESERT_RADIUS);
		return mix(DESERT_COLOR, WIZARDLAND_COLOR, smoothstep(0.0, 1.0, t));
	} else {
		float t = min((distance - WIZARDLAND_RADIUS) / 500.0, 1.0);
		return mix(WIZARDLAND_COLOR, HELL_COLOR, smoothstep(0.0, 1.0, t));
	}
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Calculate distance from origin (XZ plane)
	float distance = length(world_pos.xz);

	// Get base color from biome
	vec3 base_color = get_biome_color(distance);

	// Add height-based shading
	float height_factor = clamp(world_pos.y / 50.0, 0.0, 1.0);

	// Darken low areas, brighten high areas slightly
	base_color *= mix(0.7, 1.2, height_factor);

	// Simple lighting based on normal
	float lighting = dot(NORMAL, vec3(0.4, 0.8, 0.3)) * 0.5 + 0.5;
	vec3 final_color = base_color * mix(0.6, 1.0, lighting);

	ALBEDO = final_color;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}

shader_type spatial;

// Terrain Material - Per-Biome Colors
// Replicates BiomeGenerator noise logic to assign colors based on biome

uniform int world_seed = 42;

// Biome colors
const vec3 VALLEY_COLOR = vec3(0.4, 0.7, 0.3);      // Bright green
const vec3 FOREST_COLOR = vec3(0.2, 0.5, 0.2);      // Dark green
const vec3 SWAMP_COLOR = vec3(0.3, 0.4, 0.3);       // Murky green-brown
const vec3 MOUNTAIN_COLOR = vec3(0.6, 0.6, 0.65);   // Gray rock
const vec3 DESERT_COLOR = vec3(0.8, 0.7, 0.4);      // Sandy yellow
const vec3 WIZARDLAND_COLOR = vec3(0.6, 0.4, 0.8);  // Purple/magical
const vec3 HELL_COLOR = vec3(0.7, 0.2, 0.1);        // Red/lava

// Biome difficulty zones (match BiomeGenerator constants)
const float SAFE_ZONE_RADIUS = 800.0;
const float MID_ZONE_RADIUS = 2000.0;
const float DANGER_ZONE_RADIUS = 4000.0;

varying vec3 world_pos;

// ============================================================================
// NOISE FUNCTIONS - Match FastNoiseLite behavior
// ============================================================================

// Hash function for pseudo-random values
float hash(vec2 p, int seed) {
	vec2 ps = p + vec2(float(seed) * 0.1);
	return fract(sin(dot(ps, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D Perlin-like noise
float noise2d(vec2 p, int seed) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	// Smooth interpolation (quintic for better quality)
	vec2 u = f * f * (3.0 - 2.0 * f);

	// Get corner values
	float a = hash(i, seed);
	float b = hash(i + vec2(1.0, 0.0), seed);
	float c = hash(i + vec2(0.0, 1.0), seed);
	float d = hash(i + vec2(1.0, 1.0), seed);

	// Bilinear interpolation
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

// Fractal Brownian Motion (FBM) - generates multi-octave noise
float fbm(vec2 p, int seed, float frequency, int octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amplitude = 1.0;
	float total_amplitude = 0.0;

	vec2 pos = p * frequency;

	for (int i = 0; i < 8; i++) {
		if (i >= octaves) break;

		value += noise2d(pos, seed + i) * amplitude;
		total_amplitude += amplitude;

		pos *= lacunarity;
		amplitude *= gain;
	}

	return value / total_amplitude;
}

// ============================================================================
// BIOME SELECTION - Replicates BiomeGenerator._get_biome_at_position()
// ============================================================================

int get_biome_index(vec2 xz_pos) {
	// Calculate distance from origin
	float distance = length(xz_pos);

	// Domain warping for organic distortion (Valheim-style)
	float warp_strength = 800.0;
	float warp_x = fbm(xz_pos, world_seed + 200, 0.0005, 2, 2.0, 0.5) * warp_strength;
	float warp_z = fbm(xz_pos, world_seed + 201, 0.0005, 2, 2.0, 0.5) * warp_strength;

	vec2 warped_pos = xz_pos + vec2(warp_x, warp_z);

	// Sample biome noise at warped position
	float biome_value = fbm(warped_pos, world_seed + 100, 0.0008, 3, 2.0, 0.5);

	// Sample scale noise to vary biome patch sizes
	float scale_value = fbm(xz_pos, world_seed + 300, 0.001, 2, 2.0, 0.5);

	// Combine biome noise with scale for more variation
	float combined_value = biome_value + (scale_value * 0.3);

	// Normalize to 0-1 range
	float normalized = (combined_value + 1.0) * 0.5;

	// Determine difficulty tier based on distance
	int difficulty_tier = 0;
	if (distance < SAFE_ZONE_RADIUS) {
		difficulty_tier = 0;  // Safe biomes only (valley, forest)
	} else if (distance < MID_ZONE_RADIUS) {
		difficulty_tier = 1;  // Mid-game biomes
	} else if (distance < DANGER_ZONE_RADIUS) {
		difficulty_tier = 2;  // Dangerous biomes
	} else {
		difficulty_tier = 3;  // Mostly hell
	}

	// Select biome based on noise value and difficulty tier
	// Returns: 0=valley, 1=forest, 2=swamp, 3=mountain, 4=desert, 5=wizardland, 6=hell
	if (difficulty_tier == 0) {  // Safe zone
		if (normalized < 0.5) {
			return 0;  // valley
		} else {
			return 1;  // forest
		}
	} else if (difficulty_tier == 1) {  // Mid zone
		if (normalized < 0.25) {
			return 0;  // valley
		} else if (normalized < 0.5) {
			return 1;  // forest
		} else if (normalized < 0.75) {
			return 2;  // swamp
		} else {
			return 4;  // desert
		}
	} else if (difficulty_tier == 2) {  // Danger zone
		if (normalized < 0.15) {
			return 1;  // forest
		} else if (normalized < 0.3) {
			return 2;  // swamp
		} else if (normalized < 0.5) {
			return 4;  // desert
		} else if (normalized < 0.7) {
			return 3;  // mountain
		} else if (normalized < 0.85) {
			return 5;  // wizardland
		} else {
			return 6;  // hell
		}
	} else {  // Far zone
		if (normalized < 0.2) {
			return 3;  // mountain
		} else if (normalized < 0.3) {
			return 5;  // wizardland
		} else {
			return 6;  // hell
		}
	}

	return 0;  // Fallback to valley
}

vec3 get_biome_color(int biome_index) {
	if (biome_index == 0) return VALLEY_COLOR;
	else if (biome_index == 1) return FOREST_COLOR;
	else if (biome_index == 2) return SWAMP_COLOR;
	else if (biome_index == 3) return MOUNTAIN_COLOR;
	else if (biome_index == 4) return DESERT_COLOR;
	else if (biome_index == 5) return WIZARDLAND_COLOR;
	else if (biome_index == 6) return HELL_COLOR;
	return VALLEY_COLOR;  // Fallback
}

// ============================================================================
// VERTEX AND FRAGMENT SHADERS
// ============================================================================

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Get biome at this position
	vec2 xz_pos = world_pos.xz;
	int biome = get_biome_index(xz_pos);
	vec3 base_color = get_biome_color(biome);

	// Add subtle height-based variation
	float height_factor = clamp(world_pos.y / 50.0, 0.0, 1.0);
	vec3 color = mix(base_color * 0.8, base_color * 1.2, height_factor);

	// Simple directional lighting
	vec3 light_dir = normalize(vec3(0.5, 1.0, 0.3));
	float ndotl = max(dot(NORMAL, light_dir), 0.0);
	float ambient = 0.4;
	float lighting = ambient + (1.0 - ambient) * ndotl;

	ALBEDO = color * lighting;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}

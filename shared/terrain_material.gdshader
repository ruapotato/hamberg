shader_type spatial;

// Terrain Material - Per-Biome Colors
// Replicates BiomeGenerator noise logic to assign colors based on biome

uniform int world_seed = 42;

// Biome grass colors (flat/low slope terrain) - EXTREMELY distinct for visibility
const vec3 VALLEY_GRASS = vec3(0.2, 0.5, 1.0);      // BRIGHT BLUE (serene valley)
const vec3 FOREST_GRASS = vec3(0.1, 0.9, 0.1);      // BRIGHT GREEN (lush forest)
const vec3 SWAMP_GRASS = vec3(0.5, 0.6, 0.2);       // YELLOW-GREEN (murky swamp)
const vec3 MOUNTAIN_GRASS = vec3(0.8, 0.8, 0.8);    // WHITE (snow/ice)
const vec3 DESERT_GRASS = vec3(1.0, 0.9, 0.3);      // BRIGHT YELLOW (sandy desert)
const vec3 WIZARDLAND_GRASS = vec3(0.9, 0.2, 1.0);  // BRIGHT MAGENTA (magical)
const vec3 HELL_GRASS = vec3(0.9, 0.1, 0.0);        // BRIGHT RED (hellfire)

// Biome rock colors (steep/high slope terrain)
const vec3 VALLEY_ROCK = vec3(0.5, 0.5, 0.5);       // Gray stone
const vec3 FOREST_ROCK = vec3(0.4, 0.45, 0.4);      // Dark gray-green
const vec3 SWAMP_ROCK = vec3(0.35, 0.3, 0.3);       // Dark muddy stone
const vec3 MOUNTAIN_ROCK = vec3(0.6, 0.6, 0.65);    // Light gray rock
const vec3 DESERT_ROCK = vec3(0.65, 0.55, 0.45);    // Sandy stone
const vec3 WIZARDLAND_ROCK = vec3(0.5, 0.35, 0.6);  // Purple crystal
const vec3 HELL_ROCK = vec3(0.3, 0.1, 0.05);        // Dark obsidian

// Biome difficulty zones (match BiomeGenerator constants)
const float SAFE_ZONE_RADIUS = 5000.0;
const float MID_ZONE_RADIUS = 10000.0;
const float DANGER_ZONE_RADIUS = 15000.0;
const float EXTREME_ZONE_RADIUS = 20000.0;

varying vec3 world_pos;
varying vec3 world_normal;

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

vec3 get_biome_grass_color(int biome_index) {
	if (biome_index == 0) return VALLEY_GRASS;
	else if (biome_index == 1) return FOREST_GRASS;
	else if (biome_index == 2) return SWAMP_GRASS;
	else if (biome_index == 3) return MOUNTAIN_GRASS;
	else if (biome_index == 4) return DESERT_GRASS;
	else if (biome_index == 5) return WIZARDLAND_GRASS;
	else if (biome_index == 6) return HELL_GRASS;
	return VALLEY_GRASS;  // Fallback
}

vec3 get_biome_rock_color(int biome_index) {
	if (biome_index == 0) return VALLEY_ROCK;
	else if (biome_index == 1) return FOREST_ROCK;
	else if (biome_index == 2) return SWAMP_ROCK;
	else if (biome_index == 3) return MOUNTAIN_ROCK;
	else if (biome_index == 4) return DESERT_ROCK;
	else if (biome_index == 5) return WIZARDLAND_ROCK;
	else if (biome_index == 6) return HELL_ROCK;
	return VALLEY_ROCK;  // Fallback
}

// ============================================================================
// VERTEX AND FRAGMENT SHADERS
// ============================================================================

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Transform normal to world space using inverse transpose for correct orientation
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	// Get biome at this position
	vec2 xz_pos = world_pos.xz;

	// DEBUG: Test if distance-based coloring works at all
	float distance = length(xz_pos);
	vec3 test_color;
	if (distance < 100.0) {
		test_color = vec3(1.0, 0.0, 0.0);  // RED near spawn
	} else if (distance < 500.0) {
		test_color = vec3(0.0, 1.0, 0.0);  // GREEN mid-range
	} else {
		test_color = vec3(0.0, 0.0, 1.0);  // BLUE far away
	}

	ALBEDO = test_color;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;

	// ORIGINAL CODE - commented out for testing
	//int biome = get_biome_index(xz_pos);
	//vec3 grass_color = get_biome_grass_color(biome);
	//vec3 rock_color = get_biome_rock_color(biome);

	// Calculate slope based on how vertical the surface is (in world space)
	// world_normal.y is 1.0 for perfectly flat ground (pointing straight up)
	// world_normal.y is 0.0 for vertical walls (pointing sideways)
	// We want: flat (world_normal.y near 1.0) = grass, steep (world_normal.y near 0.0) = rock
	//float flatness = world_normal.y;  // 1.0 = flat, 0.0 = vertical

	// Blend between grass and rock based on slope
	// At 45 degrees (max walkable), normal.y = cos(45°) ≈ 0.707
	// flatness > 0.85 = flat, mostly grass
	// flatness < 0.70 = steep/walkable limit, mostly rock
	// Smooth transition between 0.70 and 0.85 (shows more rock on moderate slopes)
	//float rock_blend = 1.0 - smoothstep(0.70, 0.85, flatness);
	//vec3 base_color = mix(grass_color, rock_color, rock_blend);

	// Minimal height variation to preserve biome colors
	//vec3 color = base_color;

	// Simple directional lighting (use world-space normal)
	//vec3 light_dir = normalize(vec3(0.5, 1.0, 0.3));
	//float ndotl = max(dot(world_normal, light_dir), 0.0);
	//float ambient = 0.6;  // Higher ambient so colors show through
	//float lighting = ambient + (1.0 - ambient) * ndotl;

	//ALBEDO = color * lighting;

	// Rocky areas are slightly rougher
	//ROUGHNESS = mix(0.85, 0.95, rock_blend);
	//METALLIC = 0.0;
}

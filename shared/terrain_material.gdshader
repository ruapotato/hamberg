shader_type spatial;

// Terrain Material - Per-Biome Colors
// Uses biome map texture generated from BiomeGenerator for perfect accuracy

uniform int world_seed = 42;
uniform sampler2D biome_map : filter_linear;  // Texture containing biome colors
uniform float biome_map_world_coverage = 40000.0;  // How many meters the texture covers
uniform bool debug_biome_colors = false;  // Set to true to directly show biome texture

// Biome grass colors (flat/low slope terrain) - Fantasy bright colors, high saturation
const vec3 VALLEY_GRASS = vec3(0.25, 0.55, 0.95);   // BRIGHT BLUE (serene meadows)
const vec3 FOREST_GRASS = vec3(0.15, 0.85, 0.2);    // BRIGHT GREEN (lush forest)
const vec3 SWAMP_GRASS = vec3(0.6, 0.75, 0.3);      // YELLOW-GREEN (murky swamp)
const vec3 MOUNTAIN_GRASS = vec3(0.95, 0.97, 1.0);  // WHITE (snow/ice)
const vec3 DESERT_GRASS = vec3(0.95, 0.85, 0.35);   // BRIGHT YELLOW (sandy desert)
const vec3 WIZARDLAND_GRASS = vec3(0.9, 0.3, 1.0);  // BRIGHT MAGENTA (magical)
const vec3 HELL_GRASS = vec3(0.9, 0.2, 0.1);        // BRIGHT RED (hellfire)

// Biome rock colors (steep/high slope terrain) - Darker for contrast, richer colors
const vec3 VALLEY_ROCK = vec3(0.4, 0.42, 0.45);     // Gray stone
const vec3 FOREST_ROCK = vec3(0.3, 0.38, 0.32);     // Dark gray-green
const vec3 SWAMP_ROCK = vec3(0.25, 0.22, 0.18);     // Dark muddy stone
const vec3 MOUNTAIN_ROCK = vec3(0.6, 0.62, 0.68);   // Light gray rock
const vec3 DESERT_ROCK = vec3(0.7, 0.58, 0.4);      // Sandy stone
const vec3 WIZARDLAND_ROCK = vec3(0.55, 0.35, 0.65);// Purple crystal
const vec3 HELL_ROCK = vec3(0.3, 0.12, 0.08);       // Dark obsidian

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

// Improved hash function with better distribution
float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract(p.x * p.y);
}

// Simple 2D noise function
float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	// Smooth interpolation
	vec2 u = f * f * (3.0 - 2.0 * f);

	// Get corner values using improved hash
	float a = hash(i + vec2(0.0, 0.0));
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	// Bilinear interpolation and scale to -1 to 1
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

// Fractal Brownian Motion (FBM) - generates multi-octave noise
float fbm(vec2 p, int seed, float frequency, int octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amplitude = 1.0;
	float total_amplitude = 0.0;

	// Offset position by seed for variation
	vec2 pos = p * frequency + vec2(float(seed) * 0.1);

	for (int i = 0; i < 8; i++) {
		if (i >= octaves) break;

		value += noise2d(pos + vec2(float(i) * 10.0)) * amplitude;
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
	// EXACTLY matches BiomeGenerator._get_biome_at_position()
	if (difficulty_tier == 0) {  // Safe zone - valley and forest only
		if (normalized < 0.5) {
			return 0;  // valley
		} else {
			return 1;  // forest
		}
	} else if (difficulty_tier == 1) {  // Mid zone - more variety with swamp and desert
		if (normalized < 0.25) {
			return 0;  // valley (some safe areas still exist)
		} else if (normalized < 0.5) {
			return 1;  // forest
		} else if (normalized < 0.75) {
			return 2;  // swamp
		} else {
			return 4;  // desert
		}
	} else if (difficulty_tier == 2) {  // Danger zone - mountains and wizardland appear
		if (normalized < 0.15) {
			return 1;  // forest (occasional safe pockets)
		} else if (normalized < 0.3) {
			return 2;  // swamp
		} else if (normalized < 0.5) {
			return 4;  // desert
		} else if (normalized < 0.7) {
			return 3;  // mountain
		} else if (normalized < 0.9) {
			return 5;  // wizardland (FIXED: was 0.85, should be 0.9)
		} else {
			return 6;  // hell (hell starts appearing)
		}
	} else if (difficulty_tier == 3) {  // Extreme zone - heavy hell presence
		if (normalized < 0.15) {
			return 4;  // desert
		} else if (normalized < 0.3) {
			return 3;  // mountain
		} else if (normalized < 0.45) {
			return 5;  // wizardland
		} else {
			return 6;  // hell (hell is dominant)
		}
	} else {  // Beyond extreme - mostly pure hell
		if (normalized < 0.15) {
			return 3;  // mountain
		} else if (normalized < 0.25) {
			return 5;  // wizardland
		} else {
			return 6;  // hell (hell overwhelms)
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
// NOISE FUNCTIONS
// ============================================================================

// Sin-based random function - returns value between 0 and 1
float simple_rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Value noise - interpolate between random values at grid corners
float value_noise_simple(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	// Get random values at 4 corners
	float a = simple_rand(i);
	float b = simple_rand(i + vec2(1.0, 0.0));
	float c = simple_rand(i + vec2(0.0, 1.0));
	float d = simple_rand(i + vec2(1.0, 1.0));

	// Smooth interpolation curve
	vec2 u = f * f * (3.0 - 2.0 * f);

	// Bilinear interpolation
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Multi-octave noise
float multi_octave_noise(vec2 p) {
	float result = 0.0;
	float amp = 0.5;
	float freq = 1.0;

	result += value_noise_simple(p * freq * 2.0) * amp;
	amp *= 0.5; freq *= 2.0;

	result += value_noise_simple(p * freq * 2.0) * amp;
	amp *= 0.5; freq *= 2.0;

	result += value_noise_simple(p * freq * 2.0) * amp;
	amp *= 0.5; freq *= 2.0;

	result += value_noise_simple(p * freq * 2.0) * amp;

	return result;
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
	// Sample biome from texture (generated by BiomeGenerator - 100% accurate!)
	vec2 xz_pos = world_pos.xz;

	// Convert world position to UV coordinates (0-1 range)
	// Texture is centered at origin, covers biome_map_world_coverage meters
	vec2 uv = (xz_pos + vec2(biome_map_world_coverage * 0.5)) / biome_map_world_coverage;

	// Sample the biome texture directly - this IS the grass color
	vec3 grass_color = texture(biome_map, uv).rgb;

	// Find closest biome to get the matching rock color
	float valley_dist = length(grass_color - VALLEY_GRASS);
	float forest_dist = length(grass_color - FOREST_GRASS);
	float swamp_dist = length(grass_color - SWAMP_GRASS);
	float mountain_dist = length(grass_color - MOUNTAIN_GRASS);
	float desert_dist = length(grass_color - DESERT_GRASS);
	float wizardland_dist = length(grass_color - WIZARDLAND_GRASS);
	float hell_dist = length(grass_color - HELL_GRASS);

	// Find minimum distance to determine rock color
	float min_dist = valley_dist;
	vec3 rock_color = VALLEY_ROCK;

	if (forest_dist < min_dist) {
		min_dist = forest_dist;
		rock_color = FOREST_ROCK;
	}
	if (swamp_dist < min_dist) {
		min_dist = swamp_dist;
		rock_color = SWAMP_ROCK;
	}
	if (mountain_dist < min_dist) {
		min_dist = mountain_dist;
		rock_color = MOUNTAIN_ROCK;
	}
	if (desert_dist < min_dist) {
		min_dist = desert_dist;
		rock_color = DESERT_ROCK;
	}
	if (wizardland_dist < min_dist) {
		min_dist = wizardland_dist;
		rock_color = WIZARDLAND_ROCK;
	}
	if (hell_dist < min_dist) {
		min_dist = hell_dist;
		rock_color = HELL_ROCK;
	}

	// Calculate slope based on how vertical the surface is (in world space)
	// world_normal.y is 1.0 for perfectly flat ground (pointing straight up)
	// world_normal.y is 0.0 for vertical walls (pointing sideways)
	// We want: flat (world_normal.y near 1.0) = grass, steep (world_normal.y near 0.0) = rock
	float flatness = world_normal.y;  // 1.0 = flat, 0.0 = vertical

	// Blend between grass and rock based on slope
	// At 45 degrees (max walkable), normal.y = cos(45°) ≈ 0.707
	// flatness > 0.85 = flat, mostly grass
	// flatness < 0.70 = steep/walkable limit, mostly rock
	// Smooth transition between 0.70 and 0.85 (shows more rock on moderate slopes)
	float rock_blend = 1.0 - smoothstep(0.70, 0.85, flatness);
	vec3 base_color = mix(grass_color, rock_color, rock_blend);

	// Apply our custom noise function using full 3D position to avoid stripes on vertical surfaces
	// Mix XZ and XY/YZ patterns based on surface normal
	float noise_xz = multi_octave_noise(world_pos.xz * 0.3);
	float noise_xy = multi_octave_noise(world_pos.xy * 0.3);
	float noise_yz = multi_octave_noise(world_pos.yz * 0.3);

	// Blend noise based on surface orientation
	// Horizontal surfaces use XZ, vertical surfaces use XY/YZ
	vec3 blend_weights = abs(world_normal);
	blend_weights = blend_weights / (blend_weights.x + blend_weights.y + blend_weights.z);

	float noise_val = noise_xz * blend_weights.y +  // Horizontal surfaces
	                  noise_xy * blend_weights.z +  // North/South facing
	                  noise_yz * blend_weights.x;   // East/West facing

	// Convert to -1 to 1 range for color variation
	float combined = (noise_val - 0.5) * 2.0;

	// Apply variation to base color
	vec3 color = base_color * (1.0 + combined * 0.4);

	// Simple directional lighting
	vec3 light_dir = normalize(vec3(0.5, 1.0, 0.3));
	float ndotl = max(dot(world_normal, light_dir), 0.0);
	float ambient = 0.6;
	float lighting = ambient + (1.0 - ambient) * ndotl;

	// Debug mode: directly show the grass color from texture (for troubleshooting)
	if (debug_biome_colors) {
		// Show grass color directly - reveals if biome texture is working
		ALBEDO = grass_color;
		ROUGHNESS = 0.9;
		METALLIC = 0.0;
	} else {
		ALBEDO = color * lighting;
		// Rocky areas are slightly rougher
		ROUGHNESS = mix(0.85, 0.95, rock_blend);
		METALLIC = 0.0;
	}
}

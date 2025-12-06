shader_type sky;

// Sky colors (set by script)
uniform vec3 sky_top_color : source_color = vec3(0.3, 0.5, 0.9);
uniform vec3 sky_horizon_color : source_color = vec3(0.55, 0.7, 0.9);
uniform vec3 ground_color : source_color = vec3(0.2, 0.2, 0.2);

// Sun parameters
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float sun_size : hint_range(0.0, 1.0) = 0.05;

// Star parameters
uniform float star_brightness : hint_range(0.0, 1.0) = 0.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.5;

// Cloud parameters (set by WeatherManager)
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_speed : hint_range(0.0, 1.0) = 0.02;

// Hash functions for star generation
float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yxz + 19.19);
	return fract((p.x + p.y) * p.z);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth noise for clouds
float noise2D(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);  // Smoothstep

	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion for cloud detail
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	float total_amplitude = 0.0;

	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise2D(p * frequency);
		total_amplitude += amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return value / total_amplitude;
}

// Generate volumetric-looking clouds with realistic movement
float clouds(vec3 dir, float time) {
	// Only render clouds above horizon
	if (dir.y < 0.02) return 0.0;

	// Project direction onto a plane for 2D cloud sampling
	float cloud_height = 1.0 / max(dir.y, 0.08);
	vec2 cloud_pos = dir.xz * cloud_height * 1.5;

	// Multiple cloud layers moving at different speeds (parallax effect)
	// Base layer - large slow-moving clouds
	vec2 layer1_pos = cloud_pos * 0.5 + vec2(time * cloud_speed * 0.3, time * cloud_speed * 0.1);
	float layer1 = fbm(layer1_pos, 4);

	// Middle layer - medium clouds, slightly faster
	vec2 layer2_pos = cloud_pos * 0.8 + vec2(time * cloud_speed * 0.5, time * cloud_speed * 0.15);
	layer2_pos += vec2(sin(time * 0.1) * 0.2, cos(time * 0.08) * 0.15);  // Gentle drift
	float layer2 = fbm(layer2_pos, 5);

	// Detail layer - small wisps, fastest movement
	vec2 layer3_pos = cloud_pos * 2.0 + vec2(time * cloud_speed * 0.8, time * cloud_speed * 0.3);
	float layer3 = fbm(layer3_pos, 3);

	// Combine layers with weighting
	float cloud_noise = layer1 * 0.5 + layer2 * 0.35 + layer3 * 0.15;

	// Shape clouds based on coverage
	float cloud_threshold = 1.0 - cloud_coverage * 1.1;  // Slightly more coverage
	float cloud_value = smoothstep(cloud_threshold, cloud_threshold + 0.25, cloud_noise);

	// Add billowy detail at edges
	float edge_detail = fbm(cloud_pos * 4.0 + vec2(time * cloud_speed * 0.6, 0.0), 3);
	cloud_value = cloud_value * (0.75 + edge_detail * 0.25);

	// Soft fade near horizon for atmospheric perspective
	float horizon_fade = smoothstep(0.02, 0.25, dir.y);
	cloud_value *= horizon_fade;

	// Add subtle variation to prevent tiling look
	float variation = fbm(cloud_pos * 0.2 + vec2(time * 0.01, 0.0), 2);
	cloud_value *= 0.9 + variation * 0.1;

	return clamp(cloud_value, 0.0, 1.0);
}

// Realistic atmospheric scintillation (twinkling)
// Real twinkling is caused by atmospheric turbulence - it's rapid, irregular, and varies with altitude
float scintillation(vec3 cell, float time, float altitude) {
	// Multiple overlapping frequencies create irregular, realistic flicker
	float phase1 = hash(cell + vec3(3.0, 3.0, 3.0)) * TAU;
	float phase2 = hash(cell + vec3(4.0, 4.0, 4.0)) * TAU;
	float phase3 = hash(cell + vec3(5.0, 5.0, 5.0)) * TAU;
	float phase4 = hash(cell + vec3(6.0, 6.0, 6.0)) * TAU;
	float phase5 = hash(cell + vec3(9.0, 9.0, 9.0)) * TAU;

	// Different frequencies for each star - faster for more visible twinkling
	float speed1 = 3.0 + hash(cell + vec3(7.0, 0.0, 0.0)) * 5.0;
	float speed2 = 7.0 + hash(cell + vec3(0.0, 7.0, 0.0)) * 10.0;
	float speed3 = 15.0 + hash(cell + vec3(0.0, 0.0, 7.0)) * 20.0;  // Fast shimmer
	float speed4 = 1.0 + hash(cell + vec3(8.0, 8.0, 0.0)) * 2.0;    // Slow variation
	float speed5 = 25.0 + hash(cell + vec3(13.0, 0.0, 0.0)) * 15.0; // Very fast flicker

	// Combine multiple sine waves with STRONGER amplitudes
	float twinkle = 0.0;
	twinkle += sin(time * speed1 + phase1) * 0.5;
	twinkle += sin(time * speed2 + phase2) * 0.4;
	twinkle += sin(time * speed3 + phase3) * 0.3;   // High frequency shimmer
	twinkle += sin(time * speed4 + phase4) * 0.3;   // Slow drift
	twinkle += sin(time * speed5 + phase5) * 0.2;   // Very fast flicker

	// Add occasional bright flashes (atmospheric focusing) - more frequent
	float flash_chance = hash(cell + vec3(floor(time * 1.5), 0.0, 0.0));
	if (flash_chance > 0.85) {
		float flash_intensity = (flash_chance - 0.85) * 6.67;  // 0 to 1
		float flash_time = fract(time * 1.5);
		float flash = exp(-flash_time * 6.0) * flash_intensity;
		twinkle += flash * 0.8;
	}

	// Occasional dimming (star almost disappearing)
	float dim_chance = hash(cell + vec3(floor(time * 0.8), 1.0, 0.0));
	if (dim_chance > 0.88) {
		float dim_time = fract(time * 0.8);
		float dim = exp(-dim_time * 4.0) * 0.7;
		twinkle -= dim;
	}

	// More twinkling near horizon (more atmosphere to look through)
	// altitude: 0 = horizon, 1 = zenith
	float horizon_factor = 1.0 - altitude * 0.5;  // 1.0 at horizon, 0.5 at zenith
	twinkle *= horizon_factor;

	// Convert to brightness multiplier - WIDER range for more visible effect
	// Range: ~0.1 to ~1.8 (stars can almost disappear or get very bright)
	return clamp(0.8 + twinkle * 0.7, 0.1, 2.0);
}

// Generate star color based on "temperature" - adds realism
vec3 star_color(vec3 cell) {
	float temp = hash(cell + vec3(10.0, 10.0, 10.0));

	// Star colors from cool red to hot blue
	if (temp < 0.15) {
		return vec3(1.0, 0.6, 0.4);   // Cool red/orange star
	} else if (temp < 0.35) {
		return vec3(1.0, 0.85, 0.7);  // Warm yellow star
	} else if (temp < 0.75) {
		return vec3(1.0, 1.0, 1.0);   // White star (most common)
	} else if (temp < 0.9) {
		return vec3(0.9, 0.95, 1.0);  // Blue-white star
	} else {
		return vec3(0.8, 0.85, 1.0);  // Blue star (hottest, rarest)
	}
}

// Atmospheric color dispersion during twinkling
vec3 twinkle_color_shift(vec3 cell, float time, float base_twinkle) {
	// When twinkling strongly, add subtle color shifts (chromatic scintillation)
	float shift_phase = hash(cell + vec3(11.0, 11.0, 11.0)) * TAU;
	float shift_speed = 8.0 + hash(cell + vec3(12.0, 12.0, 12.0)) * 10.0;
	float shift = sin(time * shift_speed + shift_phase);

	// Only shift color during strong twinkle events
	float shift_amount = max(0.0, abs(base_twinkle - 0.9) - 0.2) * 2.0;

	vec3 color_shift = vec3(1.0);
	if (shift > 0.3) {
		// Brief red flash
		color_shift = vec3(1.0, 0.9, 0.85);
	} else if (shift < -0.3) {
		// Brief blue flash
		color_shift = vec3(0.85, 0.9, 1.0);
	}

	return mix(vec3(1.0), color_shift, shift_amount * 0.5);
}

// Fast background star field - thousands of tiny dim stars, very cheap
float background_stars(vec3 dir) {
	vec3 n = normalize(dir);

	// Multiple layers of background stars at different scales for depth
	float stars = 0.0;

	// Layer 1: Very dense tiny stars (scale 400)
	vec3 p1 = n * 400.0;
	vec3 cell1 = floor(p1);
	float h1 = hash(cell1);
	if (h1 > 0.985) {  // ~1.5% of cells have stars
		vec3 frac1 = fract(p1);
		vec3 star_pos = vec3(hash(cell1 + vec3(1.0, 0.0, 0.0)),
		                     hash(cell1 + vec3(0.0, 1.0, 0.0)),
		                     hash(cell1 + vec3(0.0, 0.0, 1.0)));
		float dist = length(frac1 - star_pos);
		float brightness = hash(cell1 + vec3(2.0, 2.0, 2.0)) * 0.4;
		stars += smoothstep(0.08, 0.0, dist) * brightness;
	}

	// Layer 2: Medium density small stars (scale 250)
	vec3 p2 = n * 250.0;
	vec3 cell2 = floor(p2);
	float h2 = hash(cell2 + vec3(100.0, 100.0, 100.0));
	if (h2 > 0.975) {  // ~2.5% of cells
		vec3 frac2 = fract(p2);
		vec3 star_pos = vec3(hash(cell2 + vec3(101.0, 0.0, 0.0)),
		                     hash(cell2 + vec3(0.0, 101.0, 0.0)),
		                     hash(cell2 + vec3(0.0, 0.0, 101.0)));
		float dist = length(frac2 - star_pos);
		float brightness = hash(cell2 + vec3(102.0, 102.0, 102.0)) * 0.5;
		stars += smoothstep(0.06, 0.0, dist) * brightness;
	}

	// Layer 3: Sparse slightly brighter background stars (scale 150)
	vec3 p3 = n * 150.0;
	vec3 cell3 = floor(p3);
	float h3 = hash(cell3 + vec3(200.0, 200.0, 200.0));
	if (h3 > 0.96) {  // ~4% of cells
		vec3 frac3 = fract(p3);
		vec3 star_pos = vec3(hash(cell3 + vec3(201.0, 0.0, 0.0)),
		                     hash(cell3 + vec3(0.0, 201.0, 0.0)),
		                     hash(cell3 + vec3(0.0, 0.0, 201.0)));
		float dist = length(frac3 - star_pos);
		float brightness = 0.3 + hash(cell3 + vec3(202.0, 202.0, 202.0)) * 0.5;
		stars += smoothstep(0.055, 0.0, dist) * brightness;
	}

	return stars;
}

// Generate bright twinkling stars using 3D grid
vec3 bright_stars(vec3 dir, float time) {
	vec3 n = normalize(dir);
	float altitude = clamp(n.y, 0.0, 1.0);

	// Scale for bright star density
	float scale = 80.0;
	vec3 p = n * scale;
	vec3 grid = floor(p);
	vec3 frac_p = fract(p);

	vec3 total_star = vec3(0.0);

	// Check nearby cells (reduced to 2x2x2 for performance since we have background stars now)
	for (int x = 0; x <= 1; x++) {
		for (int y = 0; y <= 1; y++) {
			for (int z = 0; z <= 1; z++) {
				vec3 cell = grid + vec3(float(x), float(y), float(z));

				// Fewer bright stars since we have background layer
				float has_star = hash(cell);
				if (has_star > (1.0 - star_density * 0.25)) {
					vec3 star_pos = vec3(
						hash(cell + vec3(1.0, 0.0, 0.0)),
						hash(cell + vec3(0.0, 1.0, 0.0)),
						hash(cell + vec3(0.0, 0.0, 1.0))
					);

					vec3 diff = frac_p - star_pos - vec3(float(x), float(y), float(z));
					float dist = length(diff);

					float base_brightness = hash(cell + vec3(2.0, 2.0, 2.0));

					// Full twinkling for bright stars
					float twinkle_reduction = base_brightness * 0.15;
					float twinkle = scintillation(cell, time, altitude);
					twinkle = mix(twinkle, 1.0, twinkle_reduction);

					float brightness = base_brightness * twinkle;
					float size = 0.06 + base_brightness * 0.1;
					float star_intensity = smoothstep(size, 0.0, dist);

					vec3 base_color = star_color(cell);
					vec3 twinkle_shift = twinkle_color_shift(cell, time, twinkle);

					vec3 final_color = base_color * twinkle_shift * brightness;
					total_star += star_intensity * final_color * (0.6 + base_brightness * 0.6);
				}
			}
		}
	}

	return total_star;
}

// Combined star field - dense background + bright twinkling stars
vec3 stars(vec3 dir, float time) {
	// Dense background star field (cheap, no twinkling)
	float bg = background_stars(dir);

	// Bright foreground stars with full twinkling
	vec3 fg = bright_stars(dir, time);

	// Combine: background is white/slightly blue, foreground has colors
	vec3 bg_color = vec3(0.9, 0.92, 1.0) * bg;

	return min(bg_color + fg, vec3(2.0));
}

void sky() {
	vec3 dir = EYEDIR;

	// Sky gradient
	float horizon_blend = smoothstep(-0.1, 0.3, dir.y);
	vec3 sky = mix(sky_horizon_color, sky_top_color, horizon_blend);

	// Ground (below horizon)
	if (dir.y < 0.0) {
		float ground_blend = smoothstep(0.0, -0.3, dir.y);
		sky = mix(sky_horizon_color, ground_color, ground_blend);
	}

	// Sun (uses LIGHT0_DIRECTION from DirectionalLight3D)
	float sun_dist = distance(dir, LIGHT0_DIRECTION);
	float sun = smoothstep(sun_size, sun_size * 0.5, sun_dist);
	float sun_glow = smoothstep(sun_size * 4.0, sun_size, sun_dist) * 0.3;

	// Only show sun above horizon
	if (LIGHT0_DIRECTION.y > -0.1) {
		sky += sun_color * (sun + sun_glow) * LIGHT0_ENERGY;
	}

	// Stars (only visible at night, above horizon, reduced by clouds)
	if (star_brightness > 0.0 && dir.y > 0.0) {
		vec3 star_value = stars(dir, TIME) * star_brightness;
		// Clouds block stars
		float star_cloud_block = 1.0 - cloud_coverage * 0.9;
		sky += star_value * star_cloud_block;
	}

	// Clouds (only above horizon)
	if (cloud_coverage > 0.01 && dir.y > 0.0) {
		float cloud_value = clouds(dir, TIME);

		// Cloud color: white when lit, darker with cloud_darkness
		vec3 cloud_lit_color = vec3(1.0, 1.0, 1.0);  // Bright white clouds
		vec3 cloud_dark_color = vec3(0.4, 0.42, 0.45);  // Dark storm clouds

		// Mix based on darkness parameter
		vec3 cloud_base_color = mix(cloud_lit_color, cloud_dark_color, cloud_darkness);

		// Clouds are lit by sun - brighter on sun side
		float sun_illumination = max(0.0, dot(dir, LIGHT0_DIRECTION));
		vec3 cloud_color = cloud_base_color * (0.7 + sun_illumination * 0.3);

		// At night, clouds are darker and slightly blue-tinted
		float night_factor = 1.0 - clamp(LIGHT0_ENERGY, 0.0, 1.0);
		cloud_color = mix(cloud_color, vec3(0.15, 0.17, 0.25), night_factor * 0.7);

		// Blend clouds over sky
		sky = mix(sky, cloud_color, cloud_value * 0.9);

		// Cloud shadows on sun - sun is dimmer behind thick clouds
		float cloud_sun_occlusion = cloud_value * cloud_coverage;
		// Already handled by mixing, but reduce sun glow through clouds
	}

	COLOR = sky;
}

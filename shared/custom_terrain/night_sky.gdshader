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

// Generate stars using 3D grid for stable positions regardless of camera rotation
float stars(vec3 dir, float time) {
	// Normalize direction to ensure consistent lookup
	vec3 n = normalize(dir);

	// Scale for star density - larger = more smaller cells = more stars
	float scale = 80.0;
	vec3 p = n * scale;

	// 3D grid-based stars
	vec3 grid = floor(p);
	vec3 frac_p = fract(p);

	float star = 0.0;

	// Check nearby cells
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 cell = grid + vec3(float(x), float(y), float(z));

				// Deterministic star presence based on cell - more stars!
				float has_star = hash(cell);
				if (has_star > (1.0 - star_density * 0.4)) {
					// Star position within cell
					vec3 star_pos = vec3(
						hash(cell + vec3(1.0, 0.0, 0.0)),
						hash(cell + vec3(0.0, 1.0, 0.0)),
						hash(cell + vec3(0.0, 0.0, 1.0))
					);

					vec3 diff = frac_p - star_pos - vec3(float(x), float(y), float(z));
					float dist = length(diff);

					// Star brightness and size
					float base_brightness = hash(cell + vec3(2.0, 2.0, 2.0));

					// Sparkle effect tied purely to time and cell position
					float sparkle_speed = 1.0 + hash(cell + vec3(3.0, 3.0, 3.0)) * 3.0;
					float sparkle_phase = hash(cell + vec3(4.0, 4.0, 4.0)) * 6.28;
					float sparkle = 0.6 + 0.4 * sin(time * sparkle_speed + sparkle_phase);

					float brightness = base_brightness * sparkle;
					float size = 0.06 + base_brightness * 0.1;
					star += smoothstep(size, 0.0, dist) * (0.4 + brightness * 0.6);
				}
			}
		}
	}

	return min(star, 1.0);
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
		float star_value = stars(dir, TIME) * star_brightness;
		// Clouds block stars
		float star_cloud_block = 1.0 - cloud_coverage * 0.9;
		sky += vec3(star_value * star_cloud_block);
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

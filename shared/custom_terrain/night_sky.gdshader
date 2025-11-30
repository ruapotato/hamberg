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

// Hash functions for star generation
float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yxz + 19.19);
	return fract((p.x + p.y) * p.z);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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

	// Stars (only visible at night, above horizon)
	if (star_brightness > 0.0 && dir.y > 0.0) {
		float star_value = stars(dir, TIME) * star_brightness;
		sky += vec3(star_value);
	}

	COLOR = sky;
}

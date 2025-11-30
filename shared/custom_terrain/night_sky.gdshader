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

// Hash function for star generation
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Generate stars at a position
float stars(vec3 dir) {
	// Use spherical coordinates for consistent star positions
	vec2 uv = vec2(atan(dir.x, dir.z), asin(dir.y));
	uv *= 100.0; // Scale for star density

	// Grid-based stars
	vec2 grid = floor(uv);
	vec2 frac_uv = fract(uv);

	float star = 0.0;

	// Check nearby cells for stars
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 cell = grid + vec2(float(x), float(y));
			vec2 star_pos = vec2(hash(cell), hash(cell + vec2(1.0, 0.0)));

			// Only some cells have stars
			if (hash(cell + vec2(0.0, 1.0)) > (1.0 - star_density * 0.3)) {
				vec2 diff = frac_uv - star_pos - vec2(float(x), float(y));
				float dist = length(diff);

				// Star brightness falloff
				float brightness = hash(cell + vec2(2.0, 0.0));
				float size = 0.02 + brightness * 0.03;
				star += smoothstep(size, 0.0, dist) * brightness;
			}
		}
	}

	return star;
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
		float star_value = stars(dir) * star_brightness;
		// Twinkle effect
		star_value *= 0.7 + 0.3 * sin(TIME * 2.0 + hash(dir.xz) * 10.0);
		sky += vec3(star_value);
	}

	COLOR = sky;
}

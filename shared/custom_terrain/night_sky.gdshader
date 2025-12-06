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

// Moon parameters
uniform vec3 moon_direction : source_color = vec3(0.5, 0.3, -0.8);
uniform float moon_size : hint_range(0.0, 0.2) = 0.045;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.5;  // 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter

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

					// Multi-layer star appearance: bright core + soft glow
					float core_size = 0.04 + base_brightness * 0.06;
					float glow_size = core_size * 3.0;

					// Sharp bright core
					float core = smoothstep(core_size, 0.0, dist);
					// Soft surrounding glow
					float glow = exp(-dist * dist / (glow_size * glow_size * 0.5)) * 0.4;
					// Very faint outer halo
					float halo = exp(-dist * dist / (glow_size * glow_size * 2.0)) * 0.1;

					float star_intensity = core + glow * base_brightness + halo * base_brightness;

					vec3 base_color = star_color(cell);
					vec3 twinkle_shift = twinkle_color_shift(cell, time, twinkle);

					vec3 final_color = base_color * twinkle_shift * brightness;
					total_star += star_intensity * final_color * (0.7 + base_brightness * 0.5);
				}
			}
		}
	}

	return total_star;
}

// Grainy noise for milky way star clouds - creates fine speckled texture
float grainy_noise(vec2 p) {
	// Multiple layers of sharp, high-frequency noise
	float grain = 0.0;
	float amp = 1.0;
	float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		vec2 cell = floor(p * freq);
		float h = hash2(cell);
		// Sharp threshold creates speckles rather than smooth blobs
		grain += step(0.7, h) * amp * h;
		amp *= 0.6;
		freq *= 2.5;
	}
	return grain;
}

// Wispy filament noise - creates elongated structures
float filament_noise(vec3 p) {
	// Stretched noise in one direction creates filaments
	vec2 stretched = vec2(p.x * 3.0 + p.z, p.y * 0.5);
	float n1 = noise2D(stretched * 8.0);
	float n2 = noise2D(stretched * 16.0 + vec2(5.3, 2.1));
	// Sharp edges
	float filament = smoothstep(0.4, 0.6, n1) * smoothstep(0.3, 0.5, n2);
	return filament;
}

// Milky way band - creates a bright band of stars/nebulosity across the sky
vec3 milky_way(vec3 dir) {
	vec3 n = normalize(dir);

	// Milky way runs roughly east-west, tilted about 60 degrees from horizon
	vec3 milky_axis = normalize(vec3(0.2, 0.6, 0.8));
	float dist_from_band = abs(dot(n, milky_axis));

	// Band intensity - strongest at center, fades at edges
	float band_width = 0.35;
	float band = 1.0 - smoothstep(0.0, band_width, dist_from_band);
	band = band * band;

	// Galactic core - a brighter central bulge
	vec3 core_dir = normalize(vec3(-0.5, 0.4, 0.7));
	float core_dist = 1.0 - dot(n, core_dir);
	float core = exp(-core_dist * 10.0) * 0.5;

	// Fine grainy star texture - this is what makes it look like countless tiny stars
	vec3 p = n * 100.0;  // High frequency for fine detail
	float grain1 = grainy_noise(p.xy + p.z * 0.3);
	float grain2 = grainy_noise(p.yz * 1.1 + p.x * 0.2);
	float grain3 = grainy_noise(p.xz * 0.9 + vec2(p.y * 0.4, 0.0));
	float star_grain = (grain1 + grain2 + grain3) * 0.33;

	// Wispy filament structure at larger scale
	vec3 p2 = n * 25.0;
	float wisps = filament_noise(p2);
	float wisps2 = filament_noise(p2 * 1.3 + vec3(3.1, 1.7, 2.3));

	// Very large scale smooth variation (not blobby, just gradual density changes)
	vec3 p3 = n * 8.0;
	float large_variation = noise2D(p3.xy + p3.z * 0.5) * 0.3 + 0.7;

	// Dark dust lanes - sharp, wispy, not blobby
	vec3 p4 = n * 15.0;
	float dust_base = noise2D(p4.xz + vec2(p4.y * 0.3, 0.0));
	float dust2 = noise2D(p4.xy * 2.0);
	// Sharp threshold for defined dark lanes
	float dark_lanes = smoothstep(0.45, 0.55, dust_base) * 0.7;
	// Add some thinner lanes
	dark_lanes += smoothstep(0.6, 0.7, dust2) * 0.3;
	dark_lanes = min(dark_lanes, 0.85);

	// Combine: grainy stars modulated by wisps and large variation
	float structure = star_grain * (0.5 + wisps * 0.3 + wisps2 * 0.2) * large_variation;

	// Final intensity
	float intensity = (band + core * 0.6) * structure * (1.0 - dark_lanes);

	// Color gradient - warmer toward core, cooler at edges
	vec3 edge_color = vec3(0.75, 0.8, 1.0);     // Cool blue-white
	vec3 mid_color = vec3(0.95, 0.9, 0.98);     // Pale white-lavender
	vec3 core_color = vec3(1.0, 0.92, 0.8);     // Warm golden

	float core_blend = core / (core + 0.2);
	vec3 base_color = mix(edge_color, mid_color, band);
	base_color = mix(base_color, core_color, core_blend * 0.5);

	vec3 color = base_color * intensity * 0.22;

	// Extra dense star glow in milky way
	float extra_glow = (band + core * 0.7) * structure * 0.08;
	color += vec3(0.9, 0.92, 1.0) * extra_glow;

	// Subtle reddish emission - use grainy texture, not blobby
	// Only in specific small regions, with sharp boundaries
	float emission_grain = grainy_noise(p.xy * 0.3 + p.z * 0.1);
	float emission_mask = step(0.85, noise2D(p3.xy * 2.0));  // Sharp mask for specific spots
	float emission = emission_grain * emission_mask * band;
	color += vec3(0.2, 0.04, 0.05) * emission * 0.15;

	return color;
}

// Nebula clouds - colorful patches with realistic structure
vec3 nebulae(vec3 dir) {
	vec3 n = normalize(dir);
	vec3 color = vec3(0.0);

	// Nebula 1 - Large emission nebula (like Orion) - red/pink with blue edges
	vec3 neb1_pos = normalize(vec3(0.5, 0.7, 0.3));
	float neb1_dist = 1.0 - dot(n, neb1_pos);
	float neb1_base = exp(-neb1_dist * 10.0);
	vec3 p1 = n * 60.0;
	float neb1_structure = fbm(p1.xy + p1.z * 0.3, 5) * 0.6 + fbm(p1.yz * 1.5, 3) * 0.4;
	float neb1_wisps = fbm(p1.xz * 3.0, 2);
	float neb1 = neb1_base * (0.3 + neb1_structure * 0.7) * 0.4;
	// Color gradient from pink core to blue-ish edges
	vec3 neb1_core = vec3(0.5, 0.15, 0.2);   // Deep pink/red
	vec3 neb1_edge = vec3(0.2, 0.25, 0.45);  // Blue reflection
	float core_factor = exp(-neb1_dist * 25.0);
	color += mix(neb1_edge, neb1_core, core_factor) * neb1;
	// Add bright wispy tendrils
	color += vec3(0.6, 0.3, 0.35) * neb1_base * smoothstep(0.55, 0.75, neb1_wisps) * 0.15;

	// Nebula 2 - Blue reflection nebula with dark core
	vec3 neb2_pos = normalize(vec3(-0.6, 0.5, -0.4));
	float neb2_dist = 1.0 - dot(n, neb2_pos);
	float neb2_base = exp(-neb2_dist * 8.0);
	vec3 p2 = n * 50.0;
	float neb2_structure = fbm(p2.yz, 4) * 0.7 + fbm(p2.xy * 2.0, 3) * 0.3;
	float neb2 = neb2_base * (0.2 + neb2_structure * 0.8) * 0.35;
	// Dark dust lane through center
	float dust_lane = smoothstep(0.4, 0.5, fbm(p2.xz * 1.5, 2));
	neb2 *= (1.0 - dust_lane * 0.6);
	color += vec3(0.2, 0.35, 0.6) * neb2;

	// Nebula 3 - Teal/cyan planetary nebula (smaller, more circular)
	vec3 neb3_pos = normalize(vec3(0.3, 0.85, -0.5));
	float neb3_dist = 1.0 - dot(n, neb3_pos);
	float neb3_ring = exp(-neb3_dist * 30.0) - exp(-neb3_dist * 50.0) * 0.7;  // Ring shape
	neb3_ring = max(0.0, neb3_ring);
	vec3 p3 = n * 80.0;
	float neb3_structure = 0.7 + fbm(p3.xz, 3) * 0.3;
	color += vec3(0.15, 0.4, 0.35) * neb3_ring * neb3_structure * 0.3;
	// Bright central star
	float central_star = exp(-neb3_dist * 80.0) * 0.4;
	color += vec3(0.8, 0.9, 1.0) * central_star;

	// Nebula 4 - Purple/magenta with pillar structures (like Pillars of Creation)
	vec3 neb4_pos = normalize(vec3(-0.4, 0.6, 0.6));
	float neb4_dist = 1.0 - dot(n, neb4_pos);
	float neb4_base = exp(-neb4_dist * 9.0);
	vec3 p4 = n * 55.0;
	float neb4_structure = fbm(p4.xy + p4.z, 5);
	// Create pillar-like dark structures
	float pillars = smoothstep(0.3, 0.5, fbm(p4.xz * 0.8 + vec2(0.0, p4.y * 2.0), 4));
	float neb4 = neb4_base * (0.3 + neb4_structure * 0.7) * 0.3;
	neb4 *= (1.0 - pillars * 0.7);
	// Gradient from magenta to deep purple
	vec3 neb4_bright = vec3(0.45, 0.15, 0.4);
	vec3 neb4_dark = vec3(0.2, 0.08, 0.25);
	color += mix(neb4_dark, neb4_bright, neb4_structure) * neb4;

	// Nebula 5 - Golden/orange supernova remnant
	vec3 neb5_pos = normalize(vec3(0.7, 0.4, -0.3));
	float neb5_dist = 1.0 - dot(n, neb5_pos);
	float neb5_shell = exp(-neb5_dist * 20.0) - exp(-neb5_dist * 35.0) * 0.5;
	neb5_shell = max(0.0, neb5_shell);
	vec3 p5 = n * 70.0;
	float neb5_filaments = fbm(p5.xy * 2.0, 3);
	color += vec3(0.5, 0.35, 0.1) * neb5_shell * (0.5 + neb5_filaments * 0.5) * 0.25;

	return color;
}

// Shooting stars / meteors - occasional bright streaks across the sky
vec3 shooting_stars(vec3 dir, float time) {
	vec3 n = normalize(dir);
	vec3 total = vec3(0.0);

	// Multiple possible meteor trails at different times
	for (int i = 0; i < 3; i++) {
		// Each meteor has a different time offset and duration
		float meteor_period = 12.0 + float(i) * 7.0;  // Different periods (less frequent)
		float meteor_time = mod(time + float(i) * 17.3, meteor_period);
		float meteor_duration = 0.6;  // How long the streak is visible

		// Only show meteor during its active window
		if (meteor_time < meteor_duration) {
			// Random start direction for this meteor
			float seed = float(i) + floor(time / meteor_period) * 7.13;
			vec3 meteor_start = normalize(vec3(
				hash(vec3(seed, 1.0, 0.0)) * 2.0 - 1.0,
				0.4 + hash(vec3(seed, 2.0, 0.0)) * 0.5,  // Above horizon
				hash(vec3(seed, 3.0, 0.0)) * 2.0 - 1.0
			));

			// Meteor direction (downward and slightly random)
			vec3 meteor_dir = normalize(vec3(
				hash(vec3(seed, 4.0, 0.0)) * 0.6 - 0.3,
				-0.6 - hash(vec3(seed, 5.0, 0.0)) * 0.3,
				hash(vec3(seed, 6.0, 0.0)) * 0.6 - 0.3
			));

			// Current meteor HEAD position along its path
			float progress = meteor_time / meteor_duration;
			float trail_length = 0.15;  // Length of visible trail behind head
			float head_t = progress * 0.5;  // How far head has traveled
			vec3 head_pos = meteor_start + meteor_dir * head_t;

			// Find closest point on trail to view direction
			// Trail goes from (head_pos - trail_length * meteor_dir) to head_pos
			vec3 trail_start = head_pos - meteor_dir * trail_length * progress;  // Trail fades in

			// Project view direction onto trail line
			float t = dot(n - trail_start, meteor_dir);
			float max_t = length(head_pos - trail_start);
			t = clamp(t, 0.0, max_t);

			vec3 closest_point = trail_start + meteor_dir * t;
			float dist_to_trail = length(n - normalize(closest_point));

			// Trail fades from head (bright) to tail (dim)
			// t=0 is tail, t=max_t is head
			float fade_along_trail = t / (max_t + 0.001);  // 0 at tail, 1 at head
			fade_along_trail = pow(fade_along_trail, 1.5);  // Sharper falloff toward tail

			// Only show if we're close to the trail
			if (dist_to_trail < 0.1) {
				// Sharp bright head
				float head_dist = length(n - normalize(head_pos));
				float head_bright = exp(-head_dist * 500.0);

				// Trail gets thinner toward the tail
				float trail_width = 200.0 + (1.0 - fade_along_trail) * 300.0;  // Wider falloff at tail
				float trail = exp(-dist_to_trail * trail_width) * fade_along_trail;

				// Soft glow around trail
				float glow = exp(-dist_to_trail * 60.0) * fade_along_trail * 0.3;

				// Fade in at start, fade out at end
				float time_fade = sin(progress * 3.14159);
				time_fade = clamp(time_fade * 1.5, 0.0, 1.0);

				// Color - white head, fading to orange/red tail
				vec3 head_color = vec3(1.0, 1.0, 0.95);
				vec3 tail_color = vec3(1.0, 0.5, 0.2);
				vec3 trail_color = mix(tail_color, head_color, fade_along_trail);

				total += (head_bright * head_color + trail * trail_color + glow * tail_color) * time_fade;
			}
		}
	}

	return total;
}

// Star halos/glow - bright stars have visible atmospheric glow
vec3 star_glow(vec3 dir, float time) {
	vec3 n = normalize(dir);
	vec3 total = vec3(0.0);

	// Check for extra-bright stars that deserve halos
	float scale = 60.0;
	vec3 p = n * scale;
	vec3 grid = floor(p);

	// Only check immediate cell for performance
	for (int x = 0; x <= 1; x++) {
		for (int y = 0; y <= 1; y++) {
			for (int z = 0; z <= 1; z++) {
				vec3 cell = grid + vec3(float(x), float(y), float(z));

				// Only ~3% of cells have stars bright enough for glow
				float has_glow_star = hash(cell);
				if (has_glow_star > 0.97) {
					vec3 star_pos = vec3(
						hash(cell + vec3(1.0, 0.0, 0.0)),
						hash(cell + vec3(0.0, 1.0, 0.0)),
						hash(cell + vec3(0.0, 0.0, 1.0))
					);

					vec3 frac_p = fract(p);
					vec3 diff = frac_p - star_pos - vec3(float(x), float(y), float(z));
					float dist = length(diff);

					// Soft glow
					float glow = exp(-dist * 15.0) * 0.15;

					// Subtle diffraction spikes (4-point star pattern)
					vec2 spike_dir = normalize(diff.xy + 0.001);
					float spike_angle = atan(spike_dir.y, spike_dir.x);
					float spikes = pow(abs(sin(spike_angle * 2.0)), 8.0);
					float spike_intensity = exp(-dist * 8.0) * spikes * 0.1;

					// Color based on star temperature
					vec3 glow_color = star_color(cell);

					// Twinkling affects the glow too
					float altitude = clamp(n.y, 0.0, 1.0);
					float twinkle = scintillation(cell, time, altitude);

					total += (glow + spike_intensity) * glow_color * twinkle * 0.6;
				}
			}
		}
	}

	return total;
}

// Atmospheric horizon glow - the subtle airglow effect at night
vec3 horizon_glow(vec3 dir) {
	vec3 n = normalize(dir);

	// Only near horizon
	float horizon_factor = 1.0 - abs(n.y);
	horizon_factor = pow(horizon_factor, 8.0);  // Very concentrated at horizon

	// Airglow is typically greenish or bluish
	vec3 airglow_color = vec3(0.08, 0.12, 0.15);  // Subtle blue-green

	// Add a warm band just above horizon (atmospheric scattering of distant lights)
	float warm_band = exp(-pow((n.y - 0.02) * 20.0, 2.0));
	vec3 warm_color = vec3(0.1, 0.06, 0.04);  // Very subtle warm glow

	return airglow_color * horizon_factor * 0.3 + warm_color * warm_band * 0.15;
}

// Combined star field - dense background + bright twinkling stars + milky way + nebulae + effects
vec3 stars(vec3 dir, float time) {
	// Atmospheric horizon glow (base layer)
	vec3 atmo = horizon_glow(dir);

	// Base background star field
	float bg = background_stars(dir);
	vec3 bg_color = vec3(0.9, 0.92, 1.0) * bg;

	// Milky way adds structure and extra stars
	vec3 milky = milky_way(dir);

	// Colorful nebulae
	vec3 neb = nebulae(dir);

	// Bright foreground stars with full twinkling
	vec3 fg = bright_stars(dir, time);

	// Star halos/glow around brightest stars
	vec3 halos = star_glow(dir, time);

	// Shooting stars (meteors)
	vec3 meteors = shooting_stars(dir, time);

	// Combine all layers
	vec3 result = atmo + bg_color + milky + neb + fg + halos + meteors;

	return min(result, vec3(2.5));
}

// Moon rendering with craters and phase
vec3 render_moon(vec3 dir, vec3 moon_dir, float size, float phase) {
	vec3 n_moon = normalize(moon_dir);
	float dist_to_moon = distance(dir, n_moon);

	// Not looking at moon
	if (dist_to_moon > size * 2.0) return vec3(0.0);

	// Moon disc
	float moon_disc = smoothstep(size, size * 0.95, dist_to_moon);

	if (moon_disc < 0.01) return vec3(0.0);

	// Calculate position on moon surface for texturing
	// Create a coordinate system on the moon face
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 moon_right = normalize(cross(up, n_moon));
	vec3 moon_up = normalize(cross(n_moon, moon_right));

	// Project view direction onto moon surface
	vec3 to_point = normalize(dir) - n_moon;
	float moon_u = dot(to_point, moon_right) / size;
	float moon_v = dot(to_point, moon_up) / size;
	vec2 moon_uv = vec2(moon_u, moon_v);

	// Distance from center of moon disc (for limb darkening and phase)
	float r = length(moon_uv);

	// Base moon color - slightly warm gray
	vec3 moon_base = vec3(0.85, 0.83, 0.8);

	// Crater texture using multiple noise layers
	vec2 crater_uv = moon_uv * 8.0;
	float craters = 0.0;

	// Large maria (dark areas)
	float maria1 = noise2D(moon_uv * 2.0 + vec2(1.5, 0.8));
	float maria2 = noise2D(moon_uv * 3.0 + vec2(0.3, 2.1));
	float maria = smoothstep(0.5, 0.7, maria1) * 0.15 + smoothstep(0.55, 0.75, maria2) * 0.1;

	// Medium craters
	float c1 = noise2D(crater_uv);
	float c2 = noise2D(crater_uv * 2.0 + vec2(3.7, 1.2));
	craters += smoothstep(0.6, 0.65, c1) * 0.12;
	craters += smoothstep(0.65, 0.7, c2) * 0.08;

	// Small craters
	float c3 = noise2D(crater_uv * 5.0 + vec2(7.1, 4.3));
	craters += smoothstep(0.7, 0.75, c3) * 0.05;

	// Apply surface detail
	float surface = 1.0 - maria - craters;
	vec3 moon_color = moon_base * surface;

	// Limb darkening - edges of moon are slightly darker
	float limb = 1.0 - r * r * 0.3;
	moon_color *= limb;

	// Phase shadow
	// phase: 0=new (dark), 0.25=first quarter, 0.5=full, 0.75=last quarter
	float phase_angle = phase * TAU;  // Convert to radians
	float shadow_x = cos(phase_angle);  // -1 to 1, determines shadow position

	// Shadow edge position based on phase
	float shadow = smoothstep(shadow_x - 0.1, shadow_x + 0.1, moon_u);

	// At new moon (phase=0), shadow_x = 1, whole moon dark
	// At full moon (phase=0.5), shadow_x = -1, whole moon lit
	if (phase < 0.5) {
		// Waxing: shadow on left (negative u), lit on right
		moon_color *= shadow;
	} else {
		// Waning: shadow on right (positive u), lit on left
		moon_color *= (1.0 - shadow);
	}

	// Soft glow around moon
	float glow = exp(-dist_to_moon * 30.0) * 0.3;
	vec3 glow_color = vec3(0.9, 0.88, 0.85) * glow;

	return moon_color * moon_disc + glow_color;
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

	// Moon (visible at night, above horizon)
	vec3 n_moon_dir = normalize(moon_direction);
	if (star_brightness > 0.0 && n_moon_dir.y > -0.1 && dir.y > 0.0) {
		vec3 moon = render_moon(dir, n_moon_dir, moon_size, moon_phase);
		// Clouds partially block moon
		float moon_cloud_block = 1.0 - cloud_coverage * 0.7;
		sky += moon * moon_cloud_block * star_brightness;
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

extends Node
class_name WeatherManager

## WeatherManager - Handles weather states, effects, and transitions
## Creates dynamic, immersive weather including rain, snow, fog, and clouds

signal weather_changed(weather_type: String)
signal weather_intensity_changed(intensity: float)

# Weather types
enum WeatherType {
	CLEAR,
	PARTLY_CLOUDY,
	CLOUDY,
	OVERCAST,
	LIGHT_RAIN,
	RAIN,
	HEAVY_RAIN,
	STORM,
	FOG,
	LIGHT_SNOW,
	SNOW,
	BLIZZARD
}

# Current weather state
var current_weather: WeatherType = WeatherType.CLEAR
var target_weather: WeatherType = WeatherType.CLEAR
var weather_intensity: float = 0.0  # 0.0 to 1.0
var target_intensity: float = 0.0
var transition_speed: float = 0.3  # How fast weather changes

# Cloud parameters (sent to sky shader)
var cloud_coverage: float = 0.0  # 0.0 = clear, 1.0 = fully overcast
var cloud_darkness: float = 0.0  # 0.0 = white fluffy, 1.0 = dark storm clouds
var target_cloud_coverage: float = 0.0
var target_cloud_darkness: float = 0.0

# Fog parameters
var fog_density: float = 0.0
var target_fog_density: float = 0.0

# Ground snow coverage (separate from particles - accumulates/melts slowly)
var ground_snow_coverage: float = 0.0
var snow_accumulation_rate: float = 0.03  # Constant rate snow builds up per second
var snow_melt_rate: float = 0.015  # How fast snow melts (slower than accumulation)
var max_snow_coverage: float = 1.0  # Maximum snow coverage (can be set by command)

# Footprint system
var footprint_texture: ImageTexture
var footprint_image: Image
const FOOTPRINT_TEXTURE_SIZE: int = 256  # Higher resolution for visible footprints
const FOOTPRINT_WORLD_SIZE: float = 64.0  # World units covered by texture
var footprint_center: Vector2 = Vector2.ZERO  # Center position in world
var last_footprint_pos: Vector2 = Vector2.ZERO  # Last position a footprint was placed
const FOOTPRINT_SPACING: float = 0.6  # Distance between footprints (closer together)
const FOOTPRINT_FADE_RATE: float = 0.3  # How fast footprints fill back in with snow
var footprint_update_timer: float = 0.0
const FOOTPRINT_UPDATE_INTERVAL: float = 0.1  # Update footprint texture every 0.1s

# References
var world_environment: WorldEnvironment
var sky_material: ShaderMaterial
var terrain_material: ShaderMaterial  # For snow coverage on ground
var sun_light: DirectionalLight3D
var day_night_cycle: DayNightCycle

# Particle systems (created at runtime)
var rain_particles: GPUParticles3D
var snow_particles: GPUParticles3D
var player_ref: Node3D

# Weather names for commands/display
const WEATHER_NAMES: Dictionary = {
	WeatherType.CLEAR: "clear",
	WeatherType.PARTLY_CLOUDY: "partly_cloudy",
	WeatherType.CLOUDY: "cloudy",
	WeatherType.OVERCAST: "overcast",
	WeatherType.LIGHT_RAIN: "light_rain",
	WeatherType.RAIN: "rain",
	WeatherType.HEAVY_RAIN: "heavy_rain",
	WeatherType.STORM: "storm",
	WeatherType.FOG: "fog",
	WeatherType.LIGHT_SNOW: "light_snow",
	WeatherType.SNOW: "snow",
	WeatherType.BLIZZARD: "blizzard"
}

# Reverse lookup
var weather_from_name: Dictionary = {}

func _ready() -> void:
	add_to_group("weather_manager")

	# Build reverse lookup
	for key in WEATHER_NAMES:
		weather_from_name[WEATHER_NAMES[key]] = key

	# Initialize footprint texture (white = no footprints)
	_init_footprint_texture()

	# Find scene nodes
	call_deferred("_find_scene_nodes")
	call_deferred("_create_particle_systems")

	print("[WeatherManager] Initialized")

func _init_footprint_texture() -> void:
	footprint_image = Image.create(FOOTPRINT_TEXTURE_SIZE, FOOTPRINT_TEXTURE_SIZE, false, Image.FORMAT_R8)
	footprint_image.fill(Color(1.0, 1.0, 1.0, 1.0))  # White = no footprints
	footprint_texture = ImageTexture.create_from_image(footprint_image)
	print("[WeatherManager] Footprint texture initialized (%dx%d)" % [FOOTPRINT_TEXTURE_SIZE, FOOTPRINT_TEXTURE_SIZE])

func _find_scene_nodes() -> void:
	# Find WorldEnvironment and sun
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if child is DirectionalLight3D and not sun_light:
				sun_light = child
			if child is WorldEnvironment and not world_environment:
				world_environment = child
			if child is DayNightCycle and not day_night_cycle:
				day_night_cycle = child

	# Get sky shader material
	if world_environment and world_environment.environment:
		var env = world_environment.environment
		if env.sky and env.sky.sky_material is ShaderMaterial:
			sky_material = env.sky.sky_material
			print("[WeatherManager] Found sky shader material")

	# Find terrain material from TerrainWorld (parent node)
	if parent and parent.has_method("get") and parent.get("terrain_material"):
		var mat = parent.get("terrain_material")
		if mat is ShaderMaterial:
			terrain_material = mat
			print("[WeatherManager] Found terrain shader material")
		elif mat is StandardMaterial3D:
			# Terrain uses StandardMaterial3D, can't set snow coverage
			print("[WeatherManager] Terrain uses StandardMaterial3D (snow coverage not supported)")

func _create_particle_systems() -> void:
	# Create rain particle system
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "RainParticles"
	rain_particles.emitting = false
	rain_particles.amount = 2000
	rain_particles.lifetime = 1.5
	rain_particles.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	rain_particles.process_material = _create_rain_material()
	rain_particles.draw_pass_1 = _create_rain_mesh()
	add_child(rain_particles)

	# Create snow particle system
	snow_particles = GPUParticles3D.new()
	snow_particles.name = "SnowParticles"
	snow_particles.emitting = false
	snow_particles.amount = 2000
	snow_particles.lifetime = 8.0
	snow_particles.preprocess = 6.0  # Pre-simulate 6 seconds so snow is already falling
	# Large AABB extending far below to ensure visibility all the way to ground
	snow_particles.visibility_aabb = AABB(Vector3(-40, -50, -40), Vector3(80, 70, 80))
	snow_particles.process_material = _create_snow_material()
	snow_particles.draw_pass_1 = _create_snow_mesh()
	add_child(snow_particles)

	print("[WeatherManager] Created particle systems")

func _create_rain_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 3.0
	mat.initial_velocity_min = 35.0
	mat.initial_velocity_max = 50.0
	mat.gravity = Vector3(0, -30, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(20, 2, 20)
	mat.color = Color(0.8, 0.85, 0.95, 0.8)
	# Add slight wind variation
	mat.direction = Vector3(0.1, -1, 0.05)
	return mat

func _create_rain_mesh() -> QuadMesh:
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.03, 0.6)  # Thicker, longer streaks for visibility

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.7)  # Brighter, more visible
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	return mesh

func _create_snow_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 12.0
	mat.gravity = Vector3(0, -8.0, 0)  # Strong gravity to reach ground
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(30, 3, 30)  # Wide emission area
	mat.color = Color(1.0, 1.0, 1.0, 1.0)
	# Turbulence for realistic drifting (reduced so it still falls down)
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 1.5
	mat.turbulence_noise_speed_random = 0.4
	mat.turbulence_noise_scale = 2.0
	# Scale variation for different snowflake sizes
	mat.scale_min = 0.7
	mat.scale_max = 1.5
	return mat

func _create_snow_mesh() -> QuadMesh:
	# Use quad for visible snowflakes
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.12, 0.12)  # Larger snowflakes for visibility

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # Always face camera
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true  # Render on top of everything for visibility
	mesh.material = mat
	return mesh

func _process(delta: float) -> void:
	# Smoothly transition weather parameters
	cloud_coverage = lerpf(cloud_coverage, target_cloud_coverage, delta * transition_speed)
	cloud_darkness = lerpf(cloud_darkness, target_cloud_darkness, delta * transition_speed)
	fog_density = lerpf(fog_density, target_fog_density, delta * transition_speed)
	weather_intensity = lerpf(weather_intensity, target_intensity, delta * transition_speed)

	# Update visuals
	_update_sky_shader()
	_update_environment()
	_update_particles()
	_update_ground_snow(delta)
	_update_footprints(delta)

	# Follow player
	_follow_player()

func _follow_player() -> void:
	if not is_instance_valid(player_ref):
		var players = get_tree().get_nodes_in_group("local_player")
		player_ref = players[0] if players.size() > 0 else null

	if player_ref:
		# Position particles above player
		var pos = player_ref.global_position
		rain_particles.global_position = Vector3(pos.x, pos.y + 20, pos.z)
		# Snow emitter positioned so snow falls through player level to ground
		snow_particles.global_position = Vector3(pos.x, pos.y + 15, pos.z)

func _update_sky_shader() -> void:
	if not sky_material:
		return

	# Set cloud parameters
	sky_material.set_shader_parameter("cloud_coverage", cloud_coverage)
	sky_material.set_shader_parameter("cloud_darkness", cloud_darkness)

func _update_environment() -> void:
	if not world_environment or not world_environment.environment:
		return

	var env = world_environment.environment

	# Fog for weather
	if fog_density > 0.01:
		env.fog_enabled = true
		env.fog_density = fog_density * 0.02
		env.fog_light_energy = 1.0 - cloud_darkness * 0.5
		# Fog color based on time of day
		var base_fog_color = Color(0.7, 0.75, 0.8)
		if day_night_cycle and day_night_cycle.is_night():
			base_fog_color = Color(0.15, 0.15, 0.2)
		env.fog_light_color = base_fog_color
	else:
		env.fog_enabled = false

	# Darken ambient during storms
	if sun_light and cloud_coverage > 0.5:
		var darkness_factor = 1.0 - (cloud_coverage - 0.5) * cloud_darkness
		sun_light.light_energy *= darkness_factor

func _update_particles() -> void:
	var is_raining = current_weather in [WeatherType.LIGHT_RAIN, WeatherType.RAIN, WeatherType.HEAVY_RAIN, WeatherType.STORM]
	var is_snowing = current_weather in [WeatherType.LIGHT_SNOW, WeatherType.SNOW, WeatherType.BLIZZARD]

	# Rain particles - much more visible
	rain_particles.emitting = is_raining and weather_intensity > 0.05
	if rain_particles.emitting:
		# Significantly more particles for visible rain
		var rain_amount = int(2000 + weather_intensity * 6000)
		rain_particles.amount = rain_amount
		# Adjust rain speed and spread for storms
		var mat = rain_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.initial_velocity_min = 35.0 + weather_intensity * 25.0
			mat.initial_velocity_max = 50.0 + weather_intensity * 30.0
			# More wind during storms
			var wind_strength = weather_intensity * 0.3
			mat.direction = Vector3(wind_strength, -1, wind_strength * 0.5).normalized()

	# Snow particles - more visible with turbulence
	snow_particles.emitting = is_snowing and weather_intensity > 0.05
	if snow_particles.emitting:
		var snow_amount = int(2000 + weather_intensity * 5000)
		snow_particles.amount = snow_amount
		snow_particles.lifetime = 8.0  # Fixed lifetime - enough to reach ground
		# Adjust turbulence and gravity for blizzard
		var mat = snow_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.turbulence_noise_strength = 1.5 + weather_intensity * 2.0
			# Add wind in blizzard but keep strong downward gravity
			mat.gravity = Vector3(weather_intensity * 3.0, -8.0 - weather_intensity * 4.0, weather_intensity * 2.0)

func _update_ground_snow(delta: float) -> void:
	var is_snowing = current_weather in [WeatherType.LIGHT_SNOW, WeatherType.SNOW, WeatherType.BLIZZARD]

	if is_snowing and weather_intensity > 0.1:
		# Snow is accumulating at constant rate (heavier snow = slightly faster)
		var rate_multiplier = 1.0 + (weather_intensity - 0.3) * 0.5  # 1.0 to 1.35x
		ground_snow_coverage = minf(ground_snow_coverage + delta * snow_accumulation_rate * rate_multiplier, max_snow_coverage)
	else:
		# Snow is melting at constant rate
		ground_snow_coverage = maxf(ground_snow_coverage - delta * snow_melt_rate, 0.0)

	# Lazily find terrain material if not yet found
	if not terrain_material:
		var parent = get_parent()
		if parent and "terrain_material" in parent:
			var mat = parent.get("terrain_material")
			if mat is ShaderMaterial:
				terrain_material = mat
				print("[WeatherManager] Found terrain shader material (deferred)")

	# Update terrain shader
	if terrain_material:
		terrain_material.set_shader_parameter("snow_coverage", ground_snow_coverage)

func _update_footprints(delta: float) -> void:
	# Only process footprints when there's snow
	if ground_snow_coverage < 0.1:
		return

	if not is_instance_valid(player_ref):
		return

	var player_pos_2d = Vector2(player_ref.global_position.x, player_ref.global_position.z)

	# Check if player is on ground (not jumping/falling)
	var player_on_ground = true
	if player_ref.has_method("is_on_floor"):
		player_on_ground = player_ref.is_on_floor()
	elif "velocity" in player_ref:
		player_on_ground = absf(player_ref.velocity.y) < 0.5

	# Update footprint center to follow player (with some hysteresis)
	var center_dist = footprint_center.distance_to(player_pos_2d)
	if center_dist > FOOTPRINT_WORLD_SIZE * 0.3:
		_shift_footprint_texture(player_pos_2d)

	# Add footprint if player moved enough and is on ground
	if player_on_ground:
		var move_dist = last_footprint_pos.distance_to(player_pos_2d)
		if move_dist >= FOOTPRINT_SPACING:
			_add_footprint(player_pos_2d)
			last_footprint_pos = player_pos_2d

	# Periodically fade footprints (snow fills them in) and update texture
	footprint_update_timer += delta
	if footprint_update_timer >= FOOTPRINT_UPDATE_INTERVAL:
		footprint_update_timer = 0.0

		# Fade footprints when snowing
		var is_snowing = current_weather in [WeatherType.LIGHT_SNOW, WeatherType.SNOW, WeatherType.BLIZZARD]
		if is_snowing and weather_intensity > 0.1:
			_fade_footprints(delta * 10.0)  # Multiply by 10 since we update every 0.1s

		# Update texture from image
		footprint_texture.update(footprint_image)

		# Update terrain shader
		if terrain_material:
			terrain_material.set_shader_parameter("footprint_texture", footprint_texture)
			terrain_material.set_shader_parameter("footprint_texture_center", footprint_center)
			terrain_material.set_shader_parameter("footprint_texture_size", FOOTPRINT_WORLD_SIZE)

func _add_footprint(world_pos: Vector2) -> void:
	# Convert world position to texture coordinates
	var offset = world_pos - footprint_center
	var uv = (offset / FOOTPRINT_WORLD_SIZE) + Vector2(0.5, 0.5)

	# Check bounds
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return

	var px = int(uv.x * FOOTPRINT_TEXTURE_SIZE)
	var py = int(uv.y * FOOTPRINT_TEXTURE_SIZE)

	# Draw footprint as elliptical foot shape (larger and more visible)
	# Foot is longer than wide
	var foot_length = 5  # pixels in Y direction
	var foot_width = 3   # pixels in X direction

	for dx in range(-foot_width - 1, foot_width + 2):
		for dy in range(-foot_length - 1, foot_length + 2):
			var fx = px + dx
			var fy = py + dy
			if fx >= 0 and fx < FOOTPRINT_TEXTURE_SIZE and fy >= 0 and fy < FOOTPRINT_TEXTURE_SIZE:
				# Elliptical distance
				var norm_x = float(dx) / float(foot_width) if foot_width > 0 else 0.0
				var norm_y = float(dy) / float(foot_length) if foot_length > 0 else 0.0
				var dist = sqrt(norm_x * norm_x + norm_y * norm_y)

				if dist <= 1.0:
					# Darker in center (0.05), lighter at edges (0.4)
					var intensity = 0.05 + 0.35 * dist
					var current = footprint_image.get_pixel(fx, fy).r
					footprint_image.set_pixel(fx, fy, Color(min(current, intensity), 0, 0, 1))

func _fade_footprints(delta: float) -> void:
	# Gradually fill footprints back in with snow
	var fade_amount = FOOTPRINT_FADE_RATE * delta * weather_intensity

	for y in range(FOOTPRINT_TEXTURE_SIZE):
		for x in range(FOOTPRINT_TEXTURE_SIZE):
			var current = footprint_image.get_pixel(x, y).r
			if current < 1.0:
				var new_val = minf(current + fade_amount, 1.0)
				footprint_image.set_pixel(x, y, Color(new_val, 0, 0, 1))

func _shift_footprint_texture(new_center: Vector2) -> void:
	# When player moves far from center, shift the texture
	# This creates a new image shifted to the new center
	var shift = new_center - footprint_center
	var shift_pixels = Vector2i(
		int(shift.x / FOOTPRINT_WORLD_SIZE * FOOTPRINT_TEXTURE_SIZE),
		int(shift.y / FOOTPRINT_WORLD_SIZE * FOOTPRINT_TEXTURE_SIZE)
	)

	# Create new image
	var new_image = Image.create(FOOTPRINT_TEXTURE_SIZE, FOOTPRINT_TEXTURE_SIZE, false, Image.FORMAT_R8)
	new_image.fill(Color(1.0, 1.0, 1.0, 1.0))  # Fresh snow

	# Copy old data shifted
	for y in range(FOOTPRINT_TEXTURE_SIZE):
		for x in range(FOOTPRINT_TEXTURE_SIZE):
			var src_x = x + shift_pixels.x
			var src_y = y + shift_pixels.y
			if src_x >= 0 and src_x < FOOTPRINT_TEXTURE_SIZE and src_y >= 0 and src_y < FOOTPRINT_TEXTURE_SIZE:
				new_image.set_pixel(x, y, footprint_image.get_pixel(src_x, src_y))

	footprint_image = new_image
	footprint_center = new_center

## Set snow coverage directly (for commands)
func set_snowpack(value: float) -> void:
	ground_snow_coverage = clampf(value, 0.0, 1.0)
	if terrain_material:
		terrain_material.set_shader_parameter("snow_coverage", ground_snow_coverage)
	print("[WeatherManager] Snowpack set to: %.0f%%" % (ground_snow_coverage * 100))

## Get current snowpack level
func get_snowpack() -> float:
	return ground_snow_coverage

## Set weather type by name (for commands)
func set_weather_by_name(name: String) -> bool:
	var lower_name = name.to_lower().replace(" ", "_")
	if lower_name in weather_from_name:
		set_weather(weather_from_name[lower_name])
		return true
	return false

## Get current weather name
func get_weather_name() -> String:
	return WEATHER_NAMES.get(current_weather, "unknown")

## Get all available weather names
func get_all_weather_names() -> Array:
	return WEATHER_NAMES.values()

## Set weather type
func set_weather(weather: WeatherType, instant: bool = false) -> void:
	target_weather = weather

	# Set target parameters based on weather type
	match weather:
		WeatherType.CLEAR:
			target_cloud_coverage = 0.0
			target_cloud_darkness = 0.0
			target_fog_density = 0.0
			target_intensity = 0.0

		WeatherType.PARTLY_CLOUDY:
			target_cloud_coverage = 0.3
			target_cloud_darkness = 0.0
			target_fog_density = 0.0
			target_intensity = 0.0

		WeatherType.CLOUDY:
			target_cloud_coverage = 0.6
			target_cloud_darkness = 0.1
			target_fog_density = 0.0
			target_intensity = 0.0

		WeatherType.OVERCAST:
			target_cloud_coverage = 0.9
			target_cloud_darkness = 0.3
			target_fog_density = 0.2
			target_intensity = 0.0

		WeatherType.LIGHT_RAIN:
			target_cloud_coverage = 0.7
			target_cloud_darkness = 0.3
			target_fog_density = 0.3
			target_intensity = 0.3

		WeatherType.RAIN:
			target_cloud_coverage = 0.85
			target_cloud_darkness = 0.5
			target_fog_density = 0.5
			target_intensity = 0.6

		WeatherType.HEAVY_RAIN:
			target_cloud_coverage = 0.95
			target_cloud_darkness = 0.7
			target_fog_density = 0.7
			target_intensity = 0.85

		WeatherType.STORM:
			target_cloud_coverage = 1.0
			target_cloud_darkness = 0.9
			target_fog_density = 0.6
			target_intensity = 1.0

		WeatherType.FOG:
			target_cloud_coverage = 0.4
			target_cloud_darkness = 0.1
			target_fog_density = 1.0
			target_intensity = 0.0

		WeatherType.LIGHT_SNOW:
			target_cloud_coverage = 0.6
			target_cloud_darkness = 0.1
			target_fog_density = 0.2
			target_intensity = 0.3

		WeatherType.SNOW:
			target_cloud_coverage = 0.8
			target_cloud_darkness = 0.2
			target_fog_density = 0.4
			target_intensity = 0.6

		WeatherType.BLIZZARD:
			target_cloud_coverage = 1.0
			target_cloud_darkness = 0.3
			target_fog_density = 0.9
			target_intensity = 1.0

	if instant:
		cloud_coverage = target_cloud_coverage
		cloud_darkness = target_cloud_darkness
		fog_density = target_fog_density
		weather_intensity = target_intensity

	current_weather = weather
	emit_signal("weather_changed", get_weather_name())
	print("[WeatherManager] Weather set to: %s" % get_weather_name())

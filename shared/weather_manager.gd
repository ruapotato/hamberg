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

# References
var world_environment: WorldEnvironment
var sky_material: ShaderMaterial
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

	# Find scene nodes
	call_deferred("_find_scene_nodes")
	call_deferred("_create_particle_systems")

	print("[WeatherManager] Initialized")

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
	snow_particles.amount = 1500
	snow_particles.lifetime = 4.0
	snow_particles.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
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
	mat.spread = 45.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -0.8, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(20, 3, 20)
	mat.color = Color(1.0, 1.0, 1.0, 1.0)
	# Turbulence for realistic drifting
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 2.5
	mat.turbulence_noise_speed_random = 0.8
	mat.turbulence_noise_scale = 4.0
	# Scale variation for different snowflake sizes
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	return mat

func _create_snow_mesh() -> QuadMesh:
	# Use quad instead of sphere for better visibility
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)  # Larger snowflakes

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # Always face camera
	mat.vertex_color_use_as_albedo = true
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
		var snow_amount = int(1000 + weather_intensity * 3000)
		snow_particles.amount = snow_amount
		snow_particles.lifetime = 5.0 - weather_intensity * 1.5  # Faster in blizzard
		# Adjust turbulence for blizzard
		var mat = snow_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.turbulence_noise_strength = 2.5 + weather_intensity * 4.0

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

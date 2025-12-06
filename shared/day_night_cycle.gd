extends Node
class_name DayNightCycle

## DayNightCycle - Manages time of day, sun position, and lighting
## Attach to TerrainWorld or add as autoload

const Equipment = preload("res://shared/equipment.gd")
const ArmorData = preload("res://shared/armor_data.gd")

signal time_changed(hour: float)
signal period_changed(period: String)  # "dawn", "day", "dusk", "night"

# Time settings
@export var day_length_minutes: float = 20.0  # Real minutes for a full day cycle
@export var start_hour: float = 8.0  # Starting hour (8 AM)

# Current time (0-24 hours)
var current_hour: float = 8.0
var current_period: String = "day"

# References to scene nodes (set in _ready or via export)
var sun_light: DirectionalLight3D
var world_environment: WorldEnvironment
var sky_material: ShaderMaterial

# Biome-based lighting
var current_biome: String = "valley"
var biome_ambient_multiplier: float = 1.0
var biome_sun_multiplier: float = 1.0
var biome_ambient_energy: float = 0.3
var biome_sky_contribution: float = 0.5
var target_ambient_multiplier: float = 1.0
var target_sun_multiplier: float = 1.0
var target_ambient_energy: float = 0.3
var target_sky_contribution: float = 0.5
const DARK_FOREST_AMBIENT_MULTIPLIER: float = 0.1  # 90% reduction - very dark!
const DARK_FOREST_SUN_MULTIPLIER: float = 0.15  # Sun is mostly blocked by trees
const DARK_FOREST_BIOMES: Array[String] = ["dark_forest"]
const BIOME_TRANSITION_SPEED: float = 1.5  # How fast to lerp (higher = faster)

# Cyclops Eye reduces the darkness effect in dark forest
const CYCLOPS_EYE_AMBIENT_MULTIPLIER: float = 0.5  # Only 50% reduction with Cyclops Eye
const CYCLOPS_EYE_SUN_MULTIPLIER: float = 0.4  # More sun visible
const CYCLOPS_EYE_AMBIENT_ENERGY: float = 0.15  # Better ambient light

# PERFORMANCE: Cached references to avoid get_tree() calls every frame
var _cached_player: Node3D = null
var _cached_terrain_world: Node = null
var _biome_check_timer: float = 0.0
const BIOME_CHECK_INTERVAL: float = 0.5  # Only check biome every 0.5 seconds

# Sun rotation (degrees)
const SUNRISE_HOUR: float = 6.0
const SUNSET_HOUR: float = 20.0
const NOON_HOUR: float = 12.0

# Light colors for different times
const COLOR_DAWN := Color(1.0, 0.7, 0.5)      # Warm orange sunrise
const COLOR_DAY := Color(1.0, 0.98, 0.95)     # Slightly warm white
const COLOR_DUSK := Color(1.0, 0.5, 0.3)      # Deep orange sunset
const COLOR_NIGHT := Color(0.3, 0.35, 0.5)    # Cool blue moonlight

# Light energy for different times
const ENERGY_DAWN: float = 0.8
const ENERGY_DAY: float = 1.2
const ENERGY_DUSK: float = 0.7
const ENERGY_NIGHT: float = 0.15

# Ambient light colors
const AMBIENT_DAWN := Color(0.6, 0.5, 0.5)
const AMBIENT_DAY := Color(0.6, 0.7, 0.8)
const AMBIENT_DUSK := Color(0.5, 0.4, 0.5)
const AMBIENT_NIGHT := Color(0.15, 0.15, 0.25)

# Sky top colors (zenith)
const SKY_TOP_DAWN := Color(0.6, 0.4, 0.5)
const SKY_TOP_DAY := Color(0.3, 0.5, 0.9)
const SKY_TOP_DUSK := Color(0.4, 0.2, 0.4)
const SKY_TOP_NIGHT := Color(0.02, 0.02, 0.08)

# Sky horizon colors
const SKY_HORIZON_DAWN := Color(1.0, 0.6, 0.4)
const SKY_HORIZON_DAY := Color(0.55, 0.7, 0.9)
const SKY_HORIZON_DUSK := Color(1.0, 0.4, 0.2)
const SKY_HORIZON_NIGHT := Color(0.05, 0.05, 0.12)

# Ground color (below horizon)
const GROUND_DAY := Color(0.25, 0.2, 0.15)
const GROUND_NIGHT := Color(0.02, 0.02, 0.03)

# Moon settings
var moon_phase: float = 0.5  # 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter
var lunar_day: float = 0.0  # Tracks which day in the lunar cycle
const LUNAR_CYCLE_DAYS: float = 8.0  # Full lunar cycle in game days (real moon is ~29.5)

func _ready() -> void:
	current_hour = start_hour
	_find_scene_nodes()
	_update_lighting()

func _find_scene_nodes() -> void:
	# Find DirectionalLight3D (sun) and WorldEnvironment in parent
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if child is DirectionalLight3D and not sun_light:
				sun_light = child
				print("[DayNightCycle] Found sun: %s" % child.name)
			if child is WorldEnvironment and not world_environment:
				world_environment = child
				print("[DayNightCycle] Found environment: %s" % child.name)

	if not sun_light:
		print("[DayNightCycle] WARNING: No DirectionalLight3D found!")
	if not world_environment:
		print("[DayNightCycle] WARNING: No WorldEnvironment found!")

	# Get sky shader material
	if world_environment and world_environment.environment:
		var env = world_environment.environment
		if env.sky and env.sky.sky_material is ShaderMaterial:
			sky_material = env.sky.sky_material
			print("[DayNightCycle] Found sky shader material")

func _process(delta: float) -> void:
	# Advance time
	var hours_per_second = 24.0 / (day_length_minutes * 60.0)
	current_hour += hours_per_second * delta

	# Wrap around at 24 hours
	if current_hour >= 24.0:
		current_hour -= 24.0

	# Advance lunar cycle (one full cycle over LUNAR_CYCLE_DAYS game days)
	var lunar_advance = delta / (day_length_minutes * 60.0 * LUNAR_CYCLE_DAYS)
	lunar_day = fmod(lunar_day + lunar_advance, 1.0)

	# PERFORMANCE: Only check player biome periodically instead of every frame
	_biome_check_timer += delta
	if _biome_check_timer >= BIOME_CHECK_INTERVAL:
		_biome_check_timer = 0.0
		_update_player_biome()

	# Smoothly lerp toward target biome lighting values
	biome_ambient_multiplier = lerpf(biome_ambient_multiplier, target_ambient_multiplier, delta * BIOME_TRANSITION_SPEED)
	biome_sun_multiplier = lerpf(biome_sun_multiplier, target_sun_multiplier, delta * BIOME_TRANSITION_SPEED)
	biome_ambient_energy = lerpf(biome_ambient_energy, target_ambient_energy, delta * BIOME_TRANSITION_SPEED)
	biome_sky_contribution = lerpf(biome_sky_contribution, target_sky_contribution, delta * BIOME_TRANSITION_SPEED)

	# Update lighting
	_update_lighting()

	# Check period changes
	var new_period = get_current_period()
	if new_period != current_period:
		current_period = new_period
		emit_signal("period_changed", current_period)

	emit_signal("time_changed", current_hour)

func _update_player_biome() -> void:
	# PERFORMANCE: Use cached player reference, only lookup if invalid
	if not is_instance_valid(_cached_player):
		var players = get_tree().get_nodes_in_group("local_player")
		_cached_player = players[0] if players.size() > 0 else null

	if not _cached_player:
		return

	# PERFORMANCE: Use cached terrain_world reference, only lookup if invalid
	if not is_instance_valid(_cached_terrain_world):
		var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
		_cached_terrain_world = terrain_worlds[0] if terrain_worlds.size() > 0 else null

	if not _cached_terrain_world or not _cached_terrain_world.has_method("get_biome_at"):
		return

	# Get biome at player position
	var pos = _cached_player.global_position
	var new_biome = _cached_terrain_world.get_biome_at(Vector2(pos.x, pos.z))

	# Check if player has Cyclops Eye equipped (reduces dark forest darkness)
	var has_cyclops_eye = _player_has_cyclops_eye()

	# Always update (not just on biome change) so equipment changes take effect
	current_biome = new_biome
	# Set target multipliers based on biome (will lerp toward these)
	if current_biome in DARK_FOREST_BIOMES:
		if has_cyclops_eye:
			# Cyclops Eye lets you see better in dark forest
			target_ambient_multiplier = CYCLOPS_EYE_AMBIENT_MULTIPLIER
			target_sun_multiplier = CYCLOPS_EYE_SUN_MULTIPLIER
			target_ambient_energy = CYCLOPS_EYE_AMBIENT_ENERGY
			target_sky_contribution = 0.1
		else:
			target_ambient_multiplier = DARK_FOREST_AMBIENT_MULTIPLIER
			target_sun_multiplier = DARK_FOREST_SUN_MULTIPLIER
			target_ambient_energy = 0.05
			target_sky_contribution = 0.0
	else:
		target_ambient_multiplier = 1.0
		target_sun_multiplier = 1.0
		target_ambient_energy = 0.3
		target_sky_contribution = 0.5

## Check if the local player has the Cyclops Eye accessory equipped
func _player_has_cyclops_eye() -> bool:
	if not is_instance_valid(_cached_player):
		return false

	var equipment_node = _cached_player.get_node_or_null("Equipment")
	if not equipment_node:
		return false

	var accessory_data = equipment_node.get_equipped_item_data(Equipment.EquipmentSlot.ACCESSORY)
	if accessory_data and accessory_data is ArmorData:
		return accessory_data.set_bonus == ArmorData.SetBonus.CYCLOPS_LIGHT

	return false

func _update_lighting() -> void:
	if sun_light:
		_update_sun_position()
		_update_sun_color()

	if world_environment:
		_update_environment()

	if sky_material:
		_update_sky()

func _update_sun_position() -> void:
	# Sun completes a full 360° orbit over 24 hours
	# Midnight (0:00) = sun directly below (nadir)
	# Noon (12:00) = sun directly above (zenith)
	# 6am = sun rising in east, 6pm = sun setting in west

	# Hour to angle: 0h = 0, 12h = PI, 24h = 2*PI
	var hour_angle = (current_hour / 24.0) * TAU

	# Sun height: highest at noon (+1), lowest at midnight (-1)
	var sun_height = -cos(hour_angle)

	# Horizontal position: +1 at 6am (east), -1 at 6pm (west), 0 at noon/midnight
	var sun_horizontal = sin(hour_angle)

	# Tilt the orbit plane so sun arcs through the southern sky
	var orbit_tilt = deg_to_rad(30.0)  # 30° tilt gives nice arc

	# Calculate sun position
	# X = east-west (positive = east)
	# Y = up-down (positive = up)
	# Z = north-south (negative = south, where sun arcs through)
	var sun_x = sun_horizontal
	var sun_y = sun_height * cos(orbit_tilt)
	var sun_z = -sun_height * sin(orbit_tilt)  # Negative so sun is to the south when high

	# Create sun position vector (where the sun actually is in the sky)
	var sun_pos = Vector3(sun_x, sun_y, sun_z).normalized() * 100.0

	# Point the directional light from sun position toward the world origin
	if sun_pos.length() > 0.001:
		# Handle edge case when sun is directly above/below
		var up_vec = Vector3.FORWARD if abs(sun_pos.normalized().y) > 0.99 else Vector3.UP
		sun_light.look_at_from_position(sun_pos, Vector3.ZERO, up_vec)

func _update_sun_color() -> void:
	var hour = current_hour
	var color: Color
	var energy: float

	if hour >= 5.0 and hour < 7.0:
		# Dawn transition (5-7)
		var t = (hour - 5.0) / 2.0
		color = COLOR_NIGHT.lerp(COLOR_DAWN, t)
		energy = lerpf(ENERGY_NIGHT, ENERGY_DAWN, t)
	elif hour >= 7.0 and hour < 9.0:
		# Morning transition (7-9)
		var t = (hour - 7.0) / 2.0
		color = COLOR_DAWN.lerp(COLOR_DAY, t)
		energy = lerpf(ENERGY_DAWN, ENERGY_DAY, t)
	elif hour >= 9.0 and hour < 18.0:
		# Full day (9-18)
		color = COLOR_DAY
		energy = ENERGY_DAY
	elif hour >= 18.0 and hour < 20.0:
		# Evening transition (18-20)
		var t = (hour - 18.0) / 2.0
		color = COLOR_DAY.lerp(COLOR_DUSK, t)
		energy = lerpf(ENERGY_DAY, ENERGY_DUSK, t)
	elif hour >= 20.0 and hour < 22.0:
		# Dusk to night (20-22) - extended to 2 hours for smoother transition
		var t = (hour - 20.0) / 2.0
		color = COLOR_DUSK.lerp(COLOR_NIGHT, t)
		energy = lerpf(ENERGY_DUSK, ENERGY_NIGHT, t)
	else:
		# Night (22-5)
		color = COLOR_NIGHT
		energy = ENERGY_NIGHT

	sun_light.light_color = color
	sun_light.light_energy = energy * biome_sun_multiplier

func _update_environment() -> void:
	var env = world_environment.environment
	if not env:
		return

	var hour = current_hour
	var ambient_color: Color

	if hour >= 5.0 and hour < 7.0:
		var t = (hour - 5.0) / 2.0
		ambient_color = AMBIENT_NIGHT.lerp(AMBIENT_DAWN, t)
	elif hour >= 7.0 and hour < 9.0:
		var t = (hour - 7.0) / 2.0
		ambient_color = AMBIENT_DAWN.lerp(AMBIENT_DAY, t)
	elif hour >= 9.0 and hour < 18.0:
		ambient_color = AMBIENT_DAY
	elif hour >= 18.0 and hour < 20.0:
		var t = (hour - 18.0) / 2.0
		ambient_color = AMBIENT_DAY.lerp(AMBIENT_DUSK, t)
	elif hour >= 20.0 and hour < 22.0:
		# Extended to 2 hours for smoother night transition
		var t = (hour - 20.0) / 2.0
		ambient_color = AMBIENT_DUSK.lerp(AMBIENT_NIGHT, t)
	else:
		ambient_color = AMBIENT_NIGHT

	# Apply biome-based ambient reduction (dark forest is darker)
	env.ambient_light_color = ambient_color * biome_ambient_multiplier

	# Apply lerped biome lighting values
	env.ambient_light_energy = biome_ambient_energy
	env.ambient_light_sky_contribution = biome_sky_contribution
	# Reflections: disable when sky contribution is very low
	env.reflected_light_source = 0 if biome_sky_contribution < 0.1 else 2

	# Fog settings - match fog to sky horizon color for seamless fade
	# Use smooth lerping instead of hard cut
	var sky_horizon: Color

	if hour >= 5.0 and hour < 7.0:
		# Dawn: night -> dawn horizon
		var t = (hour - 5.0) / 2.0
		sky_horizon = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAWN, t)
	elif hour >= 7.0 and hour < 9.0:
		# Morning: dawn -> day horizon
		var t = (hour - 7.0) / 2.0
		sky_horizon = SKY_HORIZON_DAWN.lerp(SKY_HORIZON_DAY, t)
	elif hour >= 9.0 and hour < 18.0:
		# Day
		sky_horizon = SKY_HORIZON_DAY
	elif hour >= 18.0 and hour < 20.0:
		# Evening: day -> dusk horizon
		var t = (hour - 18.0) / 2.0
		sky_horizon = SKY_HORIZON_DAY.lerp(SKY_HORIZON_DUSK, t)
	elif hour >= 20.0 and hour < 22.0:
		# Dusk to night: dusk -> night (extended to 2 hours for smoother transition)
		var t = (hour - 20.0) / 2.0
		sky_horizon = SKY_HORIZON_DUSK.lerp(SKY_HORIZON_NIGHT, t)
	else:
		# Night
		sky_horizon = SKY_HORIZON_NIGHT

	# Update fog wall manager colors (client only)
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.fog_wall_manager:
		client_node.fog_wall_manager.set_fog_color(sky_horizon)

func _update_sky() -> void:
	var hour = current_hour
	var sky_top: Color
	var sky_horizon: Color
	var ground: Color
	var star_brightness: float = 0.0

	if hour >= 5.0 and hour < 7.0:
		# Dawn
		var t = (hour - 5.0) / 2.0
		sky_top = SKY_TOP_NIGHT.lerp(SKY_TOP_DAWN, t)
		sky_horizon = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAWN, t)
		ground = GROUND_NIGHT.lerp(GROUND_DAY, t)
		star_brightness = 1.0 - t  # Stars fade out at dawn
	elif hour >= 7.0 and hour < 9.0:
		# Morning
		var t = (hour - 7.0) / 2.0
		sky_top = SKY_TOP_DAWN.lerp(SKY_TOP_DAY, t)
		sky_horizon = SKY_HORIZON_DAWN.lerp(SKY_HORIZON_DAY, t)
		ground = GROUND_DAY
		star_brightness = 0.0
	elif hour >= 9.0 and hour < 18.0:
		# Day
		sky_top = SKY_TOP_DAY
		sky_horizon = SKY_HORIZON_DAY
		ground = GROUND_DAY
		star_brightness = 0.0
	elif hour >= 18.0 and hour < 20.0:
		# Evening
		var t = (hour - 18.0) / 2.0
		sky_top = SKY_TOP_DAY.lerp(SKY_TOP_DUSK, t)
		sky_horizon = SKY_HORIZON_DAY.lerp(SKY_HORIZON_DUSK, t)
		ground = GROUND_DAY.lerp(GROUND_NIGHT, t)
		star_brightness = 0.0
	elif hour >= 20.0 and hour < 22.0:
		# Dusk to night - extended to 2 hours for smoother transition
		var t = (hour - 20.0) / 2.0
		sky_top = SKY_TOP_DUSK.lerp(SKY_TOP_NIGHT, t)
		sky_horizon = SKY_HORIZON_DUSK.lerp(SKY_HORIZON_NIGHT, t)
		ground = GROUND_NIGHT
		star_brightness = t  # Stars fade in at dusk
	else:
		# Night (22-5)
		sky_top = SKY_TOP_NIGHT
		sky_horizon = SKY_HORIZON_NIGHT
		ground = GROUND_NIGHT
		star_brightness = 1.0

	# Update shader parameters
	sky_material.set_shader_parameter("sky_top_color", Vector3(sky_top.r, sky_top.g, sky_top.b))
	sky_material.set_shader_parameter("sky_horizon_color", Vector3(sky_horizon.r, sky_horizon.g, sky_horizon.b))
	sky_material.set_shader_parameter("ground_color", Vector3(ground.r, ground.g, ground.b))
	sky_material.set_shader_parameter("star_brightness", star_brightness)

	# Update moon position and phase
	_update_moon()

## Get the current time period
func get_current_period() -> String:
	if current_hour >= 5.0 and current_hour < 7.0:
		return "dawn"
	elif current_hour >= 7.0 and current_hour < 18.0:
		return "day"
	elif current_hour >= 18.0 and current_hour < 22.0:
		return "dusk"
	else:
		return "night"

## Check if it's currently night (for gameplay effects)
func is_night() -> bool:
	return current_hour < 5.0 or current_hour >= 22.0

## Check if it's dark (dusk or night - enemies are stronger)
func is_dark() -> bool:
	return current_hour < 6.0 or current_hour >= 19.0

## Get current hour (0-24)
func get_hour() -> float:
	return current_hour

## Get formatted time string (e.g., "14:30")
func get_time_string() -> String:
	var hours = int(current_hour)
	var minutes = int((current_hour - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

## Get time with period (e.g., "2:30 PM")
func get_time_string_12h() -> String:
	var hours = int(current_hour)
	var minutes = int((current_hour - hours) * 60)
	var period = "AM" if hours < 12 else "PM"
	if hours == 0:
		hours = 12
	elif hours > 12:
		hours -= 12
	return "%d:%02d %s" % [hours, minutes, period]

## Set time directly (for debugging or server sync)
func set_time(hour: float) -> void:
	current_hour = fmod(hour, 24.0)
	if current_hour < 0:
		current_hour += 24.0
	_update_lighting()

## Update moon position and phase
func _update_moon() -> void:
	if not sky_material:
		return

	# Moon phase based on lunar day (updated in _process)
	moon_phase = lunar_day

	# Moon position - roughly opposite the sun, but offset by phase
	# At full moon (phase 0.5), moon rises at sunset and sets at sunrise
	# At new moon (phase 0), moon is near the sun (invisible)
	var moon_hour_offset = moon_phase * 12.0  # Phase shifts moon timing
	var moon_hour = fmod(current_hour + 12.0 - moon_hour_offset, 24.0)

	# Calculate moon position similar to sun but opposite
	var moon_angle = (moon_hour / 24.0) * TAU
	var moon_height = -cos(moon_angle)
	var moon_horizontal = sin(moon_angle)

	# Same tilt as sun orbit
	var orbit_tilt = deg_to_rad(30.0)
	var moon_x = moon_horizontal
	var moon_y = moon_height * cos(orbit_tilt)
	var moon_z = -moon_height * sin(orbit_tilt)

	var moon_dir = Vector3(moon_x, moon_y, moon_z).normalized()

	# Set shader parameters
	sky_material.set_shader_parameter("moon_direction", moon_dir)
	sky_material.set_shader_parameter("moon_phase", moon_phase)

## Get current moon phase name
func get_moon_phase_name() -> String:
	if moon_phase < 0.125:
		return "New Moon"
	elif moon_phase < 0.25:
		return "Waxing Crescent"
	elif moon_phase < 0.375:
		return "First Quarter"
	elif moon_phase < 0.5:
		return "Waxing Gibbous"
	elif moon_phase < 0.625:
		return "Full Moon"
	elif moon_phase < 0.75:
		return "Waning Gibbous"
	elif moon_phase < 0.875:
		return "Last Quarter"
	else:
		return "Waning Crescent"

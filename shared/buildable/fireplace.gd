extends "res://shared/buildable/buildable_object.gd"

## Fireplace - A campfire for warmth and cooking
## Can have a cooking station attached on top

var is_lit: bool = true
var has_cooking_station: bool = false
var cooking_station_node: Node3D = null

# PERFORMANCE: Proximity-based particle/light optimization
var fire_particles: GPUParticles3D = null
const PARTICLE_ACTIVATION_DISTANCE: float = 50.0  # Distance at which particles activate
const LIGHT_ACTIVATION_DISTANCE: float = 80.0  # Distance at which light activates
var _proximity_check_timer: float = 0.0
const PROXIMITY_CHECK_INTERVAL: float = 0.5  # Check every 0.5 seconds

@onready var fire_light: OmniLight3D = $FireLight
@onready var embers: MeshInstance3D = $Embers
@onready var cooking_attach_point: Marker3D = $CookingAttachPoint

func _ready() -> void:
	super._ready()
	add_to_group("fireplace")
	# Get fire particles reference
	fire_particles = get_node_or_null("FireParticles")
	_update_fire_state()

func _process(delta: float) -> void:
	# PERFORMANCE: Only check proximity periodically
	_proximity_check_timer += delta
	if _proximity_check_timer >= PROXIMITY_CHECK_INTERVAL:
		_proximity_check_timer = 0.0
		_update_proximity_effects()

func _update_fire_state() -> void:
	if fire_light:
		fire_light.visible = is_lit
	if embers:
		embers.visible = is_lit

func set_lit(lit: bool) -> void:
	is_lit = lit
	_update_fire_state()

func get_cooking_attach_position() -> Vector3:
	if cooking_attach_point:
		return cooking_attach_point.global_position
	return global_position + Vector3(0, 0.4, 0)

func attach_cooking_station(station: Node3D) -> void:
	has_cooking_station = true
	cooking_station_node = station

func detach_cooking_station() -> void:
	has_cooking_station = false
	cooking_station_node = null

## PERFORMANCE: Enable/disable particles and light based on player proximity
func _update_proximity_effects() -> void:
	if not is_lit:
		return

	# Find nearest player distance (uses cached player list)
	var min_distance := INF
	for player in EnemyAI._get_cached_players(get_tree()):
		if is_instance_valid(player):
			var dist := global_position.distance_to(player.global_position)
			if dist < min_distance:
				min_distance = dist

	# Enable/disable particles based on distance
	if fire_particles:
		fire_particles.emitting = min_distance < PARTICLE_ACTIVATION_DISTANCE

	# Enable/disable light based on distance (light has longer range than particles)
	if fire_light:
		fire_light.visible = min_distance < LIGHT_ACTIVATION_DISTANCE

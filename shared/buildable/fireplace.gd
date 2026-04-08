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

var _fire_crackle_player: AudioStreamPlayer3D = null

func _ready() -> void:
	super._ready()
	add_to_group("fireplace")
	# Get fire particles reference
	fire_particles = get_node_or_null("FireParticles")
	_update_fire_state()
	# Start fire crackle ambient sound loop
	if is_lit:
		_start_fire_crackle()

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
	if is_lit:
		_start_fire_crackle()
	else:
		_stop_fire_crackle()

func _start_fire_crackle() -> void:
	if _fire_crackle_player and is_instance_valid(_fire_crackle_player):
		return  # Already playing
	var stream = SoundManager._pick_stream("fire_crackle")
	if not stream:
		return
	_fire_crackle_player = AudioStreamPlayer3D.new()
	_fire_crackle_player.bus = "SFX"
	_fire_crackle_player.max_distance = 30.0
	_fire_crackle_player.unit_size = 3.0
	_fire_crackle_player.stream = stream
	_fire_crackle_player.volume_db = -6.0
	add_child(_fire_crackle_player)
	_fire_crackle_player.play()
	_fire_crackle_player.finished.connect(_on_fire_crackle_finished)

func _stop_fire_crackle() -> void:
	if _fire_crackle_player and is_instance_valid(_fire_crackle_player):
		_fire_crackle_player.stop()
		_fire_crackle_player.queue_free()
		_fire_crackle_player = null

func _on_fire_crackle_finished() -> void:
	if is_lit and _fire_crackle_player and is_instance_valid(_fire_crackle_player):
		var stream = SoundManager._pick_stream("fire_crackle")
		if stream:
			_fire_crackle_player.stream = stream
			_fire_crackle_player.play()

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

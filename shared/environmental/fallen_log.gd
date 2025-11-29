extends RigidBody3D

## FallenLog - A fallen tree trunk that can be split into smaller logs
## Physics-based - falls naturally and can be pushed by player
## Can be hit with axe or blunt weapons to split

@export var max_health: float = 60.0
@export var required_tool_type: String = "axe"

var chunk_position: Vector2i
var object_type: String = "fallen_log"
var object_id: int = -1

var current_health: float = 60.0
var is_destroyed: bool = false
var has_settled: bool = false
var settle_timer: float = 0.0

# Fall direction (set by spawner)
var fall_direction: Vector3 = Vector3.ZERO

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

func _ready() -> void:
	current_health = max_health

	# Apply initial tip-over impulse
	_apply_tip_impulse()

func _apply_tip_impulse() -> void:
	# Random fall direction if not set
	if fall_direction.length() < 0.1:
		var angle := randf() * TAU
		fall_direction = Vector3(cos(angle), 0, sin(angle))

	# Apply gentle torque to make the log tip over
	# Torque axis is perpendicular to fall direction
	var torque_axis := fall_direction.cross(Vector3.UP).normalized()
	var torque_strength := 150.0  # Very gentle - gravity does the work

	apply_torque_impulse(torque_axis * torque_strength)

	# Tiny nudge in fall direction
	apply_central_impulse(fall_direction * 5.0)

	print("[FallenLog] Applied tip impulse at %s" % global_position)

func _physics_process(delta: float) -> void:
	# Check if log has settled (stopped moving)
	if not has_settled:
		if linear_velocity.length() < 0.5 and angular_velocity.length() < 0.5:
			settle_timer += delta
			if settle_timer > 1.0:
				has_settled = true
				# Optionally freeze to save performance (but allow unfreezing if hit)
				# freeze = true
				print("[FallenLog] Settled at %s" % global_position)
		else:
			settle_timer = 0.0

## Check if a tool type can damage this object
func can_be_damaged_by(tool_type: String) -> bool:
	# Logs can be split with axe or blunt weapons
	if required_tool_type.is_empty() or required_tool_type == "any":
		return true
	return tool_type == "axe" or tool_type == "blunt"

func get_required_tool_type() -> String:
	return required_tool_type

## Take damage (local call - used when client is authoritative)
func take_damage(damage: float, hit_direction: Vector3 = Vector3.ZERO) -> bool:
	if is_destroyed:
		return false

	current_health -= damage
	print("[FallenLog] Took %.1f damage (%.1f/%.1f HP)" % [damage, current_health, max_health])

	# Create health bar on first damage
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(1.0)

	if health_bar:
		health_bar.update_health(current_health, max_health)

	# Play hit effect and apply small impulse
	_play_hit_effect(hit_direction)

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

## Apply damage from server (syncs health and shows effects)
func apply_server_damage(damage: float, new_health: float, new_max_health: float) -> void:
	if is_destroyed:
		return

	current_health = new_health
	max_health = new_max_health

	# Create health bar on first damage
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(1.0)

	if health_bar:
		health_bar.update_health(current_health, max_health)

	# Play hit effect
	_play_hit_effect(Vector3.ZERO)
	print("[FallenLog] Server damage: %.1f (%.1f/%.1f HP)" % [damage, current_health, max_health])

func _play_hit_effect(hit_direction: Vector3 = Vector3.ZERO) -> void:
	SoundManager.play_sound_varied("wood_hit", global_position)

	# Apply tiny impulse from hit - just a nudge
	if hit_direction.length() > 0.1:
		apply_central_impulse(-hit_direction.normalized() * 10.0)

## Destruction animation - server handles spawning split logs via RPC
func _on_destroyed() -> void:
	is_destroyed = true
	print("[FallenLog] Destroyed - server will spawn split logs")

	SoundManager.play_sound_varied("wood_split", global_position)

	# Disable physics
	freeze = true

	# Shrink and disappear
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

## Get split log positions for server to use
func get_split_positions() -> Array:
	var positions: Array = []

	# Get the log's current orientation to determine split positions
	var log_axis := -global_transform.basis.y.normalized()  # Cylinder axis after rotation
	var log_length := 5.0 * scale.x

	# 2 positions - one at each half
	for i in 2:
		var offset := (float(i) - 0.5) * log_length * 0.4
		var pos := global_position + log_axis * offset
		pos.y = maxf(pos.y, global_position.y)  # Don't spawn below current position
		positions.append([pos.x, pos.y, pos.z])

	return positions

## Get rotation for split logs
func get_split_rotation() -> float:
	return rotation.y

## Set the fall direction (called by spawner)
func set_fall_direction(dir: Vector3) -> void:
	fall_direction = dir.normalized() if dir.length() > 0.1 else Vector3.ZERO

# Standard environmental object interface
func set_chunk_position(chunk_pos: Vector2i) -> void:
	chunk_position = chunk_pos

func set_object_type(type: String) -> void:
	object_type = type

func get_object_type() -> String:
	return object_type

func set_object_id(id: int) -> void:
	object_id = id

func get_object_id() -> int:
	return object_id

func get_resource_drops() -> Dictionary:
	return {}

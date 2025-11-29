extends RigidBody3D

## SplitLog - A split log segment that drops wood when destroyed
## Physics-based - can be pushed and rolled by player
## Can be hit with any weapon (axe, blunt, even fists work but slowly)

@export var max_health: float = 45.0  # Takes ~1 spin attack to break (2 logs total)
@export var required_tool_type: String = ""  # Empty = any tool works

var chunk_position: Vector2i
var object_type: String = "split_log"
var object_id: int = -1

var current_health: float = 45.0
var is_destroyed: bool = false

# Resource drops (10-15 wood per split log)
var wood_drop_count: int = 12

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

func _ready() -> void:
	current_health = max_health
	# Random wood count (10-15 per split log)
	wood_drop_count = randi_range(10, 15)

	# Apply tiny random impulse so logs scatter slightly when spawned
	var scatter_dir := Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)).normalized()
	apply_central_impulse(scatter_dir * 5.0)
	apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))

## Check if a tool type can damage this object
func can_be_damaged_by(tool_type: String) -> bool:
	# Split logs can be hit with anything
	return true

func get_required_tool_type() -> String:
	return required_tool_type

## Take damage (local call - used when client is authoritative)
func take_damage(damage: float, hit_direction: Vector3 = Vector3.ZERO) -> bool:
	if is_destroyed:
		return false

	current_health -= damage
	print("[SplitLog] Took %.1f damage (%.1f/%.1f HP)" % [damage, current_health, max_health])

	# Create health bar on first damage
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(1.0)

	if health_bar:
		health_bar.update_health(current_health, max_health)

	# Play hit effect
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
	print("[SplitLog] Server damage: %.1f (%.1f/%.1f HP)" % [damage, current_health, max_health])

func _play_hit_effect(hit_direction: Vector3 = Vector3.ZERO) -> void:
	SoundManager.play_sound_varied("wood_hit", global_position)

	# Apply small impulse from hit - gentle nudge
	if hit_direction.length() > 0.1:
		apply_central_impulse(-hit_direction.normalized() * 15.0 + Vector3.UP * 5.0)
		apply_torque_impulse(Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3)))

## Called when destroyed - drops wood
func _on_destroyed() -> void:
	is_destroyed = true
	print("[SplitLog] Destroyed! Dropping %d wood" % wood_drop_count)

	SoundManager.play_sound_varied("wood_break", global_position)

	# Disable physics
	freeze = true

	# Destruction animation
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

## Get resource drops for this object
func get_resource_drops() -> Dictionary:
	return {"wood": wood_drop_count}

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

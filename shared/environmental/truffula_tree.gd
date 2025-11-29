extends Node3D

## TruffulaTree - A whimsical Dr. Seuss-style tree with multi-stage harvesting
## Requires an axe to chop. Falls over when destroyed, spawning a FallenLog.

@export var cull_distance: float = 150.0
@export var lod_distances: Array = [60.0, 100.0]
@export var fade_in_duration: float = 0.3
@export var fade_in_distance: float = 100.0

# Tree stats
@export var max_health: float = 100.0
@export var required_tool_type: String = "axe"  # Must use axe to damage

var chunk_position: Vector2i
var object_type: String = "truffula_tree"
var object_id: int = -1
var is_visible_in_range: bool = true
var current_lod: int = 0

# Health state
var current_health: float = 100.0
var is_destroyed: bool = false
var is_falling: bool = false

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

# Fallen log scene to spawn
const FALLEN_LOG_SCENE = preload("res://shared/environmental/fallen_log.tscn")

# Fade-in state
var is_fading_in: bool = false
var fade_timer: float = 0.0
var original_scale: Vector3 = Vector3.ONE
var target_scale: Vector3 = Vector3.ZERO
var initial_distance: float = 0.0
var skip_fade_in: bool = false

# LOD node references
var lod_nodes: Array = []

# Tree color (for variety)
var tuft_color: Color = Color(1.0, 0.4, 0.6)  # Pink default

func _ready() -> void:
	current_health = max_health

	# Find LOD nodes if they exist
	for child in get_children():
		if child.name.begins_with("LOD"):
			lod_nodes.append(child)

	# Start with LOD0 visible
	if lod_nodes.size() > 0:
		for i in lod_nodes.size():
			lod_nodes[i].visible = (i == 0)

	# Start fade-in effect
	if fade_in_duration > 0.0 and not skip_fade_in and initial_distance > fade_in_distance:
		if target_scale != Vector3.ZERO:
			original_scale = target_scale
		else:
			original_scale = scale
		scale = Vector3.ZERO
		is_fading_in = true
		fade_timer = 0.0
	else:
		if target_scale != Vector3.ZERO:
			scale = target_scale

func _process(delta: float) -> void:
	if is_fading_in:
		fade_timer += delta
		var progress := minf(fade_timer / fade_in_duration, 1.0)
		var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
		scale = original_scale * eased_progress

		if progress >= 1.0:
			is_fading_in = false
			scale = original_scale

func update_visibility(nearest_distance: float) -> void:
	var should_be_visible := nearest_distance <= cull_distance

	if should_be_visible != is_visible_in_range:
		is_visible_in_range = should_be_visible
		visible = should_be_visible

	if should_be_visible and lod_nodes.size() > 1 and lod_distances.size() > 0:
		_update_lod(nearest_distance)

func _update_lod(distance: float) -> void:
	var new_lod := 0

	for i in lod_distances.size():
		if distance > lod_distances[i]:
			new_lod = i + 1

	new_lod = mini(new_lod, lod_nodes.size() - 1)

	if new_lod != current_lod:
		lod_nodes[current_lod].visible = false
		lod_nodes[new_lod].visible = true
		current_lod = new_lod

## Check if a tool type can damage this object
func can_be_damaged_by(tool_type: String) -> bool:
	if required_tool_type.is_empty() or required_tool_type == "any":
		return true
	return tool_type == required_tool_type

## Get the required tool type for UI feedback
func get_required_tool_type() -> String:
	return required_tool_type

## Take damage (SERVER-SIDE ONLY)
func take_damage(damage: float, hit_direction: Vector3 = Vector3.ZERO) -> bool:
	if is_destroyed or is_falling:
		return false

	current_health -= damage
	print("[TruffulaTree] Took %.1f damage (%.1f/%.1f HP)" % [damage, current_health, max_health])

	# Create health bar on first damage
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		# Position above the tuft
		health_bar.set_height_offset(8.0)

	if health_bar:
		health_bar.update_health(current_health, max_health)

	# Play hit effect
	_play_hit_effect()

	if current_health <= 0.0:
		_start_falling(hit_direction)
		return true

	return false

## Play a shake/wobble effect when hit
func _play_hit_effect() -> void:
	var tween := create_tween()
	var original_rot := rotation
	# Quick wobble
	tween.tween_property(self, "rotation:x", original_rot.x + 0.05, 0.05)
	tween.tween_property(self, "rotation:x", original_rot.x - 0.03, 0.05)
	tween.tween_property(self, "rotation:x", original_rot.x, 0.05)

## Start the falling animation
func _start_falling(hit_direction: Vector3) -> void:
	is_falling = true
	is_destroyed = true

	# Determine fall direction (away from hit, or random if no direction)
	var fall_direction := Vector3.ZERO
	if hit_direction.length() > 0.1:
		fall_direction = -hit_direction.normalized()
		fall_direction.y = 0
		fall_direction = fall_direction.normalized()
	else:
		# Random fall direction
		var angle := randf() * TAU
		fall_direction = Vector3(cos(angle), 0, sin(angle))

	# Calculate target rotation (fall 90 degrees in fall direction)
	var fall_angle := atan2(fall_direction.x, fall_direction.z)

	# Hide health bar during fall
	if health_bar:
		health_bar.visible = false

	# Disable collision during fall
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true

	# Play falling sound
	SoundManager.play_sound_varied("tree_fall", global_position)

	# Animate the fall
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)

	# Rotate to fall over (rotate around the base)
	var target_rotation := Vector3(0, fall_angle, PI / 2)  # 90 degrees on Z axis
	tween.tween_property(self, "rotation", target_rotation, 1.2)

	# When fall completes, spawn the log
	tween.tween_callback(_spawn_fallen_log.bind(fall_direction))

## Spawn a fallen log at this position
func _spawn_fallen_log(fall_direction: Vector3) -> void:
	print("[TruffulaTree] Spawning fallen log at %s" % global_position)

	# Play crash sound
	SoundManager.play_sound_varied("tree_impact", global_position)

	# Get the parent to add the log to
	var parent_node := get_parent()
	if not parent_node:
		queue_free()
		return

	# Instance the fallen log
	var log_instance = FALLEN_LOG_SCENE.instantiate()
	parent_node.add_child(log_instance)

	# Position the log where the tree was, offset along fall direction
	var log_offset := fall_direction * 3.0  # Offset so it's where trunk fell
	log_instance.global_position = global_position + log_offset + Vector3(0, 0.3, 0)

	# Rotate log to match fall direction
	log_instance.rotation.y = atan2(fall_direction.x, fall_direction.z)

	# Copy chunk info
	if log_instance.has_method("set_chunk_position"):
		log_instance.set_chunk_position(chunk_position)

	# Scale based on tree scale
	var log_scale := scale.y * 0.8
	log_instance.scale = Vector3(log_scale, log_scale, log_scale)

	# Remove the tree
	queue_free()

## Set the tuft color (called during spawn for variety)
func set_tuft_color(color: Color) -> void:
	tuft_color = color
	# Apply to LOD0 tuft mesh
	var lod0 = get_node_or_null("LOD0")
	if lod0:
		var tuft = lod0.get_node_or_null("Tuft")
		if tuft and tuft is MeshInstance3D:
			var mat = tuft.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color = color

# Standard environmental object interface
func set_chunk_position(chunk_pos: Vector2i) -> void:
	chunk_position = chunk_pos

func set_object_type(type: String) -> void:
	object_type = type

func set_target_scale(scl: Vector3) -> void:
	target_scale = scl

func set_initial_distance(distance: float) -> void:
	initial_distance = distance

func get_object_type() -> String:
	return object_type

func set_object_id(id: int) -> void:
	object_id = id

func get_object_id() -> int:
	return object_id

func get_resource_drops() -> Dictionary:
	# Trees don't drop resources directly - they spawn logs
	return {}

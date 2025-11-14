extends Node3D

## Base class for environmental objects with distance-based culling and LOD
## Handles visibility management based on nearest player distance

@export var cull_distance: float = 200.0  ## Distance at which object becomes invisible
@export var lod_distances: Array = []  ## Distances for LOD transitions (if applicable)
@export var fade_in_duration: float = 0.3  ## How long to fade in when spawning (seconds)
@export var fade_in_distance: float = 150.0  ## Objects closer than this spawn instantly

# Resource system
@export var max_health: float = 100.0  ## Health points (trees ~100, rocks ~150, grass ~10)
@export var resource_drops: Dictionary = {}  ## Resources dropped when destroyed {"wood": 3, "stone": 0}
@export var rare_drops: Dictionary = {}  ## Rare drops with chance {"resin": 0.2} means 20% chance

var chunk_position: Vector2i  ## Which chunk this object belongs to
var object_type: String = ""  ## Type identifier (tree, rock, grass, etc.)
var object_id: int = -1  ## ID within the chunk (set by chunk manager)
var is_visible_in_range: bool = true
var current_lod: int = 0

# Health state
var current_health: float = 100.0
var is_destroyed: bool = false

# Fade-in state
var is_fading_in: bool = false
var fade_timer: float = 0.0
var original_scale: Vector3 = Vector3.ONE
var target_scale: Vector3 = Vector3.ZERO  # Will be set before _ready() for loaded objects
var initial_distance: float = 0.0  # Distance to nearest player when spawned
var skip_fade_in: bool = false  # Set to true to spawn instantly

# LOD node references (populated by child scenes)
var lod_nodes: Array = []

func _ready() -> void:
	# Initialize health
	current_health = max_health

	# Find LOD nodes if they exist
	for child in get_children():
		if child.name.begins_with("LOD"):
			lod_nodes.append(child)

	# Start with LOD0 visible if LODs exist
	if lod_nodes.size() > 0:
		for i in lod_nodes.size():
			lod_nodes[i].visible = (i == 0)

	# Start fade-in effect (only if far enough from player)
	if fade_in_duration > 0.0 and not skip_fade_in and initial_distance > fade_in_distance:
		# Use target_scale if set (for loaded objects), otherwise use current scale
		if target_scale != Vector3.ZERO:
			original_scale = target_scale
		else:
			original_scale = scale
		scale = Vector3.ZERO
		is_fading_in = true
		fade_timer = 0.0
	else:
		# Spawn instantly (too close to player)
		if target_scale != Vector3.ZERO:
			scale = target_scale

func _process(delta: float) -> void:
	if is_fading_in:
		fade_timer += delta
		var progress := minf(fade_timer / fade_in_duration, 1.0)

		# Ease-out cubic interpolation for smooth fade
		var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
		scale = original_scale * eased_progress

		if progress >= 1.0:
			is_fading_in = false
			scale = original_scale

## Update visibility and LOD based on nearest player distance
func update_visibility(nearest_distance: float) -> void:
	var should_be_visible := nearest_distance <= cull_distance

	if should_be_visible != is_visible_in_range:
		is_visible_in_range = should_be_visible
		visible = should_be_visible

	# Update LOD if object is visible and has LOD levels
	if should_be_visible and lod_nodes.size() > 1 and lod_distances.size() > 0:
		_update_lod(nearest_distance)

func _update_lod(distance: float) -> void:
	var new_lod := 0

	# Determine which LOD level to use
	for i in lod_distances.size():
		if distance > lod_distances[i]:
			new_lod = i + 1

	# Clamp to available LOD levels
	new_lod = mini(new_lod, lod_nodes.size() - 1)

	# Switch LOD if changed
	if new_lod != current_lod:
		lod_nodes[current_lod].visible = false
		lod_nodes[new_lod].visible = true
		current_lod = new_lod

## Set the chunk this object belongs to
func set_chunk_position(chunk_pos: Vector2i) -> void:
	chunk_position = chunk_pos

## Set the object type (tree, rock, grass, etc.)
func set_object_type(type: String) -> void:
	object_type = type

## Set target scale (for loaded objects that should fade in to this scale)
func set_target_scale(scl: Vector3) -> void:
	target_scale = scl

## Set initial distance from player (used to determine if fade-in should happen)
func set_initial_distance(distance: float) -> void:
	initial_distance = distance

## Get the object type name (for spawning/pooling)
func get_object_type() -> String:
	if object_type.is_empty():
		return name.split("@")[0]  # Fallback: Remove instance suffix from node name
	return object_type

## Set the object ID within its chunk
func set_object_id(id: int) -> void:
	object_id = id

## Get the object ID
func get_object_id() -> int:
	return object_id

## Take damage (SERVER-SIDE ONLY)
## Returns true if object was destroyed
func take_damage(damage: float) -> bool:
	if is_destroyed:
		return false

	current_health -= damage
	print("[EnvironmentalObject] %s took %.1f damage (%.1f/%.1f HP)" % [get_object_type(), damage, current_health, max_health])

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

## Called when object is destroyed
func _on_destroyed() -> void:
	is_destroyed = true
	print("[EnvironmentalObject] %s destroyed! Dropping resources: %s" % [get_object_type(), resource_drops])

	# Visual destruction effect (simple for now)
	_play_destruction_effect()

## Play destruction visual effect
func _play_destruction_effect() -> void:
	# Simple scale-down animation
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

## Get resource drops for this object (includes rare drops based on chance)
func get_resource_drops() -> Dictionary:
	var drops = resource_drops.duplicate()

	# Roll for rare drops
	for rare_item in rare_drops:
		var drop_chance: float = rare_drops[rare_item]
		if randf() < drop_chance:
			# Add rare drop (1 item)
			if drops.has(rare_item):
				drops[rare_item] += 1
			else:
				drops[rare_item] = 1
			print("[EnvironmentalObject] Rare drop! %s" % rare_item)

	return drops

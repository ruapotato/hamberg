extends Node3D

## Base class for environmental objects with distance-based culling and LOD
## Handles visibility management based on nearest player distance

@export var cull_distance: float = 200.0  ## Distance at which object becomes invisible
@export var lod_distances: Array = []  ## Distances for LOD transitions (if applicable)
@export var fade_in_duration: float = 0.3  ## How long to fade in when spawning (seconds)
@export var fade_in_distance: float = 150.0  ## Objects closer than this spawn instantly

var chunk_position: Vector2i  ## Which chunk this object belongs to
var object_type: String = ""  ## Type identifier (tree, rock, grass, etc.)
var is_visible_in_range: bool = true
var current_lod: int = 0

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

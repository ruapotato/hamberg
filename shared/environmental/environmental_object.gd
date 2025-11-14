extends Node3D

## Base class for environmental objects with distance-based culling and LOD
## Handles visibility management based on nearest player distance

@export var cull_distance: float = 100.0  ## Distance at which object becomes invisible
@export var lod_distances: Array = []  ## Distances for LOD transitions (if applicable)

var chunk_position: Vector2i  ## Which chunk this object belongs to
var is_visible_in_range: bool = true
var current_lod: int = 0

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

## Get the object type name (for spawning/pooling)
func get_object_type() -> String:
	return name.split("@")[0]  # Remove instance suffix

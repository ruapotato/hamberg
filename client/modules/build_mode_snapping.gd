class_name BuildModeSnapping
extends RefCounted

## BuildModeSnapping - Handles all snap point logic for building

var build_mode: Node

# Snap detection radius
const SNAP_RADIUS: float = 2.5
const GRID_SIZE: float = 2.0

func _init(bm: Node) -> void:
	build_mode = bm

# =============================================================================
# MAIN SNAP ROUTER
# =============================================================================

## Find nearest snap point for current piece
func find_nearest_snap_point(piece_name: String, ray_result: Dictionary) -> Dictionary:
	if ray_result.is_empty():
		return {}

	var hit_pos = ray_result.position
	var hit_normal = ray_result.normal
	var hit_object = ray_result.collider

	# Route to specific snap handler based on piece type
	match piece_name:
		"wooden_floor":
			return find_floor_snap(hit_pos, hit_normal, hit_object)
		"wooden_wall":
			return find_wall_snap(hit_pos, hit_normal, hit_object)
		"wooden_door":
			return find_door_snap(hit_pos, hit_normal, hit_object)
		"wooden_stairs":
			return find_stairs_snap(hit_pos, hit_normal, hit_object)
		"wooden_roof_26", "wooden_roof_45":
			return find_roof_snap(hit_pos, hit_normal, hit_object)
		_:
			return find_ground_snap(hit_pos, hit_normal)

# =============================================================================
# FLOOR SNAPPING
# =============================================================================

## Find snap point for floor pieces
func find_floor_snap(hit_pos: Vector3, hit_normal: Vector3, hit_object: Object) -> Dictionary:
	# First check for floor-to-floor corner snapping
	var corner_snap = find_floor_corner_snap(hit_pos, hit_object)
	if not corner_snap.is_empty():
		return corner_snap

	# Check for floor on wall top
	var wall_top_snap = find_floor_on_wall_top_snap(hit_pos, hit_object)
	if not wall_top_snap.is_empty():
		return wall_top_snap

	# Default to grid snapping on ground
	return find_floor_grid_snap(hit_pos, hit_normal)

## Find floor-to-floor corner snap
func find_floor_corner_snap(hit_pos: Vector3, hit_object: Object) -> Dictionary:
	if not hit_object or not hit_object.is_in_group("buildables"):
		return {}

	if not "piece_name" in hit_object or hit_object.piece_name != "wooden_floor":
		return {}

	# Get the floor's corners
	var floor_pos = hit_object.global_position
	var floor_rot = hit_object.rotation.y
	var half_size = GRID_SIZE / 2.0

	var corners = [
		floor_pos + Vector3(half_size, 0, half_size).rotated(Vector3.UP, floor_rot),
		floor_pos + Vector3(half_size, 0, -half_size).rotated(Vector3.UP, floor_rot),
		floor_pos + Vector3(-half_size, 0, half_size).rotated(Vector3.UP, floor_rot),
		floor_pos + Vector3(-half_size, 0, -half_size).rotated(Vector3.UP, floor_rot),
	]

	# Find closest corner
	var closest_dist = SNAP_RADIUS
	var snap_pos = Vector3.ZERO

	for corner in corners:
		var dist = hit_pos.distance_to(corner)
		if dist < closest_dist:
			closest_dist = dist
			# Snap position is offset from corner
			var dir = (corner - floor_pos).normalized()
			snap_pos = corner + dir * half_size
			snap_pos.y = floor_pos.y

	if snap_pos != Vector3.ZERO:
		return {"position": snap_pos, "rotation": floor_rot, "snapped": true}

	return {}

## Find floor on wall top snap
func find_floor_on_wall_top_snap(hit_pos: Vector3, hit_object: Object) -> Dictionary:
	if not hit_object or not hit_object.is_in_group("buildables"):
		return {}

	if not "piece_name" in hit_object or hit_object.piece_name != "wooden_wall":
		return {}

	# Place floor on top of wall
	var wall_pos = hit_object.global_position
	var wall_rot = hit_object.rotation.y
	var wall_height = 2.0  # Standard wall height

	var snap_pos = wall_pos + Vector3(0, wall_height, 0)

	return {"position": snap_pos, "rotation": wall_rot, "snapped": true}

## Find grid-based floor snap
func find_floor_grid_snap(hit_pos: Vector3, hit_normal: Vector3) -> Dictionary:
	# Only snap to relatively flat surfaces
	if hit_normal.y < 0.7:
		return {}

	# Snap to grid
	var snapped_pos = Vector3(
		round(hit_pos.x / GRID_SIZE) * GRID_SIZE,
		hit_pos.y,
		round(hit_pos.z / GRID_SIZE) * GRID_SIZE
	)

	return {"position": snapped_pos, "rotation": 0.0, "snapped": true}

# =============================================================================
# WALL SNAPPING
# =============================================================================

## Find snap point for wall pieces
func find_wall_snap(hit_pos: Vector3, hit_normal: Vector3, hit_object: Object) -> Dictionary:
	# Check for wall stacking (wall on wall)
	var stack_snap = find_wall_stack_snap(hit_pos, hit_object)
	if not stack_snap.is_empty():
		return stack_snap

	# Check for wall on floor edge
	var floor_snap = find_wall_on_floor_snap(hit_pos, hit_object)
	if not floor_snap.is_empty():
		return floor_snap

	# Default ground placement
	return find_ground_snap(hit_pos, hit_normal)

## Find wall-to-wall stacking snap
func find_wall_stack_snap(hit_pos: Vector3, hit_object: Object) -> Dictionary:
	if not hit_object or not hit_object.is_in_group("buildables"):
		return {}

	if not "piece_name" in hit_object or hit_object.piece_name != "wooden_wall":
		return {}

	var wall_pos = hit_object.global_position
	var wall_rot = hit_object.rotation.y
	var wall_height = 2.0

	# Check if hitting top of wall
	if hit_pos.y > wall_pos.y + wall_height * 0.5:
		var snap_pos = wall_pos + Vector3(0, wall_height, 0)
		return {"position": snap_pos, "rotation": wall_rot, "snapped": true}

	return {}

## Find wall on floor edge snap
func find_wall_on_floor_snap(hit_pos: Vector3, hit_object: Object) -> Dictionary:
	if not hit_object or not hit_object.is_in_group("buildables"):
		return {}

	if not "piece_name" in hit_object or hit_object.piece_name != "wooden_floor":
		return {}

	var floor_pos = hit_object.global_position
	var floor_rot = hit_object.rotation.y
	var half_size = GRID_SIZE / 2.0

	# Find closest edge
	var edges = [
		{"pos": floor_pos + Vector3(0, 0, half_size).rotated(Vector3.UP, floor_rot), "rot": floor_rot},
		{"pos": floor_pos + Vector3(0, 0, -half_size).rotated(Vector3.UP, floor_rot), "rot": floor_rot + PI},
		{"pos": floor_pos + Vector3(half_size, 0, 0).rotated(Vector3.UP, floor_rot), "rot": floor_rot + PI/2},
		{"pos": floor_pos + Vector3(-half_size, 0, 0).rotated(Vector3.UP, floor_rot), "rot": floor_rot - PI/2},
	]

	var closest_dist = SNAP_RADIUS
	var best_snap = {}

	for edge in edges:
		var dist = hit_pos.distance_to(edge.pos)
		if dist < closest_dist:
			closest_dist = dist
			best_snap = {"position": edge.pos, "rotation": edge.rot, "snapped": true}

	return best_snap

# =============================================================================
# DOOR SNAPPING
# =============================================================================

## Find snap point for door
func find_door_snap(hit_pos: Vector3, hit_normal: Vector3, hit_object: Object) -> Dictionary:
	# Doors snap like walls but need wall-sized opening
	return find_wall_snap(hit_pos, hit_normal, hit_object)

# =============================================================================
# STAIRS SNAPPING
# =============================================================================

## Find snap point for stairs
func find_stairs_snap(hit_pos: Vector3, hit_normal: Vector3, hit_object: Object) -> Dictionary:
	# Check for stair chaining
	if hit_object and hit_object.is_in_group("buildables"):
		if "piece_name" in hit_object and hit_object.piece_name == "wooden_stairs":
			var stairs_pos = hit_object.global_position
			var stairs_rot = hit_object.rotation.y
			var stair_height = 2.0

			# Snap above for continuing staircase
			var snap_pos = stairs_pos + Vector3(0, stair_height, -GRID_SIZE).rotated(Vector3.UP, stairs_rot)
			return {"position": snap_pos, "rotation": stairs_rot, "snapped": true}

	return find_ground_snap(hit_pos, hit_normal)

# =============================================================================
# ROOF SNAPPING
# =============================================================================

## Find snap point for roof pieces
func find_roof_snap(hit_pos: Vector3, hit_normal: Vector3, hit_object: Object) -> Dictionary:
	if hit_object and hit_object.is_in_group("buildables"):
		# Snap to wall tops
		if "piece_name" in hit_object and hit_object.piece_name == "wooden_wall":
			var wall_pos = hit_object.global_position
			var wall_rot = hit_object.rotation.y
			var wall_height = 2.0

			var snap_pos = wall_pos + Vector3(0, wall_height, 0)
			return {"position": snap_pos, "rotation": wall_rot, "snapped": true}

		# Snap to other roof pieces
		if "piece_name" in hit_object and hit_object.piece_name.begins_with("wooden_roof"):
			var roof_pos = hit_object.global_position
			var roof_rot = hit_object.rotation.y

			# Adjacent placement
			var snap_pos = roof_pos + Vector3(GRID_SIZE, 0, 0).rotated(Vector3.UP, roof_rot)
			return {"position": snap_pos, "rotation": roof_rot, "snapped": true}

	return find_ground_snap(hit_pos, hit_normal)

# =============================================================================
# GROUND SNAP
# =============================================================================

## Default ground placement
func find_ground_snap(hit_pos: Vector3, hit_normal: Vector3) -> Dictionary:
	# Basic placement on surface
	return {"position": hit_pos, "rotation": 0.0, "snapped": false}

# =============================================================================
# HELPERS
# =============================================================================

## Check if a position is occupied by another buildable
func is_position_occupied(position: Vector3, exclude_node: Node = null) -> bool:
	for buildable in build_mode.get_tree().get_nodes_in_group("buildables"):
		if buildable == exclude_node:
			continue
		if buildable.global_position.distance_to(position) < 0.5:
			return true
	return false

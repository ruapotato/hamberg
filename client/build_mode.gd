extends Node

## BuildMode - Valheim-style build mode for placing structures
## Activated when player has hammer equipped

signal build_piece_placed(piece_name: String, position: Vector3, rotation: float)

# Building pieces available (populated from resources)
var available_pieces: Dictionary = {
	"wooden_wall": preload("res://shared/buildable/wooden_wall.tscn"),
	"wooden_floor": preload("res://shared/buildable/wooden_floor.tscn"),
	"wooden_door": preload("res://shared/buildable/wooden_door.tscn"),
	"wooden_beam": preload("res://shared/buildable/wooden_beam.tscn"),
	"wooden_roof": preload("res://shared/buildable/wooden_roof.tscn"),
	"workbench": preload("res://shared/buildable/workbench.tscn"),
}

var is_active: bool = false
var current_piece_name: String = "wooden_wall"
var current_piece_index: int = 0
var piece_names: Array = []

# Ghost preview
var ghost_preview: Node3D = null
var placement_distance: float = 5.0
var can_place_current: bool = false

# Snapping
var snap_distance_threshold: float = 50.0  # Very aggressive - snap from anywhere nearby
var is_snapped_to_piece: bool = false  # Whether currently snapped to another piece
var snap_search_radius: float = 10.0  # Radius to search for nearby pieces
var debug_snap: bool = false  # Enable debug logging for snapping
var placed_buildables: Dictionary = {}  # Track placed positions to avoid duplicate snaps

# References
var player: Node3D = null
var camera: Camera3D = null
var world: Node3D = null

func _ready() -> void:
	piece_names = available_pieces.keys()
	piece_names.sort()

func activate(p_player: Node3D, p_camera: Camera3D, p_world: Node3D) -> void:
	if is_active:
		return

	player = p_player
	camera = p_camera
	world = p_world
	is_active = true

	_create_ghost_preview()
	print("[BuildMode] Activated - Use mouse wheel to cycle pieces, left-click to place, R to rotate")
	print("[BuildMode] Current piece: %s (1/%d)" % [current_piece_name, piece_names.size()])

func deactivate() -> void:
	if not is_active:
		return

	is_active = false
	_destroy_ghost_preview()
	print("[BuildMode] Deactivated")

func _process(_delta: float) -> void:
	if not is_active:
		return

	if ghost_preview:
		_update_ghost_position()

	_handle_input()

func _create_ghost_preview() -> void:
	if not available_pieces.has(current_piece_name):
		return

	var piece_scene = available_pieces[current_piece_name]
	ghost_preview = piece_scene.instantiate()
	ghost_preview.is_preview = true

	world.add_child(ghost_preview)
	ghost_preview._setup_preview_mode()

func _destroy_ghost_preview() -> void:
	if ghost_preview:
		ghost_preview.queue_free()
		ghost_preview = null

func _update_ghost_position() -> void:
	if not camera or not ghost_preview:
		return

	# Raycast from camera forward
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * placement_distance)

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World layer

	var result = space_state.intersect_ray(query)

	var target_position: Vector3
	var target_rotation: float = ghost_preview.rotation.y  # Preserve current rotation
	is_snapped_to_piece = false

	if result:
		var hit_point = result.position
		var hit_normal = result.normal

		# Special handling if we hit an existing floor piece directly
		var hit_object = result.get("collider")
		if hit_object and ("piece_name" in hit_object) and hit_object.piece_name == "wooden_floor" and current_piece_name == "wooden_floor":
			# Use the hit floor as reference for finding adjacent positions
			var snap_result = _find_nearest_snap_point(hit_object.global_position)

			if snap_result.has("position"):
				target_position = snap_result.position
				target_rotation = snap_result.get("rotation", 0.0)
				is_snapped_to_piece = true
			else:
				# No valid adjacent position found, use ground placement
				if ghost_preview.snap_to_grid:
					var grid = ghost_preview.grid_size
					hit_point.x = round(hit_point.x / grid.x) * grid.x
					hit_point.z = round(hit_point.z / grid.z) * grid.z

				if hit_normal.y > 0.5:
					var offset_y = ghost_preview.grid_size.y / 2.0
					hit_point.y += offset_y

				target_position = hit_point
		else:
			# Try to find nearby snap point first
			var snap_result = _find_nearest_snap_point(hit_point)

			if snap_result.has("position"):
				# Snap to nearby piece!
				target_position = snap_result.position
				target_rotation = snap_result.get("rotation", target_rotation)
				is_snapped_to_piece = true
			else:
				# No snap point found, use ground placement
				# Snap to grid (only X and Z, not Y)
				if ghost_preview.snap_to_grid:
					var grid = ghost_preview.grid_size
					hit_point.x = round(hit_point.x / grid.x) * grid.x
					hit_point.z = round(hit_point.z / grid.z) * grid.z
					# Don't snap Y - we want objects to sit on the surface

				# Align object to surface normal (make it stand upright on slopes)
				if hit_normal.y > 0.5:  # Only on relatively flat surfaces
					# Place object ON the surface, not embedded in it
					# Offset by half the grid height to sit on top
					var offset_y = ghost_preview.grid_size.y / 2.0
					hit_point.y += offset_y

				target_position = hit_point

		ghost_preview.global_position = target_position
		ghost_preview.rotation.y = target_rotation

		# Validate placement
		can_place_current = _validate_placement(target_position)
		ghost_preview.set_preview_valid(can_place_current, is_snapped_to_piece)
	else:
		# No hit - place in front of player
		ghost_preview.global_position = from + (-camera.global_transform.basis.z * placement_distance)
		can_place_current = false
		is_snapped_to_piece = false
		ghost_preview.set_preview_valid(false, false)

## Find the nearest snap point from nearby building pieces
func _find_nearest_snap_point(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview:
		return {}

	# For floors, use aggressive grid-based snapping
	if current_piece_name == "wooden_floor":
		return _find_floor_grid_snap(cursor_position)

	# For other pieces, use the old snap point system
	var nearest_snap: Dictionary = {}
	var nearest_distance: float = snap_distance_threshold

	# Find all building pieces in the world
	for child in world.get_children():
		# Skip if it's the ghost preview itself
		if child == ghost_preview:
			continue

		# Check if it's a buildable piece (has snap_points)
		if not ("snap_points" in child) or not ("piece_name" in child):
			continue

		# Skip if snap_points is empty
		if child.snap_points.is_empty():
			continue

		# Skip if too far away
		if child.global_position.distance_to(cursor_position) > snap_search_radius:
			continue

		# Check each snap point on this piece
		for snap_point in child.snap_points:
			var snap_pos_local: Vector3 = snap_point.position
			var snap_normal: Vector3 = snap_point.normal
			var snap_type: String = snap_point.get("type", "")

			# Transform to global space
			var snap_pos_global: Vector3 = child.global_transform * snap_pos_local
			var snap_normal_global: Vector3 = child.global_transform.basis * snap_normal

			# Calculate where our piece should be placed
			var our_snap_result = _find_matching_snap_point(snap_pos_global, snap_normal_global, child.rotation.y, snap_type, cursor_position)

			if our_snap_result.has("position"):
				var distance = cursor_position.distance_to(our_snap_result.position)

				if distance < nearest_distance:
					nearest_distance = distance
					nearest_snap = our_snap_result

	return nearest_snap

## Aggressive floor grid snapping - calculate all 4 adjacent positions and pick closest
func _find_floor_grid_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview:
		return {}

	var grid_size_x = ghost_preview.grid_size.x
	var grid_size_z = ghost_preview.grid_size.z

	var best_snap: Dictionary = {}
	var best_distance: float = snap_distance_threshold

	var total_floors = 0
	var total_adjacent = 0
	var occupied_count = 0

	# Find all floor pieces nearby
	for child in world.get_children():
		# Skip if it's the ghost preview itself
		if child == ghost_preview:
			continue

		# Only look for other floors
		if not ("piece_name" in child) or child.piece_name != "wooden_floor":
			continue

		total_floors += 1

		# Skip if too far away
		if child.global_position.distance_to(cursor_position) > snap_search_radius:
			continue

		# Get the floor's center position
		var floor_center = child.global_position
		var floor_y = floor_center.y  # Preserve Y height

		# Calculate ALL 4 possible adjacent positions
		var adjacent_positions = [
			Vector3(floor_center.x + grid_size_x, floor_y, floor_center.z),  # East
			Vector3(floor_center.x - grid_size_x, floor_y, floor_center.z),  # West
			Vector3(floor_center.x, floor_y, floor_center.z + grid_size_z),  # North
			Vector3(floor_center.x, floor_y, floor_center.z - grid_size_z),  # South
		]

		# Check each adjacent position
		for adj_pos in adjacent_positions:
			total_adjacent += 1

			# Skip if this position is already occupied
			if _is_position_occupied(adj_pos):
				occupied_count += 1
				continue

			# Calculate distance from cursor to this potential placement
			var distance = cursor_position.distance_to(adj_pos)

			if distance < best_distance:
				best_distance = distance
				best_snap = {
					"position": adj_pos,
					"rotation": 0.0  # Floors always at 0 rotation
				}

	if debug_snap and total_floors > 0:
		print("[BuildMode] Floor snap search: %d floors, %d adjacent slots, %d occupied, best_dist: %.2f" % [total_floors, total_adjacent, occupied_count, best_distance])
		if best_snap.has("position"):
			print("  Snapping to: %s" % best_snap.position)

	return best_snap

## Check if a position is already occupied by a floor piece
func _is_position_occupied(pos: Vector3) -> bool:
	if not world:
		return false

	var tolerance = 0.1  # Small tolerance for floating point comparison

	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child) or child.piece_name != "wooden_floor":
			continue

		var distance = child.global_position.distance_to(pos)
		if distance < tolerance:
			return true  # Position is occupied

	return false

## Find which of our snap points should connect to a target snap point
func _find_matching_snap_point(target_pos: Vector3, target_normal: Vector3, target_rotation: float, target_type: String, cursor_pos: Vector3) -> Dictionary:
	if not ghost_preview or not ("snap_points" in ghost_preview):
		return {}

	# Special handling for floor corner snapping
	if current_piece_name == "wooden_floor" and target_type == "floor_corner":
		# Determine which direction from the corner to place the new floor
		var direction = (cursor_pos - target_pos).normalized()
		direction.y = 0  # Keep on same plane

		# Determine which of our corners should connect to the target corner
		# Based on cursor direction from the target corner
		var half_x = ghost_preview.grid_size.x / 2.0
		var half_z = ghost_preview.grid_size.z / 2.0

		var our_corner_offset: Vector3

		# Choose the opposite corner to connect
		# If cursor is NE of corner, use our SW corner to connect
		if direction.x >= 0 and direction.z >= 0:  # NE quadrant
			our_corner_offset = Vector3(-half_x, 0, -half_z)  # Our SW corner
		elif direction.x < 0 and direction.z >= 0:  # NW quadrant
			our_corner_offset = Vector3(half_x, 0, -half_z)  # Our SE corner
		elif direction.x < 0 and direction.z < 0:  # SW quadrant
			our_corner_offset = Vector3(half_x, 0, half_z)  # Our NE corner
		else:  # SE quadrant
			our_corner_offset = Vector3(-half_x, 0, half_z)  # Our NW corner

		# Calculate our center position so our chosen corner aligns with target
		var our_center = target_pos - our_corner_offset

		if debug_snap:
			print("[BuildMode] Floor corner snap: dir=%s, our_corner_offset=%s" % [direction, our_corner_offset])
			print("  Target corner: %s, Our center: %s" % [target_pos, our_center])

		return {
			"position": our_center,
			"rotation": 0.0  # Floors always at 0 rotation for grid alignment
		}

	# Wall bottoms should snap to floor tops
	if current_piece_name == "wooden_wall" and target_type == "floor_top":
		for our_snap in ghost_preview.snap_points:
			var our_type: String = our_snap.get("type", "")
			if our_type == "wall_bottom":
				var our_pos_local: Vector3 = our_snap.position
				var rotated_snap_pos = Vector3(our_pos_local.x, our_pos_local.y, our_pos_local.z).rotated(Vector3.UP, ghost_preview.rotation.y)
				var our_center_pos = target_pos - rotated_snap_pos

				return {
					"position": our_center_pos,
					"rotation": ghost_preview.rotation.y
				}

	# Wall edges should snap to other wall edges
	if current_piece_name == "wooden_wall" and target_type == "wall_edge":
		for our_snap in ghost_preview.snap_points:
			var our_type: String = our_snap.get("type", "")
			if our_type != "wall_edge":
				continue

			var our_normal: Vector3 = our_snap.normal
			var our_pos_local: Vector3 = our_snap.position

			var rotated_normal = Vector3(our_normal.x, our_normal.y, our_normal.z).rotated(Vector3.UP, ghost_preview.rotation.y)
			var dot = rotated_normal.dot(target_normal)

			if dot < -0.7:  # Opposite facing
				var rotated_snap_pos = Vector3(our_pos_local.x, our_pos_local.y, our_pos_local.z).rotated(Vector3.UP, ghost_preview.rotation.y)
				var our_center_pos = target_pos - rotated_snap_pos

				return {
					"position": our_center_pos,
					"rotation": ghost_preview.rotation.y
				}

	return {}

func _validate_placement(_position: Vector3) -> bool:
	# If snapped to another piece, always valid (assumes other piece is valid)
	if is_snapped_to_piece:
		# Still check resources
		if not player:
			return false

		var player_inventory = player.get_node_or_null("Inventory")
		if not player_inventory:
			return false

		var costs = CraftingRecipes.BUILDING_COSTS.get(current_piece_name, {})
		for resource in costs:
			var required = costs[resource]
			if not player_inventory.has_item(resource, required):
				return false

		return true

	# Not snapped - check if player has required resources
	if not player:
		return false

	var player_inventory = player.get_node_or_null("Inventory")
	if not player_inventory:
		return false

	# Get required resources for this piece
	var costs = CraftingRecipes.BUILDING_COSTS.get(current_piece_name, {})
	if costs.is_empty():
		return true  # No cost means always valid

	# Check all required resources
	for resource in costs:
		var required = costs[resource]
		if not player_inventory.has_item(resource, required):
			return false  # Missing resources

	# TODO: Check for overlaps, terrain validity, etc.
	return true

func _handle_input() -> void:
	# Rotate with R key
	if Input.is_action_just_pressed("build_rotate") and ghost_preview:
		rotate_preview()

	# Place with left click
	if Input.is_action_just_pressed("attack") and can_place_current and ghost_preview:
		place_current_piece()

## Set which piece to build (called from build menu)
func set_piece(piece_name: String) -> void:
	if not available_pieces.has(piece_name):
		push_error("[BuildMode] Unknown piece: %s" % piece_name)
		return

	current_piece_name = piece_name

	# Find the index
	for i in piece_names.size():
		if piece_names[i] == piece_name:
			current_piece_index = i
			break

	_destroy_ghost_preview()
	_create_ghost_preview()

	var display_name = current_piece_name.replace("_", " ").capitalize()
	print("[BuildMode] Selected: %s" % display_name)

func cycle_piece(direction: int) -> void:
	current_piece_index = (current_piece_index + direction) % piece_names.size()
	if current_piece_index < 0:
		current_piece_index = piece_names.size() - 1

	current_piece_name = piece_names[current_piece_index]

	_destroy_ghost_preview()
	_create_ghost_preview()

	var display_name = current_piece_name.replace("_", " ").capitalize()
	print("[BuildMode] Selected: %s (%d/%d)" % [display_name, current_piece_index + 1, piece_names.size()])

func rotate_preview() -> void:
	if ghost_preview:
		ghost_preview.rotation.y += deg_to_rad(45.0)

func place_current_piece() -> void:
	if not can_place_current or not ghost_preview:
		return

	# Double-check resources before placement
	var player_inventory = player.get_node_or_null("Inventory")
	if not player_inventory:
		print("[BuildMode] ERROR: Player inventory not found")
		return

	var costs = CraftingRecipes.BUILDING_COSTS.get(current_piece_name, {})
	for resource in costs:
		var required = costs[resource]
		if not player_inventory.has_item(resource, required):
			print("[BuildMode] Cannot build - missing %d %s" % [required, resource])
			return

	var position = ghost_preview.global_position
	var rotation = ghost_preview.rotation.y

	print("[BuildMode] Placing %s at %s" % [current_piece_name, position])

	# Emit signal for server to handle actual placement and resource consumption
	build_piece_placed.emit(current_piece_name, position, rotation)

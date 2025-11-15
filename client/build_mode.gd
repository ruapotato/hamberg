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
var placement_distance: float = 15.0  # Increased from 5.0 for better reach
var can_place_current: bool = false

# Snapping
var snap_distance_threshold: float = 8.0  # Snap when within 8 units of a valid snap position
var is_snapped_to_piece: bool = false  # Whether currently snapped to another piece
var snap_search_radius: float = 8.0  # Search for nearby pieces within 8 units for grid reference
var debug_snap: bool = false  # Enable debug logging for snapping
var placed_buildables: Dictionary = {}  # Track placed positions to avoid duplicate snaps

# References
var player: Node3D = null
var camera: Camera3D = null
var world: Node3D = null
var build_menu: Control = null  # Reference to build menu to check if open

# Input cooldown
var placement_cooldown: float = 0.0  # Prevents accidental placement after menu selection

func _ready() -> void:
	piece_names = available_pieces.keys()
	piece_names.sort()

func activate(p_player: Node3D, p_camera: Camera3D, p_world: Node3D, p_build_menu: Control = null) -> void:
	if is_active:
		return

	player = p_player
	camera = p_camera
	world = p_world
	build_menu = p_build_menu
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

func _process(delta: float) -> void:
	if not is_active:
		return

	# Tick down placement cooldown
	if placement_cooldown > 0.0:
		placement_cooldown -= delta

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
		var hit_object = result.get("collider")

		# Debug: Print what we hit
		if debug_snap:
			print("[BuildMode] Raycast hit: pos=%s, normal=%s, object=%s" % [hit_point, hit_normal, hit_object])

		# Try to snap to nearby floors first (uses grid-aligned snapping for floors)
		var snap_result = _find_nearest_snap_point(hit_point)

		if snap_result.has("position"):
			# Found a valid snap position near an existing floor!
			target_position = snap_result.position
			target_rotation = snap_result.get("rotation", target_rotation)
			is_snapped_to_piece = true
		else:
			# No nearby floors - place exactly where raycast hits (no grid snapping)
			# This allows the first piece to be placed anywhere
			# Place object ON the surface, not embedded in it
			if hit_normal.y > 0.5:  # Only on relatively flat surfaces
				# Safe access to grid_size (some buildables don't have it)
				if "grid_size" in ghost_preview:
					var offset_y = ghost_preview.grid_size.y / 2.0
					hit_point.y += offset_y
				else:
					hit_point.y += 0.1  # Default small offset for non-building pieces

			target_position = hit_point
			is_snapped_to_piece = false

			# For floors: check if we're too close to an existing floor (would overlap)
			if current_piece_name == "wooden_floor" and _is_position_occupied(target_position):
				if debug_snap:
					print("[BuildMode] Ground placement would overlap with existing floor at %s" % target_position)
				# Mark as invalid but still show the ghost
				can_place_current = false
				ghost_preview.global_position = target_position
				ghost_preview.rotation.y = target_rotation
				ghost_preview.set_preview_valid(false, false)
				return  # Early return to skip normal validation

		ghost_preview.global_position = target_position
		ghost_preview.rotation.y = target_rotation

		if debug_snap:
			print("[BuildMode] Ghost position: %s (snapped=%s)" % [target_position, is_snapped_to_piece])

		# Validate placement
		can_place_current = _validate_placement(target_position)
		ghost_preview.set_preview_valid(can_place_current, is_snapped_to_piece)
	else:
		# No hit - place in front of player at player's feet level
		var forward_pos = from + (-camera.global_transform.basis.z * placement_distance)

		# Use player's Y position as reference (player should be standing on ground)
		if player:
			forward_pos.y = player.global_position.y
			# Add offset for piece height
			if "grid_size" in ghost_preview:
				forward_pos.y += ghost_preview.grid_size.y / 2.0
			else:
				forward_pos.y += 0.1
		else:
			# Fallback: use camera Y minus some height
			forward_pos.y = from.y - 1.0

		ghost_preview.global_position = forward_pos
		is_snapped_to_piece = false

		# Allow placement if player has resources
		can_place_current = _validate_placement(forward_pos)
		ghost_preview.set_preview_valid(can_place_current, false)

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

## Floor grid snapping - snap to grid coordinates aligned with nearby floors
func _find_floor_grid_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview:
		return {}

	# Safety check - ensure ghost_preview has grid_size
	if not ("grid_size" in ghost_preview):
		return {}

	var grid_size_x = ghost_preview.grid_size.x
	var grid_size_z = ghost_preview.grid_size.z

	# Find the nearest floor piece to use as grid reference
	var nearest_floor: Node3D = null
	var nearest_distance: float = snap_search_radius

	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child) or child.piece_name != "wooden_floor":
			continue

		var distance = child.global_position.distance_to(cursor_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_floor = child

	# If no nearby floor found, no grid snapping
	if not nearest_floor:
		return {}

	# Use the nearest floor as the grid reference
	var floor_center = nearest_floor.global_position
	var floor_y = floor_center.y  # Use the same Y level as the reference floor

	# Calculate what grid position the cursor should snap to
	# based on the reference floor's grid
	var offset_x = cursor_position.x - floor_center.x
	var offset_z = cursor_position.z - floor_center.z

	# Round to nearest grid cell
	var grid_x = round(offset_x / grid_size_x)
	var grid_z = round(offset_z / grid_size_z)

	# Calculate the snapped position
	var snapped_pos = Vector3(
		floor_center.x + grid_x * grid_size_x,
		floor_y,
		floor_center.z + grid_z * grid_size_z
	)

	# Check if this position is already occupied
	if _is_position_occupied(snapped_pos):
		if debug_snap:
			print("[BuildMode] Primary grid position %s is occupied, searching for nearest unoccupied..." % snapped_pos)

		# Find the nearest unoccupied grid position
		# Check adjacent positions in expanding rings
		var best_pos: Vector3 = Vector3.ZERO
		var best_dist: float = INF
		var found: bool = false

		# Check positions in a 3x3 grid around the calculated position (excluding center which is occupied)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dz == 0:
					continue  # Skip the occupied center position

				var test_pos = Vector3(
					floor_center.x + (grid_x + dx) * grid_size_x,
					floor_y,
					floor_center.z + (grid_z + dz) * grid_size_z
				)

				if not _is_position_occupied(test_pos):
					var dist = cursor_position.distance_to(test_pos)
					if dist < best_dist:
						best_dist = dist
						best_pos = test_pos
						found = true

		if found and best_dist < snap_distance_threshold:
			if debug_snap:
				print("[BuildMode] Found unoccupied position at %s (dist: %.2f)" % [best_pos, best_dist])
			return {
				"position": best_pos,
				"rotation": 0.0
			}

		# No nearby unoccupied position found
		return {}

	# Valid snap position found
	if debug_snap:
		print("[BuildMode] Snapping to grid position %s (ref floor: %s)" % [snapped_pos, floor_center])

	return {
		"position": snapped_pos,
		"rotation": 0.0
	}

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

	# Wall bottoms should snap to wall tops (for vertical stacking)
	if current_piece_name == "wooden_wall" and target_type == "wall_top":
		for our_snap in ghost_preview.snap_points:
			var our_type: String = our_snap.get("type", "")
			if our_type == "wall_bottom":
				var our_pos_local: Vector3 = our_snap.position
				var rotated_snap_pos = Vector3(our_pos_local.x, our_pos_local.y, our_pos_local.z).rotated(Vector3.UP, ghost_preview.rotation.y)
				var our_center_pos = target_pos - rotated_snap_pos

				return {
					"position": our_center_pos,
					"rotation": target_rotation  # Match the rotation of the wall below
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

	# Destroy buildable with middle mouse
	if Input.is_action_just_pressed("destroy_object"):
		_try_destroy_buildable()

	# Place with left click (but not if build menu is open or during cooldown)
	if Input.is_action_just_pressed("attack") and can_place_current and ghost_preview:
		# Check if build menu is open
		if build_menu and build_menu.is_open:
			return  # Don't place while menu is open

		# Check cooldown (prevents accidental placement after menu selection)
		if placement_cooldown > 0.0:
			return

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

	# Set cooldown to prevent immediate placement after menu selection
	placement_cooldown = 0.2  # 200ms cooldown

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

## Try to destroy a buildable at cursor position
func _try_destroy_buildable() -> void:
	if not camera or not world:
		return

	# Raycast from camera forward
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * placement_distance)

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World layer

	var result = space_state.intersect_ray(query)

	if result:
		var hit_object = result.get("collider")

		# Check if it's a buildable piece by checking if name starts with "Buildable_"
		if hit_object and hit_object.name.begins_with("Buildable_"):
			var network_id = hit_object.name.substr(10)  # Remove "Buildable_" prefix
			var piece_name = hit_object.piece_name if "piece_name" in hit_object else "unknown"

			print("[BuildMode] Requesting to destroy %s (ID: %s)" % [piece_name, network_id])

			# Send destroy request to server via NetworkManager
			NetworkManager.rpc_destroy_buildable.rpc_id(1, network_id)

extends Node

## BuildMode - Valheim-style build mode for placing structures
## Activated when player has hammer equipped

signal build_piece_placed(piece_name: String, position: Vector3, rotation: float)

# Sound effects
var place_sound: AudioStreamPlayer = null
var remove_sound: AudioStreamPlayer = null
var place_sound_stream: AudioStream = preload("res://audio/sfx/build_place.wav")
var remove_sound_stream: AudioStream = preload("res://audio/sfx/build_remove.wav")

# Building pieces available (populated from resources)
var available_pieces: Dictionary = {
	"wooden_wall": preload("res://shared/buildable/wooden_wall.tscn"),
	"wooden_floor": preload("res://shared/buildable/wooden_floor.tscn"),
	"wooden_door": preload("res://shared/buildable/wooden_door.tscn"),
	"wooden_beam": preload("res://shared/buildable/wooden_beam.tscn"),
	"wooden_roof_26": preload("res://shared/buildable/wooden_roof_26.tscn"),
	"wooden_roof_45": preload("res://shared/buildable/wooden_roof_45.tscn"),
	"wooden_stairs": preload("res://shared/buildable/wooden_stairs.tscn"),
	"workbench": preload("res://shared/buildable/workbench.tscn"),
	"chest": preload("res://shared/buildable/chest.tscn"),
	"fireplace": preload("res://shared/buildable/fireplace.tscn"),
	"cooking_station": preload("res://shared/buildable/cooking_station.tscn"),
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
var snap_distance_threshold: float = 12.0  # Snap when within 12 units of a valid snap position (increased for wall stacking)
var is_snapped_to_piece: bool = false  # Whether currently snapped to another piece
var snap_search_radius: float = 12.0  # Search for nearby pieces within 12 units (increased for wall stacking)
var debug_snap: bool = false  # Enable debug logging for snapping
var placed_buildables: Dictionary = {}  # Track placed positions to avoid duplicate snaps

# References
var player: Node3D = null
var camera: Camera3D = null
var world: Node3D = null
var build_menu: Control = null  # Reference to build menu to check if open
var status_label: Label = null  # Reference to status label for messages

# Input cooldown
var placement_cooldown: float = 0.0  # Prevents accidental placement after menu selection

# Workbench requirement
var requires_workbench: bool = true  # Whether building requires being near a workbench
var workbench_range: float = 20.0  # How close you need to be to a workbench
var is_near_workbench: bool = false  # Cached result of workbench check

func _ready() -> void:
	piece_names = available_pieces.keys()
	piece_names.sort()
	_setup_audio()

func _setup_audio() -> void:
	# Create audio players for build sounds
	place_sound = AudioStreamPlayer.new()
	place_sound.stream = place_sound_stream
	place_sound.volume_db = -3.0
	add_child(place_sound)

	remove_sound = AudioStreamPlayer.new()
	remove_sound.stream = remove_sound_stream
	remove_sound.volume_db = -3.0
	add_child(remove_sound)

func _play_place_sound() -> void:
	if place_sound and not place_sound.playing:
		place_sound.play()

func _play_remove_sound() -> void:
	if remove_sound and not remove_sound.playing:
		remove_sound.play()

func activate(p_player: Node3D, p_camera: Camera3D, p_world: Node3D, p_build_menu: Control = null, p_status_label: Label = null) -> void:
	if is_active:
		return

	player = p_player
	camera = p_camera
	world = p_world
	build_menu = p_build_menu
	status_label = p_status_label
	is_active = true

	_create_ghost_preview()
	print("[BuildMode] Activated - Use mouse wheel to cycle pieces, left-click to place, R to rotate")
	print("[BuildMode] Current piece: %s (1/%d)" % [current_piece_name, piece_names.size()])

func deactivate() -> void:
	if not is_active:
		return

	is_active = false
	_destroy_ghost_preview()
	_clear_status_message()
	print("[BuildMode] Deactivated")

func _process(delta: float) -> void:
	if not is_active:
		return

	# Tick down placement cooldown
	if placement_cooldown > 0.0:
		placement_cooldown -= delta

	# Check workbench proximity
	_update_workbench_proximity()

	if ghost_preview:
		_update_ghost_position()

	_handle_input()

func _create_ghost_preview() -> void:
	if not available_pieces.has(current_piece_name):
		return

	var piece_scene = available_pieces[current_piece_name]
	ghost_preview = piece_scene.instantiate()

	# Try to set is_preview property if it exists (for newer builds)
	if "is_preview" in ghost_preview:
		ghost_preview.is_preview = true

	world.add_child(ghost_preview)

	# Always call setup preview mode to ensure visual feedback
	if ghost_preview.has_method("_setup_preview_mode"):
		ghost_preview._setup_preview_mode()

func _destroy_ghost_preview() -> void:
	if ghost_preview:
		ghost_preview.queue_free()
		ghost_preview = null

func _update_ghost_position() -> void:
	if not camera or not ghost_preview:
		return

	# Check if shift is held to disable snapping
	var disable_snap = Input.is_action_pressed("sprint")

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

		# Try to snap to nearby pieces (unless shift held for free placement)
		var snap_result: Dictionary = {}
		if not disable_snap:
			snap_result = _find_nearest_snap_point(hit_point)

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
				# Non-building pieces (fireplace, etc.) sit directly on ground - no offset needed

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
			# Add offset for piece height (only for building pieces with grid_size)
			if "grid_size" in ghost_preview:
				forward_pos.y += ghost_preview.grid_size.y / 2.0
			# Non-building pieces sit directly at player ground level
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

	# For floors: try corner snapping first, then wall-top, then grid
	if current_piece_name == "wooden_floor":
		# First try floor-to-floor corner snapping (works for any level)
		var floor_corner_result = _find_floor_corner_snap(cursor_position)
		if not floor_corner_result.is_empty():
			return floor_corner_result
		# Then try wall-top snapping (for starting second floors)
		var wall_top_result = _find_floor_on_wall_top_snap(cursor_position)
		if not wall_top_result.is_empty():
			return wall_top_result
		# Finally fall back to grid snapping
		return _find_floor_grid_snap(cursor_position)

	# For walls trying to stack on walls, use special detection
	if current_piece_name == "wooden_wall":
		var wall_stack_result = _find_wall_stack_snap(cursor_position)
		if not wall_stack_result.is_empty():
			return wall_stack_result

	# For doors: snap to floor_top (like walls) and between walls
	if current_piece_name == "wooden_door":
		var door_snap_result = _find_door_snap(cursor_position)
		if not door_snap_result.is_empty():
			return door_snap_result

	# For stairs: snap to floor_top at bottom, floor at top
	if current_piece_name == "wooden_stairs":
		var stairs_snap_result = _find_stairs_snap(cursor_position)
		if not stairs_snap_result.is_empty():
			return stairs_snap_result

	# For roofs: snap to wall_top
	if current_piece_name in ["wooden_roof_26", "wooden_roof_45"]:
		var roof_snap_result = _find_roof_snap(cursor_position)
		if not roof_snap_result.is_empty():
			return roof_snap_result

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

## Floor-to-floor corner snapping - snap to existing floor corners
## This allows expanding floors at ANY level by pointing at floor corners
func _find_floor_corner_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview or not camera:
		return {}

	var camera_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z

	var best_snap: Dictionary = {}
	var best_distance_from_ray: float = INF
	var best_distance_along_ray: float = INF

	const MAX_PERPENDICULAR_DISTANCE: float = 1.5  # Tighter snap for corners

	var floor_half_x = ghost_preview.grid_size.x / 2.0
	var floor_half_z = ghost_preview.grid_size.z / 2.0
	var floor_half_height = ghost_preview.grid_size.y / 2.0

	# Search for nearby floors
	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child) or child.piece_name != "wooden_floor":
			continue

		# Skip if piece is too far
		var to_piece = child.global_position - camera_pos
		var distance_along_camera = to_piece.dot(camera_forward)
		if distance_along_camera < 0 or distance_along_camera > placement_distance + 5.0:
			continue

		# Check floor_corner snap points
		if not ("snap_points" in child):
			continue

		for snap_point in child.snap_points:
			var snap_type: String = snap_point.get("type", "")
			if snap_type != "floor_corner":
				continue

			var snap_pos_local: Vector3 = snap_point.position
			var snap_pos_global: Vector3 = child.global_transform * snap_pos_local

			# Calculate closest point on camera ray to this corner
			var to_corner = snap_pos_global - camera_pos
			var distance_along_ray = to_corner.dot(camera_forward)

			if distance_along_ray < 0 or distance_along_ray > placement_distance + 5.0:
				continue

			var closest_point_on_ray = camera_pos + camera_forward * distance_along_ray
			var perpendicular_distance = snap_pos_global.distance_to(closest_point_on_ray)

			if perpendicular_distance > MAX_PERPENDICULAR_DISTANCE:
				continue

			# Check if this is a better snap point
			var is_better = false
			if perpendicular_distance < best_distance_from_ray - 0.1:
				is_better = true
			elif abs(perpendicular_distance - best_distance_from_ray) < 0.1:
				if distance_along_ray < best_distance_along_ray:
					is_better = true

			if is_better:
				# Calculate floor position using corner snapping logic
				# Determine which direction from the corner to place the floor
				var direction = (cursor_position - snap_pos_global).normalized()
				direction.y = 0  # Keep on same plane

				# Choose which floor corner should connect to target corner
				var our_corner_offset: Vector3
				if direction.x >= 0 and direction.z >= 0:  # NE quadrant
					our_corner_offset = Vector3(-floor_half_x, 0, -floor_half_z)  # Our SW corner
				elif direction.x < 0 and direction.z >= 0:  # NW quadrant
					our_corner_offset = Vector3(floor_half_x, 0, -floor_half_z)  # Our SE corner
				elif direction.x < 0 and direction.z < 0:  # SW quadrant
					our_corner_offset = Vector3(floor_half_x, 0, floor_half_z)  # Our NE corner
				else:  # SE quadrant
					our_corner_offset = Vector3(-floor_half_x, 0, floor_half_z)  # Our NW corner

				# Calculate floor center so our corner aligns with target corner
				var floor_pos = Vector3(
					snap_pos_global.x - our_corner_offset.x,
					snap_pos_global.y,  # Same Y level as the floor we're snapping to
					snap_pos_global.z - our_corner_offset.z
				)

				best_snap = {
					"position": floor_pos,
					"rotation": 0.0  # Floors stay grid-aligned
				}
				best_distance_from_ray = perpendicular_distance
				best_distance_along_ray = distance_along_ray

	return best_snap

## Special snapping for floors on top of walls (for second floors)
## Floors snap to wall top CORNERS, just like floor-to-floor corner snapping
func _find_floor_on_wall_top_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview or not camera:
		return {}

	var camera_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z

	var best_snap: Dictionary = {}
	var best_distance_from_ray: float = INF
	var best_distance_along_ray: float = INF

	const MAX_PERPENDICULAR_DISTANCE: float = 3.0

	var floor_half_x = ghost_preview.grid_size.x / 2.0
	var floor_half_z = ghost_preview.grid_size.z / 2.0
	var floor_half_height = ghost_preview.grid_size.y / 2.0

	# Search for nearby walls to snap floor on top of
	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child):
			continue

		# Only snap to walls
		if child.piece_name != "wooden_wall":
			continue

		# Skip if piece is too far
		var to_piece = child.global_position - camera_pos
		var distance_along_camera = to_piece.dot(camera_forward)
		if distance_along_camera < 0 or distance_along_camera > placement_distance + 5.0:
			continue

		# Wall top corners in local space (wall is 2m wide, 2m tall)
		# Left and right corners at top of wall
		var wall_half_width = 1.0  # Wall is 2m wide
		var wall_half_height = 1.0  # Wall is 2m tall
		var wall_top_corners_local = [
			Vector3(-wall_half_width, wall_half_height, 0),  # Left corner
			Vector3(wall_half_width, wall_half_height, 0),   # Right corner
		]

		# Check each wall top corner
		for corner_local in wall_top_corners_local:
			var corner_global = child.global_transform * corner_local

			# Calculate closest point on camera ray to this corner
			var to_corner = corner_global - camera_pos
			var distance_along_ray = to_corner.dot(camera_forward)

			if distance_along_ray < 0 or distance_along_ray > placement_distance + 5.0:
				continue

			var closest_point_on_ray = camera_pos + camera_forward * distance_along_ray
			var perpendicular_distance = corner_global.distance_to(closest_point_on_ray)

			if perpendicular_distance > MAX_PERPENDICULAR_DISTANCE:
				continue

			# Check if this is a better snap point
			var is_better = false
			if perpendicular_distance < best_distance_from_ray - 0.1:
				is_better = true
			elif abs(perpendicular_distance - best_distance_from_ray) < 0.1:
				if distance_along_ray < best_distance_along_ray:
					is_better = true

			if is_better:
				# Calculate floor position using corner snapping logic (like floor-to-floor)
				# Determine which direction from the corner to place the floor based on cursor
				var direction = (cursor_position - corner_global).normalized()
				direction.y = 0  # Keep on same plane

				# Choose which floor corner should connect to wall corner
				var our_corner_offset: Vector3
				if direction.x >= 0 and direction.z >= 0:  # NE quadrant
					our_corner_offset = Vector3(-floor_half_x, 0, -floor_half_z)  # Our SW corner
				elif direction.x < 0 and direction.z >= 0:  # NW quadrant
					our_corner_offset = Vector3(floor_half_x, 0, -floor_half_z)  # Our SE corner
				elif direction.x < 0 and direction.z < 0:  # SW quadrant
					our_corner_offset = Vector3(floor_half_x, 0, floor_half_z)  # Our NE corner
				else:  # SE quadrant
					our_corner_offset = Vector3(-floor_half_x, 0, floor_half_z)  # Our NW corner

				# Calculate floor center so our corner aligns with wall corner
				var floor_pos = Vector3(
					corner_global.x - our_corner_offset.x,
					corner_global.y + floor_half_height,
					corner_global.z - our_corner_offset.z
				)

				best_snap = {
					"position": floor_pos,
					"rotation": 0.0  # Floors stay grid-aligned
				}
				best_distance_from_ray = perpendicular_distance
				best_distance_along_ray = distance_along_ray

	return best_snap

## Special snapping for walls - uses raycast proximity for both floors and walls
func _find_wall_stack_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview or not camera:
		return {}

	var camera_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z  # Forward direction (normalized)

	var best_snap: Dictionary = {}
	var best_distance_from_ray: float = INF
	var best_distance_along_ray: float = INF

	const MAX_PERPENDICULAR_DISTANCE: float = 3.0  # Snap if within 3m of ray

	# Search for nearby pieces (walls and floors) to snap to
	for child in world.get_children():
		if child == ghost_preview:
			continue

		# Look for walls and floors
		if not ("piece_name" in child):
			continue

		var is_wall = child.piece_name == "wooden_wall"
		var is_floor = child.piece_name == "wooden_floor"

		if not is_wall and not is_floor:
			continue

		# Skip if piece is too far behind or in front of camera
		var to_piece = child.global_position - camera_pos
		var distance_along_camera = to_piece.dot(camera_forward)
		if distance_along_camera < 0 or distance_along_camera > placement_distance + 5.0:
			continue

		# Check each snap point (wall_top for walls, floor_top for floors)
		if "snap_points" in child:
			for snap_point in child.snap_points:
				var snap_type: String = snap_point.get("type", "")
				# Accept both wall_top and floor_top snap points
				if snap_type != "wall_top" and snap_type != "floor_top":
					continue

				var snap_pos_local: Vector3 = snap_point.position
				var snap_pos_global: Vector3 = child.global_transform * snap_pos_local

				# Calculate closest point on camera ray to this snap point
				var to_snap = snap_pos_global - camera_pos
				var distance_along_ray = to_snap.dot(camera_forward)

				# Skip if snap point is behind camera or too far
				if distance_along_ray < 0 or distance_along_ray > placement_distance + 5.0:
					continue

				# Calculate perpendicular distance from ray to snap point
				var closest_point_on_ray = camera_pos + camera_forward * distance_along_ray
				var perpendicular_distance = snap_pos_global.distance_to(closest_point_on_ray)

				# Skip if snap point is too far from the ray
				if perpendicular_distance > MAX_PERPENDICULAR_DISTANCE:
					continue

				# This is a valid candidate - pick the one closest to the ray, then closest along ray
				var is_better = false
				if perpendicular_distance < best_distance_from_ray - 0.1:  # Significantly closer to ray
					is_better = true
				elif abs(perpendicular_distance - best_distance_from_ray) < 0.1:  # Similar distance to ray
					if distance_along_ray < best_distance_along_ray:  # Prefer closer along ray
						is_better = true

				if is_better:
					# Calculate where our wall should be placed
					var our_snap_result = _find_matching_snap_point(snap_pos_global, Vector3.UP, child.rotation.y, snap_type, cursor_position)

					if our_snap_result.has("position"):
						best_snap = our_snap_result
						best_distance_from_ray = perpendicular_distance
						best_distance_along_ray = distance_along_ray

	return best_snap

## Door snapping - snaps to floor_top like walls, fits between walls
func _find_door_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview or not camera:
		return {}

	var camera_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z

	var best_snap: Dictionary = {}
	var best_distance_from_ray: float = INF
	var best_distance_along_ray: float = INF

	const MAX_PERPENDICULAR_DISTANCE: float = 3.0

	var door_half_height = ghost_preview.grid_size.y / 2.0

	# Search for floors and walls to snap to
	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child):
			continue

		var is_floor = child.piece_name == "wooden_floor"
		var is_wall = child.piece_name == "wooden_wall"

		if not is_floor and not is_wall:
			continue

		# Skip if piece is too far
		var to_piece = child.global_position - camera_pos
		var distance_along_camera = to_piece.dot(camera_forward)
		if distance_along_camera < 0 or distance_along_camera > placement_distance + 5.0:
			continue

		if "snap_points" in child:
			for snap_point in child.snap_points:
				var snap_type: String = snap_point.get("type", "")
				# Doors snap to floor_top or wall_edge
				if snap_type != "floor_top" and snap_type != "wall_edge":
					continue

				var snap_pos_local: Vector3 = snap_point.position
				var snap_pos_global: Vector3 = child.global_transform * snap_pos_local

				var to_snap = snap_pos_global - camera_pos
				var distance_along_ray = to_snap.dot(camera_forward)

				if distance_along_ray < 0 or distance_along_ray > placement_distance + 5.0:
					continue

				var closest_point_on_ray = camera_pos + camera_forward * distance_along_ray
				var perpendicular_distance = snap_pos_global.distance_to(closest_point_on_ray)

				if perpendicular_distance > MAX_PERPENDICULAR_DISTANCE:
					continue

				var is_better = false
				if perpendicular_distance < best_distance_from_ray - 0.1:
					is_better = true
				elif abs(perpendicular_distance - best_distance_from_ray) < 0.1:
					if distance_along_ray < best_distance_along_ray:
						is_better = true

				if is_better:
					var door_pos: Vector3
					var door_rotation: float = ghost_preview.rotation.y

					if snap_type == "floor_top":
						# Place door on top of floor
						door_pos = Vector3(
							snap_pos_global.x,
							snap_pos_global.y + door_half_height,
							snap_pos_global.z
						)
					else:  # wall_edge - snap beside a wall
						# Get wall's rotation and place door with matching rotation
						door_rotation = child.rotation.y
						var wall_normal = child.global_transform.basis * snap_point.normal
						door_pos = snap_pos_global + wall_normal * 1.0  # Offset by door half-width
						door_pos.y = child.global_position.y  # Same height as wall

					best_snap = {
						"position": door_pos,
						"rotation": door_rotation
					}
					best_distance_from_ray = perpendicular_distance
					best_distance_along_ray = distance_along_ray

	return best_snap

## Stairs snapping - snaps to floor_top at bottom, or chains to other stairs
func _find_stairs_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview or not camera:
		return {}

	var camera_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z

	var best_snap: Dictionary = {}
	var best_distance_from_ray: float = INF
	var best_distance_along_ray: float = INF

	const MAX_PERPENDICULAR_DISTANCE: float = 3.0

	var stairs_half_height = ghost_preview.grid_size.y / 2.0
	var stairs_half_z = ghost_preview.grid_size.z / 2.0

	# Search for floors and stairs to snap to
	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child):
			continue

		var is_floor = child.piece_name == "wooden_floor"
		var is_stairs = child.piece_name == "wooden_stairs"

		if not is_floor and not is_stairs:
			continue

		# Skip if piece is too far
		var to_piece = child.global_position - camera_pos
		var distance_along_camera = to_piece.dot(camera_forward)
		if distance_along_camera < 0 or distance_along_camera > placement_distance + 5.0:
			continue

		if "snap_points" in child:
			for snap_point in child.snap_points:
				var snap_type: String = snap_point.get("type", "")

				# Snap to floor_top or stairs_top
				if snap_type != "floor_top" and snap_type != "stairs_top":
					continue

				var snap_pos_local: Vector3 = snap_point.position
				var snap_pos_global: Vector3 = child.global_transform * snap_pos_local

				var to_snap = snap_pos_global - camera_pos
				var distance_along_ray = to_snap.dot(camera_forward)

				if distance_along_ray < 0 or distance_along_ray > placement_distance + 5.0:
					continue

				var closest_point_on_ray = camera_pos + camera_forward * distance_along_ray
				var perpendicular_distance = snap_pos_global.distance_to(closest_point_on_ray)

				if perpendicular_distance > MAX_PERPENDICULAR_DISTANCE:
					continue

				var is_better = false
				if perpendicular_distance < best_distance_from_ray - 0.1:
					is_better = true
				elif abs(perpendicular_distance - best_distance_from_ray) < 0.1:
					if distance_along_ray < best_distance_along_ray:
						is_better = true

				if is_better:
					var stairs_pos: Vector3
					var stairs_rotation: float

					if snap_type == "floor_top":
						# Place stairs so bottom is on floor, offset by half depth
						# Stairs go UP in -Z direction (local), so offset in +Z for bottom placement
						var stairs_forward = Vector3(0, 0, 1).rotated(Vector3.UP, ghost_preview.rotation.y)
						stairs_pos = Vector3(
							snap_pos_global.x - stairs_forward.x * stairs_half_z,
							snap_pos_global.y + stairs_half_height,
							snap_pos_global.z - stairs_forward.z * stairs_half_z
						)
						stairs_rotation = ghost_preview.rotation.y
					else:  # stairs_top - chain to another stair segment
						# Match the rotation of the stairs we're connecting to
						stairs_rotation = child.rotation.y
						# Our bottom is at local (0, -half_height, half_z)
						# We want our bottom to be at snap_pos_global (the top of the existing stairs)
						# So our center = snap_pos_global - rotated_bottom_offset
						var bottom_offset_local = Vector3(0, -stairs_half_height, stairs_half_z)
						var bottom_offset_rotated = bottom_offset_local.rotated(Vector3.UP, stairs_rotation)
						stairs_pos = snap_pos_global - bottom_offset_rotated

					best_snap = {
						"position": stairs_pos,
						"rotation": stairs_rotation
					}
					best_distance_from_ray = perpendicular_distance
					best_distance_along_ray = distance_along_ray

	return best_snap

## Roof snapping - snaps to wall_top
func _find_roof_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview or not camera:
		return {}

	var camera_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z

	var best_snap: Dictionary = {}
	var best_distance_from_ray: float = INF
	var best_distance_along_ray: float = INF

	const MAX_PERPENDICULAR_DISTANCE: float = 3.0

	var roof_half_height = ghost_preview.grid_size.y / 2.0

	# Search for walls to snap to
	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child):
			continue

		if child.piece_name != "wooden_wall":
			continue

		# Skip if piece is too far
		var to_piece = child.global_position - camera_pos
		var distance_along_camera = to_piece.dot(camera_forward)
		if distance_along_camera < 0 or distance_along_camera > placement_distance + 5.0:
			continue

		if "snap_points" in child:
			for snap_point in child.snap_points:
				var snap_type: String = snap_point.get("type", "")
				if snap_type != "wall_top":
					continue

				var snap_pos_local: Vector3 = snap_point.position
				var snap_pos_global: Vector3 = child.global_transform * snap_pos_local

				var to_snap = snap_pos_global - camera_pos
				var distance_along_ray = to_snap.dot(camera_forward)

				if distance_along_ray < 0 or distance_along_ray > placement_distance + 5.0:
					continue

				var closest_point_on_ray = camera_pos + camera_forward * distance_along_ray
				var perpendicular_distance = snap_pos_global.distance_to(closest_point_on_ray)

				if perpendicular_distance > MAX_PERPENDICULAR_DISTANCE:
					continue

				var is_better = false
				if perpendicular_distance < best_distance_from_ray - 0.1:
					is_better = true
				elif abs(perpendicular_distance - best_distance_from_ray) < 0.1:
					if distance_along_ray < best_distance_along_ray:
						is_better = true

				if is_better:
					# Place roof on top of wall, matching wall rotation
					var roof_pos = Vector3(
						snap_pos_global.x,
						snap_pos_global.y + roof_half_height,
						snap_pos_global.z
					)

					best_snap = {
						"position": roof_pos,
						"rotation": child.rotation.y  # Match wall rotation
					}
					best_distance_from_ray = perpendicular_distance
					best_distance_along_ray = distance_along_ray

	return best_snap

## Floor grid snapping - snap to grid coordinates aligned with nearby floors
func _find_floor_grid_snap(cursor_position: Vector3) -> Dictionary:
	if not world or not ghost_preview or not camera:
		return {}

	# Safety check - ensure ghost_preview has grid_size
	if not ("grid_size" in ghost_preview):
		return {}

	var grid_size_x = ghost_preview.grid_size.x
	var grid_size_z = ghost_preview.grid_size.z

	# Use CAMERA Y position to determine which floor level we're building on
	# This is important because when looking at empty space from the 2nd floor,
	# the raycast hits the 1st floor, but we want to build on the 2nd floor
	var reference_y = camera.global_position.y - 1.5  # Camera is ~1.5m above floor level

	# Find the nearest floor piece to use as grid reference
	# PRIORITIZE floors at similar Y level to where the PLAYER is standing
	var nearest_floor: Node3D = null
	var nearest_score: float = INF  # Lower is better

	const Y_LEVEL_TOLERANCE: float = 1.0  # Floors within 1m Y are "same level"
	const Y_LEVEL_PENALTY: float = 100.0  # Penalty for floors at different Y levels

	for child in world.get_children():
		if child == ghost_preview:
			continue

		if not ("piece_name" in child) or child.piece_name != "wooden_floor":
			continue

		# Calculate XZ distance (horizontal)
		var xz_distance = Vector2(child.global_position.x, child.global_position.z).distance_to(
			Vector2(cursor_position.x, cursor_position.z))

		if xz_distance > snap_search_radius:
			continue

		# Calculate Y difference from CAMERA level (not cursor hit point)
		var y_diff = abs(child.global_position.y - reference_y)

		# Score: XZ distance + penalty if at different Y level than player
		var score = xz_distance
		if y_diff > Y_LEVEL_TOLERANCE:
			score += Y_LEVEL_PENALTY  # Heavily penalize floors at different heights

		if score < nearest_score:
			nearest_score = score
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
				# Rotate by target_rotation (the wall we're snapping to), not ghost's current rotation
				var rotated_snap_pos = Vector3(our_pos_local.x, our_pos_local.y, our_pos_local.z).rotated(Vector3.UP, target_rotation)
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
	# Workbench doesn't require a workbench to place (bootstrap item)
	if current_piece_name != "workbench" and requires_workbench:
		if not is_near_workbench:
			return false  # Not in range of workbench

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
	# Rotation controls
	if ghost_preview:
		# Keyboard: R to rotate clockwise
		if Input.is_action_just_pressed("build_rotate"):
			rotate_preview()
		# Keyboard: Q to rotate (when build menu is not open)
		elif Input.is_action_just_pressed("open_build_menu") and build_menu and not build_menu.is_open:
			rotate_preview()

		# Controller: D-pad left/right to rotate
		if Input.is_action_just_pressed("hotbar_prev"):
			rotate_preview_reverse()  # Counter-clockwise
		elif Input.is_action_just_pressed("hotbar_next"):
			rotate_preview()  # Clockwise

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

func rotate_preview_reverse() -> void:
	if ghost_preview:
		ghost_preview.rotation.y -= deg_to_rad(45.0)

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

	# Play place sound
	_play_place_sound()

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

			# Play remove sound
			_play_remove_sound()

			# Send destroy request to server via NetworkManager
			NetworkManager.rpc_destroy_buildable.rpc_id(1, network_id)

## Check if player is near any workbench and update status message
func _update_workbench_proximity() -> void:
	if not player:
		is_near_workbench = false
		return

	# Workbench doesn't need another workbench to be placed
	if current_piece_name == "workbench":
		is_near_workbench = true
		_clear_status_message()
		return

	# Check if near any workbench
	var was_near_workbench = is_near_workbench
	is_near_workbench = _check_near_workbench()

	# Update status message only when building something other than workbench
	if requires_workbench and current_piece_name != "workbench":
		if not is_near_workbench:
			_set_status_message("Not in range of workbench")
		elif was_near_workbench != is_near_workbench:
			# Just entered range, clear the message
			_clear_status_message()

## Check if player is within range of any workbench
func _check_near_workbench() -> bool:
	if not world or not player:
		return false

	# Search for all workbenches in the world
	var buildables = world.get_children()
	for child in buildables:
		# Check if it's a buildable object node (spawned buildables are children of world)
		if child.name.begins_with("Buildable_"):
			# Check if it has is_crafting_station property and it's a workbench
			if "is_crafting_station" in child and child.is_crafting_station:
				if "station_type" in child and child.station_type == "workbench":
					# Check distance
					var distance = player.global_position.distance_to(child.global_position)
					if distance <= workbench_range:
						return true

	return false

## Set status message on UI
func _set_status_message(message: String) -> void:
	if status_label:
		status_label.text = message
		status_label.visible = true

## Clear status message
func _clear_status_message() -> void:
	if status_label:
		status_label.text = ""
		status_label.visible = false

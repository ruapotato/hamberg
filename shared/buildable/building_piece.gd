extends StaticBody3D

## BuildingPiece - Individual building component (walls, floors, etc.)
## Used by hammer build mode for placement

@export var piece_name: String = "building_piece"
@export var grid_size: Vector3 = Vector3(2.0, 2.0, 0.2)
@export var snap_to_grid: bool = true
@export var can_rotate: bool = false
@export var rotation_angle: float = 26.5651  # Default roof angle

var max_health: float = 100.0
var current_health: float = 100.0
var is_preview: bool = false  # Ghost preview in build mode
var can_place: bool = true  # Whether current position is valid

# Snap points for piece-to-piece attachment
# Each snap point has: position (local), normal (direction away from piece), and type (what can attach)
var snap_points: Array[Dictionary] = []

func _ready() -> void:
	current_health = max_health
	_setup_snap_points()

	if is_preview:
		_setup_preview_mode()

## Set up snap points based on piece type
func _setup_snap_points() -> void:
	snap_points.clear()

	# Define snap points based on piece type
	match piece_name:
		"wooden_floor":
			# Floor: 4 corner snaps (for creating grid) + comprehensive top surface snaps for walls
			var half_x = grid_size.x / 2.0
			var half_z = grid_size.z / 2.0
			var half_height = grid_size.y / 2.0
			var wall_inset = 0.1  # Inset wall snap points by wall thickness (0.2 / 2)

			# Bottom snap point - for snapping to top of walls (second floor)
			snap_points.append({"position": Vector3(0, -half_height, 0), "normal": Vector3.DOWN, "type": "floor_bottom"})

			# Corner snap points - these define the grid expansion points
			# Each corner can attach up to 4 adjacent floor pieces
			snap_points.append({"position": Vector3(half_x, 0, half_z), "normal": Vector3.ZERO, "type": "floor_corner", "corner_id": "ne"})
			snap_points.append({"position": Vector3(-half_x, 0, half_z), "normal": Vector3.ZERO, "type": "floor_corner", "corner_id": "nw"})
			snap_points.append({"position": Vector3(-half_x, 0, -half_z), "normal": Vector3.ZERO, "type": "floor_corner", "corner_id": "sw"})
			snap_points.append({"position": Vector3(half_x, 0, -half_z), "normal": Vector3.ZERO, "type": "floor_corner", "corner_id": "se"})

			# Top surface snap points for walls - comprehensive coverage with corners and edges
			snap_points.append({"position": Vector3(0, half_height, 0), "normal": Vector3.UP, "type": "floor_top"})  # Center

			# North edge (5 points)
			snap_points.append({"position": Vector3(-half_x + wall_inset, half_height, half_z - wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # NW corner
			snap_points.append({"position": Vector3(-half_x * 0.5, half_height, half_z - wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # North left quarter
			snap_points.append({"position": Vector3(0, half_height, half_z - wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # North center
			snap_points.append({"position": Vector3(half_x * 0.5, half_height, half_z - wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # North right quarter
			snap_points.append({"position": Vector3(half_x - wall_inset, half_height, half_z - wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # NE corner

			# South edge (5 points)
			snap_points.append({"position": Vector3(-half_x + wall_inset, half_height, -half_z + wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # SW corner
			snap_points.append({"position": Vector3(-half_x * 0.5, half_height, -half_z + wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # South left quarter
			snap_points.append({"position": Vector3(0, half_height, -half_z + wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # South center
			snap_points.append({"position": Vector3(half_x * 0.5, half_height, -half_z + wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # South right quarter
			snap_points.append({"position": Vector3(half_x - wall_inset, half_height, -half_z + wall_inset), "normal": Vector3.UP, "type": "floor_top"})  # SE corner

			# East edge (3 intermediate points - corners already covered above)
			snap_points.append({"position": Vector3(half_x - wall_inset, half_height, half_z * 0.5), "normal": Vector3.UP, "type": "floor_top"})  # East north quarter
			snap_points.append({"position": Vector3(half_x - wall_inset, half_height, 0), "normal": Vector3.UP, "type": "floor_top"})  # East center
			snap_points.append({"position": Vector3(half_x - wall_inset, half_height, -half_z * 0.5), "normal": Vector3.UP, "type": "floor_top"})  # East south quarter

			# West edge (3 intermediate points - corners already covered above)
			snap_points.append({"position": Vector3(-half_x + wall_inset, half_height, half_z * 0.5), "normal": Vector3.UP, "type": "floor_top"})  # West north quarter
			snap_points.append({"position": Vector3(-half_x + wall_inset, half_height, 0), "normal": Vector3.UP, "type": "floor_top"})  # West center
			snap_points.append({"position": Vector3(-half_x + wall_inset, half_height, -half_z * 0.5), "normal": Vector3.UP, "type": "floor_top"})  # West south quarter

		"wooden_wall":
			# Wall: 2 side snaps (for adjacent walls) + bottom (for floor) + top (for walls above)
			var half_x = grid_size.x / 2.0
			var half_height = grid_size.y / 2.0

			# Side snaps (for adjacent walls) - at mid-height
			snap_points.append({"position": Vector3(half_x, 0, 0), "normal": Vector3.RIGHT, "type": "wall_edge"})
			snap_points.append({"position": Vector3(-half_x, 0, 0), "normal": Vector3.LEFT, "type": "wall_edge"})

			# Bottom snap (for floor) - at bottom edge, centered
			# No Z-offset to avoid rotation issues
			snap_points.append({"position": Vector3(0, -half_height, 0), "normal": Vector3.DOWN, "type": "wall_bottom"})

			# Top snaps (for walls/roof above) - corners + intermediate points for raycast detection
			snap_points.append({"position": Vector3(-half_x, half_height, 0), "normal": Vector3.UP, "type": "wall_top"})  # Left corner
			snap_points.append({"position": Vector3(-half_x * 0.5, half_height, 0), "normal": Vector3.UP, "type": "wall_top"})  # Left quarter
			snap_points.append({"position": Vector3(0, half_height, 0), "normal": Vector3.UP, "type": "wall_top"})  # Center
			snap_points.append({"position": Vector3(half_x * 0.5, half_height, 0), "normal": Vector3.UP, "type": "wall_top"})  # Right quarter
			snap_points.append({"position": Vector3(half_x, half_height, 0), "normal": Vector3.UP, "type": "wall_top"})  # Right corner

		"wooden_beam":
			# Beam: similar to wall but can attach at various points
			var half_height = grid_size.y / 2.0

			snap_points.append({"position": Vector3(0, -half_height, 0), "normal": Vector3.DOWN, "type": "beam_bottom"})
			snap_points.append({"position": Vector3(0, half_height, 0), "normal": Vector3.UP, "type": "beam_top"})

		"wooden_door":
			# Door: snaps like a wall (bottom, sides, top)
			var half_x = grid_size.x / 2.0
			var half_height = grid_size.y / 2.0
			# Bottom snap (to floor)
			snap_points.append({"position": Vector3(0, -half_height, 0), "normal": Vector3.DOWN, "type": "door_bottom"})
			# Side snaps (for adjacent walls)
			snap_points.append({"position": Vector3(half_x, 0, 0), "normal": Vector3.RIGHT, "type": "wall_edge"})
			snap_points.append({"position": Vector3(-half_x, 0, 0), "normal": Vector3.LEFT, "type": "wall_edge"})
			# Top snaps (for walls/roof above)
			snap_points.append({"position": Vector3(0, half_height, 0), "normal": Vector3.UP, "type": "wall_top"})

		"wooden_roof", "wooden_roof_26", "wooden_roof_45":
			# Roof: bottom edges for attaching to walls
			var half_x = grid_size.x / 2.0
			var half_height = grid_size.y / 2.0
			snap_points.append({"position": Vector3(half_x, -half_height, 0), "normal": Vector3.RIGHT, "type": "roof_edge"})
			snap_points.append({"position": Vector3(-half_x, -half_height, 0), "normal": Vector3.LEFT, "type": "roof_edge"})

		"wooden_stairs":
			# Stairs: bottom snap to floor/stairs, top snap to upper floor/stairs, side snaps to walls
			var half_x = grid_size.x / 2.0
			var half_z = grid_size.z / 2.0
			var half_height = grid_size.y / 2.0
			# Bottom snap (to floor or top of another stair segment)
			snap_points.append({"position": Vector3(0, -half_height, half_z), "normal": Vector3.DOWN, "type": "stairs_bottom"})
			# Top snap (to floor above or bottom of another stair segment) - for chaining stairs
			snap_points.append({"position": Vector3(0, half_height, -half_z), "normal": Vector3.UP, "type": "stairs_top"})
			# Side snaps for walls
			snap_points.append({"position": Vector3(half_x, 0, 0), "normal": Vector3.RIGHT, "type": "stairs_side"})
			snap_points.append({"position": Vector3(-half_x, 0, 0), "normal": Vector3.LEFT, "type": "stairs_side"})

		"workbench":
			# Workbench: just bottom snap to floor
			var half_height = grid_size.y / 2.0
			snap_points.append({"position": Vector3(0, -half_height, 0), "normal": Vector3.DOWN, "type": "workbench_bottom"})

## Set up as a ghost preview
func _setup_preview_mode() -> void:
	# Make semi-transparent
	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat = mat.duplicate()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.5
				child.set_surface_override_material(0, mat)

	# Disable collision for preview
	collision_layer = 0
	collision_mask = 0

## Update preview color based on placement validity
func set_preview_valid(valid: bool, is_snapped: bool = false) -> void:
	can_place = valid

	var color_tint: Color
	if not valid:
		color_tint = Color.RED
	elif is_snapped:
		color_tint = Color(0.3, 1.0, 0.3)  # Bright green when snapped
	else:
		color_tint = Color(0.6, 0.8, 0.6)  # Dimmer green for ground placement

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat.albedo_color = color_tint
				mat.albedo_color.a = 0.6 if is_snapped else 0.5  # Slightly more visible when snapped

## Take damage (SERVER-SIDE)
func take_damage(damage: float) -> bool:
	current_health -= damage

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

## Called when destroyed
func _on_destroyed() -> void:
	print("[BuildingPiece] %s destroyed!" % piece_name)
	queue_free()

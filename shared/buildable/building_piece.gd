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

# Building health system
var _damage_shake_timer: float = 0.0
var _is_damage_shaking: bool = false
var _original_position: Vector3 = Vector3.ZERO
var _health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

# Health values by piece type (set in _ready)
const PIECE_HEALTH_VALUES: Dictionary = {
	"wooden_wall": 200.0,
	"wooden_door": 150.0,
	"wooden_floor": 200.0,
	"wooden_beam": 150.0,
	"wooden_roof_26": 150.0,
	"wooden_roof_45": 150.0,
	"wooden_stairs": 150.0,
	"workbench": 100.0,
	"fireplace": 120.0,
	"cooking_station": 100.0,
	"chest": 80.0,
}

# Snap points for piece-to-piece attachment
# Each snap point has: position (local), normal (direction away from piece), and type (what can attach)
var snap_points: Array[Dictionary] = []

func _ready() -> void:
	# Set health based on piece type
	if PIECE_HEALTH_VALUES.has(piece_name):
		max_health = PIECE_HEALTH_VALUES[piece_name]
	current_health = max_health
	_original_position = position
	_setup_snap_points()

	if is_preview:
		_setup_preview_mode()
	else:
		# Add to player_buildings group for raid targeting
		add_to_group("player_buildings")

func _process(delta: float) -> void:
	if _is_damage_shaking:
		_damage_shake_timer += delta
		var t = _damage_shake_timer / 0.2
		if t >= 1.0:
			_is_damage_shaking = false
			position = _original_position
		else:
			position = _original_position + Vector3(
				sin(_damage_shake_timer * 40.0) * 0.05 * (1.0 - t),
				0,
				cos(_damage_shake_timer * 30.0) * 0.03 * (1.0 - t)
			)

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
	# Replace materials with simple transparent preview materials
	for child in get_children():
		if child is MeshInstance3D:
			# Create a simple StandardMaterial3D for preview (works with any source material type)
			var preview_mat = StandardMaterial3D.new()
			preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			preview_mat.albedo_color = Color(0.6, 0.8, 0.6, 0.5)  # Green tint, semi-transparent
			child.set_surface_override_material(0, preview_mat)

	# Disable collision for preview
	collision_layer = 0
	collision_mask = 0

## Update preview color based on placement validity
func set_preview_valid(valid: bool, is_snapped: bool = false) -> void:
	can_place = valid

	var color_tint: Color
	if not valid:
		color_tint = Color(1.0, 0.3, 0.3)  # Red
	elif is_snapped:
		color_tint = Color(0.3, 1.0, 0.3)  # Bright green when snapped
	else:
		color_tint = Color(0.6, 0.8, 0.6)  # Dimmer green for ground placement

	var alpha = 0.6 if is_snapped else 0.5

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				mat.albedo_color = Color(color_tint.r, color_tint.g, color_tint.b, alpha)

## Take damage from enemies or other sources
func take_damage(damage: float) -> bool:
	current_health -= damage

	# Visual feedback: shake on hit
	_is_damage_shaking = true
	_damage_shake_timer = 0.0
	_original_position = global_position if not _is_damage_shaking else _original_position

	# Visual feedback: tint based on health
	_update_damage_tint()

	# Show health bar
	if not _health_bar:
		_health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(_health_bar)
		_health_bar.set_height_offset(grid_size.y + 0.5)
	if _health_bar:
		_health_bar.update_health(current_health, max_health)

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

## Update mesh tint based on remaining health
func _update_damage_tint() -> void:
	var health_pct = current_health / max_health
	var tint: Color
	if health_pct < 0.25:
		tint = Color(1.0, 0.3, 0.3)  # Red at very low health
	elif health_pct < 0.5:
		tint = Color(1.0, 0.6, 0.4)  # Orange at half health
	else:
		tint = Color(1.0, 1.0, 1.0)  # Normal

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if not mat:
				mat = child.mesh.surface_get_material(0) if child.mesh else null
			if mat and mat is StandardMaterial3D:
				var new_mat = mat.duplicate()
				new_mat.albedo_color = tint
				child.set_surface_override_material(0, new_mat)

## Called when destroyed
func _on_destroyed() -> void:
	print("[BuildingPiece] %s destroyed!" % piece_name)

	# Drop some materials back
	var drop_items: Dictionary = {}
	match piece_name:
		"wooden_wall", "wooden_floor", "wooden_door", "wooden_stairs":
			drop_items = {"wood": 1}
		"wooden_beam":
			drop_items = {"wood": 1}
		"wooden_roof_26", "wooden_roof_45":
			drop_items = {"wood": 1}
		"workbench":
			drop_items = {"wood": 2, "stone": 1}
		"fireplace", "cooking_station":
			drop_items = {"stone": 1}

	# Give dropped items to nearby players
	if not drop_items.is_empty():
		var players = get_tree().get_nodes_in_group("local_player")
		if players.size() > 0:
			var player = players[0]
			for item_name in drop_items:
				if player.has_method("pickup_item"):
					player.pickup_item(item_name, drop_items[item_name])

	queue_free()

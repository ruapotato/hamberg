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

	if result:
		var hit_point = result.position
		var hit_normal = result.normal

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

		ghost_preview.global_position = hit_point

		# Validate placement
		can_place_current = _validate_placement(hit_point)
		ghost_preview.set_preview_valid(can_place_current)
	else:
		# No hit - place in front of player
		ghost_preview.global_position = from + (-camera.global_transform.basis.z * placement_distance)
		can_place_current = false
		ghost_preview.set_preview_valid(false)

func _validate_placement(_position: Vector3) -> bool:
	# TODO: Check for overlaps, terrain validity, etc.
	# For now, always valid if we hit something
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

	var position = ghost_preview.global_position
	var rotation = ghost_preview.rotation.y

	print("[BuildMode] Placing %s at %s" % [current_piece_name, position])

	# Emit signal for server to handle actual placement
	build_piece_placed.emit(current_piece_name, position, rotation)

	# TODO: Check if player has resources and consume them

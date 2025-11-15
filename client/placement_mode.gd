extends Node

## PlacementMode - For placing single buildable items (workbench, etc)
## Activated when player has a placeable item equipped

signal item_placed(item_name: String, position: Vector3, rotation: float)

var is_active: bool = false
var item_to_place: String = ""

# Ghost preview
var ghost_preview: Node3D = null
var placement_distance: float = 5.0
var can_place_current: bool = false

# References
var player: Node3D = null
var camera: Camera3D = null
var world: Node3D = null

func activate(p_player: Node3D, p_camera: Camera3D, p_world: Node3D, item_name: String) -> void:
	if is_active and item_to_place == item_name:
		return

	player = p_player
	camera = p_camera
	world = p_world
	item_to_place = item_name
	is_active = true

	_create_ghost_preview()
	print("[PlacementMode] Activated for %s - Left-click to place, R to rotate" % item_name)

func deactivate() -> void:
	if not is_active:
		return

	is_active = false
	_destroy_ghost_preview()
	item_to_place = ""
	print("[PlacementMode] Deactivated")

func _process(_delta: float) -> void:
	if not is_active or not ghost_preview:
		return

	_update_ghost_position()
	_handle_input()

func _create_ghost_preview() -> void:
	var scene_path = ""
	match item_to_place:
		"workbench":
			scene_path = "res://shared/buildable/workbench.tscn"
		_:
			push_error("[PlacementMode] Unknown item: %s" % item_to_place)
			return

	var piece_scene = load(scene_path)
	if not piece_scene:
		push_error("[PlacementMode] Failed to load scene: %s" % scene_path)
		return

	ghost_preview = piece_scene.instantiate()

	# Set up preview mode
	if ghost_preview.has_method("set_preview_mode"):
		ghost_preview.set_preview_mode()
	else:
		# Manual preview setup
		_setup_preview_manual(ghost_preview)

	world.add_child(ghost_preview)

func _setup_preview_manual(preview: Node3D) -> void:
	# Make semi-transparent
	for child in preview.get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat = mat.duplicate()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.5
				child.set_surface_override_material(0, mat)

	# Disable collision for preview
	if preview is StaticBody3D:
		preview.collision_layer = 0
		preview.collision_mask = 0

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

		# Snap to grid (1m grid for workbench)
		hit_point.x = round(hit_point.x)
		hit_point.y = round(hit_point.y)
		hit_point.z = round(hit_point.z)

		# Place on surface
		ghost_preview.global_position = hit_point

		# Validate placement
		can_place_current = _validate_placement(hit_point)
		_update_preview_color(can_place_current)
	else:
		# No hit - place in front of player
		ghost_preview.global_position = from + (-camera.global_transform.basis.z * placement_distance)
		can_place_current = false
		_update_preview_color(false)

func _update_preview_color(valid: bool) -> void:
	var color_tint = Color.GREEN if valid else Color.RED

	for child in ghost_preview.get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				var base_color = mat.albedo_color
				base_color = color_tint
				base_color.a = 0.5
				mat.albedo_color = base_color

func _validate_placement(_position: Vector3) -> bool:
	# TODO: Check for overlaps, terrain validity, etc.
	# For now, always valid if we hit something
	return true

func _handle_input() -> void:
	# Rotate with R key
	if Input.is_action_just_pressed("build_rotate"):
		rotate_preview()

	# Place with left click
	if Input.is_action_just_pressed("attack") and can_place_current:
		place_current_item()

func rotate_preview() -> void:
	if ghost_preview:
		ghost_preview.rotation.y += deg_to_rad(45.0)

func place_current_item() -> void:
	if not can_place_current or not ghost_preview:
		return

	var position = ghost_preview.global_position
	var rotation = ghost_preview.rotation.y

	print("[PlacementMode] Placing %s at %s" % [item_to_place, position])

	# Emit signal for server to handle actual placement
	item_placed.emit(item_to_place, position, rotation)

	# TODO: Remove item from inventory
	# For now, deactivate placement mode
	deactivate()

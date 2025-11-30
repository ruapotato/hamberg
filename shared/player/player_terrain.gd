class_name PlayerTerrain
extends RefCounted

## PlayerTerrain - Handles terrain modification (dig, place, flatten)
## Works with pickaxe and hoe tools

const PC = preload("res://shared/player/player_constants.gd")
const Equipment = preload("res://shared/equipment.gd")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# MAIN TERRAIN HANDLING
# =============================================================================

## Handle terrain modification input (CLIENT-SIDE)
## Returns true if a terrain action was handled, false if normal combat should proceed
func handle_terrain_input(input_data: Dictionary) -> bool:
	if not player.is_local_player or player.is_dead:
		return false

	# Check equipped main hand item
	var main_hand_id := ""
	if player.equipment:
		main_hand_id = player.equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)

	var is_pickaxe := main_hand_id == "stone_pickaxe"
	var is_hoe := main_hand_id == "stone_hoe"

	if not is_pickaxe and not is_hoe:
		return false  # No terrain tool

	var camera := _get_camera()
	if not camera:
		return false

	# Determine operation
	var operation := ""
	var left_click: bool = input_data.get("attack", false)
	var right_click: bool = input_data.get("secondary_action", false)

	if is_pickaxe:
		if left_click:
			if player.inventory and player.inventory.has_item("earth", 1):
				operation = "place_square"
			else:
				print("[Player] Cannot place earth - need earth in inventory!")
				return false
		elif right_click:
			operation = "dig_square"
	elif is_hoe:
		if left_click or right_click:
			operation = "flatten_square"

	if operation.is_empty():
		return false

	# Get target position
	var target_pos := _get_target_position(operation, camera)
	if target_pos == Vector3.ZERO:
		return false

	# Safety check for placing
	if operation == "place_square":
		var distance := player.global_position.distance_to(target_pos)
		if distance < 2.0:
			print("[Player] Too close to place terrain safely")
			return false

	# Send request and show feedback
	_send_terrain_request(operation, target_pos, main_hand_id)
	_trigger_tool_animation()
	_show_placement_preview(target_pos)

	return true

## Update persistent terrain preview (shows cube when tool equipped)
func update_persistent_preview() -> void:
	if not player.terrain_dig_preview_cube or not player.terrain_place_preview_cube:
		return

	var main_hand_id := ""
	if player.equipment:
		main_hand_id = player.equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)

	var is_pickaxe := main_hand_id == "stone_pickaxe"
	var is_hoe := main_hand_id == "stone_hoe"

	if is_pickaxe:
		_show_pickaxe_preview()
	elif is_hoe:
		_show_hoe_preview()
	else:
		_hide_previews()

## Update terrain preview timer
func update_preview_timer(delta: float) -> void:
	if player.terrain_preview_timer > 0:
		player.terrain_preview_timer -= delta
		if player.terrain_preview_timer <= 0:
			if player.terrain_preview_cube:
				player.terrain_preview_cube.visible = false

# =============================================================================
# PREVIEW DISPLAY
# =============================================================================

func _show_pickaxe_preview() -> void:
	var camera := _get_camera()
	if not camera:
		return

	# RED cube: dig position
	var dig_pos := _raycast_grid_cell(camera)
	if dig_pos != Vector3.ZERO:
		player.cached_dig_position = dig_pos
		player.terrain_dig_preview_cube.global_position = dig_pos
		player.terrain_dig_preview_cube.scale = Vector3(1.05, 1.05, 1.05)
		player.terrain_dig_preview_cube.visible = player.terrain_preview_timer <= 0.0

	# WHITE cube: place position
	var place_pos := _calculate_place_position(camera)
	if place_pos != Vector3.ZERO:
		player.cached_place_position = place_pos
		player.terrain_place_preview_cube.global_position = place_pos
		player.terrain_place_preview_cube.scale = Vector3(1.05, 1.05, 1.05)
		player.terrain_place_preview_cube.visible = player.terrain_preview_timer <= 0.0

	player.is_showing_persistent_preview = true

func _show_hoe_preview() -> void:
	var camera := _get_camera()
	if not camera:
		return

	var target_pos := _raycast_terrain_target(camera)
	if target_pos != Vector3.ZERO:
		target_pos = _snap_to_grid(target_pos)
		player.terrain_dig_preview_cube.global_position = target_pos
		player.terrain_dig_preview_cube.scale = Vector3(8.4, 2.1, 8.4)  # 8x8 area
		player.terrain_dig_preview_cube.visible = player.terrain_preview_timer <= 0.0
		player.terrain_place_preview_cube.visible = false
		player.is_showing_persistent_preview = true

func _hide_previews() -> void:
	if player.is_showing_persistent_preview:
		player.terrain_dig_preview_cube.visible = false
		player.terrain_place_preview_cube.visible = false
		player.is_showing_persistent_preview = false

func _show_placement_preview(position: Vector3) -> void:
	if not player.terrain_preview_cube:
		return

	player.terrain_preview_cube.global_position = position
	player.terrain_preview_cube.scale = Vector3(1.05, 1.05, 1.05)
	player.terrain_preview_cube.visible = true
	player.terrain_preview_timer = PC.TERRAIN_PREVIEW_DURATION

# =============================================================================
# GRID & RAYCASTING
# =============================================================================

func _snap_to_grid(pos: Vector3) -> Vector3:
	var grid_size := 2.0
	return Vector3(
		floor(pos.x / grid_size) * grid_size + grid_size / 2.0,
		floor(pos.y / grid_size) * grid_size + grid_size / 2.0,
		floor(pos.z / grid_size) * grid_size + grid_size / 2.0
	)

func _raycast_grid_cell(camera: Camera3D) -> Vector3:
	var from := camera.global_position
	var direction := -camera.global_transform.basis.z.normalized()
	var to := from + direction * 50.0

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1

	var result := space_state.intersect_ray(query)
	if result:
		var normal: Vector3 = result.normal
		var point_inside: Vector3 = result.position - normal * 1.5
		return _snap_to_grid(point_inside)
	else:
		var point_in_air := from + direction * 5.0
		return _snap_to_grid(point_in_air)

func _raycast_terrain_target(camera: Camera3D) -> Vector3:
	var viewport_size := player.get_viewport().get_visible_rect().size
	var crosshair_pos := viewport_size / 2
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 50.0)
	query.collision_mask = 1
	query.exclude = [player]

	var result := space_state.intersect_ray(query)
	if result:
		return result.position
	return Vector3.ZERO

func _calculate_place_position(camera: Camera3D) -> Vector3:
	var viewport_size := player.get_viewport().get_visible_rect().size
	var crosshair_pos := viewport_size / 2
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 50.0)
	query.collision_mask = 1
	query.exclude = [player]

	var result := space_state.intersect_ray(query)
	if result:
		var normal: Vector3 = result.normal
		var point_above := result.position + normal * 1.5
		return _snap_to_grid(point_above)
	return Vector3.ZERO

func _get_target_position(operation: String, camera: Camera3D) -> Vector3:
	match operation:
		"dig_square":
			return player.cached_dig_position
		"place_square":
			return player.cached_place_position
		"flatten_square":
			var target := _raycast_terrain_target(camera)
			if target == Vector3.ZERO:
				target = player.global_position
			return _snap_to_grid(target)
	return Vector3.ZERO

# =============================================================================
# NETWORK & ANIMATION
# =============================================================================

func _send_terrain_request(operation: String, position: Vector3, tool: String) -> void:
	var data := {"tool": tool}

	if operation == "flatten_square":
		var grid_size: float = 2.0
		var feet_height: float = player.global_position.y - 1.0
		var platform_height: float = floor(feet_height / grid_size) * grid_size + grid_size / 2.0
		data["target_height"] = platform_height

	var pos_array := [position.x, position.y, position.z]
	NetworkManager.rpc_modify_terrain.rpc_id(1, operation, pos_array, data)
	print("[Player] Sent terrain modification: %s at %s" % [operation, position])

func _trigger_tool_animation() -> void:
	player.is_attacking = true
	player.attack_timer = 0.0
	player.current_attack_animation_time = 0.3

	if player.equipped_weapon_visual:
		var tween = player.create_tween()
		tween.tween_property(player.equipped_weapon_visual, "rotation_degrees:x", -30.0, 0.1)
		tween.tween_property(player.equipped_weapon_visual, "rotation_degrees:x", 90.0, 0.2)

func _get_camera() -> Camera3D:
	var camera_controller := player.get_node_or_null("CameraController")
	if camera_controller and camera_controller.has_method("get_camera"):
		return camera_controller.get_camera()
	return null

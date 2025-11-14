extends CharacterBody3D

## Player - Networked player entity with client-side prediction
## This entity works on both client and server, with different logic paths

# Movement parameters
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0
const JUMP_VELOCITY: float = 8.0
const ACCELERATION: float = 10.0
const FRICTION: float = 8.0
const AIR_CONTROL: float = 0.3

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Player state
var current_animation_state: String = "idle"
var is_local_player: bool = false

# Client prediction state
var input_sequence: int = 0
var input_history: Array[Dictionary] = []
const MAX_INPUT_HISTORY: int = 60  # 2 seconds at 30 fps

# Server reconciliation
var last_server_state: Dictionary = {}

# Interpolation for remote players
var interpolation_buffer: Array[Dictionary] = []
const INTERPOLATION_DELAY: float = 0.1  # 100ms
var render_timestamp: float = 0.0

# Visual representation
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	# Determine if this is the local player
	is_local_player = is_multiplayer_authority()

	print("[Player] Player ready (ID: %d, Local: %s)" % [get_multiplayer_authority(), is_local_player])

	# Set collision layer
	collision_layer = 2  # Players layer
	collision_mask = 1   # World layer

	if is_local_player:
		# Local player uses client prediction
		set_physics_process(true)
	else:
		# Remote players use interpolation
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	if not is_local_player:
		# Remote players don't process physics locally
		return

	# CLIENT: Predict movement locally
	var input_data := _gather_input()

	# Handle attack input
	if input_data.get("attack", false):
		_handle_attack()

	# Apply movement prediction
	_apply_movement(input_data, delta)

	# Update animation state
	_update_animation_state()

	# Send position update to server (client-authoritative)
	if NetworkManager.is_client:
		var position_data := {
			"position": global_position,
			"rotation": rotation.y,
			"velocity": velocity,
			"animation_state": current_animation_state
		}
		NetworkManager.rpc_send_player_position.rpc_id(1, position_data)

func _process(delta: float) -> void:
	if not is_local_player:
		# Remote players: Interpolate between states
		_interpolate_remote_player(delta)

# ============================================================================
# INPUT HANDLING (CLIENT-SIDE)
# ============================================================================

func _gather_input() -> Dictionary:
	"""Gather input from the player"""
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var is_sprinting := Input.is_action_pressed("sprint")
	var jump_pressed := Input.is_action_just_pressed("jump")

	# Attack input (left mouse button or custom action if defined)
	var attack_pressed := false
	if Input.is_action_just_pressed("attack") if InputMap.has_action("attack") else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		attack_pressed = true

	return {
		"move_x": input_dir.x,
		"move_z": input_dir.y,
		"sprint": is_sprinting,
		"jump": jump_pressed,
		"attack": attack_pressed,
		"camera_basis": _get_camera_basis()
	}

func _get_camera_basis() -> Basis:
	"""Get the camera's orientation for movement"""
	# Get camera controller if it exists
	var camera_controller := get_node_or_null("CameraController")
	if camera_controller and camera_controller.has_method("get_camera"):
		var camera: Camera3D = camera_controller.get_camera()
		if camera:
			return camera.global_transform.basis

	# Fallback to identity (world-space movement)
	return Basis()

# ============================================================================
# MOVEMENT LOGIC (SHARED: CLIENT PREDICTION & SERVER)
# ============================================================================

func _apply_movement(input_data: Dictionary, delta: float) -> void:
	"""Apply movement based on input (used for both prediction and server)"""

	# Get input values
	var move_x: float = input_data.get("move_x", 0.0)
	var move_z: float = input_data.get("move_z", 0.0)
	var is_sprinting: bool = input_data.get("sprint", false)
	var jump_pressed: bool = input_data.get("jump", false)

	# Calculate movement direction
	var camera_basis: Basis = input_data.get("camera_basis", Basis())
	var input_dir := Vector2(move_x, move_z).normalized()
	var direction := (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jumping
	if jump_pressed and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement speed
	var target_speed := SPRINT_SPEED if is_sprinting else WALK_SPEED
	var control_factor := 1.0 if is_on_floor() else AIR_CONTROL

	# Horizontal movement
	if direction:
		var target_velocity := direction * target_speed
		velocity.x = lerp(velocity.x, target_velocity.x, ACCELERATION * delta * control_factor)
		velocity.z = lerp(velocity.z, target_velocity.z, ACCELERATION * delta * control_factor)
	else:
		# Apply friction
		velocity.x = lerp(velocity.x, 0.0, FRICTION * delta * control_factor)
		velocity.z = lerp(velocity.z, 0.0, FRICTION * delta * control_factor)

	# Apply movement
	move_and_slide()

func _update_animation_state() -> void:
	"""Update animation state based on velocity"""
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if not is_on_floor():
		current_animation_state = "jump"
	elif horizontal_speed > 6.0:
		current_animation_state = "run"
	elif horizontal_speed > 0.5:
		current_animation_state = "walk"
	else:
		current_animation_state = "idle"

# ============================================================================
# SERVER-SIDE INPUT PROCESSING
# ============================================================================

func apply_server_input(input_data: Dictionary) -> void:
	"""SERVER: Apply input from client"""
	if not NetworkManager.is_server:
		return

	# Server processes input and simulates physics
	var delta := get_physics_process_delta_time()
	_apply_movement(input_data, delta)

	# TODO: Send authoritative state back to client for reconciliation
	# For Phase 1, we're using a simpler broadcast approach

# ============================================================================
# CLIENT-SIDE STATE RECONCILIATION
# ============================================================================

func apply_server_state(state: Dictionary) -> void:
	"""CLIENT: Apply authoritative state from server (for remote players)"""
	if is_local_player:
		# Local player uses reconciliation (not implemented in Phase 1)
		# _reconcile_with_server(state)
		return

	# Remote players: Add to interpolation buffer
	interpolation_buffer.append(state)

	# Limit buffer size
	if interpolation_buffer.size() > 30:
		interpolation_buffer.pop_front()

func _reconcile_with_server(state: Dictionary) -> void:
	"""CLIENT: Reconcile local prediction with server state"""
	# TODO: Implement full reconciliation for Phase 2
	# For Phase 1, we're trusting client prediction

	var server_position: Vector3 = state.get("position", Vector3.ZERO)
	var server_sequence: int = state.get("sequence", 0)

	# Check if we need to reconcile
	var position_error := global_position.distance_to(server_position)

	if position_error > 1.0:  # More than 1 meter off
		print("[Player] Large position error (%.2f), reconciling" % position_error)

		# Snap to server position
		global_position = server_position
		velocity = state.get("velocity", Vector3.ZERO)

		# Replay inputs after server state
		for input_data in input_history:
			if input_data.get("sequence", 0) > server_sequence:
				_apply_movement(input_data, get_physics_process_delta_time())

# ============================================================================
# INTERPOLATION FOR REMOTE PLAYERS
# ============================================================================

func _interpolate_remote_player(delta: float) -> void:
	"""Interpolate remote player movement for smooth rendering"""
	if interpolation_buffer.size() < 1:
		return

	# For now (Phase 1), just snap to the latest server position
	# TODO: Implement proper time-based interpolation in Phase 2
	var latest_state := interpolation_buffer[interpolation_buffer.size() - 1]

	# Snap to server position
	var target_pos: Vector3 = latest_state.get("position", global_position)
	var target_rot: float = latest_state.get("rotation", rotation.y)

	# Smooth lerp for visual quality (but use high alpha for responsiveness)
	global_position = global_position.lerp(target_pos, 0.3)
	rotation.y = lerp_angle(rotation.y, target_rot, 0.3)

	# Update animation state
	current_animation_state = latest_state.get("animation_state", "idle")

# ============================================================================
# ATTACK/RESOURCE GATHERING
# ============================================================================

## Handle attack input (CLIENT-SIDE)
func _handle_attack() -> void:
	if not is_local_player:
		return

	# Get camera for raycasting
	var camera := _get_camera()
	if not camera:
		print("[Player] No camera found for attack")
		return

	# Raycast from camera center
	var viewport_size := get_viewport().get_visible_rect().size
	var ray_origin := camera.project_ray_origin(viewport_size / 2)
	var ray_direction := camera.project_ray_normal(viewport_size / 2)
	var ray_end := ray_origin + ray_direction * 5.0  # 5 meter reach

	# Perform raycast
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Only check world layer (environmental objects, terrain)
	query.exclude = [self]  # Exclude the player themselves from the raycast

	var result := space_state.intersect_ray(query)
	if result:
		var hit_object: Object = result.collider
		print("[Player] Hit object: %s at %s" % [hit_object.name, result.position])

		# Check if it's an environmental object
		if hit_object.has_method("get_object_type") and hit_object.has_method("get_object_id"):
			var object_type: String = hit_object.get_object_type()
			var object_id: int = hit_object.get_object_id()
			var chunk_pos: Vector2i = hit_object.chunk_position if hit_object.has("chunk_position") else Vector2i.ZERO

			print("[Player] Attacking %s (ID: %d in chunk %s)" % [object_type, object_id, chunk_pos])

			# Send damage request to server
			_send_damage_request(chunk_pos, object_id, 25.0, result.position)
		else:
			print("[Player] Hit non-environmental object")
	else:
		print("[Player] Attack missed")

## Get the camera for raycasting
func _get_camera() -> Camera3D:
	var camera_controller := get_node_or_null("CameraController")
	if camera_controller and camera_controller.has_method("get_camera"):
		return camera_controller.get_camera()
	return null

## Send damage request to server
func _send_damage_request(chunk_pos: Vector2i, object_id: int, damage: float, hit_position: Vector3) -> void:
	# Send RPC to server via NetworkManager
	NetworkManager.rpc_damage_environmental_object.rpc_id(1, [chunk_pos.x, chunk_pos.y], object_id, damage, hit_position)

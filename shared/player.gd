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

	# Apply movement prediction
	_apply_movement(input_data, delta)

	# Store input in history for reconciliation
	input_data["sequence"] = input_sequence
	input_data["timestamp"] = Time.get_ticks_msec()
	input_history.append(input_data)
	input_sequence += 1

	# Limit input history size
	if input_history.size() > MAX_INPUT_HISTORY:
		input_history.pop_front()

	# Send input to server through NetworkManager
	if NetworkManager.is_client:
		NetworkManager.rpc_send_player_input.rpc_id(1, input_data)

	# Update animation state
	_update_animation_state()

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

	return {
		"move_x": input_dir.x,
		"move_z": input_dir.y,
		"sprint": is_sprinting,
		"jump": jump_pressed,
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
	if interpolation_buffer.size() < 2:
		return

	render_timestamp += delta

	# Find two states to interpolate between
	var render_time := Time.get_ticks_msec() / 1000.0 - INTERPOLATION_DELAY

	# Simple interpolation: just use the two most recent states
	var state_a := interpolation_buffer[interpolation_buffer.size() - 2]
	var state_b := interpolation_buffer[interpolation_buffer.size() - 1]

	var alpha := 0.5  # Simple lerp factor

	# Interpolate position
	var pos_a: Vector3 = state_a.get("position", global_position)
	var pos_b: Vector3 = state_b.get("position", global_position)
	global_position = pos_a.lerp(pos_b, alpha)

	# Interpolate rotation
	var rot_a: float = state_a.get("rotation", rotation.y)
	var rot_b: float = state_b.get("rotation", rotation.y)
	rotation.y = lerp_angle(rot_a, rot_b, alpha)

	# Update animation state
	current_animation_state = state_b.get("animation_state", "idle")

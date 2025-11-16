extends CharacterBody3D

## Player - Networked player entity with client-side prediction
## This entity works on both client and server, with different logic paths

# Preload classes
const Equipment = preload("res://shared/equipment.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")

# Movement parameters
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0
const JUMP_VELOCITY: float = 8.0
const ACCELERATION: float = 10.0
const FRICTION: float = 8.0
const AIR_CONTROL: float = 0.3
const head_height: float = 1.50

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Player state
var current_animation_state: String = "idle"
var is_local_player: bool = false
var animation_phase: float = 0.0  # Accumulated phase for smooth animation cycles

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

# Visual representation (removed - now using body_container from player_body.tscn)

# Attack cooldown
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 0.3  # Match animation time for responsive combat

# Attack animation
var is_attacking: bool = false
var attack_timer: float = 0.0
const ATTACK_ANIMATION_TIME: float = 0.3

# Block/Parry system
var is_blocking: bool = false
var block_timer: float = 0.0
const PARRY_WINDOW: float = 0.2  # Parry window at start of block
const BLOCK_DAMAGE_REDUCTION: float = 0.8  # 80% damage reduction when blocking
const BLOCK_SPEED_MULTIPLIER: float = 0.4  # Move at 40% speed while blocking

# Stun state
var is_stunned: bool = false
var stun_timer: float = 0.0
const STUN_DURATION: float = 1.5  # How long the stun lasts
const STUN_DAMAGE_MULTIPLIER: float = 1.5  # Extra damage taken while stunned

# Viewmodel (first-person arms)
var viewmodel_arms: Node3D = null

# Player body visuals
var body_container: Node3D = null

# Player identity
var player_name: String = "Unknown"

# Inventory (server-authoritative)
var inventory: Node = null

# Equipment (server-authoritative)
var equipment = null  # Equipment instance

# Stamina system
const MAX_STAMINA: float = 100.0
const STAMINA_REGEN_RATE: float = 15.0  # Per second
const STAMINA_REGEN_DELAY: float = 1.0  # Delay after using stamina
const SPRINT_STAMINA_DRAIN: float = 10.0  # Per second
const JUMP_STAMINA_COST: float = 10.0

var stamina: float = MAX_STAMINA
var stamina_regen_timer: float = 0.0  # Time since last stamina use

# Health system
const MAX_HEALTH: float = 100.0
var health: float = MAX_HEALTH
var is_dead: bool = false

# Blocking start time (for shield parry timing)
var block_start_time: float = 0.0

func _ready() -> void:
	# Create inventory
	var Inventory = preload("res://shared/inventory.gd")
	inventory = Inventory.new(get_multiplayer_authority())
	inventory.name = "Inventory"
	add_child(inventory)

	# Create equipment
	equipment = Equipment.new(get_multiplayer_authority())
	equipment.name = "Equipment"
	add_child(equipment)
	equipment.equipment_changed.connect(_on_equipment_changed)
	# Determine if this is the local player
	is_local_player = is_multiplayer_authority()

	print("[Player] Player ready (ID: %d, Local: %s)" % [get_multiplayer_authority(), is_local_player])

	# Set collision layer
	collision_layer = 2  # Players layer
	collision_mask = 1   # World layer

	# Setup player body visuals
	_setup_player_body()

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

	# Update attack cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# Update stun timer
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			stun_timer = 0.0

	# Update stamina regeneration
	_update_stamina(delta)

	# Handle blocking input
	_handle_block_input(delta)

	# CLIENT: Predict movement locally
	var input_data := _gather_input()

	# Handle attack input (can't attack while stunned)
	if input_data.get("attack", false) and attack_cooldown <= 0 and not is_stunned:
		_handle_attack()
		attack_cooldown = ATTACK_COOLDOWN_TIME

	# Apply movement prediction
	_apply_movement(input_data, delta)

	# Update animation state
	_update_animation_state()

	# Update body animations if they exist
	if body_container:
		_update_body_animations(delta)

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

	# Jumping (with stamina cost)
	if jump_pressed and is_on_floor():
		if consume_stamina(JUMP_STAMINA_COST):
			velocity.y = JUMP_VELOCITY

	# Movement speed (sprint drains stamina, blocking reduces speed)
	var can_sprint = is_sprinting and stamina > 0 and not is_blocking  # Can't sprint while blocking
	if can_sprint:
		consume_stamina(SPRINT_STAMINA_DRAIN * delta)
	var target_speed := SPRINT_SPEED if can_sprint else WALK_SPEED

	# Apply blocking speed reduction
	if is_blocking:
		target_speed *= BLOCK_SPEED_MULTIPLIER

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

	# Rotate VISUAL body to face movement direction (not the CharacterBody3D!)
	if direction and body_container:
		var horizontal_speed_check = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed_check > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			body_container.rotation.y = lerp_angle(body_container.rotation.y, target_rotation, delta * 10.0)

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
	if not is_local_player or is_dead:
		return

	# Check if blocking (can't attack while blocking)
	if is_blocking:
		return

	# Get equipped weapon (or default to fists)
	var weapon_data = null  # WeaponData

	if equipment:
		weapon_data = equipment.get_equipped_weapon()

	# Default to fists if no weapon equipped
	if not weapon_data:
		weapon_data = ItemDatabase.get_item("fists")

	# Use weapon stats
	var damage: float = weapon_data.damage
	var knockback: float = weapon_data.knockback
	var attack_speed: float = weapon_data.attack_speed
	var stamina_cost: float = weapon_data.stamina_cost
	var attack_range: float = 5.0  # Melee range (TODO: make this weapon-specific)

	# Check stamina cost
	if not consume_stamina(stamina_cost):
		print("[Player] Not enough stamina to attack!")
		return

	# Trigger attack animation
	is_attacking = true
	attack_timer = 0.0

	# Get camera for raycasting
	var camera := _get_camera()
	if not camera:
		print("[Player] No camera found for attack")
		return

	# Rotate player mesh to face attack direction (one-time rotation at attack start)
	if is_local_player and body_container:
		# Get camera controller's independent yaw (not affected by player rotation)
		var camera_controller = get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			var camera_yaw = camera_controller.camera_rotation.x  # Independent yaw
			body_container.rotation.y = camera_yaw + PI  # Add PI to account for mesh facing +Z (needs 180° flip)

	# Raycast from crosshair position
	var viewport_size := get_viewport().get_visible_rect().size

	# Crosshair is offset to match crosshair.tscn (20px right, 50px up)
	var crosshair_offset := Vector2(21.0, -50.0)
	var crosshair_pos := viewport_size / 2 + crosshair_offset
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)
	var ray_end := ray_origin + ray_direction * 5.0  # 5 meter reach

	# Perform raycast
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1 | 4  # World layer (1) and Enemies layer (bit 2 = 4)
	query.exclude = [self]  # Exclude the player themselves from the raycast

	var result := space_state.intersect_ray(query)
	if result:
		var hit_object: Object = result.collider

		# Check if it's an enemy
		if hit_object.has_method("take_damage") and hit_object.collision_layer & 4:  # Enemy layer
			print("[Player] Attacking enemy %s with %s (%.1f damage, %.1f knockback)" % [hit_object.name, weapon_data.display_name, damage, knockback])
			# CLIENT-AUTHORITATIVE: Damage enemy directly on client
			hit_object.take_damage(damage, knockback, ray_direction)

		# Check if it's an environmental object
		elif hit_object.has_method("get_object_type") and hit_object.has_method("get_object_id"):
			var object_type: String = hit_object.get_object_type()
			var object_id: int = hit_object.get_object_id()
			var chunk_pos: Vector2i = hit_object.chunk_position if "chunk_position" in hit_object else Vector2i.ZERO

			print("[Player] Attacking %s (ID: %d in chunk %s)" % [object_type, object_id, chunk_pos])

			# Send damage request to server
			_send_damage_request(chunk_pos, object_id, damage, result.position)
		else:
			print("[Player] Hit non-damageable object")
	else:
		# Attack missed (no raycast hit)
		pass

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

## Send enemy damage request to server
func _send_enemy_damage_request(enemy_path: NodePath, damage: float, knockback: float, direction: Vector3) -> void:
	# Send RPC to server via NetworkManager
	NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_path, damage, knockback, direction)

# ============================================================================
# BLOCKING & PARRY SYSTEM
# ============================================================================

## Handle block input (CLIENT-SIDE)
func _handle_block_input(delta: float) -> void:
	if not is_local_player or is_dead:
		return

	# Check if player has a shield equipped
	var shield_data = null  # ShieldData
	if equipment:
		shield_data = equipment.get_equipped_shield()

	# Check if block button is pressed (right mouse button)
	var block_pressed = Input.is_action_pressed("block") if InputMap.has_action("block") else false

	# Can't block while stunned
	if block_pressed and stamina > 0 and not is_stunned:
		if not is_blocking:
			is_blocking = true
			block_timer = 0.0
			block_start_time = Time.get_ticks_msec() / 1000.0
			print("[Player] Started blocking%s" % (" (fists)" if not shield_data else " (shield)"))

		# Update block timer
		block_timer += delta

		# Blocking drains stamina (less with shield)
		if shield_data:
			consume_stamina(shield_data.stamina_drain_per_hit * delta * 0.2)
		else:
			# Fist blocking drains more stamina
			consume_stamina(2.0 * delta)
	else:
		if is_blocking:
			print("[Player] Stopped blocking")
		is_blocking = false
		block_timer = 0.0

## Check if attack can be parried (called when taking damage)
func can_parry(shield_data) -> bool:  # shield_data is ShieldData
	if not is_blocking or not shield_data:
		return false

	# Check if within parry window
	var time_blocking = (Time.get_ticks_msec() / 1000.0) - block_start_time
	return time_blocking <= shield_data.parry_window

# ============================================================================
# PLAYER BODY VISUALS
# ============================================================================

func _setup_player_body() -> void:
	"""Create player body from TSCN file"""
	# Load the complete body scene
	var body_scene = preload("res://shared/player_body.tscn")
	body_container = body_scene.instantiate()

	# Add directly to player (this CharacterBody3D)
	add_child(body_container)

	print("[Player] Player body loaded from player_body.tscn")
	print("[Player] Body container parent: %s" % body_container.get_parent().name)

func _update_body_animations(delta: float) -> void:
	"""Animate the legs, arms, and torso based on movement"""
	if not body_container:
		return

	var left_leg = body_container.get_node_or_null("LeftLeg")
	var right_leg = body_container.get_node_or_null("RightLeg")
	var left_arm = body_container.get_node_or_null("LeftArm")
	var right_arm = body_container.get_node_or_null("RightArm")
	var hips = body_container.get_node_or_null("Hips")
	var torso = body_container.get_node_or_null("Torso")
	var neck = body_container.get_node_or_null("Neck")
	var head = body_container.get_node_or_null("Head")

	if not left_leg or not right_leg:
		return

	# Update attack animation
	if is_attacking:
		attack_timer += delta
		if attack_timer >= ATTACK_ANIMATION_TIME:
			is_attacking = false
			attack_timer = 0.0

	# Stun animation overrides everything
	if is_stunned:
		_animate_stun(delta, left_arm, right_arm, left_leg, right_leg)
		return

	# Blocking animation overrides everything (arms forward like push-up stance)
	if is_blocking:
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, -1.2, delta * 25.0)  # Arms forward at shoulder height (fast)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 25.0)  # Keep arms straight forward, not spread
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, -1.2, delta * 25.0)  # Arms forward at shoulder height (fast)
			right_arm.rotation.z = lerp(right_arm.rotation.z, 0.0, delta * 25.0)  # Keep arms straight forward, not spread
	# Attack animation overrides arm movement
	elif is_attacking and right_arm:
		# Swing right arm forward then back
		var attack_progress = attack_timer / ATTACK_ANIMATION_TIME
		var swing_angle = -sin(attack_progress * PI) * 1.2  # Swing forward
		right_arm.rotation.x = swing_angle
	elif right_arm:
		# Normal arm swing will be handled below
		pass

	# When blocking, rotate player mesh to face camera direction (camera stays free)
	if is_local_player and is_blocking and body_container:
		var camera_controller = get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			# Camera remains free to move - we only rotate the mesh
			var camera_yaw = camera_controller.camera_rotation.x
			var target_rotation = camera_yaw + PI  # Add PI to account for mesh facing +Z (needs 180° flip)
			body_container.rotation.y = lerp_angle(body_container.rotation.y, target_rotation, delta * 10.0)

	# Movement animations (walking or defensive shuffle)
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()

	if horizontal_speed > 0.5:
		# Moving - different animation based on blocking state
		var speed_multiplier = horizontal_speed / WALK_SPEED
		animation_phase += delta * 8.0 * speed_multiplier

		if is_blocking:
			# Defensive shuffle - small leg movements, arms stay forward
			var leg_angle = sin(animation_phase) * 0.15  # Half the normal swing
			left_leg.rotation.x = leg_angle
			right_leg.rotation.x = -leg_angle

			# Arms stay in defensive position (already set above)
			# No arm swinging during defensive movement

			# Less torso sway when defending
			if torso:
				var sway = sin(animation_phase) * 0.02
				torso.rotation.z = sway

			# Minimal head bob
			if head:
				var bob = sin(animation_phase * 2.0) * 0.008
				head.position.y = head_height + bob
		else:
			# Normal walking animation
			var leg_angle = sin(animation_phase) * 0.3
			var arm_angle = sin(animation_phase) * 0.2

			# Legs swing opposite
			left_leg.rotation.x = leg_angle
			right_leg.rotation.x = -leg_angle

			# Arms swing opposite to legs (natural walking motion)
			if left_arm and not is_blocking:
				left_arm.rotation.x = -arm_angle  # Left arm swings opposite to left leg
			if right_arm and not is_attacking and not is_blocking:
				right_arm.rotation.x = arm_angle   # Right arm swings opposite to right leg

			# Add subtle torso sway
			if torso:
				var sway = sin(animation_phase) * 0.05
				torso.rotation.z = sway

			# Add subtle head bob
			if head:
				var bob = sin(animation_phase * 2.0) * 0.015
				head.position.y = head_height + bob
	else:
		# Standing still - return to neutral and reset animation phase
		animation_phase = 0.0

		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)

		# Don't reset arms if blocking or attacking
		if left_arm and not is_blocking:
			left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 5.0)
		if right_arm and not is_attacking and not is_blocking:
			right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, 0.0, delta * 5.0)

		if torso:
			torso.rotation.z = lerp(torso.rotation.z, 0.0, delta * 5.0)

		if head:
			head.position.y = lerp(head.position.y, head_height, delta * 5.0)

## Called after camera controller is attached
func setup_viewmodel() -> void:
	"""Setup first-person viewmodel (weapon holder)"""
	# NOTE: Viewmodel is for weapons, not arms
	# Arms are now part of the player body and move with it
	if not is_local_player:
		return

	print("[Player] Viewmodel setup (arms are now part of player body)")

# ============================================================================
# INVENTORY & ITEM PICKUP
# ============================================================================

## Pick up an item (called by resource items on collision)
## Returns true if at least some items were picked up
func pickup_item(item_name: String, amount: int) -> bool:
	if not inventory:
		return false

	var remaining = inventory.add_item(item_name, amount)

	if remaining < amount:
		var picked_up = amount - remaining
		print("[Player] Picked up %d x %s" % [picked_up, item_name])

		# Play pickup sound (TODO)
		# Show pickup notification (TODO)
		return true

	if remaining > 0:
		print("[Player] Inventory full! Couldn't pick up %d x %s" % [remaining, item_name])

	return remaining < amount

# ============================================================================
# STAMINA & HEALTH SYSTEM
# ============================================================================

## Update stamina regeneration
func _update_stamina(delta: float) -> void:
	# Regenerate stamina after delay
	stamina_regen_timer += delta

	if stamina_regen_timer >= STAMINA_REGEN_DELAY:
		stamina = min(stamina + STAMINA_REGEN_RATE * delta, MAX_STAMINA)

## Consume stamina (returns true if enough stamina available)
func consume_stamina(amount: float) -> bool:
	if stamina >= amount:
		stamina -= amount
		stamina_regen_timer = 0.0  # Reset regen delay
		return true
	return false

## Take damage (with blocking/parry support)
func take_damage(damage: float, attacker_id: int = -1, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	var final_damage = damage
	var was_parried = false

	# Apply stun damage multiplier if stunned
	if is_stunned:
		final_damage *= STUN_DAMAGE_MULTIPLIER
		print("[Player] Taking extra damage while stunned! (%.1fx multiplier)" % STUN_DAMAGE_MULTIPLIER)

	# Check for blocking/parrying
	if is_blocking:
		var shield_data = null
		var weapon_data = null
		if equipment:
			shield_data = equipment.get_equipped_shield()
			weapon_data = equipment.get_equipped_weapon()

		# Default to fists if no weapon equipped
		if not weapon_data:
			weapon_data = ItemDatabase.get_item("fists")

		# Get parry window from weapon
		var parry_window = weapon_data.parry_window if weapon_data else 0.15

		# Check for parry (within parry window)
		if block_timer <= parry_window:
			print("[Player] PARRY! Negating damage and stunning attacker%s" % (" (fists)" if not shield_data else " (shield)"))
			was_parried = true
			final_damage = 0

			# Apply stun to attacker
			_apply_stun_to_attacker(attacker_id)
		else:
			# Normal block
			if shield_data:
				# Shield blocking (high reduction)
				final_damage = max(0, damage - shield_data.block_armor)
				consume_stamina(shield_data.stamina_drain_per_hit)
				print("[Player] Blocked with shield! Damage reduced from %d to %d" % [damage, final_damage])
			else:
				# Fist blocking (moderate reduction)
				final_damage = damage * (1.0 - BLOCK_DAMAGE_REDUCTION)
				consume_stamina(10.0)  # Fist blocking costs more stamina
				print("[Player] Blocked with fists! Damage reduced from %d to %d" % [damage, final_damage])

	# Apply damage
	health -= final_damage
	print("[Player] Took %d damage, health: %d" % [final_damage, health])

	# Apply knockback (if not parried)
	if not was_parried and knockback_dir.length() > 0:
		velocity += knockback_dir * 5.0  # Knockback multiplier

	if health <= 0:
		health = 0
		_die()

## Apply stun to attacker (when parry succeeds)
func _apply_stun_to_attacker(attacker_id: int) -> void:
	if attacker_id == -1:
		return

	# Find attacker by instance ID
	var attacker = instance_from_id(attacker_id)
	if not attacker or not is_instance_valid(attacker):
		return

	# Apply stun if the attacker has the apply_stun method (from AnimatedCharacter)
	if attacker.has_method("apply_stun"):
		attacker.apply_stun()
		print("[Player] Stunned attacker: %s" % attacker.name)

## Animate stun wobble effect
func _animate_stun(delta: float, left_arm: Node3D, right_arm: Node3D, left_leg: Node3D, right_leg: Node3D) -> void:
	if not body_container:
		return

	# Wobble the entire body container
	var wobble_speed = 15.0  # Fast wobble
	var wobble_intensity = 0.25  # Strong wobble (radians)

	# Use stun_timer for continuous wobble
	var time = (STUN_DURATION - stun_timer) * wobble_speed
	var wobble_x = sin(time) * wobble_intensity
	var wobble_z = cos(time * 1.3) * wobble_intensity  # Different frequency for more chaotic wobble

	body_container.rotation.x = wobble_x
	body_container.rotation.z = wobble_z

	# Also make arms flail a bit
	if left_arm:
		left_arm.rotation.x = sin(time * 2.0) * 0.5
	if right_arm:
		right_arm.rotation.x = cos(time * 2.0) * 0.5

	# Legs wobble
	if left_leg:
		left_leg.rotation.x = sin(time * 1.5) * 0.3
	if right_leg:
		right_leg.rotation.x = -sin(time * 1.5) * 0.3

## Apply stun to this player
func apply_stun(duration: float = STUN_DURATION) -> void:
	is_stunned = true
	stun_timer = duration
	print("[Player] Stunned for %.1f seconds!" % duration)

## Handle player death
func _die() -> void:
	if is_dead:
		return

	is_dead = true
	print("[Player] Player died!")

	# Disable physics
	set_physics_process(false)

	# Play death animation (programmatic - fall over)
	if body_container:
		var tween = create_tween()
		tween.tween_property(body_container, "rotation:x", PI / 2, 1.0)
		tween.parallel().tween_property(body_container, "position:y", -0.5, 1.0)

	# Notify server of death
	if is_local_player and NetworkManager.is_client:
		NetworkManager.rpc_player_died.rpc_id(1)

	# Respawn after delay
	if is_local_player:
		await get_tree().create_timer(5.0).timeout
		_request_respawn()

## Request respawn from server
func _request_respawn() -> void:
	if not is_local_player:
		return

	print("[Player] Requesting respawn...")
	if NetworkManager.is_client:
		NetworkManager.rpc_request_respawn.rpc_id(1)

## Respawn player (called by server via RPC)
func respawn_at(spawn_position: Vector3) -> void:
	is_dead = false
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	global_position = spawn_position
	velocity = Vector3.ZERO

	print("[Player] Player respawned at %s!" % spawn_position)

	# Reset body rotation and position
	if body_container:
		body_container.rotation = Vector3.ZERO
		body_container.position = Vector3.ZERO

	# Re-enable physics (for all instances)
	set_physics_process(true)

	# Reset camera if this is the local player
	if is_local_player:
		# Camera will follow the repositioned player automatically
		pass

# ============================================================================
# EQUIPMENT SYSTEM
# ============================================================================

## Called when equipment changes (spawn/despawn visuals)
func _on_equipment_changed(slot) -> void:  # slot is Equipment.EquipmentSlot
	print("[Player] Equipment changed in slot: %s" % slot)
	# TODO: Update visual representation
	# - Spawn weapon/shield models in hand
	# - Update armor visuals
	# This will be implemented when we create the weapon/shield scenes

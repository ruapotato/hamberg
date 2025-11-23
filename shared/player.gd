extends CharacterBody3D

## Player - Networked player entity with client-side prediction
## This entity works on both client and server, with different logic paths

# Preload classes
const Equipment = preload("res://shared/equipment.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")
const Projectile = preload("res://shared/projectiles/projectile.gd")

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
var is_game_loaded: bool = false  # Set to true when loading is complete

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
const KNIFE_ANIMATION_TIME: float = 0.225  # 25% faster than normal (0.3 * 0.75)
const SWORD_ANIMATION_TIME: float = 0.3  # Normal speed
var current_attack_animation_time: float = 0.3  # Actual animation time for current attack

# Combo system (for weapons like knife)
var combo_count: int = 0  # Current combo hit (0, 1, 2 for knife's 3-hit combo)
var combo_timer: float = 0.0  # Time since last attack in combo
const COMBO_WINDOW: float = 1.0  # Time window to continue combo
const MAX_COMBO: int = 3  # Maximum combo hits (knife has 3-hit combo)
var current_combo_animation: int = 0  # Which animation to play (0=right slash, 1=left slash, 2=jab)

# Special attack state
var is_special_attacking: bool = false
var special_attack_timer: float = 0.0
const SPECIAL_ATTACK_ANIMATION_TIME: float = 0.5  # Longer than normal attacks
const KNIFE_SPECIAL_ANIMATION_TIME: float = 0.4  # Faster for knife lunge
const SWORD_SPECIAL_ANIMATION_TIME: float = 0.6  # Slower for sword jab
var current_special_attack_animation_time: float = 0.5  # Actual special animation time
var is_lunging: bool = false  # Track if player is performing a lunge attack
var lunge_direction: Vector3 = Vector3.ZERO  # Direction of lunge for maintaining momentum
const LUNGE_FORWARD_FORCE: float = 15.0  # Continuous forward force during lunge
var was_in_air_lunging: bool = false  # Track if we were in air during lunge (for landing detection)

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

# Equipped weapon/shield visuals
var equipped_weapon_visual: Node3D = null  # Main hand weapon
var equipped_shield_visual: Node3D = null  # Off hand shield

# Terrain dig visual feedback
var terrain_preview_sphere: MeshInstance3D = null  # Persistent preview sphere (shows when tool equipped)
var terrain_preview_cube: MeshInstance3D = null    # Temporary shape after placement
var terrain_preview_timer: float = 0.0
const TERRAIN_PREVIEW_DURATION: float = 0.8  # How long to show the actual placed shape
var is_showing_persistent_preview: bool = false   # Track if we're showing the persistent preview

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

# Brain Power system (for magic)
const MAX_BRAIN_POWER: float = 100.0
const BRAIN_POWER_REGEN_RATE: float = 10.0  # Per second (slower than stamina)
const BRAIN_POWER_REGEN_DELAY: float = 2.0  # Delay after using brain power (longer than stamina)

var brain_power: float = MAX_BRAIN_POWER
var brain_power_regen_timer: float = 0.0  # Time since last brain power use

# Health system
const MAX_HEALTH: float = 100.0
var health: float = MAX_HEALTH
var is_dead: bool = false

# Fall death system (for falling out of world)
var fall_time_below_ground: float = 0.0
const FALL_DEATH_TIME: float = 15.0  # 15 seconds of falling below ground = death

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

	# Setup terrain preview shapes (only for local player)
	if is_local_player:
		_setup_terrain_preview_shapes()

	if is_local_player:
		# Local player uses client prediction
		set_physics_process(true)
	else:
		# Remote players use interpolation
		set_physics_process(false)

func _exit_tree() -> void:
	"""Clean up terrain preview shapes when player is removed"""
	if terrain_preview_sphere and is_instance_valid(terrain_preview_sphere):
		terrain_preview_sphere.queue_free()
	if terrain_preview_cube and is_instance_valid(terrain_preview_cube):
		terrain_preview_cube.queue_free()

func _physics_process(delta: float) -> void:
	if not is_local_player:
		# Remote players don't process physics locally
		return

	# Don't process input or movement if game is not fully loaded
	if not is_game_loaded:
		return

	# Update attack cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# Update combo timer
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			# Combo window expired, reset combo
			combo_count = 0
			combo_timer = 0.0

	# Update stun timer
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			stun_timer = 0.0

	# Update stamina regeneration
	_update_stamina(delta)

	# Update brain power regeneration
	_update_brain_power(delta)

	# Handle blocking input
	_handle_block_input(delta)

	# CLIENT: Predict movement locally
	var input_data := _gather_input()

	# Handle terrain modification input (pickaxe/hoe/placing)
	if input_data.get("attack", false) or input_data.get("secondary_action", false) or input_data.get("middle_mouse", false):
		var handled_terrain_action = _handle_terrain_modification_input(input_data)
		# Only process combat if terrain modification wasn't handled
		if not handled_terrain_action:
			# Handle special attack input (can't attack while stunned or blocking)
			if input_data.get("special_attack", false) and attack_cooldown <= 0 and not is_stunned and not is_blocking:
				_handle_special_attack()
				attack_cooldown = ATTACK_COOLDOWN_TIME
			# Handle normal attack input (can't attack while stunned or blocking)
			elif input_data.get("attack", false) and attack_cooldown <= 0 and not is_stunned and not is_blocking:
				_handle_attack()
				attack_cooldown = ATTACK_COOLDOWN_TIME
	# Handle special attack input when no other input (can't attack while stunned or blocking)
	elif input_data.get("special_attack", false) and attack_cooldown <= 0 and not is_stunned and not is_blocking:
		_handle_special_attack()
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
	else:
		# Local player: Update persistent terrain preview
		_update_persistent_terrain_preview()

		# Update temporary shape timer (cube/sphere shown after placement)
		if terrain_preview_timer > 0.0:
			terrain_preview_timer -= delta
			if terrain_preview_timer <= 0.0:
				# Hide temporary shape when timer expires
				if terrain_preview_cube:
					terrain_preview_cube.visible = false
				# Re-enable persistent preview if we have a terrain tool equipped
				_update_persistent_terrain_preview()

# ============================================================================
# INPUT HANDLING (CLIENT-SIDE)
# ============================================================================

func _gather_input() -> Dictionary:
	"""Gather input from the player"""
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var is_sprinting := Input.is_action_pressed("sprint")

	# Don't allow jump when mouse is visible (menus are open)
	var jump_pressed := false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		jump_pressed = Input.is_action_just_pressed("jump")

	# Attack input (left mouse button or custom action if defined)
	var attack_pressed := false
	if Input.is_action_just_pressed("attack") if InputMap.has_action("attack") else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		attack_pressed = true

	# Secondary action input (right mouse button / right bumper for controller)
	var secondary_action_pressed := false
	if Input.is_action_just_pressed("secondary_action") if InputMap.has_action("secondary_action") else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		secondary_action_pressed = true

	# Special attack input (middle mouse button)
	var special_attack_pressed := false
	if Input.is_action_just_pressed("special_attack"):
		special_attack_pressed = true

	# Middle mouse button (for terrain grow/erode)
	var middle_mouse_pressed := false
	if Input.is_action_just_pressed("special_attack"):  # Middle mouse is already mapped to special_attack
		middle_mouse_pressed = true

	return {
		"move_x": input_dir.x,
		"move_z": input_dir.y,
		"sprint": is_sprinting,
		"jump": jump_pressed,
		"attack": attack_pressed,
		"secondary_action": secondary_action_pressed,
		"special_attack": special_attack_pressed,
		"middle_mouse": middle_mouse_pressed,
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

	# Gravity (only apply if game is loaded)
	if not is_on_floor() and is_game_loaded:
		velocity.y -= gravity * delta

	# Fall death detection: Track time falling below ground level
	if is_game_loaded and is_local_player:
		var ground_level: float = 0.0  # Sea level is at Y=0
		if global_position.y < ground_level and not is_on_floor():
			# Player is below ground and falling
			fall_time_below_ground += delta

			if fall_time_below_ground >= FALL_DEATH_TIME:
				print("[Player] Fall death! Fell below ground for %.1f seconds" % fall_time_below_ground)
				# Kill the player
				health = 0
				_die()
		else:
			# Reset fall timer if above ground or on floor
			fall_time_below_ground = 0.0

	# Lunge momentum - maintain forward arc while lunging in the air
	if is_lunging and not is_on_floor():
		# Continuously apply forward force to maintain arc trajectory
		velocity.x = lunge_direction.x * 5.0  # Maintain constant forward speed (matching initial velocity)
		velocity.z = lunge_direction.z * 5.0
		# Don't modify y velocity - let gravity create the arc and pull down hard

		# STUCK DETECTION: If velocity magnitude is near zero, we hit a wall/enemy - stop lunging
		var velocity_magnitude = Vector3(velocity.x, 0, velocity.z).length()
		if velocity_magnitude < 0.5:  # Nearly stopped
			print("[Player] Lunge STUCK (velocity near zero)! Ending lunge state.")
			is_lunging = false
			was_in_air_lunging = false
			lunge_direction = Vector3.ZERO
			velocity.x = 0.0
			velocity.z = 0.0
			# Reset weapon rotation
			if equipped_weapon_visual:
				equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
				print("[Player] Reset weapon to 90 degrees")

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

	# Horizontal movement (skip if lunging - lunge controls movement)
	if not is_lunging:
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

	# LUNGE LANDING DETECTION - Check immediately after move_and_slide() updates is_on_floor()
	# Track if we're in the air during lunge
	if is_lunging and not is_on_floor():
		if not was_in_air_lunging:
			print("[Player] Lunge entered air! was_in_air_lunging now TRUE")
		was_in_air_lunging = true

	# Detect landing: were in air lunging, now on floor
	if is_lunging and was_in_air_lunging and is_on_floor():
		# LANDED! End lunge immediately
		print("[Player] Lunge LANDED! Ending lunge state. is_on_floor: %s, velocity: %s" % [is_on_floor(), velocity])

		is_lunging = false
		was_in_air_lunging = false
		lunge_direction = Vector3.ZERO

		# STOP all momentum immediately to prevent sliding
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0

		# Reset weapon rotation when lunge completes (on landing)
		if equipped_weapon_visual:
			equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
			print("[Player] Reset weapon to 90 degrees")

	# Rotate VISUAL body to face movement direction (not the CharacterBody3D!)
	# UNLESS blocking or lunging - then stay facing shield/lunge direction
	if direction and body_container and not is_blocking and not is_lunging:
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

	# COMBO SYSTEM: Check if this is a knife (which has combo attacks)
	var is_knife = weapon_data.item_id == "stone_knife"
	var is_sword = weapon_data.item_id == "stone_sword"
	var combo_multiplier: float = 1.0  # Damage multiplier based on combo

	# Set animation speed based on weapon type
	if is_knife:
		current_attack_animation_time = KNIFE_ANIMATION_TIME  # 25% faster
	elif is_sword:
		current_attack_animation_time = SWORD_ANIMATION_TIME  # Normal speed
	else:
		current_attack_animation_time = ATTACK_ANIMATION_TIME  # Default

	if is_knife:
		# Store current combo animation BEFORE incrementing
		current_combo_animation = combo_count  # 0=right slash, 1=left slash, 2=jab

		# Knife has a 3-hit combo: right slash, left slash, forward JAB (third is stronger)
		if combo_count == 2:  # Third hit (index 2)
			combo_multiplier = 1.5  # 50% more damage on jab
			print("[Player] Knife combo FINISHER - Forward JAB! (Hit %d)" % (combo_count + 1))

			# Rotate knife to 0 degrees (straight) for jab finisher
			if equipped_weapon_visual:
				equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)
		elif combo_count == 0:
			print("[Player] Knife combo hit 1 - Right slash")
			# Reset to normal angle for slashes
			if equipped_weapon_visual:
				equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
		else:
			print("[Player] Knife combo hit 2 - Left slash")
			# Reset to normal angle for slashes
			if equipped_weapon_visual:
				equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)

		# Advance combo
		combo_count = (combo_count + 1) % MAX_COMBO
		combo_timer = COMBO_WINDOW  # Reset combo window
	else:
		# Non-combo weapons always use default slash animation
		current_combo_animation = 0
		combo_count = 0
		combo_timer = 0.0

		# Reset weapon to normal angle
		if equipped_weapon_visual:
			equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)

	# Use weapon stats
	var damage: float = weapon_data.damage * combo_multiplier
	var knockback: float = weapon_data.knockback
	var attack_speed: float = weapon_data.attack_speed
	var stamina_cost: float = weapon_data.stamina_cost
	var attack_range: float = 5.0  # Melee range (TODO: make this weapon-specific)

	# Check resource cost (brain power for magic weapons, stamina for others)
	var is_magic_weapon = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC
	if is_magic_weapon:
		if not consume_brain_power(stamina_cost):  # For magic weapons, stamina_cost is actually brain power cost
			print("[Player] Not enough brain power to attack!")
			return
	else:
		if not consume_stamina(stamina_cost):
			print("[Player] Not enough stamina to attack!")
			return

	# Trigger attack animation
	is_attacking = true
	attack_timer = 0.0

	# Get camera for raycasting/aiming
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

	# Check if this is a ranged weapon (magic or ranged)
	var is_ranged = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC or weapon_data.weapon_type == WeaponData.WeaponType.RANGED

	if is_ranged:
		# RANGED ATTACK: Spawn projectile
		_spawn_projectile(weapon_data, camera)
	else:
		# MELEE ATTACK: Raycast from crosshair position
		var viewport_size := get_viewport().get_visible_rect().size

		# Crosshair is offset to match crosshair.tscn (20px right, 50px up)
		var crosshair_offset := Vector2(21.0, -50.0)
		var crosshair_pos := viewport_size / 2 + crosshair_offset
		var ray_origin := camera.project_ray_origin(crosshair_pos)
		var ray_direction := camera.project_ray_normal(crosshair_pos)
		var ray_end := ray_origin + ray_direction * attack_range

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

## Handle special attack input (CLIENT-SIDE) - Middle mouse button attacks
func _handle_special_attack() -> void:
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

	# Get camera for raycasting/aiming
	var camera := _get_camera()
	if not camera:
		print("[Player] No camera found for special attack")
		return

	# Reset combo on special attack
	combo_count = 0
	combo_timer = 0.0

	# Different special attacks based on weapon type
	match weapon_data.item_id:
		"stone_knife":
			_special_attack_knife_lunge(weapon_data, camera)
		"stone_sword":
			_special_attack_sword_stab(weapon_data, camera)
		"fire_wand":
			_special_attack_fire_wand_area(weapon_data, camera)
		_:
			# Default special attack (same as normal attack but 1.5x damage)
			_special_attack_default(weapon_data, camera)

## Knife special: Lunge forward jab (high damage, high stamina, moves player forward)
func _special_attack_knife_lunge(weapon_data: WeaponData, camera: Camera3D) -> void:
	var stamina_cost: float = 25.0  # High stamina cost
	var damage: float = weapon_data.damage * 2.5  # 2.5x damage for lunge
	var knockback: float = weapon_data.knockback * 1.5
	var attack_range: float = 7.0  # Longer range for lunge

	# Check stamina cost
	if not consume_stamina(stamina_cost):
		print("[Player] Not enough stamina for knife lunge!")
		return

	# LEAP forward in camera direction (powerful lunge)
	var camera_forward = -camera.global_transform.basis.z  # Camera facing direction
	var horizontal_direction = Vector3(camera_forward.x, 0, camera_forward.z).normalized()

	# Store lunge direction for continuous momentum
	lunge_direction = horizontal_direction

	# Moderate forward leap with upward component (arcs down harder)
	velocity = horizontal_direction * 5.0  # Reduced forward momentum for tighter control
	velocity.y = 9.0  # Reduced upward component for shorter, tighter arc

	print("[Player] Knife LUNGE LEAP attack! is_on_floor: %s" % is_on_floor())

	# Trigger special attack animation (faster for knife)
	is_special_attacking = true
	is_lunging = true  # Enable crouch animation
	was_in_air_lunging = false  # Reset landing tracker (will be set to true when in air)
	special_attack_timer = 0.0
	current_special_attack_animation_time = KNIFE_SPECIAL_ANIMATION_TIME

	print("[Player] Lunge state set: is_lunging=%s, was_in_air_lunging=%s" % [is_lunging, was_in_air_lunging])

	# IMMEDIATELY snap player mesh to face lunge direction (no lerp - prevents tangled mesh)
	if is_local_player and body_container:
		var camera_controller = get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			var camera_yaw = camera_controller.camera_rotation.x
			body_container.rotation.y = camera_yaw + PI  # Instant snap to face lunge direction
			print("[Player] Snapped mesh to face lunge direction: %.2f radians" % body_container.rotation.y)

	# Rotate knife to 0 degrees (straight/horizontal) for lunge
	if equipped_weapon_visual:
		equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)  # Straight angle for lunge

	# Perform melee raycast attack
	_perform_melee_attack(camera, attack_range, damage, knockback)

## Sword special: Stab forward (piercing jab attack - longer and slower than third swipe)
func _special_attack_sword_stab(weapon_data: WeaponData, camera: Camera3D) -> void:
	var stamina_cost: float = 20.0
	var damage: float = weapon_data.damage * 2.2  # 2.2x damage for powerful jab
	var knockback: float = weapon_data.knockback * 0.5  # Less knockback, more penetration
	var attack_range: float = 6.5  # Longer range for jab

	# Check stamina cost
	if not consume_stamina(stamina_cost):
		print("[Player] Not enough stamina for sword jab!")
		return

	print("[Player] Sword powerful JAB attack!")

	# Trigger special attack animation (slower for sword jab - longer and more powerful)
	is_special_attacking = true
	special_attack_timer = 0.0
	current_special_attack_animation_time = SWORD_SPECIAL_ANIMATION_TIME

	# Rotate player mesh to face attack direction
	if is_local_player and body_container:
		var camera_controller = get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			var camera_yaw = camera_controller.camera_rotation.x
			body_container.rotation.y = camera_yaw + PI

	# Rotate sword to 0 degrees (straight/horizontal) for jab
	if equipped_weapon_visual:
		equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)  # Straight angle for jab

	# Perform melee raycast attack
	_perform_melee_attack(camera, attack_range, damage, knockback)

## Fire wand special: Area fire effect at mouse position (ground fire)
func _special_attack_fire_wand_area(weapon_data: WeaponData, camera: Camera3D) -> void:
	var brain_power_cost: float = 30.0  # Very high brain power cost
	var damage: float = weapon_data.damage * 1.2  # 1.2x damage per tick
	var area_radius: float = 5.0  # 5 meter radius
	var duration: float = 3.0  # 3 seconds of burning

	# Check brain power cost (fire wand is a MAGIC weapon)
	if not consume_brain_power(brain_power_cost):
		print("[Player] Not enough brain power for fire area!")
		return

	print("[Player] Fire wand AREA EFFECT!")

	# Trigger special attack animation
	is_special_attacking = true
	special_attack_timer = 0.0

	# Raycast to find ground position at mouse cursor
	var viewport_size := get_viewport().get_visible_rect().size
	var crosshair_offset := Vector2(21.0, -50.0)
	var crosshair_pos := viewport_size / 2 + crosshair_offset
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 100.0)
	query.collision_mask = 1  # World layer only
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	if result:
		var ground_pos: Vector3 = result.position
		print("[Player] Creating fire area at %s" % ground_pos)

		# Spawn fire area effect scene
		var fire_area_scene = load("res://shared/effects/fire_area.tscn")
		var fire_area = fire_area_scene.instantiate()
		get_tree().root.add_child(fire_area)
		fire_area.global_position = ground_pos
		fire_area.radius = area_radius
		fire_area.damage = damage
		fire_area.duration = duration
	else:
		print("[Player] No ground found for fire area")

## Default special attack (1.5x damage, same as normal attack otherwise)
func _special_attack_default(weapon_data: WeaponData, camera: Camera3D) -> void:
	var resource_cost: float = weapon_data.stamina_cost * 2.0
	var damage: float = weapon_data.damage * 1.5
	var knockback: float = weapon_data.knockback
	var attack_range: float = 5.0

	# Check resource cost (brain power for magic weapons, stamina for others)
	var is_magic_weapon = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC
	if is_magic_weapon:
		if not consume_brain_power(resource_cost):
			print("[Player] Not enough brain power for special attack!")
			return
	else:
		if not consume_stamina(resource_cost):
			print("[Player] Not enough stamina for special attack!")
			return

	print("[Player] Special attack!")

	# Trigger special attack animation
	is_special_attacking = true
	special_attack_timer = 0.0

	# Rotate player mesh to face attack direction
	if is_local_player and body_container:
		var camera_controller = get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			var camera_yaw = camera_controller.camera_rotation.x
			body_container.rotation.y = camera_yaw + PI

	# Check if ranged weapon
	var is_ranged = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC or weapon_data.weapon_type == WeaponData.WeaponType.RANGED
	if is_ranged:
		_spawn_projectile(weapon_data, camera)
	else:
		_perform_melee_attack(camera, attack_range, damage, knockback)

## Helper: Perform melee raycast attack (extracted from _handle_attack)
func _perform_melee_attack(camera: Camera3D, attack_range: float, damage: float, knockback: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var crosshair_offset := Vector2(21.0, -50.0)
	var crosshair_pos := viewport_size / 2 + crosshair_offset
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)
	var ray_end := ray_origin + ray_direction * attack_range

	# Perform raycast
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1 | 4  # World layer (1) and Enemies layer (bit 2 = 4)
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	if result:
		var hit_object: Object = result.collider

		# Check if it's an enemy
		if hit_object.has_method("take_damage") and hit_object.collision_layer & 4:  # Enemy layer
			print("[Player] Hit enemy %s (%.1f damage, %.1f knockback)" % [hit_object.name, damage, knockback])
			hit_object.take_damage(damage, knockback, ray_direction)

		# Check if it's an environmental object
		elif hit_object.has_method("get_object_type") and hit_object.has_method("get_object_id"):
			var object_type: String = hit_object.get_object_type()
			var object_id: int = hit_object.get_object_id()
			var chunk_pos: Vector2i = hit_object.chunk_position if "chunk_position" in hit_object else Vector2i.ZERO

			print("[Player] Attacking %s (ID: %d in chunk %s)" % [object_type, object_id, chunk_pos])
			_send_damage_request(chunk_pos, object_id, damage, result.position)

## Helper: Deal damage to all enemies in an area
func _deal_area_damage(center: Vector3, radius: float, damage: float) -> void:
	# Get all enemies in the scene
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check if enemy is in range
		var distance = enemy.global_position.distance_to(center)
		if distance <= radius:
			var direction = (enemy.global_position - center).normalized()
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage, 2.0, direction)
				print("[Player] Area damage hit %s at distance %.1fm" % [enemy.name, distance])

## Spawn a projectile for ranged weapons
func _spawn_projectile(weapon_data: WeaponData, camera: Camera3D) -> void:
	# Check if weapon has a projectile scene
	if not weapon_data.projectile_scene:
		print("[Player] Weapon %s has no projectile scene" % weapon_data.item_id)
		return

	# Calculate spawn position (from wand tip or hand)
	var spawn_pos := global_position + Vector3(0, 1.5, 0)  # Default: chest height

	# Try to get wand/weapon tip position
	if equipped_weapon_visual and is_instance_valid(equipped_weapon_visual):
		# Find the tip node if it exists, otherwise use the weapon position
		if equipped_weapon_visual.has_node("Tip"):
			var tip = equipped_weapon_visual.get_node("Tip")
			spawn_pos = tip.global_position
		else:
			spawn_pos = equipped_weapon_visual.global_position
			# Offset forward a bit from weapon position
			spawn_pos += equipped_weapon_visual.global_transform.basis.z * 0.3

	# Calculate target position from crosshair
	var viewport_size := get_viewport().get_visible_rect().size
	var crosshair_offset := Vector2(21.0, -50.0)
	var crosshair_pos := viewport_size / 2 + crosshair_offset
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	# Raycast to find target position
	var target_pos := ray_origin + ray_direction * 100.0  # Default: far away

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 100.0)
	query.collision_mask = 1 | 2 | 4  # World, Players, Enemies
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	if result:
		target_pos = result.position

	# Calculate direction from spawn position to target
	var direction := (target_pos - spawn_pos).normalized()

	# Instantiate projectile
	var projectile: Projectile = weapon_data.projectile_scene.instantiate()
	get_tree().root.add_child(projectile)

	# Set up projectile with weapon stats
	var speed := weapon_data.projectile_speed if weapon_data.projectile_speed > 0 else 30.0
	projectile.setup(spawn_pos, direction, speed, weapon_data.damage, get_instance_id())

	print("[Player] Spawned %s projectile toward %s" % [weapon_data.item_id, target_pos])

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
# TERRAIN MODIFICATION (PICKAXE, HOE, PLACING)
# ============================================================================

## Handle terrain modification input (CLIENT-SIDE)
## Returns true if a terrain action was handled, false if normal combat should proceed
func _handle_terrain_modification_input(input_data: Dictionary) -> bool:
	if not is_local_player or is_dead:
		return false

	# Check equipped main hand item
	var main_hand_id := ""
	if equipment:
		main_hand_id = equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)

	# Check if it's a terrain tool or if we have placeable material
	var is_pickaxe := main_hand_id == "stone_pickaxe"
	var is_hoe := main_hand_id == "stone_hoe"
	var is_placeable_material := main_hand_id == "earth" if inventory and inventory.has_item("earth", 1) else false

	# Check if any terrain action applies
	if not is_pickaxe and not is_hoe and not is_placeable_material:
		# Debug: Show what's equipped when player tries to use terrain tools
		if main_hand_id.is_empty():
			print("[Player] No terrain tool - nothing equipped to main hand")
		else:
			print("[Player] No terrain tool - equipped: %s" % main_hand_id)
		return false  # No terrain tool, proceed with normal combat

	# Debug: Confirm terrain tool is equipped
	print("[Player] Terrain tool equipped: %s" % main_hand_id)

	# Get camera for raycasting
	var camera := _get_camera()
	if not camera:
		print("[Player] ERROR: No camera found for terrain raycast")
		return false

	# Raycast to find target position on terrain
	var target_pos := _raycast_terrain_target(camera)
	if target_pos == Vector3.ZERO:
		print("[Player] No valid terrain target found - aim at the ground/terrain")
		return false

	# Determine operation based on tool and input
	var operation := ""
	var left_click: bool = input_data.get("attack", false)
	var right_click: bool = input_data.get("secondary_action", false)
	var middle_click: bool = input_data.get("middle_mouse", false)

	if is_pickaxe:
		if left_click:
			operation = "dig_circle"
		elif right_click or middle_click:
			# Right-click (mouse) or RB (controller) does square dig
			operation = "dig_square"
	elif is_hoe:
		if left_click or right_click:
			operation = "level_circle"
	elif is_placeable_material:
		if left_click:
			operation = "place_circle"
		elif right_click or middle_click:
			# Right-click (mouse) or RB (controller) does square placement
			operation = "place_square"

	# Safety check: Don't allow terrain placement too close to player (prevents clipping through mesh)
	if not operation.is_empty() and operation in ["place_circle", "place_square"]:
		var distance_to_player := global_position.distance_to(target_pos)
		if distance_to_player < 2.0:
			print("[Player] Too close to place terrain safely (min distance: 2.0m)")
			return false

	# Send terrain modification request to server
	if not operation.is_empty():
		_send_terrain_modification_request(operation, target_pos, main_hand_id)
		print("[Player] Sent terrain modification: %s at %s" % [operation, target_pos])

		# Trigger visual feedback animation
		_trigger_terrain_tool_animation(operation)

		# Show terrain preview shape
		_show_terrain_preview(operation, target_pos)

		return true

	return false

## Update persistent terrain preview (shows sphere when tool equipped)
func _update_persistent_terrain_preview() -> void:
	if not terrain_preview_sphere:
		return

	# Check if we have a terrain tool equipped
	var main_hand_id := ""
	if equipment:
		main_hand_id = equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)

	var is_pickaxe := main_hand_id == "stone_pickaxe"
	var is_hoe := main_hand_id == "stone_hoe"
	var is_placeable_material := main_hand_id == "earth"

	# If we have a terrain tool equipped, show persistent preview
	if is_pickaxe or is_hoe or is_placeable_material:
		# Get camera for raycasting
		var camera := _get_camera()
		if camera:
			# Raycast to find target position on terrain
			var target_pos := _raycast_terrain_target(camera)
			if target_pos != Vector3.ZERO:
				# Show sphere preview at target position
				terrain_preview_sphere.global_position = target_pos

				# Size the sphere appropriately based on tool
				if is_hoe:
					terrain_preview_sphere.scale = Vector3(4.0, 4.0, 4.0)  # Leveling radius
				else:
					terrain_preview_sphere.scale = Vector3(1.0, 1.0, 1.0)  # Standard radius (approximates 2x2 cube)

				# Only show if we're not showing a temporary shape
				if terrain_preview_timer <= 0.0:
					terrain_preview_sphere.visible = true
				else:
					terrain_preview_sphere.visible = false

				is_showing_persistent_preview = true
				return

	# No terrain tool equipped, hide persistent preview
	if is_showing_persistent_preview:
		terrain_preview_sphere.visible = false
		is_showing_persistent_preview = false

## Show terrain preview shape (after placement) - briefly shows the actual placed shape
func _show_terrain_preview(operation: String, position: Vector3) -> void:
	if not terrain_preview_sphere or not terrain_preview_cube:
		return

	# For square operations, show cube briefly. For all others, show sphere
	var is_square_operation := operation in ["dig_square", "place_square"]

	if is_square_operation:
		# Show cube briefly, aligned to voxel grid like the actual dig
		var center_x := roundi(position.x)
		var center_y := roundi(position.y)
		var center_z := roundi(position.z)
		terrain_preview_cube.global_position = Vector3(center_x, center_y, center_z)
		terrain_preview_cube.visible = true
		terrain_preview_sphere.visible = false  # Hide persistent preview temporarily
	else:
		# Show sphere with appropriate size based on operation
		terrain_preview_sphere.global_position = position

		# Scale sphere based on operation
		if operation == "level_circle":
			terrain_preview_sphere.scale = Vector3(4.0, 4.0, 4.0)  # Match smooth_radius
		elif operation == "grow_sphere" or operation == "erode_sphere":
			terrain_preview_sphere.scale = Vector3(3.0, 3.0, 3.0)  # Match grow/erode radius
		else:
			terrain_preview_sphere.scale = Vector3(1.0, 1.0, 1.0)  # Match CIRCLE_RADIUS

		terrain_preview_sphere.visible = true
		terrain_preview_cube.visible = false

	# Reset the timer to keep shape visible temporarily
	terrain_preview_timer = TERRAIN_PREVIEW_DURATION

## Trigger animation for terrain tool usage
func _trigger_terrain_tool_animation(operation: String) -> void:
	# Trigger attack animation for visual feedback
	is_attacking = true
	attack_timer = 0.0

	# Use different animation times based on operation
	if operation in ["dig_circle", "place_circle"]:
		current_attack_animation_time = 0.25  # Quick animation for circles
	else:
		current_attack_animation_time = 0.3  # Slightly slower for squares

	# Weapon swing animation (if we had a weapon visual, it would swing)
	if equipped_weapon_visual:
		# Rotate the tool for visual feedback
		var tween = create_tween()
		tween.tween_property(equipped_weapon_visual, "rotation_degrees:x", -30.0, 0.1)
		tween.tween_property(equipped_weapon_visual, "rotation_degrees:x", 90.0, 0.2)

## Raycast to find terrain target position
func _raycast_terrain_target(camera: Camera3D) -> Vector3:
	var viewport_size := get_viewport().get_visible_rect().size
	var crosshair_pos := viewport_size / 2
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	# Raycast for terrain (layer 1 = world/terrain)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 50.0)
	query.collision_mask = 1  # World layer only
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	if result:
		return result.position

	return Vector3.ZERO

## Send terrain modification request to server
func _send_terrain_modification_request(operation: String, position: Vector3, tool: String) -> void:
	var data := {
		"tool": tool
	}

	# For hoe leveling, include player's standing height
	if operation == "level_circle":
		data["target_height"] = global_position.y

	# For grow/erode sphere, include strength and radius
	if operation == "grow_sphere" or operation == "erode_sphere":
		data["strength"] = 5.0  # Moderate strength for gradual changes
		data["radius"] = 3.0    # 3 meter radius

	# Send RPC to server via NetworkManager
	var pos_array := [position.x, position.y, position.z]
	NetworkManager.rpc_modify_terrain.rpc_id(1, operation, pos_array, data)

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

	# Don't block if holding a terrain tool (pickaxe, hoe, or placeable material)
	var main_hand_id := ""
	if equipment:
		main_hand_id = equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)

	var is_terrain_tool := main_hand_id == "stone_pickaxe" or main_hand_id == "stone_hoe" or main_hand_id == "earth"

	if is_terrain_tool:
		# Clear blocking state if we have a terrain tool equipped
		if is_blocking:
			is_blocking = false
			block_timer = 0.0
		return

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

func _setup_terrain_preview_shapes() -> void:
	"""Create preview shapes for terrain modification feedback"""
	# Create sphere preview
	terrain_preview_sphere = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.0  # Will match CIRCLE_RADIUS from terrain_modifier
	sphere_mesh.height = 2.0
	terrain_preview_sphere.mesh = sphere_mesh

	# Semi-transparent white material
	var sphere_material = StandardMaterial3D.new()
	sphere_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_material.albedo_color = Color(1.0, 1.0, 1.0, 0.3)  # White, 30% opacity
	sphere_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terrain_preview_sphere.material_override = sphere_material

	terrain_preview_sphere.visible = false
	get_tree().root.add_child(terrain_preview_sphere)  # Add to scene root, not player

	# Create cube preview
	terrain_preview_cube = MeshInstance3D.new()
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(2.0, 2.0, 2.0)  # Will match SQUARE_SIZE and SQUARE_DEPTH (2x2x2)
	terrain_preview_cube.mesh = cube_mesh

	# Semi-transparent white material
	var cube_material = StandardMaterial3D.new()
	cube_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cube_material.albedo_color = Color(1.0, 1.0, 1.0, 0.3)  # White, 30% opacity
	cube_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terrain_preview_cube.material_override = cube_material

	terrain_preview_cube.visible = false
	get_tree().root.add_child(terrain_preview_cube)  # Add to scene root, not player

	print("[Player] Terrain preview shapes created")

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
		if attack_timer >= current_attack_animation_time:
			is_attacking = false
			attack_timer = 0.0

			# Reset weapon rotation after attack completes
			if equipped_weapon_visual:
				equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)

	# Update special attack animation
	if is_special_attacking:
		special_attack_timer += delta
		if special_attack_timer >= current_special_attack_animation_time:
			is_special_attacking = false
			special_attack_timer = 0.0
			# DON'T reset is_lunging here - it persists until landing!
			# DON'T reset weapon rotation here - knife stays horizontal until landing!

	# Stun animation overrides everything
	if is_stunned:
		_animate_stun(delta, left_arm, right_arm, left_leg, right_leg)
		return

	# Lunge crouch animation overrides everything (ball shape for dramatic leap)
	if is_lunging and body_container:
		# Crouch the body into a ball shape with aggressive forward dive
		body_container.rotation.x = lerp(body_container.rotation.x, 1.3, delta * 20.0)  # Lean forward aggressively (30 degrees more)
		body_container.scale.y = lerp(body_container.scale.y, 0.7, delta * 20.0)  # Compress vertically

		# Tuck arms and legs in
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, -0.8, delta * 20.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.5, delta * 20.0)
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, -0.8, delta * 20.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, -0.5, delta * 20.0)
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.6, delta * 20.0)
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.6, delta * 20.0)
		return  # Skip other animations while lunging

	# Reset body container scale and rotation when not lunging
	if body_container and not is_lunging and not is_stunned:
		body_container.rotation.x = lerp(body_container.rotation.x, 0.0, delta * 10.0)
		body_container.scale.y = lerp(body_container.scale.y, 1.0, delta * 10.0)

		# Also reset limbs from lunge position
		if left_arm and not is_blocking:
			left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 10.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 10.0)
		if right_arm and not is_attacking and not is_special_attacking:
			right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 10.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, 0.0, delta * 10.0)
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 10.0)
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 10.0)

	# Blocking animation overrides everything (only LEFT arm raised for shield defense)
	if is_blocking:
		# Raise LEFT arm for blocking (shield is in left hand)
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, -1.2, delta * 25.0)  # Left arm forward at shoulder height (fast)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.3, delta * 25.0)  # Slight outward angle for shield
		# Right arm (weapon) stays relaxed or in natural position
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, -0.3, delta * 15.0)  # Slightly forward, relaxed
			right_arm.rotation.z = lerp(right_arm.rotation.z, -0.2, delta * 15.0)  # Slight inward angle
	# Special attack animation overrides arm movement (more dramatic, RIGHT arm for weapons)
	elif is_special_attacking and right_arm:
		var attack_progress = special_attack_timer / current_special_attack_animation_time

		# Strong overhead slash or thrust (more dramatic than normal attacks)
		var swing_x = -sin(attack_progress * PI) * 2.0  # Very strong forward/down motion
		var swing_z = sin(attack_progress * PI) * -0.5  # Some horizontal motion
		right_arm.rotation.x = swing_x
		right_arm.rotation.z = swing_z
	# Attack animation overrides arm movement (RIGHT arm for weapons)
	elif is_attacking and right_arm:
		var attack_progress = attack_timer / current_attack_animation_time

		# Different animations based on combo type
		match current_combo_animation:
			0:  # Right-to-left slash (starts right, sweeps left across body)
				# Horizontal sweep from right to left
				var start_z = -1.2  # Start extended to right
				var end_z = 0.6     # End swept across to left
				var horizontal_angle = lerp(start_z, end_z, attack_progress)
				right_arm.rotation.z = horizontal_angle

				# Forward motion during slash
				var forward_angle = -sin(attack_progress * PI) * 0.8
				right_arm.rotation.x = forward_angle

			1:  # Left-to-right slash (reverse of first slash)
				# Horizontal sweep from left to right
				var start_z = 0.6   # Start crossed over to left
				var end_z = -1.2    # End swept to right
				var horizontal_angle = lerp(start_z, end_z, attack_progress)
				right_arm.rotation.z = horizontal_angle

				# Forward motion during slash
				var forward_angle = -sin(attack_progress * PI) * 0.8
				right_arm.rotation.x = forward_angle

			2:  # Forward jab/thrust (finisher)
				# Strong forward thrust (minimal horizontal movement)
				var jab_angle = -sin(attack_progress * PI) * 1.8  # Strong forward jab
				right_arm.rotation.x = jab_angle
				right_arm.rotation.z = -0.3  # Slight angle for natural look

			_:  # Default slash (same as animation 0)
				var start_z = -1.0
				var end_z = 0.5
				var horizontal_angle = lerp(start_z, end_z, attack_progress)
				right_arm.rotation.z = horizontal_angle
				var forward_angle = -sin(attack_progress * PI) * 0.8
				right_arm.rotation.x = forward_angle
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
			# Defensive shuffle - small leg movements, LEFT arm stays raised (shield)
			var leg_angle = sin(animation_phase) * 0.15  # Half the normal swing
			left_leg.rotation.x = leg_angle
			right_leg.rotation.x = -leg_angle

			# Left arm (shield) stays in defensive position (already set above)
			# Right arm (weapon) stays relaxed (already set above)
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
			if right_arm and not is_attacking and not is_special_attacking and not is_blocking:
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

		# Don't reset arms if blocking, attacking, or special attacking
		# Left arm: reset unless blocking (shield raised)
		if left_arm and not is_blocking:
			left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 5.0)
		# Right arm: reset unless attacking or special attacking (weapon swinging)
		if right_arm and not is_attacking and not is_special_attacking:
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

## Update brain power regeneration
func _update_brain_power(delta: float) -> void:
	# Regenerate brain power after delay
	brain_power_regen_timer += delta

	if brain_power_regen_timer >= BRAIN_POWER_REGEN_DELAY:
		brain_power = min(brain_power + BRAIN_POWER_REGEN_RATE * delta, MAX_BRAIN_POWER)

## Consume brain power (returns true if enough brain power available)
func consume_brain_power(amount: float) -> bool:
	if brain_power >= amount:
		brain_power -= amount
		brain_power_regen_timer = 0.0  # Reset regen delay
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
	brain_power = MAX_BRAIN_POWER
	global_position = spawn_position
	velocity = Vector3.ZERO

	print("[Player] Player respawned at %s!" % spawn_position)

	# Reset body rotation and position
	if body_container:
		body_container.rotation = Vector3.ZERO
		body_container.position = Vector3.ZERO

	# Reset fall timer
	fall_time_below_ground = 0.0

	# Re-enable physics (for all instances)
	set_physics_process(true)

	# Reset camera if this is the local player
	if is_local_player:
		# Camera will follow the repositioned player automatically
		pass

## Enable game loaded state (called when loading is complete)
func set_game_loaded(loaded: bool) -> void:
	is_game_loaded = loaded
	if loaded:
		print("[Player] Game fully loaded - input and physics enabled")
	else:
		print("[Player] Game loading - input and physics disabled")

# ============================================================================
# EQUIPMENT SYSTEM
# ============================================================================

## Called when equipment changes (spawn/despawn visuals)
func _on_equipment_changed(slot) -> void:  # slot is Equipment.EquipmentSlot
	print("[Player] Equipment changed in slot: %s" % slot)

	# Update visual representation based on slot
	match slot:
		Equipment.EquipmentSlot.MAIN_HAND:
			_update_weapon_visual()
		Equipment.EquipmentSlot.OFF_HAND:
			_update_shield_visual()
		Equipment.EquipmentSlot.HEAD, Equipment.EquipmentSlot.CHEST, Equipment.EquipmentSlot.LEGS:
			# TODO: Implement armor visuals
			pass

## Update the main hand weapon visual
func _update_weapon_visual() -> void:
	# Remove existing weapon visual
	if equipped_weapon_visual:
		equipped_weapon_visual.queue_free()
		equipped_weapon_visual = null

	# Get equipped weapon
	var weapon_id = equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)
	if weapon_id.is_empty():
		return

	# Get weapon data
	var weapon_data = ItemDatabase.get_item(weapon_id)
	if not weapon_data:
		push_error("[Player] Unknown weapon: %s" % weapon_id)
		return

	# Special case: fists have no visual (just the arms)
	if weapon_id == "fists":
		return

	# Load weapon scene
	var weapon_scene = weapon_data.get("weapon_scene")
	if not weapon_scene:
		push_warning("[Player] No weapon scene for: %s" % weapon_id)
		return

	# Instantiate weapon visual
	equipped_weapon_visual = weapon_scene.instantiate()

	# Find right hand bone attachment point
	var right_hand_attach = _find_hand_attach_point("RightHand")
	if right_hand_attach:
		right_hand_attach.add_child(equipped_weapon_visual)
		# Rotate weapon 90 degrees forward (X-axis) so it points forward instead of down
		equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)

		# Apply mount point offset if weapon has a MountPoint node
		if equipped_weapon_visual.has_node("MountPoint"):
			var mount_point = equipped_weapon_visual.get_node("MountPoint")
			equipped_weapon_visual.position = -mount_point.position

		print("[Player] Equipped weapon visual: %s" % weapon_id)
	else:
		# Fallback: attach to body container
		if body_container:
			body_container.add_child(equipped_weapon_visual)
			equipped_weapon_visual.position = Vector3(0.3, 1.2, 0)  # Approximate hand position
			equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
			print("[Player] Equipped weapon visual (fallback): %s" % weapon_id)
		else:
			equipped_weapon_visual.queue_free()
			equipped_weapon_visual = null
			push_warning("[Player] No attachment point for weapon")

## Update the off hand shield visual
func _update_shield_visual() -> void:
	# Remove existing shield visual
	if equipped_shield_visual:
		equipped_shield_visual.queue_free()
		equipped_shield_visual = null

	# Get equipped shield
	var shield_id = equipment.get_equipped_item(Equipment.EquipmentSlot.OFF_HAND)
	if shield_id.is_empty():
		return

	# Get shield data
	var shield_data = ItemDatabase.get_item(shield_id)
	if not shield_data:
		push_error("[Player] Unknown shield: %s" % shield_id)
		return

	# Load shield scene
	var shield_scene = shield_data.get("shield_scene")
	if not shield_scene:
		push_warning("[Player] No shield scene for: %s" % shield_id)
		return

	# Instantiate shield visual
	equipped_shield_visual = shield_scene.instantiate()

	# Find left hand bone attachment point
	var left_hand_attach = _find_hand_attach_point("LeftHand")
	if left_hand_attach:
		left_hand_attach.add_child(equipped_shield_visual)
		# Rotate shield 90 degrees forward (X-axis) so it faces forward
		equipped_shield_visual.rotation_degrees = Vector3(90, 0, 0)

		# Apply mount point offset if shield has a MountPoint node
		if equipped_shield_visual.has_node("MountPoint"):
			var mount_point = equipped_shield_visual.get_node("MountPoint")
			equipped_shield_visual.position = -mount_point.position

		print("[Player] Equipped shield visual: %s" % shield_id)
	else:
		# Fallback: attach to body container
		if body_container:
			body_container.add_child(equipped_shield_visual)
			equipped_shield_visual.position = Vector3(-0.3, 1.2, 0)  # Approximate hand position
			equipped_shield_visual.rotation_degrees = Vector3(90, 0, 0)
			print("[Player] Equipped shield visual (fallback): %s" % shield_id)
		else:
			equipped_shield_visual.queue_free()
			equipped_shield_visual = null
			push_warning("[Player] No attachment point for shield")

## Find a hand attachment point (HandAttach node in arm)
func _find_hand_attach_point(hand_name: String) -> Node3D:
	if not body_container:
		return null

	# Map hand name to arm node name
	var arm_name = ""
	if hand_name == "RightHand":
		arm_name = "RightArm"
	elif hand_name == "LeftHand":
		arm_name = "LeftArm"
	else:
		return null

	# Find the arm node in body container
	if not body_container.has_node(arm_name):
		return null

	var arm = body_container.get_node(arm_name)
	if not arm or not is_instance_valid(arm):
		return null

	# Find HandAttach node in the arm
	if arm.has_node("HandAttach"):
		return arm.get_node("HandAttach")

	return null

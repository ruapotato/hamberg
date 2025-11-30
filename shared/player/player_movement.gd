class_name PlayerMovement
extends RefCounted

## PlayerMovement - Handles player movement, physics, and step-up mechanics
## Works for both client prediction and server simulation

const PC = preload("res://shared/player/player_constants.gd")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# MAIN MOVEMENT
# =============================================================================

## Apply movement based on input (used for both prediction and server)
func apply_movement(input_data: Dictionary, delta: float) -> void:
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
	if not player.is_on_floor() and player.is_game_loaded:
		player.velocity.y -= player.gravity * delta

	# Fall death detection
	_check_fall_death(delta)

	# Lunge momentum handling
	_handle_lunge_momentum()

	# Jumping (with stamina cost)
	if jump_pressed and player.is_on_floor():
		if player.resources.consume_stamina(PC.JUMP_STAMINA_COST):
			player.velocity.y = PC.JUMP_VELOCITY
			if player.is_local_player:
				SoundManager.play_sound_varied("jump", player.global_position, -3.0, 0.1)

	# Calculate target speed
	var target_speed := _calculate_target_speed(is_sprinting, delta)

	var control_factor := 1.0 if player.is_on_floor() else PC.AIR_CONTROL

	# Horizontal movement (skip if lunging - lunge controls movement)
	if not player.is_lunging:
		if direction:
			var target_velocity := direction * target_speed
			player.velocity.x = lerp(player.velocity.x, target_velocity.x, PC.ACCELERATION * delta * control_factor)
			player.velocity.z = lerp(player.velocity.z, target_velocity.z, PC.ACCELERATION * delta * control_factor)
		else:
			# Apply friction
			player.velocity.x = lerp(player.velocity.x, 0.0, PC.FRICTION * delta * control_factor)
			player.velocity.z = lerp(player.velocity.z, 0.0, PC.FRICTION * delta * control_factor)

	# Apply movement with step-up logic
	handle_step_up(delta)
	player.move_and_slide()

	# Handle post-movement lunge state
	_handle_post_movement_lunge()

	# Rotate body to face movement direction
	_rotate_body_to_direction(direction, delta)

## Calculate target movement speed based on current state
func _calculate_target_speed(is_sprinting: bool, delta: float) -> float:
	# Can't sprint while blocking or exhausted
	var can_sprint = is_sprinting and not player.is_blocking and not player.is_exhausted
	if can_sprint:
		# Only sprint if we have enough stamina
		can_sprint = player.resources.consume_stamina(PC.SPRINT_STAMINA_DRAIN * delta)

	var target_speed := PC.SPRINT_SPEED if can_sprint else PC.WALK_SPEED

	# Apply exhausted speed reduction
	if player.is_exhausted:
		target_speed *= PC.EXHAUSTED_SPEED_MULTIPLIER

	# Apply blocking speed reduction
	if player.is_blocking:
		target_speed *= PC.BLOCK_SPEED_MULTIPLIER

	# Reduce speed during spin attack
	if player.is_spinning:
		target_speed *= 0.3

	return target_speed

## Check for fall death (falling below world for too long)
func _check_fall_death(delta: float) -> void:
	if not player.is_game_loaded or not player.is_local_player:
		return

	var ground_level: float = 0.0  # Sea level is at Y=0
	if player.global_position.y < ground_level and not player.is_on_floor():
		# Player is below ground and falling
		player.fall_time_below_ground += delta

		if player.fall_time_below_ground >= PC.FALL_DEATH_TIME:
			print("[Player] Fall death! Fell below ground for %.1f seconds" % player.fall_time_below_ground)
			player.health = 0
			player.resources.die()
	else:
		# Reset fall timer if above ground or on floor
		player.fall_time_below_ground = 0.0

# =============================================================================
# LUNGE MECHANICS
# =============================================================================

## Handle lunge momentum while in the air
func _handle_lunge_momentum() -> void:
	if not player.is_lunging or player.is_on_floor():
		return

	# Continuously apply forward force to maintain arc trajectory
	player.velocity.x = player.lunge_direction.x * 5.0
	player.velocity.z = player.lunge_direction.z * 5.0
	# Don't modify y velocity - let gravity create the arc

	# STUCK DETECTION: If velocity magnitude is near zero, we hit a wall/enemy
	var velocity_magnitude = Vector3(player.velocity.x, 0, player.velocity.z).length()
	if velocity_magnitude < 0.5:
		print("[Player] Lunge STUCK (velocity near zero)! Ending lunge state.")
		_end_lunge()

## Handle post-movement lunge state (landing detection, etc.)
func _handle_post_movement_lunge() -> void:
	if not player.is_lunging:
		return

	# Track if we're in the air during lunge
	if not player.is_on_floor():
		if not player.was_in_air_lunging:
			print("[Player] Lunge entered air! was_in_air_lunging now TRUE")
		player.was_in_air_lunging = true

	# CONTINUOUS LUNGE DAMAGE - delegated to combat module
	if player.is_local_player and player.combat:
		player.combat.check_lunge_collision()

	# Detect landing: were in air lunging, now on floor
	if player.was_in_air_lunging and player.is_on_floor():
		print("[Player] Lunge LANDED! Ending lunge state.")
		_end_lunge()
		# STOP all momentum immediately
		player.velocity = Vector3.ZERO

## End lunge state and reset related variables
func _end_lunge() -> void:
	player.is_lunging = false
	player.was_in_air_lunging = false
	player.lunge_direction = Vector3.ZERO
	player.lunge_hit_enemies.clear()

	# Reset weapon rotation
	if player.equipped_weapon_visual:
		player.equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
	if player.weapon_wrist_pivot:
		player.weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

# =============================================================================
# STEP-UP MECHANICS
# =============================================================================

## Handle stepping up small ledges like floor boards and stairs
func handle_step_up(delta: float) -> void:
	# Only attempt step-up when on ground and moving horizontally
	if not player.is_on_floor():
		return

	var horizontal_velocity = Vector3(player.velocity.x, 0, player.velocity.z)
	var h_speed = horizontal_velocity.length()
	if h_speed < 0.1:
		return

	# Don't step up during special movement states
	if player.is_lunging or player.is_jumping:
		return

	# Test if we would collide at current height
	var motion = horizontal_velocity * delta
	var collision = player.move_and_collide(motion, true)  # Test only

	if not collision:
		return  # No obstacle

	# Check collision normal - only step up on steep/vertical surfaces
	var collision_normal = collision.get_normal()
	if collision_normal.y > 0.75:
		return  # Sloped terrain, not a step

	# Test if we can move up by step height
	var step_up_motion = Vector3(0, PC.STEP_HEIGHT, 0)
	var step_collision = player.move_and_collide(step_up_motion, true)

	if step_collision:
		return  # Can't move up (ceiling)

	# Temporarily move up to test forward motion
	var original_y = player.global_position.y
	player.global_position.y += PC.STEP_HEIGHT

	# Test forward motion at elevated position
	var elevated_collision = player.move_and_collide(motion, true)

	# Restore position
	player.global_position.y = original_y

	if elevated_collision:
		return  # Still blocked - it's a wall, not a step

	# Success! Apply upward velocity
	var step_up_speed = 2.5 + h_speed * 0.5
	player.velocity.y = maxf(player.velocity.y, step_up_speed)
	player.is_stepping_up = true

# =============================================================================
# BODY ROTATION
# =============================================================================

## Rotate visual body to face movement direction
func _rotate_body_to_direction(direction: Vector3, delta: float) -> void:
	if not direction or not player.body_container:
		return
	if player.is_blocking or player.is_lunging or player.is_spinning:
		return

	var horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
	if horizontal_speed > 0.1:
		var target_rotation = atan2(direction.x, direction.z)
		player.body_container.rotation.y = lerp_angle(player.body_container.rotation.y, target_rotation, delta * 10.0)

# =============================================================================
# ANIMATION STATE
# =============================================================================

## Update animation state based on velocity
func update_animation_state() -> void:
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var on_floor := player.is_on_floor()

	# Detect landing (transition from air to ground)
	if on_floor and not player.was_on_floor_last_frame:
		# Don't play landing animation/sound for small step-ups
		if not player.is_stepping_up:
			player.is_landing = true
			player.landing_timer = 0.0
			if player.is_local_player:
				SoundManager.play_sound_varied("land", player.global_position, -3.0, 0.1)
		player.is_jumping = false
		player.is_falling = false
		player.is_stepping_up = false

	# Update floor tracking
	player.was_on_floor_last_frame = on_floor

	# Set animation state
	if player.is_landing:
		player.current_animation_state = "landing"
	elif not on_floor and not player.is_stepping_up:
		if player.velocity.y > 0.5:
			player.current_animation_state = "jump"
			player.is_jumping = true
			player.is_falling = false
		else:
			player.current_animation_state = "falling"
			player.is_falling = true
	elif horizontal_speed > 6.0:
		player.current_animation_state = "run"
	elif horizontal_speed > 0.5:
		player.current_animation_state = "walk"
	else:
		player.current_animation_state = "idle"

# =============================================================================
# NETWORK RECONCILIATION
# =============================================================================

## SERVER: Apply input from client
func apply_server_input(input_data: Dictionary) -> void:
	if not NetworkManager.is_server:
		return
	var delta := player.get_physics_process_delta_time()
	apply_movement(input_data, delta)

## CLIENT: Apply authoritative state from server (for remote players)
func apply_server_state(state: Dictionary) -> void:
	if player.is_local_player:
		return  # Local player uses reconciliation

	# Remote players: Add to interpolation buffer
	player.interpolation_buffer.append(state)

	# Limit buffer size
	if player.interpolation_buffer.size() > 30:
		player.interpolation_buffer.pop_front()

## Interpolate remote player movement for smooth rendering
func interpolate_remote_player(_delta: float) -> void:
	if player.interpolation_buffer.size() < 1:
		return

	var latest_state := player.interpolation_buffer[player.interpolation_buffer.size() - 1]

	# Smooth lerp to server position
	var target_pos: Vector3 = latest_state.get("position", player.global_position)
	var target_rot: float = latest_state.get("rotation", player.rotation.y)

	player.global_position = player.global_position.lerp(target_pos, 0.3)
	player.rotation.y = lerp_angle(player.rotation.y, target_rot, 0.3)

	# Update animation state
	player.current_animation_state = latest_state.get("animation_state", "idle")

extends CharacterBody3D

## Player - Networked player entity with client-side prediction
## This entity works on both client and server, with different logic paths

# Preload classes
const Equipment = preload("res://shared/equipment.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")
const ArmorData = preload("res://shared/armor_data.gd")
const Projectile = preload("res://shared/projectiles/projectile.gd")
const HitEffectScene = preload("res://shared/effects/hit_effect.tscn")
const ParryEffectScene = preload("res://shared/effects/parry_effect.tscn")

# Default player colors (unarmored - skin tones)
const DEFAULT_SKIN_COLOR: Color = Color(0.9, 0.75, 0.65, 1.0)  # Natural skin tone
const DEFAULT_CLOTHES_COLOR: Color = Color(0.7, 0.65, 0.6, 1.0)  # Light tan (minimal clothing)
const DEFAULT_PANTS_COLOR: Color = Color(0.6, 0.55, 0.5, 1.0)  # Slightly darker tan

# Cape visual reference
var cape_visual: Node3D = null
# Hood visual reference
var hood_visual: Node3D = null
# Cyclops eye light effect
var cyclops_light: OmniLight3D = null

# Movement parameters
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0
const JUMP_VELOCITY: float = 10.0
const ACCELERATION: float = 10.0
const FRICTION: float = 8.0
const AIR_CONTROL: float = 0.3
const head_height: float = 1.50
const STEP_HEIGHT: float = 0.35  # Maximum height player can step up without jumping (stairs, floor boards)

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Player state
var current_animation_state: String = "idle"
var is_local_player: bool = false
var animation_phase: float = 0.0  # Accumulated phase for smooth animation cycles
var _last_footstep_phase: float = 0.0  # Track phase for footstep sound triggering
var is_game_loaded: bool = false  # Set to true when loading is complete

# Jump/landing animation state
var is_jumping: bool = false  # Set on jump button press
var is_falling: bool = false  # Set when falling without jumping
var is_stepping_up: bool = false  # Set during step-up to prevent fall animation
var was_on_floor_last_frame: bool = false  # Track floor state for landing detection
var landing_timer: float = 0.0  # Timer for landing animation
const LANDING_ANIMATION_TIME: float = 0.2  # How long landing animation plays
var is_landing: bool = false  # Currently playing landing animation
var has_used_double_jump: bool = false  # Track if air jump has been used (for pig armor set bonus)

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
const AXE_ANIMATION_TIME: float = 0.45  # Faster swings
var current_attack_animation_time: float = 0.3  # Actual animation time for current attack

# Combo system (for weapons like knife and axe)
var combo_count: int = 0  # Current combo hit (0, 1, 2 for 3-hit combo)
var combo_timer: float = 0.0  # Time since last attack in combo
const COMBO_WINDOW: float = 1.2  # Time window to continue combo
const MAX_COMBO: int = 3  # Maximum combo hits
var current_combo_animation: int = 0  # Which animation to play
var current_weapon_type: String = ""  # Track weapon for combo animations (knife, axe, etc.)

# Special attack state
var is_special_attacking: bool = false
var special_attack_timer: float = 0.0
const SPECIAL_ATTACK_ANIMATION_TIME: float = 0.5  # Longer than normal attacks
const KNIFE_SPECIAL_ANIMATION_TIME: float = 0.4  # Faster for knife lunge
const SWORD_SPECIAL_ANIMATION_TIME: float = 0.6  # Slower for sword jab
const AXE_SPECIAL_ANIMATION_TIME: float = 0.8  # Full spin takes longer
var current_special_attack_animation_time: float = 0.5  # Actual special animation time

# Axe spin attack state
var is_spinning: bool = false
var spin_rotation: float = 0.0  # Current spin rotation for body
var spin_hit_times: Dictionary = {}  # enemy_id -> last_hit_time for multi-hit with cooldown
var is_lunging: bool = false  # Track if player is performing a lunge attack
var lunge_direction: Vector3 = Vector3.ZERO  # Direction of lunge for maintaining momentum
const LUNGE_FORWARD_FORCE: float = 15.0  # Continuous forward force during lunge
var was_in_air_lunging: bool = false  # Track if we were in air during lunge (for landing detection)
var lunge_damage: float = 0.0  # Stored damage for continuous lunge hits
var lunge_knockback: float = 0.0  # Stored knockback for continuous lunge hits
var lunge_hit_enemies: Array = []  # Enemies already hit during this lunge (prevents double damage)
const LUNGE_HIT_RADIUS: float = 1.5  # Radius around player to detect enemy collisions during lunge

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

# Equipment sync for remote players (server stores latest equipment data here)
var synced_equipment: Dictionary = {}

# Viewmodel (first-person arms)
var viewmodel_arms: Node3D = null

# Player body visuals
var body_container: Node3D = null

# Equipped weapon/shield visuals
var equipped_weapon_visual: Node3D = null  # Main hand weapon
var equipped_shield_visual: Node3D = null  # Off hand shield
var weapon_wrist_pivot: Node3D = null  # Pivot point for weapon rotation (simulates wrist)

# Weapon hitbox collision detection (Valheim-style)
var weapon_hitbox: Area3D = null  # Reference to weapon's hitbox Area3D
var hitbox_hit_enemies: Array = []  # Enemies hit during current attack swing (prevents multi-hit)
var hitbox_active: bool = false  # Is the hitbox currently enabled for collision detection

# Terrain dig visual feedback
var terrain_preview_cube: MeshInstance3D = null    # Temporary shape after placement
var terrain_dig_preview_cube: MeshInstance3D = null  # Red cube showing which block will be dug
var terrain_place_preview_cube: MeshInstance3D = null  # White cube showing where block will be placed
var cached_dig_position: Vector3 = Vector3.ZERO    # Cached position from red preview cube
var cached_place_position: Vector3 = Vector3.ZERO  # Cached position from white preview cube
var terrain_preview_timer: float = 0.0
const TERRAIN_PREVIEW_DURATION: float = 0.8  # How long to show the actual placed shape
var is_showing_persistent_preview: bool = false   # Track if we're showing the persistent preview

# Player identity
var player_name: String = "Unknown"

# Inventory (server-authoritative)
var inventory: Node = null

# Equipment (server-authoritative)
var equipment = null  # Equipment instance

# Player Constants reference
const PC = preload("res://shared/player/player_constants.gd")

# Stamina system (base values - modified by food)
var stamina: float = PC.BASE_STAMINA
var stamina_regen_timer: float = 0.0  # Time since last stamina use
var is_exhausted: bool = false  # True when stamina fully depleted, until 10% recovered

# Brain Power system (for magic, base values - modified by food)
var brain_power: float = PC.BASE_BRAIN_POWER
var brain_power_regen_timer: float = 0.0  # Time since last brain power use

# Health system (base values - modified by food)
var health: float = PC.BASE_HEALTH
var is_dead: bool = false
var god_mode: bool = false  # Debug god mode - unlimited stamina/brain power

# Gold currency (separate from inventory, doesn't take a slot)
var gold: int = 0

# PERFORMANCE: Throttle position sync from 60Hz to 20Hz
var position_sync_timer: float = 0.0
const POSITION_SYNC_INTERVAL: float = 0.05  # 20Hz (every 50ms)
var last_synced_position: Vector3 = Vector3.ZERO
const POSITION_SYNC_THRESHOLD: float = 0.1  # Only sync if moved more than this

# Food system node (added in _ready)
var player_food: Node = null
var _previous_max_health: float = 0.0  # Tracks max health for percentage scaling

# Fall death system (for falling out of world)
var fall_time_below_ground: float = 0.0

# Remote player animation time (for walk cycles on other clients)
var remote_anim_time: float = 0.0

# Blocking start time (for shield parry timing)
var block_start_time: float = 0.0

# Combat module (handles attacks, combos, hitbox detection)
var combat = null

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

	# Create food system
	var PlayerFoodScript = preload("res://shared/player/player_food.gd")
	player_food = PlayerFoodScript.new()
	player_food.name = "PlayerFood"
	add_child(player_food)
	_previous_max_health = PC.BASE_HEALTH  # Initialize for health percentage tracking

	# Create combat module (handles attacks, combos, hitbox detection)
	var PlayerCombatScript = preload("res://shared/player/player_combat.gd")
	combat = PlayerCombatScript.new(self)

	# Determine if this is the local player
	is_local_player = is_multiplayer_authority()

	# Add to group for easy lookup by other systems (e.g., day/night cycle biome detection)
	if is_local_player:
		add_to_group("local_player")

	print("[Player] Player ready (ID: %d, Local: %s)" % [get_multiplayer_authority(), is_local_player])

	# Set collision layer
	collision_layer = 2  # Players layer
	collision_mask = 1 | 4  # World layer + Enemies/NPCs layer

	# Setup player body visuals
	_setup_player_body()

	# Initialize armor visuals to default (unarmored) skin colors
	_initialize_armor_visuals()

	# Setup terrain preview shapes (only for local player)
	if is_local_player:
		_setup_terrain_preview_shapes()
		# Start ambient wind sound for atmosphere
		SoundManager.play_ambient("wind_ambient")

	if is_local_player:
		# Local player uses client prediction
		set_physics_process(true)
	else:
		# Remote players use interpolation
		set_physics_process(false)

func _exit_tree() -> void:
	"""Clean up terrain preview shapes when player is removed"""
	if terrain_preview_cube and is_instance_valid(terrain_preview_cube):
		terrain_preview_cube.queue_free()
	if terrain_dig_preview_cube and is_instance_valid(terrain_dig_preview_cube):
		terrain_dig_preview_cube.queue_free()
	if terrain_place_preview_cube and is_instance_valid(terrain_place_preview_cube):
		terrain_place_preview_cube.queue_free()

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

	# Handle terrain modification input (pickaxe, hoe)
	if input_data.get("attack", false) or input_data.get("secondary_action", false) or input_data.get("middle_mouse", false):
		var handled_terrain_action = _handle_terrain_modification_input(input_data)
		# Only process combat if terrain modification wasn't handled
		if not handled_terrain_action:
			# Handle special attack input (can't attack while stunned, blocking, or exhausted)
			if input_data.get("special_attack", false) and attack_cooldown <= 0 and not is_stunned and not is_blocking and not is_exhausted:
				_handle_special_attack()
				attack_cooldown = ATTACK_COOLDOWN_TIME
			# Handle normal attack input (can't attack while stunned, blocking, or exhausted)
			elif input_data.get("attack", false) and attack_cooldown <= 0 and not is_stunned and not is_blocking and not is_exhausted:
				_handle_attack()
				attack_cooldown = ATTACK_COOLDOWN_TIME
	# Handle special attack input when no other input (can't attack while stunned, blocking, or exhausted)
	elif input_data.get("special_attack", false) and attack_cooldown <= 0 and not is_stunned and not is_blocking and not is_exhausted:
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
	# PERFORMANCE: Throttled to 20Hz instead of 60Hz
	if NetworkManager.is_client:
		position_sync_timer += delta
		var should_sync := false

		# Always sync at interval
		if position_sync_timer >= POSITION_SYNC_INTERVAL:
			position_sync_timer = 0.0
			should_sync = true

		# Also sync immediately if position changed significantly (for responsiveness)
		if global_position.distance_to(last_synced_position) > POSITION_SYNC_THRESHOLD:
			should_sync = true

		if should_sync:
			last_synced_position = global_position
			var position_data := {
				"position": global_position,
				"rotation": global_rotation.y,
				"velocity": velocity,
				"animation_state": current_animation_state,
				# Combat state for other clients to see attacks/blocking
				"is_attacking": is_attacking,
				"is_blocking": is_blocking,
				"is_stunned": is_stunned,
				"is_dead": is_dead,
				"attack_timer": attack_timer,
				"current_attack_animation_time": current_attack_animation_time,
				"is_special_attacking": is_special_attacking,
				"special_attack_timer": special_attack_timer,
				"current_special_attack_animation_time": current_special_attack_animation_time,
				"is_lunging": is_lunging,
				"is_spinning": is_spinning,
				"combo_count": combo_count,
				# Equipment for visual sync (weapon, shield, armor)
				"equipment": equipment.get_equipment_data() if equipment else {}
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
	# Don't process movement input if a text input has focus (e.g., debug console)
	var focused_control = get_viewport().gui_get_focus_owner()
	if focused_control and (focused_control is LineEdit or focused_control is TextEdit):
		return {
			"move_x": 0.0,
			"move_z": 0.0,
			"sprint": false,
			"jump": false,
			"attack": false,
			"secondary_action": false,
			"special_attack": false,
			"middle_mouse": false,
			"camera_basis": _get_camera_basis()
		}

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

			if fall_time_below_ground >= PC.FALL_DEATH_TIME:
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
			lunge_hit_enemies.clear()  # Reset hit tracking
			velocity.x = 0.0
			velocity.z = 0.0
			# Reset weapon rotation
			if equipped_weapon_visual:
				equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
			if weapon_wrist_pivot:
				weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

	# Jumping (with stamina cost)
	# Check for double jump ability (pig armor set bonus)
	var has_double_jump_ability = equipment and equipment.has_double_jump_bonus()
	var can_ground_jump = is_on_floor()
	var can_double_jump = (not is_on_floor()
		and not has_used_double_jump
		and has_double_jump_ability)

	if jump_pressed and (can_ground_jump or can_double_jump):
		if consume_stamina(PC.JUMP_STAMINA_COST):
			velocity.y = PC.JUMP_VELOCITY
			if is_local_player:
				SoundManager.play_sound_varied("jump", global_position, -3.0, 0.1)
			# Mark double jump as used if we jumped in the air
			if can_double_jump:
				has_used_double_jump = true
				print("[Player] Used double jump (Pig Armor set bonus)")

	# Movement speed (sprint drains stamina, blocking reduces speed)
	# Can't sprint while blocking or exhausted
	var can_sprint = is_sprinting and not is_blocking and not is_exhausted
	if can_sprint:
		# Calculate sprint stamina cost (deer armor set bonus reduces by 50%)
		var sprint_cost = PC.SPRINT_STAMINA_DRAIN * delta
		if equipment and equipment.has_stamina_saver_bonus():
			sprint_cost *= 0.5
		# Only sprint if we have enough stamina (consume_stamina returns false if not enough)
		can_sprint = consume_stamina(sprint_cost)
	var target_speed := PC.SPRINT_SPEED if can_sprint else PC.WALK_SPEED

	# Apply armor speed modifier (heavy armor slows you down)
	if equipment:
		var speed_mod = equipment.get_total_speed_modifier()
		if speed_mod != 0.0:
			target_speed *= (1.0 + speed_mod)  # speed_mod is negative for slow, e.g., -0.15

	# Apply exhausted speed reduction (slower walking)
	if is_exhausted:
		target_speed *= PC.EXHAUSTED_SPEED_MULTIPLIER

	# Apply blocking speed reduction
	if is_blocking:
		target_speed *= PC.BLOCK_SPEED_MULTIPLIER

	# Reduce speed during spin attack - can slowly adjust position but not run
	if is_spinning:
		target_speed *= 0.3

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

	# Apply movement with step-up logic
	_handle_step_up(delta)
	move_and_slide()

	# LUNGE LANDING DETECTION - Check immediately after move_and_slide() updates is_on_floor()
	# Track if we're in the air during lunge
	if is_lunging and not is_on_floor():
		if not was_in_air_lunging:
			print("[Player] Lunge entered air! was_in_air_lunging now TRUE")
		was_in_air_lunging = true

	# CONTINUOUS LUNGE DAMAGE - Check for enemies near player during lunge arc
	if is_lunging and is_local_player:
		_check_lunge_collision()

	# Detect landing: were in air lunging, now on floor
	if is_lunging and was_in_air_lunging and is_on_floor():
		# LANDED! End lunge immediately
		print("[Player] Lunge LANDED! Ending lunge state. is_on_floor: %s, velocity: %s" % [is_on_floor(), velocity])

		is_lunging = false
		was_in_air_lunging = false
		lunge_direction = Vector3.ZERO
		lunge_hit_enemies.clear()  # Reset hit tracking

		# STOP all momentum immediately to prevent sliding
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0

		# Reset weapon rotation when lunge completes (on landing)
		if equipped_weapon_visual:
			equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
		if weapon_wrist_pivot:
			weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

	# Rotate body to face movement direction
	# UNLESS blocking, lunging, or spinning - those animations control body rotation
	if direction and body_container and not is_blocking and not is_lunging and not is_spinning:
		var horizontal_speed_check = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed_check > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			body_container.rotation.y = lerp_angle(body_container.rotation.y, target_rotation, delta * 10.0)
			# Also update global rotation for network sync
			global_rotation.y = body_container.rotation.y

func _handle_step_up(_delta: float) -> void:
	"""Handle stepping up small ledges like floor boards and stairs - smooth version"""
	# Only attempt step-up when on ground and moving horizontally
	if not is_on_floor():
		return

	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var h_speed = horizontal_velocity.length()
	if h_speed < 0.1:
		return

	# Don't step up during special movement states
	if is_lunging or is_jumping:
		return

	# Test if we would collide at current height
	var motion = horizontal_velocity * _delta
	var collision = move_and_collide(motion, true)  # Test only, don't actually move

	if not collision:
		return  # No obstacle, no step-up needed

	# Check collision normal - only step up on steep/vertical surfaces (steps, walls)
	# Not on sloped terrain (normal pointing mostly upward)
	var collision_normal = collision.get_normal()
	if collision_normal.y > 0.75:
		return  # This is sloped terrain, not a step - let normal movement handle it

	# There's a steep obstacle - check if it's a step we can climb
	# Test if we can move up by step height
	var step_up_motion = Vector3(0, STEP_HEIGHT, 0)
	var step_collision = move_and_collide(step_up_motion, true)

	if step_collision:
		return  # Can't move up (ceiling or something)

	# Temporarily move up to test forward motion
	var original_y = global_position.y
	global_position.y += STEP_HEIGHT

	# Test forward motion at elevated position
	var elevated_collision = move_and_collide(motion, true)

	# Restore position - we'll use velocity for smooth movement
	global_position.y = original_y

	if elevated_collision:
		return  # Still blocked at elevated position - it's a wall, not a step

	# Success! Apply upward velocity to glide up the step
	# Strong enough to clear steps smoothly but not launch into the air
	var step_up_speed = 2.5 + h_speed * 0.5  # Moderate lift, scales with speed
	velocity.y = maxf(velocity.y, step_up_speed)
	is_stepping_up = true  # Prevent fall animation during step-up

func _update_animation_state() -> void:
	"""Update animation state based on velocity"""
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var on_floor := is_on_floor()

	# Detect landing (transition from air to ground)
	if on_floor and not was_on_floor_last_frame:
		# Don't play landing animation/sound for small step-ups
		if not is_stepping_up:
			is_landing = true
			landing_timer = 0.0
			if is_local_player:
				SoundManager.play_sound_varied("land", global_position, -3.0, 0.1)
		is_jumping = false
		is_falling = false
		is_stepping_up = false  # Clear step-up flag when back on ground
		has_used_double_jump = false  # Reset double jump when landing

	# Update floor tracking
	was_on_floor_last_frame = on_floor

	# Set animation state
	if is_landing:
		current_animation_state = "landing"
	elif not on_floor and not is_stepping_up:
		# Only show jump/fall animation if not stepping up
		if velocity.y > 0.5:
			current_animation_state = "jump"
			is_jumping = true
			is_falling = false
		else:
			current_animation_state = "falling"
			is_falling = true
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

	# Apply combat states from server for attack/block animations
	is_attacking = latest_state.get("is_attacking", false)
	is_blocking = latest_state.get("is_blocking", false)
	is_stunned = latest_state.get("is_stunned", false)
	is_dead = latest_state.get("is_dead", false)
	attack_timer = latest_state.get("attack_timer", 0.0)
	current_attack_animation_time = latest_state.get("current_attack_animation_time", 0.3)
	is_special_attacking = latest_state.get("is_special_attacking", false)
	special_attack_timer = latest_state.get("special_attack_timer", 0.0)
	current_special_attack_animation_time = latest_state.get("current_special_attack_animation_time", 0.5)
	is_lunging = latest_state.get("is_lunging", false)
	is_spinning = latest_state.get("is_spinning", false)
	combo_count = latest_state.get("combo_count", 0)

	# Apply equipment visuals from synced data
	var synced_equipment = latest_state.get("equipment", {})
	if equipment and synced_equipment and synced_equipment.size() > 0:
		equipment.set_equipment_data(synced_equipment)

	# Apply rotation to body_container for visual (remote players don't run _physics_process)
	if body_container:
		# Smooth rotation sync - rotation is now sent from body_container directly
		body_container.rotation.y = lerp_angle(body_container.rotation.y, target_rot, 0.3)

	# Apply animations for remote players (including combat animations)
	_update_remote_player_animations(delta)

func _update_remote_player_animations(delta: float) -> void:
	"""Animations for remote players based on synced combat and movement state"""
	if not body_container:
		return

	var left_leg = body_container.get_node_or_null("LeftLeg")
	var right_leg = body_container.get_node_or_null("RightLeg")
	var left_arm = body_container.get_node_or_null("LeftArm")
	var right_arm = body_container.get_node_or_null("RightArm")
	var left_knee = left_leg.get_node_or_null("Knee") if left_leg else null
	var right_knee = right_leg.get_node_or_null("Knee") if right_leg else null
	var left_elbow = left_arm.get_node_or_null("Elbow") if left_arm else null
	var right_elbow = right_arm.get_node_or_null("Elbow") if right_arm else null

	if not left_leg or not right_leg:
		return

	# ==== COMBAT STATE ANIMATIONS (HIGHEST PRIORITY) ====

	# Death animation - fall over (highest priority)
	if is_dead:
		# Smoothly fall forward
		body_container.rotation.x = lerp(body_container.rotation.x, PI / 2, delta * 2.0)
		body_container.position.y = lerp(body_container.position.y, -0.5, delta * 2.0)
		return

	# Stun animation overrides everything - wobble the whole body
	if is_stunned:
		remote_anim_time += delta
		var wobble_speed = 15.0
		var wobble_intensity = 0.25
		var time = remote_anim_time * wobble_speed
		var wobble_x = sin(time) * wobble_intensity
		var wobble_z = cos(time * 1.3) * wobble_intensity

		body_container.rotation.x = wobble_x
		body_container.rotation.z = wobble_z

		# Arms flail
		if left_arm:
			left_arm.rotation.x = sin(time * 2.0) * 0.5
		if right_arm:
			right_arm.rotation.x = cos(time * 2.0) * 0.5

		# Legs wobble
		if left_leg:
			left_leg.rotation.x = sin(time * 1.5) * 0.3
		if right_leg:
			right_leg.rotation.x = -sin(time * 1.5) * 0.3
		return

	# Reset body rotation if not stunned
	body_container.rotation.x = lerp(body_container.rotation.x, 0.0, delta * 10.0)
	body_container.rotation.z = lerp(body_container.rotation.z, 0.0, delta * 10.0)

	# Track if arms are controlled by combat (to skip arm movement in walk/run)
	var arms_controlled := false

	# Blocking animation - left arm raised for shield defense
	if is_blocking:
		arms_controlled = true
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, -1.2, delta * 25.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.3, delta * 25.0)
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, -0.3, delta * 15.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, -0.2, delta * 15.0)

	# Special attack animations (spinning, lunging, etc.)
	elif is_special_attacking:
		arms_controlled = true
		var attack_progress = attack_timer / current_special_attack_animation_time if current_special_attack_animation_time > 0 else 0.0
		attack_progress = clamp(attack_progress, 0.0, 1.0)

		if is_spinning:
			# Axe spin - arms extended horizontally
			if right_arm:
				right_arm.rotation.x = -0.3
				right_arm.rotation.z = -1.5
			if left_arm:
				left_arm.rotation.x = -0.3
				left_arm.rotation.z = 1.5
			if right_elbow:
				right_elbow.rotation.x = -0.1
			if left_elbow:
				left_elbow.rotation.x = -0.1
		elif is_lunging:
			# Knife lunge - arm thrust forward
			if right_arm:
				right_arm.rotation.x = lerp(-0.5, -1.8, attack_progress)
				right_arm.rotation.z = 0.0
			if right_elbow:
				right_elbow.rotation.x = lerp(-0.3, 0.0, attack_progress)
		else:
			# Default special attack - powerful swing
			var swing_x = -sin(attack_progress * PI) * 2.0
			var swing_z = sin(attack_progress * PI) * -0.5
			if right_arm:
				right_arm.rotation.x = swing_x
				right_arm.rotation.z = swing_z
			if right_elbow:
				right_elbow.rotation.x = -sin(attack_progress * PI) * 0.8

	# Normal attack animations
	elif is_attacking and right_arm:
		arms_controlled = true
		var attack_progress = attack_timer / current_attack_animation_time if current_attack_animation_time > 0 else 0.0
		attack_progress = clamp(attack_progress, 0.0, 1.0)

		# Default slash animation (works for sword, fists, etc.)
		var start_z = -1.0
		var end_z = 0.5
		var horizontal_angle = lerp(start_z, end_z, attack_progress)
		right_arm.rotation.z = horizontal_angle
		var forward_angle = -sin(attack_progress * PI) * 0.8
		right_arm.rotation.x = forward_angle

		if right_elbow:
			var elbow_bend = -sin(attack_progress * PI) * 0.6
			right_elbow.rotation.x = elbow_bend

	# ==== MOVEMENT ANIMATIONS ====
	match current_animation_state:
		"walk":
			remote_anim_time += delta
			var walk_speed = 6.0
			var t = remote_anim_time * walk_speed

			# Leg swing
			var leg_swing = sin(t) * 0.4
			left_leg.rotation.x = leg_swing
			right_leg.rotation.x = -leg_swing

			# Knee bend when leg swings forward
			if left_knee:
				left_knee.rotation.x = max(0.0, leg_swing) * 0.8
			if right_knee:
				right_knee.rotation.x = max(0.0, -leg_swing) * 0.8

			# Arm swing opposite to legs (only if not controlled by combat)
			if not arms_controlled:
				if left_arm:
					left_arm.rotation.x = -leg_swing * 0.5
				if right_arm:
					right_arm.rotation.x = leg_swing * 0.5

		"run":
			remote_anim_time += delta
			var run_speed = 10.0
			var t = remote_anim_time * run_speed

			# More pronounced leg swing for running
			var leg_swing = sin(t) * 0.6
			left_leg.rotation.x = leg_swing
			right_leg.rotation.x = -leg_swing

			# More knee bend for running
			if left_knee:
				left_knee.rotation.x = max(0.0, leg_swing) * 1.2
			if right_knee:
				right_knee.rotation.x = max(0.0, -leg_swing) * 1.2

			# More arm swing for running (only if not controlled by combat)
			if not arms_controlled:
				if left_arm:
					left_arm.rotation.x = -leg_swing * 0.7
				if right_arm:
					right_arm.rotation.x = leg_swing * 0.7

		"jump", "falling":
			# Legs in jumping pose
			if left_leg:
				left_leg.rotation.x = lerp(left_leg.rotation.x, 0.4, delta * 10.0)
			if right_leg:
				right_leg.rotation.x = lerp(right_leg.rotation.x, -0.3, delta * 10.0)

			# Arms out for balance (only if not controlled by combat)
			if not arms_controlled:
				if left_arm:
					left_arm.rotation.x = lerp(left_arm.rotation.x, -0.2, delta * 10.0)
					left_arm.rotation.z = lerp(left_arm.rotation.z, -0.4, delta * 10.0)
				if right_arm:
					right_arm.rotation.x = lerp(right_arm.rotation.x, -0.2, delta * 10.0)
					right_arm.rotation.z = lerp(right_arm.rotation.z, 0.4, delta * 10.0)

		"idle", _:
			# Legs return to neutral
			if left_leg:
				left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 8.0)
			if right_leg:
				right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 8.0)
			if left_knee:
				left_knee.rotation.x = lerp(left_knee.rotation.x, 0.0, delta * 8.0)
			if right_knee:
				right_knee.rotation.x = lerp(right_knee.rotation.x, 0.0, delta * 8.0)

			# Arms return to neutral (only if not controlled by combat)
			if not arms_controlled:
				if left_arm:
					left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 8.0)
					left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 8.0)
				if right_arm:
					right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 8.0)
					right_arm.rotation.z = lerp(right_arm.rotation.z, 0.0, delta * 8.0)

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

	# COMBO SYSTEM: Check weapon type for combo attacks
	var is_knife = weapon_data.item_id == "stone_knife"
	var is_sword = weapon_data.item_id == "stone_sword"
	var is_axe = weapon_data.item_id == "stone_axe"
	var combo_multiplier: float = 1.0  # Damage multiplier based on combo

	# Track weapon type for animations
	current_weapon_type = weapon_data.item_id

	# Set animation speed based on weapon type
	if is_knife:
		current_attack_animation_time = KNIFE_ANIMATION_TIME  # 25% faster
	elif is_sword:
		current_attack_animation_time = SWORD_ANIMATION_TIME  # Normal speed
	elif is_axe:
		current_attack_animation_time = AXE_ANIMATION_TIME  # Slower, heavier
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

	elif is_axe:
		# Store current combo animation BEFORE incrementing
		current_combo_animation = combo_count  # 0=right sweep, 1=left sweep, 2=overhead slam

		# Axe 3-hit combo: right sweep, left sweep, OVERHEAD SLAM finisher
		if combo_count == 0:
			print("[Player] Axe combo hit 1 - RIGHT SWEEP!")
		elif combo_count == 1:
			print("[Player] Axe combo hit 2 - LEFT SWEEP!")
		else:  # combo_count == 2
			combo_multiplier = 2.0  # 2x damage on overhead slam finisher
			print("[Player] Axe combo FINISHER - OVERHEAD SLAM! (Hit %d)" % (combo_count + 1))

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
		if weapon_wrist_pivot:
			weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

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

	# Play attack sound based on weapon type
	if equipped_weapon_visual:
		if weapon_data.weapon_type == WeaponData.WeaponType.MAGIC:
			SoundManager.play_sound_varied("fire_cast", global_position)
		else:
			SoundManager.play_sound_varied("sword_swing", global_position)
	else:
		SoundManager.play_sound_varied("punch_swing", global_position)

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
			global_rotation.y = body_container.rotation.y

	# Check if this is a ranged weapon (magic or ranged)
	var is_ranged = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC or weapon_data.weapon_type == WeaponData.WeaponType.RANGED

	if is_ranged:
		# RANGED ATTACK: Spawn projectile
		_spawn_projectile(weapon_data, camera)
	else:
		# MELEE ATTACK: Valheim-style hitbox collision detection
		# Enemy damage is handled by weapon hitbox Area3D collision (see player_equipment_visual.gd)
		# The hitbox is enabled/disabled during attack animation (see update_hitbox_during_attack)

		# Get attack direction for environmental object raycast
		var viewport_size := get_viewport().get_visible_rect().size
		var crosshair_offset := Vector2(-41.0, -50.0)
		var crosshair_pos := viewport_size / 2 + crosshair_offset
		var ray_origin := camera.project_ray_origin(crosshair_pos)
		var ray_direction := camera.project_ray_normal(crosshair_pos)

		# Only check environmental objects via raycast (trees, rocks, etc.)
		# Enemy detection is now handled by weapon hitbox collision
		var ray_end := ray_origin + ray_direction * attack_range
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.collision_mask = 1  # World layer only (NOT enemies)
		query.exclude = [self]

		var result := space_state.intersect_ray(query)
		if result:
			var hit_object: Object = result.collider
			# Check if it's an environmental object (tree, rock, etc.)
			if hit_object.has_method("get_object_type") and hit_object.has_method("get_object_id"):
				var tool_type: String = weapon_data.tool_type if "tool_type" in weapon_data else ""

				# Check tool requirement
				if hit_object.has_method("can_be_damaged_by"):
					if not hit_object.can_be_damaged_by(tool_type):
						var required_tool: String = hit_object.get_required_tool_type() if hit_object.has_method("get_required_tool_type") else "unknown"
						print("[Player] Cannot damage %s - requires %s!" % [hit_object.get_object_type(), required_tool])
						SoundManager.play_sound_varied("wrong_tool", global_position)
						return

				var hit_node := hit_object as Node3D
				var object_name: String = hit_node.name if hit_node else ""
				var is_dynamic := object_name.begins_with("FallenLog_") or object_name.begins_with("SplitLog_")

				if is_dynamic:
					_send_dynamic_damage_request(object_name, damage, result.position)
				else:
					var object_id: int = hit_object.get_object_id()
					var chunk_pos: Vector2i = hit_object.chunk_position if "chunk_position" in hit_object else Vector2i.ZERO
					_send_damage_request(chunk_pos, object_id, damage, result.position)

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
		"stone_axe":
			_special_attack_axe_spin(weapon_data, camera)
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

	# Store damage values for continuous hit detection during lunge
	lunge_damage = damage
	lunge_knockback = knockback
	lunge_hit_enemies.clear()  # Reset hit tracking for new lunge

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
			global_rotation.y = body_container.rotation.y
			print("[Player] Snapped mesh to face lunge direction: %.2f radians" % body_container.rotation.y)

	# Rotate knife to 0 degrees (straight/horizontal) for lunge
	if equipped_weapon_visual:
		equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)  # Straight angle for lunge

	# NOTE: No initial _perform_melee_attack call - continuous detection handles damage throughout the arc

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
			global_rotation.y = body_container.rotation.y

	# Rotate sword to 0 degrees (straight/horizontal) for jab
	if equipped_weapon_visual:
		equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)  # Straight angle for jab

	# Perform melee raycast attack
	_perform_melee_attack(camera, attack_range, damage, knockback)

## Axe special: Spinning whirlwind attack (360 degree spin, hits everything around)
func _special_attack_axe_spin(weapon_data: WeaponData, camera: Camera3D) -> void:
	var stamina_cost: float = 35.0  # High stamina cost for powerful spin
	var damage: float = weapon_data.damage * 1.5  # 1.5x damage during spin
	var knockback: float = weapon_data.knockback * 2.0  # Double knockback, sends enemies flying
	var attack_range: float = 4.0  # Close range spin

	# Check stamina cost
	if not consume_stamina(stamina_cost):
		print("[Player] Not enough stamina for axe spin!")
		return

	print("[Player] Axe WHIRLWIND SPIN attack!")

	# Trigger special attack animation
	is_special_attacking = true
	is_spinning = true
	spin_rotation = 0.0
	spin_hit_times.clear()
	special_attack_timer = 0.0
	current_special_attack_animation_time = AXE_SPECIAL_ANIMATION_TIME

	# Store attack parameters for continuous hit detection during spin
	lunge_damage = damage  # Reuse lunge_damage for spin damage
	lunge_knockback = knockback

	# Rotate player mesh to face initial attack direction
	if is_local_player and body_container:
		var camera_controller = get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			var camera_yaw = camera_controller.camera_rotation.x
			body_container.rotation.y = camera_yaw + PI
			global_rotation.y = body_container.rotation.y

	SoundManager.play_sound_varied("sword_swing", global_position)

	# Perform initial hit check in front (damage dealt continuously during spin via _physics_process)

## Fire wand special: Area fire effect around the player (defensive fire ring)
func _special_attack_fire_wand_area(weapon_data: WeaponData, _camera: Camera3D) -> void:
	var brain_power_cost: float = 25.0  # Moderate brain power cost
	var damage: float = weapon_data.damage * 0.4  # 0.4x damage per tick (low DoT)
	var area_radius: float = 3.5  # 3.5 meter radius defensive ring
	var duration: float = 3.0  # 3 seconds of burning

	# Check brain power cost (fire wand is a MAGIC weapon)
	if not consume_brain_power(brain_power_cost):
		print("[Player] Not enough brain power for fire area!")
		return

	print("[Player] Fire wand AREA EFFECT around player!")

	# Trigger special attack animation
	is_special_attacking = true
	special_attack_timer = 0.0

	# Spawn fire area at player's position (defensive fire ring)
	var player_ground_pos: Vector3 = global_position
	print("[Player] Creating fire area around player at %s" % player_ground_pos)

	# Spawn fire area effect scene
	var fire_area_scene = load("res://shared/effects/fire_area.tscn")
	var fire_area = fire_area_scene.instantiate()
	# Set properties BEFORE adding to tree so _ready() uses correct values
	fire_area.radius = area_radius
	fire_area.damage = damage
	fire_area.duration = duration
	get_tree().root.add_child(fire_area)
	fire_area.global_position = player_ground_pos

	# Sync fire area visual to other clients
	var pos = player_ground_pos
	NetworkManager.rpc_spawn_fire_area.rpc_id(1, [pos.x, pos.y, pos.z], area_radius, duration)

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

	# Play sound effect for magic weapons
	if is_magic_weapon:
		SoundManager.play_sound_varied("fire_cast", global_position)

	# Trigger special attack animation
	is_special_attacking = true
	special_attack_timer = 0.0

	# Rotate player mesh to face attack direction
	if is_local_player and body_container:
		var camera_controller = get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			var camera_yaw = camera_controller.camera_rotation.x
			body_container.rotation.y = camera_yaw + PI
			global_rotation.y = body_container.rotation.y

	# Check if ranged weapon
	var is_ranged = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC or weapon_data.weapon_type == WeaponData.WeaponType.RANGED
	if is_ranged:
		_spawn_projectile(weapon_data, camera)
	else:
		_perform_melee_attack(camera, attack_range, damage, knockback)

## Helper: Perform melee raycast attack (extracted from _handle_attack)
func _perform_melee_attack(camera: Camera3D, attack_range: float, damage: float, knockback: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var crosshair_offset := Vector2(-41.0, -50.0)
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
			# Use network damage system (same as _handle_attack)
			var enemy_network_id = hit_object.network_id if "network_id" in hit_object else 0
			if enemy_network_id > 0:
				print("[Player] Special attack hit enemy %s (net_id=%d, %.1f damage, %.1f knockback)" % [hit_object.name, enemy_network_id, damage, knockback])
				_send_enemy_damage_request(enemy_network_id, damage, knockback, ray_direction)
			else:
				print("[Player] Hit enemy %s but it has no network_id!" % hit_object.name)

		# Check if it's an environmental object
		elif hit_object.has_method("get_object_type") and hit_object.has_method("get_object_id"):
			var object_type: String = hit_object.get_object_type()
			var object_id: int = hit_object.get_object_id()
			var chunk_pos: Vector2i = hit_object.chunk_position if "chunk_position" in hit_object else Vector2i.ZERO

			print("[Player] Attacking %s (ID: %d in chunk %s)" % [object_type, object_id, chunk_pos])
			_send_damage_request(chunk_pos, object_id, damage, result.position)

## Helper: Deal damage to all enemies in an area
func _deal_area_damage(center: Vector3, radius: float, damage: float) -> void:
	# Get all enemies in the scene (using cached list)
	var enemies = EnemyAI._get_cached_enemies(get_tree())
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check if enemy is in range
		var distance = enemy.global_position.distance_to(center)
		if distance <= radius:
			var direction = (enemy.global_position - center).normalized()
			# Use network damage system (same as _handle_attack)
			var enemy_network_id = enemy.network_id if "network_id" in enemy else 0
			if enemy_network_id > 0:
				print("[Player] Area damage hit %s (net_id=%d) at distance %.1fm" % [enemy.name, enemy_network_id, distance])
				_send_enemy_damage_request(enemy_network_id, damage, 2.0, direction)
			else:
				print("[Player] Area damage hit enemy %s but it has no network_id!" % enemy.name)

## Helper: Check for enemy collisions during lunge (called every physics frame while lunging)
func _check_lunge_collision() -> void:
	if lunge_damage <= 0:
		return  # No damage set, skip

	# Get all enemies in the scene (using cached list for performance)
	var enemies = EnemyAI._get_cached_enemies(get_tree())
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Skip if we already hit this enemy during this lunge
		var enemy_id = enemy.get_instance_id()
		if enemy_id in lunge_hit_enemies:
			continue

		# Check if enemy is within lunge hit radius of player
		var distance = enemy.global_position.distance_to(global_position)
		if distance <= LUNGE_HIT_RADIUS:
			# HIT! Add to hit list and deal damage
			lunge_hit_enemies.append(enemy_id)

			var direction = lunge_direction if lunge_direction != Vector3.ZERO else (enemy.global_position - global_position).normalized()
			var enemy_network_id = enemy.network_id if "network_id" in enemy else 0
			if enemy_network_id > 0:
				print("[Player] LUNGE HIT %s (net_id=%d) at distance %.1fm! (%.1f damage)" % [enemy.name, enemy_network_id, distance, lunge_damage])
				_send_enemy_damage_request(enemy_network_id, lunge_damage, lunge_knockback, direction)
			else:
				print("[Player] Lunge hit enemy %s but it has no network_id!" % enemy.name)

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
	var crosshair_offset := Vector2(-41.0, -50.0)
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

	# Sync projectile visual to other clients
	var projectile_type := "fireball"  # Default, expand as more projectiles added
	if weapon_data.item_id == "fire_wand":
		projectile_type = "fireball"
	NetworkManager.rpc_spawn_projectile.rpc_id(1, projectile_type,
		[spawn_pos.x, spawn_pos.y, spawn_pos.z],
		[direction.x, direction.y, direction.z],
		speed)

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

## Send damage request for dynamic objects (fallen logs, split logs, etc.)
func _send_dynamic_damage_request(object_name: String, damage: float, hit_position: Vector3) -> void:
	# Send RPC to server via NetworkManager
	NetworkManager.rpc_damage_dynamic_object.rpc_id(1, object_name, damage, hit_position)

## Send enemy damage request to server (client-authoritative hit using network_id)
func _send_enemy_damage_request(enemy_network_id: int, damage: float, knockback: float, direction: Vector3) -> void:
	# Send RPC to server via NetworkManager
	var dir_array = [direction.x, direction.y, direction.z]
	print("[Player] Sending rpc_damage_enemy to server: net_id=%d, damage=%.1f" % [enemy_network_id, damage])
	NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_network_id, damage, knockback, dir_array)

## Show feedback when player tries to damage something with the wrong tool
func _show_wrong_tool_feedback(required_tool: String) -> void:
	# Play a "bonk" or denial sound
	SoundManager.play_sound_varied("wrong_tool", global_position)

	# Emit signal for UI to show message (if connected)
	# For now, the print statement in the caller is sufficient
	# TODO: Add floating text like "Requires Axe" above the object

# ============================================================================
# TERRAIN MODIFICATION (PICKAXE, HOE)
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

	# Check if it's a terrain tool
	var is_pickaxe := main_hand_id == "stone_pickaxe"
	var is_hoe := main_hand_id == "stone_hoe"

	# Check if any terrain action applies
	if not is_pickaxe and not is_hoe:
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

	# Determine operation based on tool and input first (to know which raycast to use)
	var operation := ""
	var left_click: bool = input_data.get("attack", false)
	var right_click: bool = input_data.get("secondary_action", false)
	var middle_click: bool = input_data.get("middle_mouse", false)

	if is_pickaxe:
		if left_click:
			# Left click = place (fill terrain)
			# Check if player has earth for placing
			if inventory and inventory.has_item("earth", 1):
				operation = "place_square"
			else:
				print("[Player] Cannot place earth - need earth in inventory!")
				return false
		elif right_click:
			# Right click = dig (remove terrain)
			operation = "dig_square"
	elif is_hoe:
		if left_click or right_click:
			operation = "flatten_square"

	# Get target position using cached preview positions (ensures dig/place match the preview cubes)
	var target_pos := Vector3.ZERO
	if operation == "dig_square":
		# For digging: use cached red cube position
		target_pos = cached_dig_position
	elif operation == "place_square":
		# For placing: use cached white cube position
		target_pos = cached_place_position
	elif operation == "flatten_square":
		# For flattening: raycast to ground and use player position
		target_pos = _raycast_terrain_target(camera)
		if target_pos == Vector3.ZERO:
			target_pos = global_position  # Fallback to player position
		target_pos = _snap_to_grid(target_pos)

	if target_pos == Vector3.ZERO:
		print("[Player] No valid target found")
		return false

	# Safety check: Don't allow terrain placement too close to player (prevents clipping through mesh)
	if not operation.is_empty() and operation == "place_square":
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

## Snap position to 2-meter grid for square placement
func _snap_to_grid(pos: Vector3) -> Vector3:
	# Snap to 2-meter grid (matching SQUARE_SIZE)
	var grid_size := 2.0
	return Vector3(
		floor(pos.x / grid_size) * grid_size + grid_size / 2.0,
		floor(pos.y / grid_size) * grid_size + grid_size / 2.0,
		floor(pos.z / grid_size) * grid_size + grid_size / 2.0
	)

## Raycast from camera to find grid cell (for digging walls/air blocks)
func _raycast_grid_cell_from_camera(camera: Camera3D) -> Vector3:
	# Raycast in camera direction to find which grid cell player is pointing at
	var from := camera.global_position
	var direction := -camera.global_transform.basis.z.normalized()
	var to := from + direction * 50.0  # 50 meter max range

	# Perform raycast using physics space
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World layer

	var result := space_state.intersect_ray(query)
	if result:
		# Hit something - use the normal to offset into the surface by 1 full grid unit
		# This ensures we're deep inside the block we hit, not in air or on the edge
		var normal: Vector3 = result.normal
		var point_inside: Vector3 = result.position - normal * 1.5  # Move 1.5m into surface (opposite of normal)
		var snapped := _snap_to_grid(point_inside)
		return snapped
	else:
		# No hit - calculate grid cell along ray at reasonable distance (5 meters)
		var point_in_air := from + direction * 5.0
		return _snap_to_grid(point_in_air)

	return Vector3.ZERO

## Update persistent terrain preview (shows cube when tool equipped)
func _update_persistent_terrain_preview() -> void:
	if not terrain_dig_preview_cube or not terrain_place_preview_cube:
		return

	# Check if we have a terrain tool equipped
	var main_hand_id := ""
	if equipment:
		main_hand_id = equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)

	var is_pickaxe := main_hand_id == "stone_pickaxe"
	var is_hoe := main_hand_id == "stone_hoe"

	# If we have a terrain tool equipped, show persistent preview
	if is_pickaxe:
		# Get camera for raycasting
		var camera := _get_camera()
		if camera:
			# RED cube: Show which block will be dug (camera raycast)
			var dig_pos := _raycast_grid_cell_from_camera(camera)
			if dig_pos != Vector3.ZERO:
				cached_dig_position = dig_pos  # Cache for actual dig operation
				terrain_dig_preview_cube.global_position = dig_pos
				terrain_dig_preview_cube.scale = Vector3(1.05, 1.05, 1.05)
				if terrain_preview_timer <= 0.0:
					terrain_dig_preview_cube.visible = true
				else:
					terrain_dig_preview_cube.visible = false

			# WHITE cube: Show where block will be placed (above ground surface)
			var place_pos := _calculate_place_position(camera)
			if place_pos != Vector3.ZERO:
				cached_place_position = place_pos  # Cache for actual place operation
				terrain_place_preview_cube.global_position = place_pos
				terrain_place_preview_cube.scale = Vector3(1.05, 1.05, 1.05)
				if terrain_preview_timer <= 0.0:
					terrain_place_preview_cube.visible = true
				else:
					terrain_place_preview_cube.visible = false

			is_showing_persistent_preview = true
			return
	elif is_hoe:
		# For hoe: show a larger 4x4 preview (8m x 8m area)
		var camera := _get_camera()
		if camera:
			var target_pos := _raycast_terrain_target(camera)
			if target_pos != Vector3.ZERO:
				target_pos = _snap_to_grid(target_pos)
				terrain_dig_preview_cube.global_position = target_pos
				terrain_dig_preview_cube.scale = Vector3(8.4, 2.1, 8.4)  # 8x8 area, 2m tall, slightly larger for visibility
				if terrain_preview_timer <= 0.0:
					terrain_dig_preview_cube.visible = true
				else:
					terrain_dig_preview_cube.visible = false
				terrain_place_preview_cube.visible = false
				is_showing_persistent_preview = true
				return

	# No terrain tool equipped, hide persistent preview
	if is_showing_persistent_preview:
		terrain_dig_preview_cube.visible = false
		terrain_place_preview_cube.visible = false
		is_showing_persistent_preview = false

## Show terrain preview shape (after placement) - briefly shows the actual placed shape
func _show_terrain_preview(operation: String, position: Vector3) -> void:
	if not terrain_preview_cube:
		return

	# Show cube briefly at grid-snapped position (position is already snapped)
	terrain_preview_cube.global_position = position
	terrain_preview_cube.scale = Vector3(1.05, 1.05, 1.05)  # Slightly larger than 2x2x2 block for visibility
	terrain_preview_cube.visible = true

	# Reset the timer to keep shape visible temporarily
	terrain_preview_timer = TERRAIN_PREVIEW_DURATION

## Trigger animation for terrain tool usage
func _trigger_terrain_tool_animation(operation: String) -> void:
	# Trigger attack animation for visual feedback
	is_attacking = true
	attack_timer = 0.0
	current_attack_animation_time = 0.3  # Animation time for square operations

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

## Calculate place position - finds grid cell adjacent to the surface in the direction of the normal
func _calculate_place_position(camera: Camera3D) -> Vector3:
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
		# Use the surface normal to determine which adjacent grid cell to place in
		var normal: Vector3 = result.normal
		var hit_point: Vector3 = result.position

		# Move slightly along the normal (into the air, away from surface)
		var point_above := hit_point + normal * 1.5

		# Snap to grid
		return _snap_to_grid(point_above)

	return Vector3.ZERO

## Send terrain modification request to server
func _send_terrain_modification_request(operation: String, position: Vector3, tool: String) -> void:
	var data := {
		"tool": tool
	}

	# For hoe flattening, snap to the grid level at player's feet
	# This keeps you at the same height if ground is flat, or levels to where you're standing
	if operation == "flatten_square":
		var grid_size: float = 2.0
		var feet_height: float = global_position.y - 1.0  # Player's feet (character is ~2m tall)
		# Snap using the same logic as _snap_to_grid to ensure perfect alignment
		var platform_height: float = floor(feet_height / grid_size) * grid_size + grid_size / 2.0
		data["target_height"] = platform_height
		print("[Player] Flatten height: feet=%.2f, snapped=%.2f" % [feet_height, platform_height])

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

	# Don't block if holding a terrain tool (pickaxe or hoe)
	var main_hand_id := ""
	if equipment:
		main_hand_id = equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)

	var is_terrain_tool := main_hand_id == "stone_pickaxe" or main_hand_id == "stone_hoe"

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
	# Create cube preview (temporary - shown after placement)
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

	# Create RED dig preview cube (shows which block will be dug)
	terrain_dig_preview_cube = MeshInstance3D.new()
	var dig_cube_mesh = BoxMesh.new()
	dig_cube_mesh.size = Vector3(2.0, 2.0, 2.0)
	terrain_dig_preview_cube.mesh = dig_cube_mesh

	# Semi-transparent red material
	var dig_material = StandardMaterial3D.new()
	dig_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dig_material.albedo_color = Color(1.0, 0.0, 0.0, 0.3)  # Red, 30% opacity
	dig_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terrain_dig_preview_cube.material_override = dig_material

	terrain_dig_preview_cube.visible = false
	get_tree().root.add_child(terrain_dig_preview_cube)

	# Create WHITE place preview cube (shows where block will be placed)
	terrain_place_preview_cube = MeshInstance3D.new()
	var place_cube_mesh = BoxMesh.new()
	place_cube_mesh.size = Vector3(2.0, 2.0, 2.0)
	terrain_place_preview_cube.mesh = place_cube_mesh

	# Semi-transparent white material
	var place_material = StandardMaterial3D.new()
	place_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	place_material.albedo_color = Color(1.0, 1.0, 1.0, 0.3)  # White, 30% opacity
	place_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terrain_place_preview_cube.material_override = place_material

	terrain_place_preview_cube.visible = false
	get_tree().root.add_child(terrain_place_preview_cube)

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
			# Reset wrist pivot to neutral
			if weapon_wrist_pivot:
				weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

	# Update weapon hitbox state during attacks (Valheim-style collision detection)
	if combat and is_local_player:
		combat.update_hitbox_during_attack()

	# Update special attack animation
	if is_special_attacking:
		special_attack_timer += delta

		# Axe spin: rotate body and check for hits during spin
		if is_spinning and body_container:
			var spin_progress = special_attack_timer / current_special_attack_animation_time
			# Full 360 degree spin (plus a bit extra for follow-through)
			spin_rotation = spin_progress * TAU * 1.1
			body_container.rotation.y += delta * 15.0  # Fast spin

			# Check for enemies in range during spin (every frame)
			_check_spin_hits()

		if special_attack_timer >= current_special_attack_animation_time:
			is_special_attacking = false
			special_attack_timer = 0.0
			# Reset spin state
			if is_spinning:
				is_spinning = false
				spin_hit_times.clear()
				# Reset wrist pivot after spin (but NOT weapon - stay at 90 degrees)
				if weapon_wrist_pivot:
					weapon_wrist_pivot.rotation_degrees = Vector3.ZERO
			# DON'T reset is_lunging here - it persists until landing!
			# DON'T reset weapon rotation here - knife stays horizontal until landing!

	# Stun animation overrides everything
	if is_stunned:
		_animate_stun(delta, left_arm, right_arm, left_leg, right_leg)
		return

	# Update landing animation timer
	if is_landing:
		landing_timer += delta
		if landing_timer >= LANDING_ANIMATION_TIME:
			is_landing = false
			landing_timer = 0.0

	# Get elbow and knee nodes for articulated animations
	var left_elbow = left_arm.get_node_or_null("Elbow") if left_arm else null
	var right_elbow = right_arm.get_node_or_null("Elbow") if right_arm else null
	var left_knee = left_leg.get_node_or_null("Knee") if left_leg else null
	var right_knee = right_leg.get_node_or_null("Knee") if right_leg else null

	# Landing animation (impact bounce) - high priority
	if is_landing:
		var landing_progress = landing_timer / LANDING_ANIMATION_TIME
		var bounce_curve = sin(landing_progress * PI)  # 0 -> 1 -> 0

		# Compress body on impact
		if body_container:
			body_container.scale.y = lerp(1.0, 0.85, bounce_curve * 0.5)

		# Bend knees on impact
		if left_knee:
			left_knee.rotation.x = lerp(0.0, 0.8, bounce_curve)
		if right_knee:
			right_knee.rotation.x = lerp(0.0, 0.8, bounce_curve)

		# Arms swing down slightly
		if left_arm and not is_blocking:
			left_arm.rotation.x = lerp(0.0, 0.3, bounce_curve)
			if left_elbow:
				left_elbow.rotation.x = lerp(0.0, -0.2, bounce_curve)
		if right_arm and not is_attacking and not is_special_attacking:
			right_arm.rotation.x = lerp(0.0, 0.3, bounce_curve)
			if right_elbow:
				right_elbow.rotation.x = lerp(0.0, -0.2, bounce_curve)

		# Don't process other movement animations during landing
		return

	# Jump/falling animation - Light running jump style
	if (is_jumping or is_falling) and not is_on_floor():
		# Arms spread slightly to the sides for balance
		var arm_intensity = 1.0 if is_jumping else 0.7

		if left_arm and not is_blocking:
			# Arm out to the side, slight forward angle
			left_arm.rotation.x = lerp(left_arm.rotation.x, -0.2 * arm_intensity, delta * 10.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, -0.4 * arm_intensity, delta * 10.0)  # Out to left side (negative = outward)
			if left_elbow:
				left_elbow.rotation.x = lerp(left_elbow.rotation.x, 0.0, delta * 10.0)  # Keep straight

		if right_arm and not is_attacking and not is_special_attacking:
			# Arm out to the side, slight forward angle
			right_arm.rotation.x = lerp(right_arm.rotation.x, -0.2 * arm_intensity, delta * 10.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, 0.4 * arm_intensity, delta * 10.0)  # Out to right side (positive = outward)
			if right_elbow:
				right_elbow.rotation.x = lerp(right_elbow.rotation.x, 0.0, delta * 10.0)  # Keep straight

		# Running pose: one leg forward, one leg back (asymmetric)
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.4, delta * 10.0)  # Forward
			if left_knee:
				left_knee.rotation.x = lerp(left_knee.rotation.x, 0.6, delta * 10.0)  # Moderate bend
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, -0.3, delta * 10.0)  # Back
			if right_knee:
				right_knee.rotation.x = lerp(right_knee.rotation.x, 0.3, delta * 10.0)  # Slight bend

		# No forward lean - keep body upright
		if body_container:
			body_container.rotation.x = lerp(body_container.rotation.x, 0.0, delta * 10.0)

		# NOTE: Don't return here - allow attack animations to process below
		# The right_arm is already skipped above if attacking, so attack animations will handle it

	# Lunge crouch animation overrides everything (ball shape for dramatic leap)
	if is_lunging and body_container:
		# Crouch the body into a ball shape with aggressive forward dive
		body_container.rotation.x = lerp(body_container.rotation.x, 1.3, delta * 20.0)  # Lean forward aggressively (30 degrees more)
		body_container.scale.y = lerp(body_container.scale.y, 0.7, delta * 20.0)  # Compress vertically

		# Tuck arms and legs in
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, -0.8, delta * 20.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.5, delta * 20.0)
			if left_elbow:
				left_elbow.rotation.x = lerp(left_elbow.rotation.x, -0.9, delta * 20.0)  # Tuck elbow in
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, -0.8, delta * 20.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, -0.5, delta * 20.0)
			if right_elbow:
				right_elbow.rotation.x = lerp(right_elbow.rotation.x, -0.9, delta * 20.0)  # Tuck elbow in
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.6, delta * 20.0)
			if left_knee:
				left_knee.rotation.x = lerp(left_knee.rotation.x, 1.2, delta * 20.0)  # Bend knee tightly
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.6, delta * 20.0)
			if right_knee:
				right_knee.rotation.x = lerp(right_knee.rotation.x, 1.2, delta * 20.0)  # Bend knee tightly
		return  # Skip other animations while lunging

	# Reset body container scale and rotation when not lunging, not in air
	# Don't reset when jumping/falling - preserve the falling pose
	var in_air = (is_jumping or is_falling) and not is_on_floor()
	if body_container and not is_lunging and not is_stunned and not in_air:
		body_container.rotation.x = lerp(body_container.rotation.x, 0.0, delta * 10.0)
		body_container.scale.y = lerp(body_container.scale.y, 1.0, delta * 10.0)

		# Also reset limbs from lunge position
		if left_arm and not is_blocking:
			left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 10.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 10.0)
			if left_elbow:
				left_elbow.rotation.x = lerp(left_elbow.rotation.x, 0.0, delta * 10.0)
		if right_arm and not is_attacking and not is_special_attacking:
			right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 10.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, 0.0, delta * 10.0)
			if right_elbow:
				right_elbow.rotation.x = lerp(right_elbow.rotation.x, 0.0, delta * 10.0)
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 10.0)
			if left_knee:
				left_knee.rotation.x = lerp(left_knee.rotation.x, 0.0, delta * 10.0)
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 10.0)
			if right_knee:
				right_knee.rotation.x = lerp(right_knee.rotation.x, 0.0, delta * 10.0)

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

		if is_spinning:
			# AXE SPIN - Arms extended horizontally, spinning with body
			# Both arms out to sides holding the axe
			right_arm.rotation.x = -0.3  # Slightly forward
			right_arm.rotation.z = -1.5  # Extended to the right
			if left_arm:
				left_arm.rotation.x = -0.3
				left_arm.rotation.z = 1.5  # Extended to the left
			# Arms fully extended during spin
			if right_elbow:
				right_elbow.rotation.x = -0.1
			if left_elbow:
				left_elbow.rotation.x = -0.1
		else:
			# Default special attack animation
			# Strong overhead slash or thrust (more dramatic than normal attacks)
			var swing_x = -sin(attack_progress * PI) * 2.0  # Very strong forward/down motion
			var swing_z = sin(attack_progress * PI) * -0.5  # Some horizontal motion
			right_arm.rotation.x = swing_x
			right_arm.rotation.z = swing_z

			# Elbow bends during windup and extends on strike
			if right_elbow:
				var elbow_bend = -sin(attack_progress * PI) * 0.8  # Negative = bend inward
				right_elbow.rotation.x = elbow_bend
	# Attack animation overrides arm movement (RIGHT arm for weapons)
	elif is_attacking and right_arm:
		var attack_progress = attack_timer / current_attack_animation_time

		# Different animations based on weapon type and combo
		if current_weapon_type == "stone_axe":
			# AXE COMBO ANIMATIONS - Big, powerful two-handed swings
			_animate_axe_attack(attack_progress, right_arm, left_arm, right_elbow, left_elbow)
		elif current_weapon_type == "stone_knife":
			# KNIFE COMBO ANIMATIONS
			_animate_knife_attack(attack_progress, right_arm, right_elbow)
		else:
			# DEFAULT SLASH ANIMATION
			var start_z = -1.0
			var end_z = 0.5
			var horizontal_angle = lerp(start_z, end_z, attack_progress)
			right_arm.rotation.z = horizontal_angle
			var forward_angle = -sin(attack_progress * PI) * 0.8
			right_arm.rotation.x = forward_angle

			if right_elbow:
				var elbow_bend = -sin(attack_progress * PI) * 0.6
				right_elbow.rotation.x = elbow_bend
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

		# Play footstep sound when leg hits ground (phase crosses PI boundaries)
		# Each PI of phase = one footstep (left or right foot)
		if is_on_floor() and is_local_player and not is_spinning:
			var current_step = int(animation_phase / PI)
			var last_step = int(_last_footstep_phase / PI)
			if current_step != last_step:
				SoundManager.play_sound_varied("footstep_grass", global_position, -8.0, 0.15)
		_last_footstep_phase = animation_phase

		# Skip walk animation during spin - legs stay neutral, body spins
		if is_spinning:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 10.0)
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 10.0)
			if left_knee:
				left_knee.rotation.x = lerp(left_knee.rotation.x, 0.0, delta * 10.0)
			if right_knee:
				right_knee.rotation.x = lerp(right_knee.rotation.x, 0.0, delta * 10.0)
		elif is_blocking:
			# Defensive shuffle - small leg movements, LEFT arm stays raised (shield)
			var leg_angle = sin(animation_phase) * 0.15  # Half the normal swing
			left_leg.rotation.x = leg_angle
			right_leg.rotation.x = -leg_angle

			# Add knee bend for walking
			var knee_angle = sin(animation_phase) * 0.4
			if left_knee:
				left_knee.rotation.x = max(0.0, knee_angle)
			if right_knee:
				right_knee.rotation.x = max(0.0, -knee_angle)

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

			# Legs swing opposite with knee articulation
			left_leg.rotation.x = leg_angle
			right_leg.rotation.x = -leg_angle

			# Add natural knee bend - knees bend more when leg is forward
			var knee_angle = sin(animation_phase) * 0.5
			if left_knee:
				left_knee.rotation.x = max(0.0, knee_angle)  # Only bend forward
			if right_knee:
				right_knee.rotation.x = max(0.0, -knee_angle)  # Only bend forward

			# Arms swing opposite to legs with elbow articulation (natural walking motion)
			if left_arm and not is_blocking:
				left_arm.rotation.x = -arm_angle  # Left arm swings opposite to left leg
				if left_elbow:
					# Elbow bends slightly when arm is back
					left_elbow.rotation.x = max(0.0, arm_angle * 0.8)
			if right_arm and not is_attacking and not is_special_attacking and not is_blocking:
				right_arm.rotation.x = arm_angle   # Right arm swings opposite to right leg
				if right_elbow:
					# Elbow bends slightly when arm is back
					right_elbow.rotation.x = max(0.0, -arm_angle * 0.8)

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

		# Reset knee joints
		if left_knee:
			left_knee.rotation.x = lerp(left_knee.rotation.x, 0.0, delta * 5.0)
		if right_knee:
			right_knee.rotation.x = lerp(right_knee.rotation.x, 0.0, delta * 5.0)

		# Don't reset arms if blocking, attacking, or special attacking
		# Left arm: reset unless blocking (shield raised)
		if left_arm and not is_blocking:
			left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 5.0)
			if left_elbow:
				left_elbow.rotation.x = lerp(left_elbow.rotation.x, 0.0, delta * 5.0)
		# Right arm: reset unless attacking or special attacking (weapon swinging)
		if right_arm and not is_attacking and not is_special_attacking:
			right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, 0.0, delta * 5.0)
			if right_elbow:
				right_elbow.rotation.x = lerp(right_elbow.rotation.x, 0.0, delta * 5.0)

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
# WEAPON ATTACK ANIMATIONS
# ============================================================================

## Animate knife combo attacks
func _animate_knife_attack(progress: float, right_arm: Node3D, right_elbow: Node3D) -> void:
	match current_combo_animation:
		0:  # Right-to-left slash
			var start_z = -1.2
			var end_z = 0.6
			var horizontal_angle = lerp(start_z, end_z, progress)
			right_arm.rotation.z = horizontal_angle
			var forward_angle = -sin(progress * PI) * 0.8
			right_arm.rotation.x = forward_angle
			if right_elbow:
				right_elbow.rotation.x = -sin(progress * PI) * 0.6

		1:  # Left-to-right slash
			var start_z = 0.6
			var end_z = -1.2
			var horizontal_angle = lerp(start_z, end_z, progress)
			right_arm.rotation.z = horizontal_angle
			var forward_angle = -sin(progress * PI) * 0.8
			right_arm.rotation.x = forward_angle
			if right_elbow:
				right_elbow.rotation.x = -sin(progress * PI) * 0.6

		2:  # Forward jab (finisher)
			var jab_angle = -sin(progress * PI) * 1.8
			right_arm.rotation.x = jab_angle
			right_arm.rotation.z = -0.3
			if right_elbow:
				right_elbow.rotation.x = -sin(progress * PI) * 0.9

## Check for enemy hits during axe spin attack
## Hits enemies and environmental objects multiple times with a cooldown
func _check_spin_hits() -> void:
	if not is_local_player:
		return

	var spin_radius = 3.5  # Attack radius
	var hit_cooldown = 0.25  # Time between hits - limits to ~4 hits per spin (0.8s duration)
	var spin_damage = lunge_damage * 0.4  # Reduced damage for wood harvesting balance
	var current_time = Time.get_ticks_msec() / 1000.0

	# Get weapon data for tool type check
	var weapon_data = null
	if equipment:
		weapon_data = equipment.get_equipped_weapon()
	if not weapon_data:
		weapon_data = ItemDatabase.get_item("fists")
	var tool_type: String = weapon_data.tool_type if weapon_data and "tool_type" in weapon_data else ""

	# Check enemies (using cached list)
	var enemies = EnemyAI._get_cached_enemies(get_tree())
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var distance = enemy.global_position.distance_to(global_position)
		if distance <= spin_radius:
			var hit_direction = (enemy.global_position - global_position).normalized()
			var enemy_id = enemy.get_instance_id()
			var enemy_network_id = enemy.network_id if "network_id" in enemy else 0

			var last_hit_time = spin_hit_times.get(enemy_id, 0.0)
			if current_time - last_hit_time >= hit_cooldown:
				spin_hit_times[enemy_id] = current_time
				if enemy_network_id > 0:
					print("[Player] SPIN HIT enemy %s at distance %.1fm!" % [enemy.name, distance])
					_send_enemy_damage_request(enemy_network_id, spin_damage, lunge_knockback, hit_direction)
					SoundManager.play_sound_varied("sword_swing", global_position)

	# Check environmental objects using sphere query
	var space_state = get_world_3d().direct_space_state
	var shape = SphereShape3D.new()
	shape.radius = spin_radius
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 1, 0))
	query.collision_mask = 1  # World layer

	var results = space_state.intersect_shape(query, 32)
	for result in results:
		var hit_object = result.collider
		if not is_instance_valid(hit_object):
			continue

		# Check if it's an environmental object
		if hit_object.has_method("get_object_type"):
			var obj_id = hit_object.get_instance_id()
			var last_hit_time = spin_hit_times.get(obj_id, 0.0)
			if current_time - last_hit_time < hit_cooldown:
				continue

			# Check tool requirement
			if hit_object.has_method("can_be_damaged_by"):
				if not hit_object.can_be_damaged_by(tool_type):
					continue  # Wrong tool, skip

			spin_hit_times[obj_id] = current_time
			var object_type: String = hit_object.get_object_type()

			# Check if dynamic object (fallen log, split log)
			var hit_node := hit_object as Node3D
			var object_name: String = hit_node.name if hit_node else ""
			var is_dynamic := object_name.begins_with("FallenLog_") or object_name.begins_with("SplitLog_")

			if is_dynamic:
				print("[Player] SPIN HIT dynamic %s!" % object_name)
				_send_dynamic_damage_request(object_name, spin_damage, hit_node.global_position)
			elif hit_object.has_method("get_object_id"):
				var object_id: int = hit_object.get_object_id()
				var chunk_pos: Vector2i = hit_object.chunk_position if "chunk_position" in hit_object else Vector2i.ZERO
				print("[Player] SPIN HIT %s (ID: %d)!" % [object_type, object_id])
				_send_damage_request(chunk_pos, object_id, spin_damage, hit_node.global_position)

			SoundManager.play_sound_varied("wood_hit", global_position)

## Animate axe combo attacks - SIMPLE wide sweeping arcs
## The ARM does the work - axe head sweeps IN FRONT of the player
## Axe aligns with arm (0 degrees) during swings
func _animate_axe_attack(progress: float, right_arm: Node3D, left_arm: Node3D, right_elbow: Node3D, left_elbow: Node3D) -> void:
	# Reset wrist pivot
	if weapon_wrist_pivot:
		weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

	# Align axe with arm during swings, head pointing AWAY from player
	if equipped_weapon_visual:
		equipped_weapon_visual.rotation_degrees.x = 180.0

	match current_combo_animation:
		0:  # SWEEP RIGHT TO LEFT - two-handed, chest height
			var windup_end = 0.25

			if progress < windup_end:
				var t = progress / windup_end
				var t_ease = t * t * (3.0 - 2.0 * t)

				# Lower chest height
				right_arm.rotation.x = lerp(0.0, -0.9, t_ease)   # Lower
				right_arm.rotation.z = lerp(0.0, -1.6, t_ease)
				if right_elbow:
					right_elbow.rotation.x = lerp(0.0, -0.7, t_ease)

				if left_arm:
					left_arm.rotation.x = lerp(0.0, -1.0, t_ease)
					left_arm.rotation.z = lerp(0.0, -0.8, t_ease)
				if left_elbow:
					left_elbow.rotation.x = lerp(0.0, -0.9, t_ease)

			else:
				var t = (progress - windup_end) / (1.0 - windup_end)
				var t_power = t * t

				right_arm.rotation.x = lerp(-0.9, -1.0, t_power)
				right_arm.rotation.z = lerp(-1.6, 1.3, t_power)
				if right_elbow:
					right_elbow.rotation.x = lerp(-0.7, -0.5, t_power)

				if left_arm:
					left_arm.rotation.x = lerp(-1.0, -0.9, t_power)
					left_arm.rotation.z = lerp(-0.8, 0.6, t_power)
				if left_elbow:
					left_elbow.rotation.x = lerp(-0.9, -0.7, t_power)

		1:  # SWEEP LEFT TO RIGHT - two-handed, chest height
			var windup_end = 0.25

			if progress < windup_end:
				var t = progress / windup_end
				var t_ease = t * t * (3.0 - 2.0 * t)

				right_arm.rotation.x = lerp(0.0, -0.9, t_ease)   # Lower
				right_arm.rotation.z = lerp(0.0, 1.0, t_ease)
				if right_elbow:
					right_elbow.rotation.x = lerp(0.0, -0.7, t_ease)

				if left_arm:
					left_arm.rotation.x = lerp(0.0, -1.0, t_ease)
					left_arm.rotation.z = lerp(0.0, 1.2, t_ease)
				if left_elbow:
					left_elbow.rotation.x = lerp(0.0, -0.6, t_ease)

			else:
				var t = (progress - windup_end) / (1.0 - windup_end)
				var t_power = t * t

				right_arm.rotation.x = lerp(-0.9, -1.0, t_power)
				right_arm.rotation.z = lerp(1.0, -1.6, t_power)
				if right_elbow:
					right_elbow.rotation.x = lerp(-0.7, -0.5, t_power)

				if left_arm:
					left_arm.rotation.x = lerp(-1.0, -0.9, t_power)
					left_arm.rotation.z = lerp(1.2, -0.8, t_power)
				if left_elbow:
					left_elbow.rotation.x = lerp(-0.6, -0.9, t_power)

		2:  # OVERHEAD SLAM - raise up, slam DOWN
			var windup_end = 0.2

			if progress < windup_end:
				# Raise axe overhead
				var t = progress / windup_end
				var t_ease = t * t * (3.0 - 2.0 * t)

				right_arm.rotation.x = lerp(0.0, -2.0, t_ease)   # Raise up
				right_arm.rotation.z = lerp(0.0, 0.0, t_ease)
				if right_elbow:
					right_elbow.rotation.x = lerp(0.0, -0.5, t_ease)

				if left_arm:
					left_arm.rotation.x = lerp(0.0, -1.8, t_ease)
					left_arm.rotation.z = lerp(0.0, 0.0, t_ease)
				if left_elbow:
					left_elbow.rotation.x = lerp(0.0, -0.5, t_ease)

			else:
				# SLAM DOWN
				var t = (progress - windup_end) / (1.0 - windup_end)
				var t_slam = t * t * t

				# Slam from overhead down
				right_arm.rotation.x = lerp(-2.0, -0.4, t_slam)   # Down
				right_arm.rotation.z = lerp(0.0, 0.0, t_slam)
				if right_elbow:
					right_elbow.rotation.x = lerp(-0.5, -0.8, t_slam)

				if left_arm:
					left_arm.rotation.x = lerp(-1.8, -0.3, t_slam)
					left_arm.rotation.z = lerp(0.0, 0.0, t_slam)
				if left_elbow:
					left_elbow.rotation.x = lerp(-0.5, -0.8, t_slam)

		_:  # Fallback
			right_arm.rotation.x = -0.9
			right_arm.rotation.z = lerp(-1.5, 1.3, progress)

# ============================================================================
# STAMINA & HEALTH SYSTEM
# ============================================================================

## Update stamina regeneration
func _update_stamina(delta: float) -> void:
	var max_stam = player_food.get_max_stamina() if player_food else PC.BASE_STAMINA

	# God mode: unlimited stamina, never exhausted
	if god_mode:
		stamina = max_stam
		is_exhausted = false
		return

	# Regenerate stamina after delay
	stamina_regen_timer += delta

	if stamina_regen_timer >= PC.STAMINA_REGEN_DELAY:
		stamina = min(stamina + PC.STAMINA_REGEN_RATE * delta, max_stam)

	# Check for exhaustion recovery (need 10% stamina to recover)
	if is_exhausted and stamina >= max_stam * PC.EXHAUSTED_RECOVERY_THRESHOLD:
		is_exhausted = false
		print("[Player] Recovered from exhaustion")

## Consume stamina (returns true if enough stamina available)
func consume_stamina(amount: float) -> bool:
	# God mode: unlimited stamina
	if god_mode:
		return true
	if stamina >= amount:
		stamina -= amount
		stamina_regen_timer = 0.0  # Reset regen delay
		# Check if we just became exhausted (stamina depleted)
		if stamina <= 0:
			stamina = 0
			if not is_exhausted:
				is_exhausted = true
				print("[Player] Exhausted! Must recover stamina before sprinting/attacking")
		return true
	else:
		# Failed to consume - become exhausted if stamina is very low
		if stamina < amount and not is_exhausted:
			is_exhausted = true
			print("[Player] Exhausted! Not enough stamina")
		return false

## Update brain power regeneration
func _update_brain_power(delta: float) -> void:
	var max_bp = player_food.get_max_brain_power() if player_food else PC.BASE_BRAIN_POWER

	# God mode: unlimited brain power
	if god_mode:
		brain_power = max_bp
		return

	# Regenerate brain power after delay
	brain_power_regen_timer += delta

	if brain_power_regen_timer >= PC.BRAIN_POWER_REGEN_DELAY:
		brain_power = min(brain_power + PC.BRAIN_POWER_REGEN_RATE * delta, max_bp)

## Consume brain power (returns true if enough brain power available)
func consume_brain_power(amount: float) -> bool:
	# God mode: unlimited brain power
	if god_mode:
		return true
	if brain_power >= amount:
		brain_power -= amount
		brain_power_regen_timer = 0.0  # Reset regen delay
		return true
	return false

# =============================================================================
# GOLD CURRENCY
# =============================================================================

## Add gold to player
func add_gold(amount: int) -> void:
	gold += amount
	print("[Player] Gained %d gold, total: %d" % [amount, gold])

## Spend gold (returns true if enough gold available)
func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		print("[Player] Spent %d gold, remaining: %d" % [amount, gold])
		return true
	print("[Player] Not enough gold! Have %d, need %d" % [gold, amount])
	return false

## Check if player can afford something
func can_afford(amount: int) -> bool:
	return gold >= amount

## Get current gold amount
func get_gold() -> int:
	return gold

## Take damage (with blocking/parry support and armor reduction)
## damage_type: WeaponData.DamageType enum (-1 = physical/untyped)
func take_damage(damage: float, attacker_id: int = -1, knockback_dir: Vector3 = Vector3.ZERO, damage_type: int = -1) -> void:
	if is_dead:
		return

	# God mode: ignore damage but still play hit effects for debugging
	if god_mode:
		print("[Player] God mode - ignoring %d damage" % damage)
		_spawn_hit_effect()
		return

	var final_damage = damage
	var was_parried = false

	# Apply armor damage reduction FIRST (before blocking)
	# Armor is flat subtraction based on damage type, minimum 1 damage
	if equipment:
		var armor = equipment.get_total_armor(damage_type)
		if armor > 0:
			var reduced_damage = max(1.0, final_damage - armor)
			print("[Player] Armor (%.1f vs type %d) reduced damage: %.1f -> %.1f" % [armor, damage_type, final_damage, reduced_damage])
			final_damage = reduced_damage

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

			# Spawn parry effect
			_spawn_parry_effect()

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

	# Spawn hit effect if damage was dealt
	if final_damage > 0:
		_spawn_hit_effect()

	# Apply knockback (if not parried)
	if not was_parried and knockback_dir.length() > 0:
		var knockback_mult = 2.0  # Base knockback (reduced from 5.0)
		if is_blocking:
			knockback_mult = 0.5  # Blocking greatly reduces knockback
		velocity += knockback_dir * knockback_mult

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

## Spawn hit particle effect at player position
func _spawn_hit_effect() -> void:
	var pos = global_position + Vector3(0, 1.0, 0)  # Chest height
	var effect = HitEffectScene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = pos  # Set position after adding to tree

	# Play player hurt sound
	SoundManager.play_sound_varied("player_hurt", pos)

	# Sync hit effect to other clients
	if is_local_player:
		NetworkManager.rpc_spawn_hit_effect.rpc_id(1, [pos.x, pos.y, pos.z])

## Spawn parry particle effect at player position
func _spawn_parry_effect() -> void:
	var pos = global_position + Vector3(0, 1.2, 0)  # Shield height
	var effect = ParryEffectScene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = pos  # Set position after adding to tree

	# Play parry sound
	SoundManager.play_sound("parry", pos)

	# Sync parry effect to other clients
	if is_local_player:
		NetworkManager.rpc_spawn_parry_effect.rpc_id(1, [pos.x, pos.y, pos.z])

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

	# Play death sound (using player_hurt as placeholder)
	SoundManager.play_sound("player_hurt", global_position)

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
	# Use base stats on respawn (food buffs are cleared)
	health = PC.BASE_HEALTH
	stamina = PC.BASE_STAMINA
	brain_power = PC.BASE_BRAIN_POWER
	global_position = spawn_position
	velocity = Vector3.ZERO

	# Clear food buffs on death
	if player_food:
		player_food.clear_all_foods()

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
# FOOD SYSTEM HELPERS
# ============================================================================

## Scale health to preserve percentage when max health changes (used when food expires)
## Uses the tracked previous max health
func scale_health_to_new_max(new_max_health: float) -> void:
	# Get the old max health from before the change
	var old_max = _previous_max_health if _previous_max_health > 0 else PC.BASE_HEALTH

	if old_max > 0 and old_max != new_max_health:
		var health_percent = health / old_max
		health = health_percent * new_max_health
		# Ensure we don't exceed new max
		health = min(health, new_max_health)
		print("[Player] Health scaled (expire): %.1f%% of %.0f -> %.0f/%.0f" % [health_percent * 100, old_max, health, new_max_health])

	# Update the tracked max for next time
	_previous_max_health = new_max_health

## Scale health with explicit old max (used when eating food)
## Example: 12/25 HP (48%) -> eat food -> new max 50 -> 24/50 HP (still 48%)
func scale_health_with_old_max(old_max_health: float, new_max_health: float) -> void:
	if old_max_health > 0 and old_max_health != new_max_health:
		var health_percent = health / old_max_health
		health = health_percent * new_max_health
		# Ensure we don't exceed new max
		health = min(health, new_max_health)
		print("[Player] Health scaled (eat): %.1f%% of %.0f -> %.0f/%.0f" % [health_percent * 100, old_max_health, health, new_max_health])

	# Update the tracked max for next time
	_previous_max_health = new_max_health

## Clamp current stats to max values (called when food buffs expire)
func clamp_stats_to_max() -> void:
	if player_food:
		health = min(health, player_food.get_max_health())
		stamina = min(stamina, player_food.get_max_stamina())
		brain_power = min(brain_power, player_food.get_max_brain_power())
	else:
		health = min(health, PC.BASE_HEALTH)
		stamina = min(stamina, PC.BASE_STAMINA)
		brain_power = min(brain_power, PC.BASE_BRAIN_POWER)

## Eat a food item (consume from inventory and apply buff)
func eat_food(food_id: String) -> bool:
	if not player_food:
		return false

	# Check if we have the food item
	if not inventory.has_item(food_id, 1):
		print("[Player] Don't have %s to eat" % food_id)
		return false

	# Try to eat it
	if player_food.eat_food(food_id):
		inventory.remove_item(food_id, 1)
		return true

	return false

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
		Equipment.EquipmentSlot.HEAD:
			_update_head_armor_visual()
		Equipment.EquipmentSlot.CHEST:
			_update_chest_armor_visual()
		Equipment.EquipmentSlot.LEGS:
			_update_legs_armor_visual()
		Equipment.EquipmentSlot.CAPE:
			_update_cape_visual()
		Equipment.EquipmentSlot.ACCESSORY:
			_update_accessory_visual()

## Update the main hand weapon visual
func _update_weapon_visual() -> void:
	# Remove existing weapon visual and wrist pivot
	if equipped_weapon_visual:
		equipped_weapon_visual.queue_free()
		equipped_weapon_visual = null
	if weapon_wrist_pivot:
		weapon_wrist_pivot.queue_free()
		weapon_wrist_pivot = null

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

	# Create a wrist pivot node for natural weapon rotation during swings
	weapon_wrist_pivot = Node3D.new()
	weapon_wrist_pivot.name = "WristPivot"

	# Find right hand bone attachment point
	var right_hand_attach = _find_hand_attach_point("RightHand")
	if right_hand_attach:
		# Attach wrist pivot to hand, then weapon to pivot
		right_hand_attach.add_child(weapon_wrist_pivot)
		weapon_wrist_pivot.add_child(equipped_weapon_visual)

		# Rotate weapon 90 degrees forward (X-axis) so it points forward instead of down
		equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)

		# Apply mount point offset - MUST transform by rotation first!
		# The mount point is defined in unrotated weapon space, but we need
		# to offset in the rotated space so the grip ends up at the pivot
		if equipped_weapon_visual.has_node("MountPoint"):
			var mount_point = equipped_weapon_visual.get_node("MountPoint")
			# Transform mount point position by weapon's rotation basis
			var rotated_offset = equipped_weapon_visual.basis * mount_point.position
			equipped_weapon_visual.position = -rotated_offset

		# Setup weapon hitbox for collision-based combat (Valheim-style)
		_setup_weapon_hitbox()

		print("[Player] Equipped weapon visual: %s (with wrist pivot)" % weapon_id)
	else:
		# Fallback: attach to body container
		if body_container:
			body_container.add_child(weapon_wrist_pivot)
			weapon_wrist_pivot.add_child(equipped_weapon_visual)
			weapon_wrist_pivot.position = Vector3(0.3, 1.2, 0)  # Approximate hand position
			equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
			# Setup weapon hitbox for collision-based combat (Valheim-style)
			_setup_weapon_hitbox()
			print("[Player] Equipped weapon visual (fallback): %s" % weapon_id)
		else:
			weapon_wrist_pivot.queue_free()
			weapon_wrist_pivot = null
			equipped_weapon_visual.queue_free()
			equipped_weapon_visual = null
			push_warning("[Player] No attachment point for weapon")

## Setup weapon hitbox for collision-based combat (Valheim-style)
func _setup_weapon_hitbox() -> void:
	# Clear any previous hitbox reference
	weapon_hitbox = null

	if not equipped_weapon_visual:
		print("[Player] _setup_weapon_hitbox: No equipped_weapon_visual!")
		return

	print("[Player] _setup_weapon_hitbox: Looking for Hitbox in %s" % equipped_weapon_visual.name)
	print("[Player] Children: %s" % str(equipped_weapon_visual.get_children()))

	# Find the Hitbox Area3D in the weapon scene
	if equipped_weapon_visual.has_node("Hitbox"):
		weapon_hitbox = equipped_weapon_visual.get_node("Hitbox")
		print("[Player] Found Hitbox: %s" % weapon_hitbox)

		# Connect body_entered signal for collision detection
		if not weapon_hitbox.body_entered.is_connected(_on_weapon_hitbox_body_entered):
			weapon_hitbox.body_entered.connect(_on_weapon_hitbox_body_entered)

		# Ensure hitbox starts disabled
		weapon_hitbox.monitoring = false
		var collision_shape = weapon_hitbox.get_node_or_null("CollisionShape3D")
		if collision_shape:
			collision_shape.disabled = true
			print("[Player] CollisionShape3D found, shape: %s" % collision_shape.shape)
		else:
			print("[Player] WARNING: No CollisionShape3D in Hitbox!")

		# DEBUG: Add visual mesh for hitbox (always visible)
		_add_weapon_hitbox_debug_visual(weapon_hitbox, collision_shape)

		print("[Player] Weapon hitbox connected: %s" % equipped_weapon_visual.name)
	else:
		print("[Player] Weapon has no Hitbox node: %s" % equipped_weapon_visual.name)
		print("[Player] Available nodes: %s" % str(equipped_weapon_visual.get_children()))

## Called when weapon hitbox collides with a body during attack
func _on_weapon_hitbox_body_entered(body: Node3D) -> void:
	print("[Hitbox] body_entered signal! body=%s, hitbox_active=%s, is_attacking=%s" % [body.name, hitbox_active, is_attacking])

	if not is_local_player or not hitbox_active:
		print("[Hitbox] Skipped - local=%s, active=%s" % [is_local_player, hitbox_active])
		return

	# Only process if we're attacking
	if not is_attacking and not is_special_attacking:
		print("[Hitbox] Skipped - not attacking")
		return

	# Check if it's an enemy
	if body.has_method("take_damage") and body.collision_layer & 4:
		var enemy_id = body.get_instance_id()

		# Prevent hitting same enemy twice per swing
		if enemy_id in hitbox_hit_enemies:
			print("[Hitbox] Skipped - already hit this enemy")
			return

		hitbox_hit_enemies.append(enemy_id)
		print("[Hitbox] HIT ENEMY: %s" % body.name)

		# Get damage from combat module
		if combat:
			combat.process_hitbox_hit(body)
	else:
		print("[Hitbox] Not an enemy - has_take_damage=%s, layer=%d" % [body.has_method("take_damage"), body.collision_layer])

## DEBUG: Add visual representation of weapon hitbox (always visible)
func _add_weapon_hitbox_debug_visual(hitbox: Area3D, collision_shape: CollisionShape3D) -> void:
	if not hitbox or not collision_shape:
		return

	# Remove existing debug mesh if any
	var existing = collision_shape.get_node_or_null("DebugMesh")
	if existing:
		existing.queue_free()

	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "DebugMesh"

	# Create mesh matching the collision shape
	if collision_shape.shape:
		var shape = collision_shape.shape
		print("[DEBUG] Weapon hitbox shape type: %s" % shape.get_class())
		if shape is CapsuleShape3D:
			var capsule = CapsuleMesh.new()
			capsule.radius = shape.radius
			capsule.height = shape.height
			debug_mesh.mesh = capsule
		elif shape is BoxShape3D:
			var box = BoxMesh.new()
			box.size = shape.size
			debug_mesh.mesh = box
		elif shape is SphereShape3D:
			var sphere = SphereMesh.new()
			sphere.radius = shape.radius
			debug_mesh.mesh = sphere
		else:
			var sphere = SphereMesh.new()
			sphere.radius = 0.3
			debug_mesh.mesh = sphere
	else:
		var sphere = SphereMesh.new()
		sphere.radius = 0.3
		debug_mesh.mesh = sphere

	# Create green translucent material - ALWAYS VISIBLE
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.0, 0.5)  # Green
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true  # Always visible through objects
	debug_mesh.material_override = mat
	debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Add to collision_shape so it inherits the shape's transform/rotation
	collision_shape.add_child(debug_mesh)
	debug_mesh.visible = DebugSettings.show_hitboxes  # Respect current toggle state
	print("[DEBUG] Weapon hitbox debug mesh added (parent: %s)" % collision_shape.name)

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

	# Find HandAttach node in the arm (it's under Elbow)
	if arm.has_node("Elbow/HandAttach"):
		return arm.get_node("Elbow/HandAttach")
	# Fallback: check directly under arm
	if arm.has_node("HandAttach"):
		return arm.get_node("HandAttach")

	return null

# ============================================================================
# ARMOR VISUALS
# ============================================================================

## Update head armor visual (changes head/neck color and adds hood)
func _update_head_armor_visual() -> void:
	# Remove existing hood
	if hood_visual:
		hood_visual.queue_free()
		hood_visual = null

	if not body_container:
		return

	var armor_data = equipment.get_equipped_item_data(Equipment.EquipmentSlot.HEAD)
	var color = DEFAULT_SKIN_COLOR

	if armor_data is ArmorData:
		color = armor_data.primary_color
		print("[Player] Equipped head armor: %s (color: %s)" % [armor_data.item_id, color])

		# Create hood visual
		_create_hood_visual(armor_data.primary_color, armor_data.secondary_color)
	else:
		print("[Player] Unequipped head armor - reverting to skin color")

	# Apply color to head and neck (skin shows through without hood, colored with hood)
	_set_mesh_color(body_container, "Head", color)
	_set_mesh_color(body_container, "Neck", color)

## Create a hood mesh over the player's head
func _create_hood_visual(primary_color: Color, secondary_color: Color) -> void:
	if not body_container:
		return

	hood_visual = Node3D.new()
	hood_visual.name = "Hood"

	# Find the head node to attach hood to
	var head = body_container.get_node_or_null("Head")
	if head:
		head.add_child(hood_visual)
	else:
		body_container.add_child(hood_visual)
		hood_visual.position = Vector3(0, 1.5, 0)

	# Create hood mesh - a half-sphere/dome shape over the head
	var hood_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.18
	hood_mesh.mesh = sphere

	# Create material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = primary_color
	hood_mesh.material_override = mat

	# Position hood slightly above and behind head center
	hood_mesh.position = Vector3(0, 0.02, -0.02)
	hood_mesh.scale = Vector3(1.1, 0.9, 1.0)  # Slightly wider, flatter
	hood_visual.add_child(hood_mesh)

	# Add hood back/drape piece
	var hood_back = MeshInstance3D.new()
	var back_box = BoxMesh.new()
	back_box.size = Vector3(0.18, 0.15, 0.08)
	hood_back.mesh = back_box

	var back_mat = StandardMaterial3D.new()
	back_mat.albedo_color = secondary_color
	hood_back.material_override = back_mat

	hood_back.position = Vector3(0, -0.05, -0.08)
	hood_visual.add_child(hood_back)

	print("[Player] Created hood visual")

## Update chest armor visual (changes torso color)
func _update_chest_armor_visual() -> void:
	if not body_container:
		return

	var armor_data = equipment.get_equipped_item_data(Equipment.EquipmentSlot.CHEST)
	var color = DEFAULT_CLOTHES_COLOR

	if armor_data is ArmorData:
		color = armor_data.primary_color
		print("[Player] Equipped chest armor: %s (color: %s)" % [armor_data.item_id, color])
	else:
		print("[Player] Unequipped chest armor - reverting to default clothes color")

	# Apply color to torso
	_set_mesh_color(body_container, "Torso", color)
	# Also color the child mesh inside torso if present
	var torso = body_container.get_node_or_null("Torso")
	if torso:
		_set_mesh_color(torso, "MeshInstance3D", color)

	# Apply secondary color to arms if armor equipped
	if armor_data is ArmorData:
		_set_arm_colors(armor_data.secondary_color)
	else:
		_set_arm_colors(DEFAULT_SKIN_COLOR)

## Update legs armor visual (changes legs and hips color)
func _update_legs_armor_visual() -> void:
	if not body_container:
		return

	var armor_data = equipment.get_equipped_item_data(Equipment.EquipmentSlot.LEGS)
	var color = DEFAULT_PANTS_COLOR

	if armor_data is ArmorData:
		color = armor_data.primary_color
		print("[Player] Equipped leg armor: %s (color: %s)" % [armor_data.item_id, color])
	else:
		print("[Player] Unequipped leg armor - reverting to default pants color")

	# Apply color to hips and legs
	_set_mesh_color(body_container, "Hips", color)
	_set_leg_colors(color)

## Update cape visual (creates/removes cape mesh)
func _update_cape_visual() -> void:
	# Remove existing cape
	if cape_visual:
		cape_visual.queue_free()
		cape_visual = null

	if not body_container:
		return

	var armor_data = equipment.get_equipped_item_data(Equipment.EquipmentSlot.CAPE)
	if not armor_data is ArmorData:
		print("[Player] Unequipped cape")
		return

	print("[Player] Equipped cape: %s" % armor_data.item_id)

	# Create cape visual (simple flowing shape attached to shoulders)
	cape_visual = Node3D.new()
	cape_visual.name = "Cape"
	body_container.add_child(cape_visual)

	# Create cape mesh - a simple elongated shape hanging from the back
	var cape_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.25, 0.6, 0.05)  # Wide, tall, thin
	cape_mesh.mesh = box

	# Create material with armor colors
	var mat = StandardMaterial3D.new()
	mat.albedo_color = armor_data.primary_color
	cape_mesh.material_override = mat

	cape_mesh.position = Vector3(0, -0.3, -0.08)  # Behind and below attachment
	cape_visual.add_child(cape_mesh)

	# Position cape at upper back (between shoulders)
	cape_visual.position = Vector3(0, 1.35, -0.05)

## Update accessory visual (Cyclops Eye glow effect)
func _update_accessory_visual() -> void:
	# Remove existing light
	if cyclops_light:
		cyclops_light.queue_free()
		cyclops_light = null

	# Remove any existing body glow
	_remove_cyclops_glow()

	if not body_container:
		return

	var armor_data = equipment.get_equipped_item_data(Equipment.EquipmentSlot.ACCESSORY)
	if not armor_data is ArmorData:
		print("[Player] Unequipped accessory")
		return

	print("[Player] Equipped accessory: %s" % armor_data.item_id)

	# Check for Cyclops Eye effect
	if armor_data.set_bonus == ArmorData.SetBonus.CYCLOPS_LIGHT:
		_apply_cyclops_glow()

## Apply the Cyclops Eye glow effect - light aura and body emission
func _apply_cyclops_glow() -> void:
	if not body_container:
		return

	# Create OmniLight3D for light aura
	cyclops_light = OmniLight3D.new()
	cyclops_light.name = "CyclopsLight"
	cyclops_light.light_color = Color(1.0, 0.85, 0.4)  # Warm golden glow
	cyclops_light.light_energy = 3.0
	cyclops_light.omni_range = 15.0
	cyclops_light.omni_attenuation = 1.5
	cyclops_light.position = Vector3(0, 1.0, 0)  # At player center
	body_container.add_child(cyclops_light)

	# Apply emission glow to body parts
	var glow_color = Color(1.0, 0.9, 0.5)  # Warm yellow glow
	var emission_strength = 1.5

	# Apply to all visible body meshes
	var body_parts = ["Head", "Neck", "Torso", "LeftUpperArm", "LeftLowerArm", "LeftHand",
					  "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg",
					  "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]

	for part_name in body_parts:
		var mesh = body_container.get_node_or_null(part_name)
		if mesh and mesh is MeshInstance3D:
			var mat = mesh.material_override
			if mat and mat is StandardMaterial3D:
				mat.emission_enabled = true
				mat.emission = glow_color
				mat.emission_energy_multiplier = emission_strength

## Remove the Cyclops Eye glow effect
func _remove_cyclops_glow() -> void:
	if not body_container:
		return

	# Remove emission from body parts
	var body_parts = ["Head", "Neck", "Torso", "LeftUpperArm", "LeftLowerArm", "LeftHand",
					  "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg",
					  "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]

	for part_name in body_parts:
		var mesh = body_container.get_node_or_null(part_name)
		if mesh and mesh is MeshInstance3D:
			var mat = mesh.material_override
			if mat and mat is StandardMaterial3D:
				mat.emission_enabled = false

## Initialize all armor visuals to default (unarmored) state
func _initialize_armor_visuals() -> void:
	if not body_container:
		return

	print("[Player] Initializing armor visuals to default skin colors")

	# Head - skin color
	_set_mesh_color(body_container, "Head", DEFAULT_SKIN_COLOR)
	_set_mesh_color(body_container, "Neck", DEFAULT_SKIN_COLOR)

	# Torso - light tan (minimal clothing)
	_set_mesh_color(body_container, "Torso", DEFAULT_CLOTHES_COLOR)
	var torso = body_container.get_node_or_null("Torso")
	if torso:
		_set_mesh_color(torso, "MeshInstance3D", DEFAULT_CLOTHES_COLOR)

	# Arms - skin color
	_set_arm_colors(DEFAULT_SKIN_COLOR)

	# Hips and legs - slightly darker tan
	_set_mesh_color(body_container, "Hips", DEFAULT_PANTS_COLOR)
	_set_leg_colors(DEFAULT_PANTS_COLOR)

# ============================================================================
# ARMOR VISUAL HELPERS
# ============================================================================

## Set the color of a named MeshInstance3D node
func _set_mesh_color(parent: Node3D, node_name: String, color: Color) -> void:
	var mesh_node = parent.get_node_or_null(node_name)
	if mesh_node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mesh_node.material_override = mat

## Set colors for arm meshes
func _set_arm_colors(color: Color) -> void:
	for arm_name in ["LeftArm", "RightArm"]:
		var arm = body_container.get_node_or_null(arm_name)
		if not arm:
			continue

		# Color the upper arm mesh (first MeshInstance3D child)
		for child in arm.get_children():
			if child is MeshInstance3D:
				var mat = StandardMaterial3D.new()
				mat.albedo_color = color
				child.material_override = mat
				break

		# Color forearm (Elbow node and its mesh)
		var elbow = arm.get_node_or_null("Elbow")
		if elbow:
			for child in elbow.get_children():
				if child is MeshInstance3D:
					var mat = StandardMaterial3D.new()
					mat.albedo_color = color
					child.material_override = mat
					break

			# Color hand
			var hand = elbow.get_node_or_null("HandAttach")
			if hand:
				for child in hand.get_children():
					if child is MeshInstance3D:
						var mat = StandardMaterial3D.new()
						mat.albedo_color = color
						child.material_override = mat
						break

## Set colors for leg meshes
func _set_leg_colors(color: Color) -> void:
	for leg_name in ["LeftLeg", "RightLeg"]:
		var leg = body_container.get_node_or_null(leg_name)
		if not leg:
			continue

		# Color upper leg mesh
		for child in leg.get_children():
			if child is MeshInstance3D:
				var mat = StandardMaterial3D.new()
				mat.albedo_color = color
				child.material_override = mat
				break

		# Color knee/lower leg
		var knee = leg.get_node_or_null("Knee")
		if knee:
			for child in knee.get_children():
				if child is MeshInstance3D:
					var mat = StandardMaterial3D.new()
					mat.albedo_color = color
					child.material_override = mat
					break

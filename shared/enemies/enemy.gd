extends "res://shared/animated_character.gd"
class_name Enemy

## Enemy - Gahnome enemy with Grayling-inspired AI
## Stalks from distance, circles, throws rocks, then charges in for melee
##
## SERVER-AUTHORITATIVE SYNC:
## - Server runs full AI and physics, broadcasts state at 10Hz
## - Clients only interpolate position/rotation and play animations
## - Health and death are server-authoritative

signal died(enemy: Enemy)

# AI States
enum AIState {
	IDLE,           # No target, wandering or standing
	STALKING,       # Watching player from distance, deciding what to do
	CIRCLING,       # Strafing around the player, looking for opening
	APPROACHING,    # Moving closer but cautiously (not a direct charge)
	CHARGING,       # Committed rush attack
	ATTACKING,      # Melee attack in progress
	THROWING,       # Rock throw attack
	RETREATING,     # Backing away after attack or when hurt
}

# Network sync - client interpolation
var is_remote: bool = false  # True on clients (visual only)
var server_position: Vector3 = Vector3.ZERO
var server_rotation_y: float = 0.0
var interpolation_speed: float = 15.0  # How fast to lerp to server state

# Enemy stats
@export var enemy_name: String = "Gahnome"
@export var max_health: float = 50.0
@export var move_speed: float = 3.0
@export var charge_speed: float = 5.5  # Faster when charging
@export var strafe_speed: float = 2.0  # Slower when circling
@export var attack_range: float = 1.2  # Slightly longer melee range
@export var attack_cooldown_time: float = 1.2  # Time between melee attacks
@export var detection_range: float = 18.0  # Can see further
@export var preferred_distance: float = 6.0  # Likes to stay this far when stalking
@export var throw_range: float = 12.0  # Max range for rock throw
@export var throw_min_range: float = 4.0  # Min range for rock throw (too close = melee)
@export var throw_cooldown_time: float = 3.5  # Time between throws
@export var rock_damage: float = 8.0  # Damage from thrown rock
@export var rock_speed: float = 15.0  # Projectile speed
@export var loot_table: Dictionary = {"wood": 2, "resin": 1}
@export var weapon_id: String = "fists"

# Weapon data (loaded from ItemDatabase)
var weapon_data = null  # WeaponData

# AI State
var ai_state: AIState = AIState.IDLE
var state_timer: float = 0.0  # Time spent in current state
var decision_timer: float = 0.0  # Timer for making decisions

# Enemy state
var health: float = max_health
var is_dead: bool = false
var target_player: CharacterBody3D = null
var attack_cooldown: float = 0.0
var throw_cooldown: float = 0.0

# Circling behavior
var circle_direction: int = 1  # 1 = clockwise, -1 = counter-clockwise
var circle_timer: float = 0.0  # How long we've been circling

# Charge behavior
var charge_target_pos: Vector3 = Vector3.ZERO  # Where we're charging to
var has_committed_charge: bool = false  # Once charging, commit to it

# Wandering behavior (when no target)
var wander_direction: Vector3 = Vector3.ZERO  # Current wander direction
var wander_timer: float = 0.0  # Time until we change wander direction
var wander_pause_timer: float = 0.0  # Time we pause between wanders
var is_wander_paused: bool = true  # Start paused

# Aggression and personality (randomized per enemy for variety)
var aggression: float = 0.5  # 0-1, affects how likely to charge vs throw
var patience: float = 0.5  # 0-1, affects how long they stalk before acting

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

# Projectiles
const ThrownRock = preload("res://shared/enemies/thrown_rock.gd")

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Terrain reference for collision checking (server-side)
var terrain_world: Node = null
var last_valid_position: Vector3 = Vector3.ZERO  # Last known position with collision
var spawn_y: float = 0.0  # Y position at spawn time (fallback reference)
var fall_timer: float = 0.0  # Track how long we've been falling

func _ready() -> void:
	# Set collision layers
	collision_layer = 4  # Enemies layer (bit 2)
	collision_mask = 1 | 2  # World (1) and Players (2)

	# Load weapon data
	weapon_data = ItemDatabase.get_item(weapon_id)
	if not weapon_data:
		push_warning("[Enemy] Unknown weapon: %s, defaulting to fists" % weapon_id)
		weapon_data = ItemDatabase.get_item("fists")

	# Configure animation base class
	walk_speed = move_speed
	attack_animation_time = 0.3

	# Create visual body
	_setup_body()

	# Randomize personality for variety (each gahnome is slightly different)
	aggression = randf_range(0.3, 0.8)  # How aggressive (prefers charging vs throwing)
	patience = randf_range(0.3, 0.7)  # How long they stalk before acting
	circle_direction = 1 if randf() > 0.5 else -1  # Random initial circle direction

	# Don't create health bar until damaged (performance optimization)
	# It will be created in take_damage() when first hit

	# Find terrain world reference (for collision checking on server)
	_find_terrain_world()

	# Initialize last valid position and spawn reference
	last_valid_position = global_position
	spawn_y = global_position.y

	print("[Enemy] %s ready (Health: %d, Aggro: %.2f, Patience: %.2f)" % [enemy_name, max_health, aggression, patience])

## Find TerrainWorld node in scene (server-side only)
func _find_terrain_world() -> void:
	if not multiplayer.is_server():
		return

	# Look for TerrainWorld in common parent locations
	var current = get_parent()
	while current:
		if current.has_node("TerrainWorld"):
			terrain_world = current.get_node("TerrainWorld")
			return
		current = current.get_parent()

## Check if a position has terrain collision loaded
func _has_terrain_collision(pos: Vector3) -> bool:
	if not terrain_world:
		return true  # Assume valid if no terrain reference
	if not terrain_world.has_method("has_collision_at_position"):
		return true  # Assume valid if method doesn't exist
	return terrain_world.has_collision_at_position(pos)

func _setup_body() -> void:
	# Create body container (similar to player, but smaller)
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI  # Rotate 180° to face forward (mesh is built facing +Z, but look_at uses -Z)
	add_child(body_container)

	# Scale factor for smaller gnome-like creature (2/3 of player size)
	var scale_factor: float = 0.66

	# Materials
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.45, 0.55, 0.35, 1)  # Greenish skin

	var clothes_mat = StandardMaterial3D.new()
	clothes_mat.albedo_color = Color(0.4, 0.25, 0.15, 1)  # Brown clothes

	var hair_mat = StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.7, 0.7, 0.7, 1)  # Gray hair

	# Hips
	var hips = MeshInstance3D.new()
	var hips_mesh = BoxMesh.new()
	hips_mesh.size = Vector3(0.18, 0.15, 0.1) * scale_factor
	hips.mesh = hips_mesh
	hips.material_override = clothes_mat
	hips.position = Vector3(0, 0.58 * scale_factor, 0)
	body_container.add_child(hips)

	# Torso (store reference)
	torso = MeshInstance3D.new()
	var torso_mesh = CapsuleMesh.new()
	torso_mesh.radius = 0.08 * scale_factor
	torso_mesh.height = 0.4 * scale_factor
	torso.mesh = torso_mesh
	torso.material_override = clothes_mat
	torso.position = Vector3(0, 0.75 * scale_factor, 0)
	body_container.add_child(torso)

	# Neck
	var neck = MeshInstance3D.new()
	var neck_mesh = CapsuleMesh.new()
	neck_mesh.radius = 0.03 * scale_factor
	neck_mesh.height = 0.08 * scale_factor
	neck.mesh = neck_mesh
	neck.material_override = skin_mat
	neck.position = Vector3(0, 0.92 * scale_factor, 0)
	body_container.add_child(neck)

	# Head (store reference)
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.1 * scale_factor
	head_mesh.height = 0.2 * scale_factor
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0, 0.99 * scale_factor, 0)
	body_container.add_child(head)

	# Pointy hat (gnome style!) - using prism mesh instead of cone
	var hat = MeshInstance3D.new()
	var hat_mesh = PrismMesh.new()
	hat_mesh.size = Vector3(0.22 * scale_factor, 0.25 * scale_factor, 0.22 * scale_factor)
	hat.mesh = hat_mesh
	hat.material_override = hair_mat
	hat.position = Vector3(0, 1.11 * scale_factor, 0)
	head.add_child(hat)

	# Nose - use proper sphere proportions (height = 2 * radius for round nose)
	var nose = MeshInstance3D.new()
	var nose_mesh = SphereMesh.new()
	var nose_radius = 0.02 * scale_factor
	nose_mesh.radius = nose_radius
	nose_mesh.height = nose_radius * 2.0  # Ensure perfectly round sphere
	nose.mesh = nose_mesh
	nose.material_override = skin_mat
	nose.position = Vector3(0, -0.01 * scale_factor, 0.09 * scale_factor)
	head.add_child(nose)

	# Eyes - use proper sphere proportions (height = 2 * radius for round eyes)
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.05, 1)  # Dark eyes

	var left_eye = MeshInstance3D.new()
	var eye_mesh = SphereMesh.new()
	var eye_radius = 0.015 * scale_factor
	eye_mesh.radius = eye_radius
	eye_mesh.height = eye_radius * 2.0  # Ensure perfectly round sphere
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.04 * scale_factor, 0.02 * scale_factor, 0.08 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.04 * scale_factor, 0.02 * scale_factor, 0.08 * scale_factor)
	head.add_child(right_eye)

	# Left Leg with articulated knee
	var thigh_mesh = CapsuleMesh.new()
	thigh_mesh.radius = 0.04 * scale_factor
	thigh_mesh.height = 0.175 * scale_factor  # Half of original leg length

	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.06 * scale_factor, 0.58 * scale_factor, 0)  # Hip position
	body_container.add_child(left_leg)

	var left_thigh_mesh = MeshInstance3D.new()
	left_thigh_mesh.mesh = thigh_mesh
	left_thigh_mesh.material_override = clothes_mat
	left_thigh_mesh.position = Vector3(0, -0.0875 * scale_factor, 0)  # Offset down by half thigh length
	left_leg.add_child(left_thigh_mesh)

	# Left knee joint
	var left_knee = Node3D.new()
	left_knee.name = "Knee"
	left_knee.position = Vector3(0, -0.175 * scale_factor, 0)  # At knee position
	left_leg.add_child(left_knee)

	var left_shin_mesh = MeshInstance3D.new()
	left_shin_mesh.mesh = thigh_mesh  # Reuse same mesh
	left_shin_mesh.material_override = clothes_mat
	left_shin_mesh.position = Vector3(0, -0.0875 * scale_factor, 0)  # Offset down by half shin length
	left_knee.add_child(left_shin_mesh)

	# Right Leg with articulated knee
	right_leg = Node3D.new()
	right_leg.position = Vector3(0.06 * scale_factor, 0.58 * scale_factor, 0)  # Hip position
	body_container.add_child(right_leg)

	var right_thigh_mesh = MeshInstance3D.new()
	right_thigh_mesh.mesh = thigh_mesh
	right_thigh_mesh.material_override = clothes_mat
	right_thigh_mesh.position = Vector3(0, -0.0875 * scale_factor, 0)  # Offset down by half thigh length
	right_leg.add_child(right_thigh_mesh)

	# Right knee joint
	var right_knee = Node3D.new()
	right_knee.name = "Knee"
	right_knee.position = Vector3(0, -0.175 * scale_factor, 0)  # At knee position
	right_leg.add_child(right_knee)

	var right_shin_mesh = MeshInstance3D.new()
	right_shin_mesh.mesh = thigh_mesh  # Reuse same mesh
	right_shin_mesh.material_override = clothes_mat
	right_shin_mesh.position = Vector3(0, -0.0875 * scale_factor, 0)  # Offset down by half shin length
	right_knee.add_child(right_shin_mesh)

	# Left Arm with articulated elbow
	var upper_arm_mesh = CapsuleMesh.new()
	upper_arm_mesh.radius = 0.03 * scale_factor
	upper_arm_mesh.height = 0.15 * scale_factor  # Half of original arm length

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.11 * scale_factor, 0.90 * scale_factor, 0)  # Shoulder position
	body_container.add_child(left_arm)

	var left_upper_arm_mesh = MeshInstance3D.new()
	left_upper_arm_mesh.mesh = upper_arm_mesh
	left_upper_arm_mesh.material_override = skin_mat
	left_upper_arm_mesh.position = Vector3(0, -0.075 * scale_factor, 0)  # Offset down by half upper arm length
	left_arm.add_child(left_upper_arm_mesh)

	# Left elbow joint
	var left_elbow = Node3D.new()
	left_elbow.name = "Elbow"
	left_elbow.position = Vector3(0, -0.15 * scale_factor, 0)  # At elbow position
	left_arm.add_child(left_elbow)

	var left_forearm_mesh = MeshInstance3D.new()
	left_forearm_mesh.mesh = upper_arm_mesh  # Reuse same mesh
	left_forearm_mesh.material_override = skin_mat
	left_forearm_mesh.position = Vector3(0, -0.075 * scale_factor, 0)  # Offset down by half forearm length
	left_elbow.add_child(left_forearm_mesh)

	# Right Arm with articulated elbow
	right_arm = Node3D.new()
	right_arm.position = Vector3(0.11 * scale_factor, 0.90 * scale_factor, 0)  # Shoulder position
	body_container.add_child(right_arm)

	var right_upper_arm_mesh = MeshInstance3D.new()
	right_upper_arm_mesh.mesh = upper_arm_mesh
	right_upper_arm_mesh.material_override = skin_mat
	right_upper_arm_mesh.position = Vector3(0, -0.075 * scale_factor, 0)  # Offset down by half upper arm length
	right_arm.add_child(right_upper_arm_mesh)

	# Right elbow joint
	var right_elbow = Node3D.new()
	right_elbow.name = "Elbow"
	right_elbow.position = Vector3(0, -0.15 * scale_factor, 0)  # At elbow position
	right_arm.add_child(right_elbow)

	var right_forearm_mesh = MeshInstance3D.new()
	right_forearm_mesh.mesh = upper_arm_mesh  # Reuse same mesh
	right_forearm_mesh.material_override = skin_mat
	right_forearm_mesh.position = Vector3(0, -0.075 * scale_factor, 0)  # Offset down by half forearm length
	right_elbow.add_child(right_forearm_mesh)

	# Set head base height for animation base class
	head_base_height = 0.99 * scale_factor


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Both server and client run full AI simulation
	# Server state is used for corrections when is_remote is true

	# Apply server state corrections for remote enemies (client-side)
	if is_remote:
		_apply_server_corrections(delta)

	# Update cooldowns
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if throw_cooldown > 0:
		throw_cooldown -= delta

	# Update state timer
	state_timer += delta
	decision_timer += delta

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Run AI
	_update_ai(delta)

	# Server-side: Robust terrain collision safety
	if multiplayer.is_server() and not is_remote:
		var has_collision_here = _has_terrain_collision(global_position)
		var has_collision_ahead = _has_terrain_collision(global_position + velocity * delta)

		# Track falling state
		if is_on_floor() and has_collision_here:
			# We're safely on ground with collision - reset fall timer and save position
			fall_timer = 0.0
			last_valid_position = global_position
		elif not is_on_floor():
			# We're in the air (jumping or falling)
			fall_timer += delta

		# SAFETY CHECK 1: Don't move into chunks without collision
		if not has_collision_ahead:
			velocity.x = 0
			velocity.z = 0

		# SAFETY CHECK 2: If no collision at current position, freeze completely
		if not has_collision_here:
			velocity = Vector3.ZERO

		# SAFETY CHECK 3: Detect falling through world and recover
		# Triggers if: falling for >0.5s, OR Y dropped >10m below spawn, OR Y < -50
		var fell_too_far = global_position.y < spawn_y - 10.0
		var fell_too_long = fall_timer > 0.5 and velocity.y < -5.0
		var fell_through_world = global_position.y < -50.0

		if fell_through_world or fell_too_far or (fell_too_long and not has_collision_here):
			# Teleport back to last valid position (or spawn height)
			if last_valid_position != Vector3.ZERO and _has_terrain_collision(last_valid_position):
				global_position = last_valid_position + Vector3(0, 1.0, 0)
			else:
				# Fallback: reset to spawn Y at current XZ
				global_position.y = spawn_y + 2.0
			velocity = Vector3.ZERO
			fall_timer = 0.0

	# Move
	move_and_slide()

	# Update programmatic animations
	update_animations(delta)

## Apply server state corrections (soft correction - blend toward server state)
## This runs on clients to gently correct drift without overriding local simulation
func _apply_server_corrections(delta: float) -> void:
	# Only correct if we have a valid server position
	if server_position == Vector3.ZERO:
		return

	# Soft correction - gently nudge toward server position
	# This allows local physics to run while staying roughly in sync
	var correction_strength = 3.0  # Lower = smoother, higher = snappier
	var position_error = server_position - global_position

	# Only correct if error is significant (avoid jitter from small differences)
	if position_error.length() > 0.1:
		global_position = global_position.lerp(server_position, correction_strength * delta)

	# Correct rotation
	var current_rot = rotation.y
	var target_rot = server_rotation_y
	var diff = fmod(target_rot - current_rot + PI, TAU) - PI
	if abs(diff) > 0.1:
		rotation.y = current_rot + diff * correction_strength * delta

## Apply server state (called from client when receiving network update)
func apply_server_state(pos: Vector3, rot_y: float, state: int, hp: float) -> void:
	server_position = pos
	server_rotation_y = rot_y

	# Apply state changes
	if ai_state != state:
		ai_state = state as AIState

	# Apply health
	if health != hp:
		var old_health = health
		health = hp
		# Update health bar if it exists
		if health_bar and old_health != hp:
			health_bar.update_health(health, max_health)
		# Check for death
		if health <= 0 and not is_dead:
			_die()

## Get current state for network sync (called by server)
## Compact format to reduce packet size
func get_sync_state() -> Array:
	# Use array instead of dictionary for smaller packets
	# Format: [px, py, pz, rot_y, state, hp]
	return [
		snappedf(global_position.x, 0.01),
		snappedf(global_position.y, 0.01),
		snappedf(global_position.z, 0.01),
		snappedf(rotation.y, 0.01),
		ai_state,
		snappedf(health, 0.1),
	]

## AI Update - State machine based behavior
func _update_ai(delta: float) -> void:
	# Stunned enemies can't move or attack
	if is_stunned:
		velocity.x = 0
		velocity.z = 0
		return

	# Find nearest player if we don't have a target
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_nearest_player()
		if target_player:
			_change_state(AIState.STALKING)

	# No target - idle
	if not target_player:
		_update_idle(delta)
		return

	# Check distance to target
	var distance_to_target = global_position.distance_to(target_player.global_position)

	# Lost target - too far away
	if distance_to_target > detection_range:
		target_player = null
		_change_state(AIState.IDLE)
		return

	# Face player only when attacking/throwing, otherwise face movement direction
	# This is handled per-state for more control

	# State machine
	match ai_state:
		AIState.IDLE:
			_update_idle(delta)
		AIState.STALKING:
			_update_stalking(delta, distance_to_target)
		AIState.CIRCLING:
			_update_circling(delta, distance_to_target)
		AIState.APPROACHING:
			_update_approaching(delta, distance_to_target)
		AIState.CHARGING:
			_update_charging(delta, distance_to_target)
		AIState.ATTACKING:
			_update_attacking(delta, distance_to_target)
		AIState.THROWING:
			_update_throwing(delta, distance_to_target)
		AIState.RETREATING:
			_update_retreating(delta, distance_to_target)

## Change to a new AI state
func _change_state(new_state: AIState) -> void:
	if ai_state == new_state:
		return
	ai_state = new_state
	state_timer = 0.0
	decision_timer = 0.0
	has_committed_charge = false

## Face the target player
func _face_target() -> void:
	if not target_player:
		return
	var direction = target_player.global_position - global_position
	direction.y = 0
	if direction.length() > 0.1:
		look_at(global_position + direction.normalized(), Vector3.UP)

## Face the movement direction (for wandering, circling, retreating)
func _face_movement_direction() -> void:
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	if horizontal_velocity.length() > 0.1:
		look_at(global_position + horizontal_velocity.normalized(), Vector3.UP)

## IDLE - No target, wandering around randomly
func _update_idle(delta: float) -> void:
	# Update timers
	if is_wander_paused:
		wander_pause_timer -= delta
		if wander_pause_timer <= 0:
			# Start wandering in a new random direction
			is_wander_paused = false
			var angle = randf() * TAU  # Random angle 0-2PI
			wander_direction = Vector3(cos(angle), 0, sin(angle))
			wander_timer = randf_range(1.5, 4.0)  # Wander for 1.5-4 seconds
	else:
		wander_timer -= delta
		if wander_timer <= 0:
			# Stop and pause
			is_wander_paused = true
			wander_pause_timer = randf_range(2.0, 5.0)  # Pause for 2-5 seconds
			velocity.x = 0
			velocity.z = 0
			return

	# Move in wander direction if not paused
	if not is_wander_paused and wander_direction.length() > 0.1:
		velocity.x = wander_direction.x * strafe_speed * 0.5  # Slow wander speed
		velocity.z = wander_direction.z * strafe_speed * 0.5
		_face_movement_direction()
	else:
		velocity.x = 0
		velocity.z = 0

## STALKING - Watching from distance, deciding what to do
func _update_stalking(delta: float, distance: float) -> void:
	# Player got too close - react!
	if distance < throw_min_range:
		# Too close for comfort - either charge or retreat
		if randf() < aggression:
			_change_state(AIState.CHARGING)
			charge_target_pos = target_player.global_position
		else:
			_change_state(AIState.RETREATING)
		return

	# Maintain preferred distance - back up if too close, approach if too far
	var distance_diff = distance - preferred_distance

	if abs(distance_diff) > 1.5:
		# Move to maintain distance
		var direction = target_player.global_position - global_position
		direction.y = 0
		direction = direction.normalized()

		if distance_diff < 0:
			# Too close - back up slowly
			velocity.x = -direction.x * strafe_speed * 0.7
			velocity.z = -direction.z * strafe_speed * 0.7
		else:
			# Too far - approach cautiously
			velocity.x = direction.x * strafe_speed
			velocity.z = direction.z * strafe_speed
		# Face movement direction when moving
		_face_movement_direction()
	else:
		velocity.x = 0
		velocity.z = 0
		# Face player when stationary and watching
		_face_target()

	# Decision making - what to do next?
	var stalk_duration = 1.5 + patience * 2.0  # 1.5-3.5 seconds based on patience
	if state_timer > stalk_duration:
		_make_combat_decision(distance)

## Make a decision about what action to take
func _make_combat_decision(distance: float) -> void:
	# Can we throw? (in range and cooldown ready)
	var can_throw = distance >= throw_min_range and distance <= throw_range and throw_cooldown <= 0

	# Should we charge? (based on aggression and distance)
	var charge_chance = aggression * 0.6  # Base charge chance from aggression

	# More likely to charge if player is closer
	if distance < preferred_distance:
		charge_chance += 0.2

	# Less likely to charge if we can throw
	if can_throw:
		charge_chance -= 0.3

	var roll = randf()

	if can_throw and roll > charge_chance + 0.3:
		# Throw a rock!
		_change_state(AIState.THROWING)
	elif roll < charge_chance:
		# CHARGE!
		_change_state(AIState.CHARGING)
		charge_target_pos = target_player.global_position
	else:
		# Circle around, looking for opening
		_change_state(AIState.CIRCLING)
		circle_timer = 0.0
		# Maybe change circle direction
		if randf() < 0.3:
			circle_direction *= -1

## CIRCLING - Strafing around player
func _update_circling(delta: float, distance: float) -> void:
	circle_timer += delta

	# Player rushed us - react!
	if distance < attack_range * 1.5:
		_change_state(AIState.ATTACKING)
		return

	# Calculate strafe direction (perpendicular to player direction)
	var to_player = target_player.global_position - global_position
	to_player.y = 0
	to_player = to_player.normalized()

	# Perpendicular direction for circling
	var strafe_dir = Vector3(-to_player.z, 0, to_player.x) * circle_direction

	# Also adjust distance while circling
	var distance_diff = distance - preferred_distance
	var approach_factor = clamp(distance_diff / 3.0, -0.5, 0.5)

	var move_dir = (strafe_dir + to_player * approach_factor).normalized()

	velocity.x = move_dir.x * strafe_speed
	velocity.z = move_dir.z * strafe_speed

	# Face movement direction while circling
	_face_movement_direction()

	# Occasionally change direction or make a new decision
	if circle_timer > 2.0 + randf() * 1.5:
		if randf() < 0.4:
			circle_direction *= -1
			circle_timer = 0.0
		else:
			_make_combat_decision(distance)

## APPROACHING - Moving closer cautiously (not committed)
func _update_approaching(delta: float, distance: float) -> void:
	# Close enough to attack
	if distance <= attack_range:
		_change_state(AIState.ATTACKING)
		return

	# Move toward player
	var direction = target_player.global_position - global_position
	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * move_speed * 0.8
	velocity.z = direction.z * move_speed * 0.8

	# Face movement direction
	_face_movement_direction()

	# Timeout - change mind and go back to stalking
	if state_timer > 2.5:
		_change_state(AIState.STALKING)

## CHARGING - Committed rush attack
func _update_charging(delta: float, distance: float) -> void:
	# Update charge target to track player (but less accurately once committed)
	if not has_committed_charge:
		charge_target_pos = target_player.global_position
		if state_timer > 0.3:  # Short windup before committing
			has_committed_charge = true

	# Reached attack range - attack!
	if distance <= attack_range:
		_change_state(AIState.ATTACKING)
		return

	# Charge toward target position
	var direction = charge_target_pos - global_position
	direction.y = 0

	if direction.length() > 0.5:
		direction = direction.normalized()
		velocity.x = direction.x * charge_speed
		velocity.z = direction.z * charge_speed
		look_at(global_position + direction, Vector3.UP)
	else:
		# Reached charge target but player moved - reassess
		if distance > attack_range * 2:
			_change_state(AIState.STALKING)
		else:
			_change_state(AIState.APPROACHING)

	# Charge timeout - don't charge forever
	if state_timer > 3.0:
		_change_state(AIState.STALKING)

## ATTACKING - Melee attack
func _update_attacking(delta: float, distance: float) -> void:
	velocity.x = 0
	velocity.z = 0

	# Face the target when attacking
	_face_target()

	# In range and cooldown ready - attack!
	if distance <= attack_range and attack_cooldown <= 0:
		_attack_player(target_player)
		attack_cooldown = attack_cooldown_time

		# After attacking, decide what to do
		if randf() < 0.4:
			# Retreat after hit
			_change_state(AIState.RETREATING)
		else:
			# Stay aggressive
			_change_state(AIState.CIRCLING)
	elif distance > attack_range * 1.5:
		# Player moved away
		_change_state(AIState.STALKING)
	elif state_timer > 1.5:
		# Timeout - couldn't land the hit, reassess
		_change_state(AIState.STALKING)

## THROWING - Rock throw attack
func _update_throwing(delta: float, distance: float) -> void:
	velocity.x = 0
	velocity.z = 0

	# Face the target when throwing
	_face_target()

	# Short windup then throw
	if state_timer > 0.4 and throw_cooldown <= 0:
		_throw_rock()
		throw_cooldown = throw_cooldown_time

		# After throwing, decide what to do
		if distance < preferred_distance:
			_change_state(AIState.RETREATING)
		else:
			_change_state(AIState.CIRCLING)
	elif state_timer > 1.0:
		# Took too long, abort
		_change_state(AIState.STALKING)

## RETREATING - Backing away
func _update_retreating(delta: float, distance: float) -> void:
	# Move away from player
	var direction = global_position - target_player.global_position
	direction.y = 0

	if direction.length() > 0.1:
		direction = direction.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

		# Face away (running away)
		look_at(global_position + direction, Vector3.UP)

	# Stop retreating when far enough or timeout
	if distance > preferred_distance * 1.2 or state_timer > 2.0:
		_change_state(AIState.STALKING)

## Find nearest player
func _find_nearest_player() -> CharacterBody3D:
	var nearest_player: CharacterBody3D = null
	var nearest_distance: float = INF

	# Get all nodes in the scene
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		# Skip if it's this enemy or another enemy
		if player == self or player.is_in_group("enemies"):
			continue

		if player is CharacterBody3D:
			var distance = global_position.distance_to(player.global_position)
			if distance < nearest_distance and distance <= detection_range:
				nearest_distance = distance
				nearest_player = player

	return nearest_player

## Attack a player (melee)
func _attack_player(player: CharacterBody3D) -> void:
	print("[Enemy] %s attacks player with %s!" % [enemy_name, weapon_data.display_name])

	# Start attack animation
	start_attack_animation()

	# Calculate knockback direction
	var knockback_dir = (player.global_position - global_position).normalized()

	# Use weapon stats for damage and knockback
	var damage = weapon_data.damage
	var knockback = weapon_data.knockback

	# Apply damage (if player has take_damage method)
	if player.has_method("take_damage"):
		player.take_damage(damage, get_instance_id(), knockback_dir)

## Throw a rock at the player
func _throw_rock() -> void:
	if not target_player:
		return

	if not is_inside_tree():
		return

	print("[Enemy] %s throws a rock!" % enemy_name)

	# Start throw animation (uses the attack animation for now)
	start_throw_animation()

	# Create the rock projectile
	var rock = ThrownRock.new()
	rock.damage = rock_damage
	rock.speed = rock_speed
	rock.thrower = self

	# Calculate spawn position and direction BEFORE adding to scene
	var spawn_pos = global_position + Vector3(0, 0.8, 0)  # Roughly at shoulder height
	var target_pos = target_player.global_position + Vector3(0, 0.8, 0)
	var direction = (target_pos - spawn_pos).normalized()

	# Add slight upward arc for more natural throw
	direction.y += 0.15
	direction = direction.normalized()

	rock.direction = direction

	# Add to scene FIRST, then set position (node must be in tree for global_position)
	get_tree().current_scene.add_child(rock)
	rock.global_position = spawn_pos

## Take damage
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	var final_damage = damage

	# Apply stun damage multiplier if stunned
	if is_stunned:
		final_damage *= STUN_DAMAGE_MULTIPLIER
		print("[Enemy] %s taking extra damage while stunned! (%.1fx multiplier)" % [enemy_name, STUN_DAMAGE_MULTIPLIER])

	health -= final_damage
	print("[Enemy] %s took %.1f damage, health: %.1f, knockback: %.1f" % [enemy_name, final_damage, health, knockback])

	# Create health bar on first damage (lazy loading for performance)
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(1.2)  # Position above enemy head

	# Update health bar
	if health_bar:
		health_bar.update_health(health, max_health)

	# Apply knockback (horizontal only, don't launch enemies into the air)
	if knockback > 0 and direction.length() > 0:
		var knockback_dir = direction.normalized()
		knockback_dir.y = 0  # Keep knockback horizontal
		knockback_dir = knockback_dir.normalized()

		# Apply knockback to velocity
		velocity += knockback_dir * knockback
		print("[Enemy] Applied knockback: %s (magnitude: %.1f)" % [knockback_dir * knockback, knockback])

	if health <= 0:
		health = 0
		_die()

## Handle death
func _die() -> void:
	if is_dead:
		return

	is_dead = true
	print("[Enemy] %s died!" % enemy_name)

	# Emit died signal
	died.emit(self)

	# Drop loot
	if multiplayer.is_server():
		_drop_loot()

	# Play death animation (programmatic fade/fall)
	if body_container:
		var tween = create_tween()
		tween.tween_property(body_container, "position:y", -1.0, 1.0)
		tween.parallel().tween_property(body_container, "rotation:x", PI / 2, 1.0)
		tween.tween_callback(queue_free)

## Drop loot on death (SERVER-SIDE ONLY)
func _drop_loot() -> void:
	if loot_table.is_empty():
		return

	print("[Enemy] Dropping loot: %s" % loot_table)

	# Generate network IDs for each loot item
	var network_ids: Array = []
	for resource_type in loot_table:
		var amount: int = loot_table[resource_type]
		for i in amount:
			# Use server time and enemy info for unique IDs
			var net_id = "%s_%d_%d" % [enemy_name, Time.get_ticks_msec(), i]
			network_ids.append(net_id)

	# Spawn resource drops at enemy position
	var pos_array = [global_position.x, global_position.y, global_position.z]
	NetworkManager.rpc_spawn_resource_drops.rpc(loot_table, pos_array, network_ids)

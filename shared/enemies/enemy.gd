extends "res://shared/animated_character.gd"
class_name Enemy

## Enemy - Gahnome enemy with Valheim-style client-host networking
##
## VALHEIM-STYLE CLIENT-HOST MODEL:
## - One client is the "host" for each enemy (runs full AI/physics)
## - Host client has local terrain collision and runs AI
## - Host sends position/state to server at 10Hz
## - Server relays to all other clients (server does NOT run AI)
## - Non-host clients interpolate toward synced position
## - Damage is LOCAL-FIRST: each client handles damage to their own player

signal died(enemy: Enemy)

# AI States
enum AIState {
	IDLE,           # No target, wandering or standing
	STALKING,       # Watching player from distance
	CIRCLING,       # Strafing around the player
	CHARGING,       # Committed rush attack
	ATTACKING,      # Melee attack in progress
	THROWING,       # Rock throw attack
	RETREATING,     # Backing away after attack
}

# ============================================================================
# NETWORK IDENTITY
# ============================================================================
var network_id: int = 0          # Unique ID assigned by server
var host_peer_id: int = 0        # Which peer runs AI for this enemy
var is_host: bool = false        # True if THIS client runs AI
var is_remote: bool = false      # True on clients (not server)

# ============================================================================
# SYNC STATE (received from host via server relay)
# ============================================================================
var sync_position: Vector3 = Vector3.ZERO
var sync_rotation_y: float = 0.0
var sync_ai_state: int = 0
var sync_health: float = 50.0
var sync_target_peer: int = 0    # Which player the enemy is targeting

# Interpolation
var sync_velocity: Vector3 = Vector3.ZERO
var last_sync_position: Vector3 = Vector3.ZERO
var last_sync_time: float = 0.0
const INTERPOLATION_SPEED: float = 12.0
const SNAP_DISTANCE: float = 5.0

# Host reporting (10Hz)
var report_timer: float = 0.0
const REPORT_INTERVAL: float = 0.1

# ============================================================================
# ENEMY STATS
# ============================================================================
@export var enemy_name: String = "Gahnome"
@export var max_health: float = 50.0
@export var move_speed: float = 3.0
@export var charge_speed: float = 5.5
@export var strafe_speed: float = 2.0
@export var attack_range: float = 1.2
@export var attack_cooldown_time: float = 1.2
@export var detection_range: float = 18.0
@export var preferred_distance: float = 6.0
@export var throw_range: float = 12.0
@export var throw_min_range: float = 4.0
@export var throw_cooldown_time: float = 3.5
@export var rock_damage: float = 8.0
@export var rock_speed: float = 15.0
@export var loot_table: Dictionary = {"wood": 2, "resin": 1}
@export var weapon_id: String = "fists"

# Weapon data
var weapon_data = null

# ============================================================================
# AI STATE (only used by host)
# ============================================================================
var ai_state: AIState = AIState.IDLE
var state_timer: float = 0.0
var health: float = max_health
var is_dead: bool = false
var target_player: CharacterBody3D = null
var attack_cooldown: float = 0.0
var throw_cooldown: float = 0.0

# Circling
var circle_direction: int = 1
var circle_timer: float = 0.0

# Charging
var charge_target_pos: Vector3 = Vector3.ZERO
var has_committed_charge: bool = false

# Wandering
var wander_direction: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var wander_pause_timer: float = 0.0
var is_wander_paused: bool = true

# Personality (randomized)
var aggression: float = 0.5
var patience: float = 0.5

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

# Projectiles
const ThrownRock = preload("res://shared/enemies/thrown_rock.gd")

# Physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	collision_layer = 4  # Enemies layer
	collision_mask = 1 | 2  # World and Players

	# Add to enemies group for raycast detection by player attacks
	add_to_group("enemies")

	weapon_data = ItemDatabase.get_item(weapon_id)
	if not weapon_data:
		weapon_data = ItemDatabase.get_item("fists")

	walk_speed = move_speed
	attack_animation_time = 0.3

	_setup_body()

	# Random personality
	aggression = randf_range(0.3, 0.8)
	patience = randf_range(0.3, 0.7)
	circle_direction = 1 if randf() > 0.5 else -1

	health = max_health

	print("[Enemy] %s ready (network_id=%d, host_peer=%d, is_host=%s)" % [enemy_name, network_id, host_peer_id, is_host])

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# VALHEIM-STYLE: Host runs AI, others interpolate
	if is_host:
		_run_host_ai(delta)
		_send_position_report(delta)
	else:
		_run_follower_interpolation(delta)

	update_animations(delta)

# ============================================================================
# HOST: Run full AI and physics
# ============================================================================
func _run_host_ai(delta: float) -> void:
	# Update cooldowns
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if throw_cooldown > 0:
		throw_cooldown -= delta

	state_timer += delta

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Run AI state machine
	_update_ai(delta)

	# Move
	move_and_slide()

func _send_position_report(delta: float) -> void:
	report_timer += delta
	if report_timer < REPORT_INTERVAL:
		return
	report_timer = 0.0

	# Get target peer ID
	var target_peer: int = 0
	if target_player and is_instance_valid(target_player):
		var pname = target_player.name
		if pname.begins_with("Player_"):
			target_peer = pname.substr(7).to_int()

	# Send to server
	var pos_array = [global_position.x, global_position.y, global_position.z]
	NetworkManager.rpc_report_enemy_position.rpc_id(1, network_id, pos_array, rotation.y, ai_state, target_peer)

# ============================================================================
# FOLLOWER: Interpolate toward synced position
# ============================================================================
func _run_follower_interpolation(delta: float) -> void:
	if sync_position == Vector3.ZERO:
		return

	# Calculate predicted position using velocity
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_sync = current_time - last_sync_time
	var predicted_pos = sync_position + sync_velocity * minf(time_since_sync, 0.2)

	# Interpolate position
	var distance = global_position.distance_to(predicted_pos)
	if distance > SNAP_DISTANCE:
		global_position = predicted_pos
	else:
		var lerp_speed = minf(INTERPOLATION_SPEED * delta, 0.5)
		global_position = global_position.lerp(predicted_pos, lerp_speed)

	# Interpolate rotation
	rotation.y = lerp_angle(rotation.y, sync_rotation_y, 8.0 * delta)

	# Set velocity for animation system (so walk animation plays)
	velocity = sync_velocity

	# Update AI state for animations
	var prev_state = ai_state
	ai_state = sync_ai_state as AIState

	# Trigger animations AND local damage checks on state change
	if prev_state != ai_state:
		match ai_state:
			AIState.ATTACKING:
				start_attack_animation()
				# LOCAL-FIRST: Non-host clients also check for damage to their player
				if not is_host:
					_check_local_melee_damage()
			AIState.THROWING:
				start_throw_animation()

	# Update target from sync (for looking at player)
	_update_target_from_sync()

	# Update health
	if health != sync_health:
		var old_health = health
		health = sync_health
		if health_bar:
			health_bar.update_health(health, max_health)
		if health <= 0 and not is_dead:
			_die()

func _update_target_from_sync() -> void:
	if sync_target_peer == 0:
		target_player = null
		return

	var player_name = "Player_" + str(sync_target_peer)
	var world = get_parent()
	if world:
		target_player = world.get_node_or_null(player_name)

# ============================================================================
# SYNC STATE APPLICATION (called from client.gd)
# ============================================================================
func apply_sync_state(pos: Vector3, rot_y: float, state: int, hp: float, target_peer: int = 0) -> void:
	# Calculate velocity from position delta
	var current_time = Time.get_ticks_msec() / 1000.0
	if last_sync_time > 0:
		var dt = current_time - last_sync_time
		if dt > 0.01:
			sync_velocity = (pos - last_sync_position) / dt

	last_sync_position = pos
	last_sync_time = current_time

	# Store sync state
	sync_position = pos
	sync_rotation_y = rot_y
	sync_ai_state = state
	sync_health = hp
	sync_target_peer = target_peer

# For compatibility with existing code
func apply_server_state(pos: Vector3, rot_y: float, state: int, hp: float, target_peer: int = 0) -> void:
	apply_sync_state(pos, rot_y, state, hp, target_peer)

## Get sync state for network broadcast (called by host client)
func get_sync_state() -> Array:
	var target_peer: int = 0
	if target_player and is_instance_valid(target_player):
		var pname = target_player.name
		if pname.begins_with("Player_"):
			target_peer = pname.substr(7).to_int()

	return [
		snappedf(global_position.x, 0.01),
		snappedf(global_position.y, 0.01),
		snappedf(global_position.z, 0.01),
		snappedf(rotation.y, 0.01),
		ai_state,
		snappedf(health, 0.1),
		target_peer,
	]

# ============================================================================
# AI STATE MACHINE (only runs on host)
# ============================================================================
func _update_ai(delta: float) -> void:
	if is_stunned:
		velocity.x = 0
		velocity.z = 0
		return

	# Find target
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_nearest_player()
		if target_player:
			_change_state(AIState.STALKING)

	if not target_player:
		_update_idle(delta)
		return

	var distance = global_position.distance_to(target_player.global_position)

	# Lost target
	if distance > detection_range:
		target_player = null
		_change_state(AIState.IDLE)
		return

	match ai_state:
		AIState.IDLE:
			_update_idle(delta)
		AIState.STALKING:
			_update_stalking(delta, distance)
		AIState.CIRCLING:
			_update_circling(delta, distance)
		AIState.CHARGING:
			_update_charging(delta, distance)
		AIState.ATTACKING:
			_update_attacking(delta, distance)
		AIState.THROWING:
			_update_throwing(delta, distance)
		AIState.RETREATING:
			_update_retreating(delta, distance)

func _change_state(new_state: AIState) -> void:
	if ai_state == new_state:
		return
	ai_state = new_state
	state_timer = 0.0
	has_committed_charge = false

func _face_target() -> void:
	if not target_player:
		return
	var direction = target_player.global_position - global_position
	direction.y = 0
	if direction.length() > 0.1:
		look_at(global_position + direction.normalized(), Vector3.UP)

func _face_movement() -> void:
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	if horizontal_velocity.length() > 0.1:
		look_at(global_position + horizontal_velocity.normalized(), Vector3.UP)

func _update_idle(delta: float) -> void:
	if is_wander_paused:
		wander_pause_timer -= delta
		if wander_pause_timer <= 0:
			is_wander_paused = false
			var angle = randf() * TAU
			wander_direction = Vector3(cos(angle), 0, sin(angle))
			wander_timer = randf_range(1.5, 4.0)
	else:
		wander_timer -= delta
		if wander_timer <= 0:
			is_wander_paused = true
			wander_pause_timer = randf_range(2.0, 5.0)
			velocity.x = 0
			velocity.z = 0
			return

	if not is_wander_paused and wander_direction.length() > 0.1:
		velocity.x = wander_direction.x * strafe_speed * 0.5
		velocity.z = wander_direction.z * strafe_speed * 0.5
		_face_movement()
	else:
		velocity.x = 0
		velocity.z = 0

func _update_stalking(delta: float, distance: float) -> void:
	if distance < throw_min_range:
		if randf() < aggression:
			_change_state(AIState.CHARGING)
			charge_target_pos = target_player.global_position
		else:
			_change_state(AIState.RETREATING)
		return

	var distance_diff = distance - preferred_distance
	if abs(distance_diff) > 1.5:
		var direction = target_player.global_position - global_position
		direction.y = 0
		direction = direction.normalized()

		if distance_diff < 0:
			velocity.x = -direction.x * strafe_speed * 0.7
			velocity.z = -direction.z * strafe_speed * 0.7
		else:
			velocity.x = direction.x * strafe_speed
			velocity.z = direction.z * strafe_speed
		_face_movement()
	else:
		velocity.x = 0
		velocity.z = 0
		_face_target()

	var stalk_duration = 1.5 + patience * 2.0
	if state_timer > stalk_duration:
		_make_combat_decision(distance)

func _make_combat_decision(distance: float) -> void:
	var can_throw = distance >= throw_min_range and distance <= throw_range and throw_cooldown <= 0
	var charge_chance = aggression * 0.6

	if distance < preferred_distance:
		charge_chance += 0.2
	if can_throw:
		charge_chance -= 0.3

	var roll = randf()

	if can_throw and roll > charge_chance + 0.3:
		_change_state(AIState.THROWING)
	elif roll < charge_chance:
		_change_state(AIState.CHARGING)
		charge_target_pos = target_player.global_position
	else:
		_change_state(AIState.CIRCLING)
		circle_timer = 0.0
		if randf() < 0.3:
			circle_direction *= -1

func _update_circling(delta: float, distance: float) -> void:
	circle_timer += delta

	if distance < attack_range * 1.5:
		_change_state(AIState.ATTACKING)
		return

	var to_player = target_player.global_position - global_position
	to_player.y = 0
	to_player = to_player.normalized()

	var strafe_dir = Vector3(-to_player.z, 0, to_player.x) * circle_direction
	var distance_diff = distance - preferred_distance
	var approach_factor = clamp(distance_diff / 3.0, -0.5, 0.5)
	var move_dir = (strafe_dir + to_player * approach_factor).normalized()

	velocity.x = move_dir.x * strafe_speed
	velocity.z = move_dir.z * strafe_speed
	_face_movement()

	if circle_timer > 2.0 + randf() * 1.5:
		if randf() < 0.4:
			circle_direction *= -1
			circle_timer = 0.0
		else:
			_make_combat_decision(distance)

func _update_charging(delta: float, distance: float) -> void:
	if not has_committed_charge:
		charge_target_pos = target_player.global_position
		if state_timer > 0.3:
			has_committed_charge = true

	if distance <= attack_range:
		_change_state(AIState.ATTACKING)
		return

	var direction = charge_target_pos - global_position
	direction.y = 0

	if direction.length() > 0.5:
		direction = direction.normalized()
		velocity.x = direction.x * charge_speed
		velocity.z = direction.z * charge_speed
		look_at(global_position + direction, Vector3.UP)
	else:
		if distance > attack_range * 2:
			_change_state(AIState.STALKING)
		else:
			_change_state(AIState.ATTACKING)

	if state_timer > 3.0:
		_change_state(AIState.STALKING)

func _update_attacking(delta: float, distance: float) -> void:
	velocity.x = 0
	velocity.z = 0
	_face_target()

	if distance <= attack_range and attack_cooldown <= 0:
		_do_melee_attack()
		attack_cooldown = attack_cooldown_time

		if randf() < 0.4:
			_change_state(AIState.RETREATING)
		else:
			_change_state(AIState.CIRCLING)
	elif distance > attack_range * 1.5:
		_change_state(AIState.STALKING)
	elif state_timer > 1.5:
		_change_state(AIState.STALKING)

func _update_throwing(delta: float, distance: float) -> void:
	velocity.x = 0
	velocity.z = 0
	_face_target()

	if state_timer > 0.4 and throw_cooldown <= 0:
		_throw_rock()
		throw_cooldown = throw_cooldown_time

		if distance < preferred_distance:
			_change_state(AIState.RETREATING)
		else:
			_change_state(AIState.CIRCLING)
	elif state_timer > 1.0:
		_change_state(AIState.STALKING)

func _update_retreating(delta: float, distance: float) -> void:
	var direction = global_position - target_player.global_position
	direction.y = 0

	if direction.length() > 0.1:
		direction = direction.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		look_at(global_position + direction, Vector3.UP)

	if distance > preferred_distance * 1.2 or state_timer > 2.0:
		_change_state(AIState.STALKING)

func _find_nearest_player() -> CharacterBody3D:
	var nearest: CharacterBody3D = null
	var nearest_dist: float = INF

	for player in get_tree().get_nodes_in_group("players"):
		if player == self or player.is_in_group("enemies"):
			continue
		if player is CharacterBody3D:
			var dist = global_position.distance_to(player.global_position)
			if dist < nearest_dist and dist <= detection_range:
				nearest_dist = dist
				nearest = player

	return nearest

# ============================================================================
# COMBAT: LOCAL-FIRST DAMAGE
# Each client checks if THEIR player is being attacked
# ============================================================================
func _do_melee_attack() -> void:
	print("[Enemy] %s attacks with %s!" % [enemy_name, weapon_data.display_name])
	start_attack_animation()

	# LOCAL-FIRST: Check if MY local player is in range and being targeted
	var my_peer_id = multiplayer.get_unique_id()
	var local_player = _get_local_player()

	if not local_player:
		return

	# Check if local player is within attack range
	var dist = global_position.distance_to(local_player.global_position)
	if dist > attack_range * 1.5:
		return  # Too far

	# Apply damage to local player
	var knockback_dir = (local_player.global_position - global_position).normalized()
	var damage = weapon_data.damage
	var knockback = weapon_data.knockback

	if local_player.has_method("take_damage"):
		print("[Enemy] Dealing %.1f melee damage to local player" % damage)
		local_player.take_damage(damage, -1, knockback_dir * knockback)

## Check if local player should take melee damage (for non-host clients)
## Called when we see ATTACKING state from network sync
func _check_local_melee_damage() -> void:
	var local_player = _get_local_player()
	if not local_player:
		return

	# Check if local player is within attack range
	var dist = global_position.distance_to(local_player.global_position)
	if dist > attack_range * 1.5:
		return  # Too far

	# Apply damage to local player
	var knockback_dir = (local_player.global_position - global_position).normalized()
	var damage = weapon_data.damage
	var knockback = weapon_data.knockback

	if local_player.has_method("take_damage"):
		print("[Enemy] (non-host) Dealing %.1f melee damage to local player" % damage)
		local_player.take_damage(damage, -1, knockback_dir * knockback)

func _throw_rock() -> void:
	if not target_player:
		return

	print("[Enemy] %s throws a rock!" % enemy_name)
	start_throw_animation()

	# Create rock projectile
	var rock = ThrownRock.new()
	rock.damage = rock_damage
	rock.speed = rock_speed
	rock.thrower = self

	var spawn_pos = global_position + Vector3(0, 0.8, 0)
	var target_pos = target_player.global_position + Vector3(0, 0.8, 0)
	var direction = (target_pos - spawn_pos).normalized()
	direction.y += 0.15
	direction = direction.normalized()

	rock.direction = direction

	get_tree().current_scene.add_child(rock)
	rock.global_position = spawn_pos

func _get_local_player() -> CharacterBody3D:
	var my_peer_id = multiplayer.get_unique_id()
	var player_name = "Player_" + str(my_peer_id)
	var world = get_parent()
	if world:
		return world.get_node_or_null(player_name)
	return null

# ============================================================================
# DAMAGE AND DEATH
# ============================================================================
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	var final_damage = damage
	if is_stunned:
		final_damage *= STUN_DAMAGE_MULTIPLIER

	health -= final_damage
	print("[Enemy] %s took %.1f damage, health: %.1f" % [enemy_name, final_damage, health])

	# Create health bar on first damage
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(1.2)

	if health_bar:
		health_bar.update_health(health, max_health)

	# Apply knockback
	if knockback > 0 and direction.length() > 0:
		var kb_dir = direction.normalized()
		kb_dir.y = 0
		kb_dir = kb_dir.normalized()
		velocity += kb_dir * knockback

	if health <= 0:
		health = 0
		_die()

func _die() -> void:
	if is_dead:
		return

	is_dead = true
	print("[Enemy] %s died!" % enemy_name)

	died.emit(self)

	# Drop loot (only host does this to avoid duplicates)
	if is_host:
		_drop_loot()

	# Death animation
	if body_container:
		var tween = create_tween()
		tween.tween_property(body_container, "position:y", -1.0, 1.0)
		tween.parallel().tween_property(body_container, "rotation:x", PI / 2, 1.0)
		tween.tween_callback(queue_free)

func _drop_loot() -> void:
	if loot_table.is_empty():
		return

	print("[Enemy] Dropping loot: %s" % loot_table)

	var network_ids: Array = []
	for resource_type in loot_table:
		var amount: int = loot_table[resource_type]
		for i in amount:
			var net_id = "%s_%d_%d" % [enemy_name, Time.get_ticks_msec(), i]
			network_ids.append(net_id)

	var pos_array = [global_position.x, global_position.y, global_position.z]
	NetworkManager.rpc_spawn_resource_drops.rpc_id(1, loot_table, pos_array, network_ids)

# ============================================================================
# VISUAL SETUP
# ============================================================================
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	var scale_factor: float = 0.66

	# Materials
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.45, 0.55, 0.35, 1)

	var clothes_mat = StandardMaterial3D.new()
	clothes_mat.albedo_color = Color(0.4, 0.25, 0.15, 1)

	var hair_mat = StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.7, 0.7, 0.7, 1)

	# Hips
	var hips = MeshInstance3D.new()
	var hips_mesh = BoxMesh.new()
	hips_mesh.size = Vector3(0.18, 0.15, 0.1) * scale_factor
	hips.mesh = hips_mesh
	hips.material_override = clothes_mat
	hips.position = Vector3(0, 0.58 * scale_factor, 0)
	body_container.add_child(hips)

	# Torso
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

	# Head
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.1 * scale_factor
	head_mesh.height = 0.2 * scale_factor
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0, 0.99 * scale_factor, 0)
	body_container.add_child(head)

	# Hat
	var hat = MeshInstance3D.new()
	var hat_mesh = PrismMesh.new()
	hat_mesh.size = Vector3(0.22 * scale_factor, 0.25 * scale_factor, 0.22 * scale_factor)
	hat.mesh = hat_mesh
	hat.material_override = hair_mat
	hat.position = Vector3(0, 1.11 * scale_factor, 0)
	head.add_child(hat)

	# Nose
	var nose = MeshInstance3D.new()
	var nose_mesh = SphereMesh.new()
	var nose_radius = 0.02 * scale_factor
	nose_mesh.radius = nose_radius
	nose_mesh.height = nose_radius * 2.0
	nose.mesh = nose_mesh
	nose.material_override = skin_mat
	nose.position = Vector3(0, -0.01 * scale_factor, 0.09 * scale_factor)
	head.add_child(nose)

	# Eyes
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.05, 1)

	var eye_mesh = SphereMesh.new()
	var eye_radius = 0.015 * scale_factor
	eye_mesh.radius = eye_radius
	eye_mesh.height = eye_radius * 2.0

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.04 * scale_factor, 0.02 * scale_factor, 0.08 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.04 * scale_factor, 0.02 * scale_factor, 0.08 * scale_factor)
	head.add_child(right_eye)

	# Legs
	var thigh_mesh = CapsuleMesh.new()
	thigh_mesh.radius = 0.04 * scale_factor
	thigh_mesh.height = 0.175 * scale_factor

	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.06 * scale_factor, 0.58 * scale_factor, 0)
	body_container.add_child(left_leg)

	var left_thigh = MeshInstance3D.new()
	left_thigh.mesh = thigh_mesh
	left_thigh.material_override = clothes_mat
	left_thigh.position = Vector3(0, -0.0875 * scale_factor, 0)
	left_leg.add_child(left_thigh)

	var left_knee = Node3D.new()
	left_knee.name = "Knee"
	left_knee.position = Vector3(0, -0.175 * scale_factor, 0)
	left_leg.add_child(left_knee)

	var left_shin = MeshInstance3D.new()
	left_shin.mesh = thigh_mesh
	left_shin.material_override = clothes_mat
	left_shin.position = Vector3(0, -0.0875 * scale_factor, 0)
	left_knee.add_child(left_shin)

	right_leg = Node3D.new()
	right_leg.position = Vector3(0.06 * scale_factor, 0.58 * scale_factor, 0)
	body_container.add_child(right_leg)

	var right_thigh = MeshInstance3D.new()
	right_thigh.mesh = thigh_mesh
	right_thigh.material_override = clothes_mat
	right_thigh.position = Vector3(0, -0.0875 * scale_factor, 0)
	right_leg.add_child(right_thigh)

	var right_knee = Node3D.new()
	right_knee.name = "Knee"
	right_knee.position = Vector3(0, -0.175 * scale_factor, 0)
	right_leg.add_child(right_knee)

	var right_shin = MeshInstance3D.new()
	right_shin.mesh = thigh_mesh
	right_shin.material_override = clothes_mat
	right_shin.position = Vector3(0, -0.0875 * scale_factor, 0)
	right_knee.add_child(right_shin)

	# Arms
	var arm_mesh = CapsuleMesh.new()
	arm_mesh.radius = 0.03 * scale_factor
	arm_mesh.height = 0.15 * scale_factor

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.11 * scale_factor, 0.90 * scale_factor, 0)
	body_container.add_child(left_arm)

	var left_upper = MeshInstance3D.new()
	left_upper.mesh = arm_mesh
	left_upper.material_override = skin_mat
	left_upper.position = Vector3(0, -0.075 * scale_factor, 0)
	left_arm.add_child(left_upper)

	var left_elbow = Node3D.new()
	left_elbow.name = "Elbow"
	left_elbow.position = Vector3(0, -0.15 * scale_factor, 0)
	left_arm.add_child(left_elbow)

	var left_forearm = MeshInstance3D.new()
	left_forearm.mesh = arm_mesh
	left_forearm.material_override = skin_mat
	left_forearm.position = Vector3(0, -0.075 * scale_factor, 0)
	left_elbow.add_child(left_forearm)

	right_arm = Node3D.new()
	right_arm.position = Vector3(0.11 * scale_factor, 0.90 * scale_factor, 0)
	body_container.add_child(right_arm)

	var right_upper = MeshInstance3D.new()
	right_upper.mesh = arm_mesh
	right_upper.material_override = skin_mat
	right_upper.position = Vector3(0, -0.075 * scale_factor, 0)
	right_arm.add_child(right_upper)

	var right_elbow = Node3D.new()
	right_elbow.name = "Elbow"
	right_elbow.position = Vector3(0, -0.15 * scale_factor, 0)
	right_arm.add_child(right_elbow)

	var right_forearm = MeshInstance3D.new()
	right_forearm.mesh = arm_mesh
	right_forearm.material_override = skin_mat
	right_forearm.position = Vector3(0, -0.075 * scale_factor, 0)
	right_elbow.add_child(right_forearm)

	head_base_height = 0.99 * scale_factor

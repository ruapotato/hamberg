class_name EnemyAI
extends RefCounted

## EnemyAI - Handles enemy AI state machine and decision making

var enemy: CharacterBody3D

# PERFORMANCE: Static cache for player list (shared across all EnemyAI instances)
# This avoids calling get_nodes_in_group("players") for every enemy every frame
static var _cached_players: Array = []
static var _cache_frame: int = -1  # Engine frame when cache was last updated

# AI States
enum State { IDLE, STALKING, CIRCLING, CHARGING, WINDING_UP, ATTACKING, THROWING, RETREATING }

# State tracking
var current_state: State = State.IDLE
var state_timer: float = 0.0
var target_player: Node = null

# Circle state
var circle_direction: int = 1  # 1 = clockwise, -1 = counter-clockwise
var circle_timer: float = 0.0

# Charge state
var charge_target_pos: Vector3 = Vector3.ZERO
var has_committed_charge: bool = false

# Wander state
var wander_direction: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var wander_pause_timer: float = 0.0
var is_wander_paused: bool = false

func _init(e: CharacterBody3D) -> void:
	enemy = e

# =============================================================================
# MAIN AI UPDATE
# =============================================================================

## Main AI update - call from _physics_process
func update(delta: float) -> void:
	state_timer += delta

	match current_state:
		State.IDLE:
			update_idle(delta)
		State.STALKING:
			update_stalking(delta)
		State.CIRCLING:
			update_circling(delta)
		State.CHARGING:
			update_charging(delta)
		State.WINDING_UP:
			update_winding_up(delta)
		State.ATTACKING:
			update_attacking(delta)
		State.THROWING:
			update_throwing(delta)
		State.RETREATING:
			update_retreating(delta)

# =============================================================================
# STATE TRANSITIONS
# =============================================================================

## Change to a new state
func change_state(new_state: State) -> void:
	if current_state == new_state:
		return

	# Exit current state
	match current_state:
		State.CHARGING:
			has_committed_charge = false

	current_state = new_state
	state_timer = 0.0

	# Enter new state
	match new_state:
		State.CIRCLING:
			circle_direction = 1 if randf() > 0.5 else -1
			circle_timer = randf_range(1.0, 3.0)
		State.CHARGING:
			if target_player:
				charge_target_pos = target_player.global_position
		State.IDLE:
			wander_timer = 0.0
			wander_pause_timer = randf_range(1.0, 3.0)
			is_wander_paused = true

# =============================================================================
# STATE UPDATES
# =============================================================================

## Idle state - wander or look for targets
func update_idle(delta: float) -> void:
	# Look for players
	var nearest = find_nearest_player()
	if nearest and enemy.global_position.distance_to(nearest.global_position) < enemy.detection_range:
		target_player = nearest
		change_state(State.STALKING)
		return

	# Wander behavior
	if is_wander_paused:
		wander_pause_timer -= delta
		if wander_pause_timer <= 0:
			is_wander_paused = false
			wander_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			wander_timer = randf_range(2.0, 5.0)
	else:
		wander_timer -= delta
		if wander_timer <= 0:
			is_wander_paused = true
			wander_pause_timer = randf_range(1.0, 3.0)
		else:
			# Move in wander direction
			enemy.velocity.x = wander_direction.x * enemy.move_speed * 0.5
			enemy.velocity.z = wander_direction.z * enemy.move_speed * 0.5
			face_movement()

## Stalking state - approach target
func update_stalking(delta: float) -> void:
	if not is_instance_valid(target_player):
		change_state(State.IDLE)
		return

	var distance = enemy.global_position.distance_to(target_player.global_position)

	if distance > enemy.detection_range * 1.5:
		target_player = null
		change_state(State.IDLE)
		return

	if distance <= enemy.preferred_distance:
		make_combat_decision()
		return

	# Move toward target
	var dir = (target_player.global_position - enemy.global_position).normalized()
	enemy.velocity.x = dir.x * enemy.move_speed
	enemy.velocity.z = dir.z * enemy.move_speed
	face_target()

## Circling state - strafe around target
func update_circling(delta: float) -> void:
	if not is_instance_valid(target_player):
		change_state(State.IDLE)
		return

	circle_timer -= delta
	if circle_timer <= 0:
		make_combat_decision()
		return

	var distance = enemy.global_position.distance_to(target_player.global_position)

	# Maintain preferred distance while strafing
	var to_target = (target_player.global_position - enemy.global_position).normalized()
	var strafe_dir = Vector3(-to_target.z * circle_direction, 0, to_target.x * circle_direction)

	# Adjust distance
	if distance < enemy.preferred_distance * 0.8:
		strafe_dir -= to_target * 0.5  # Back away
	elif distance > enemy.preferred_distance * 1.2:
		strafe_dir += to_target * 0.5  # Get closer

	enemy.velocity.x = strafe_dir.x * enemy.strafe_speed
	enemy.velocity.z = strafe_dir.z * enemy.strafe_speed
	face_target()

## Charging state - rush at target
func update_charging(_delta: float) -> void:
	if not has_committed_charge:
		has_committed_charge = true
		if target_player:
			charge_target_pos = target_player.global_position

	var distance = enemy.global_position.distance_to(charge_target_pos)

	if distance < enemy.attack_range:
		change_state(State.WINDING_UP)
		return

	if state_timer > 3.0:  # Charge timeout
		change_state(State.CIRCLING)
		return

	# Charge toward target position
	var dir = (charge_target_pos - enemy.global_position).normalized()
	enemy.velocity.x = dir.x * enemy.charge_speed
	enemy.velocity.z = dir.z * enemy.charge_speed
	face_movement()

## Winding up for attack
func update_winding_up(_delta: float) -> void:
	# Stop moving during windup
	enemy.velocity.x = 0
	enemy.velocity.z = 0

	face_target()

	if state_timer >= enemy.windup_time:
		change_state(State.ATTACKING)

## Attacking state
func update_attacking(_delta: float) -> void:
	if state_timer >= 0.3:  # Attack duration
		change_state(State.RETREATING)

## Throwing state
func update_throwing(_delta: float) -> void:
	enemy.velocity.x = 0
	enemy.velocity.z = 0
	face_target()

	if state_timer >= 0.5:
		change_state(State.CIRCLING)

## Retreating state
func update_retreating(_delta: float) -> void:
	if not is_instance_valid(target_player):
		change_state(State.IDLE)
		return

	if state_timer >= 1.0:
		make_combat_decision()
		return

	# Back away from target
	var dir = (enemy.global_position - target_player.global_position).normalized()
	enemy.velocity.x = dir.x * enemy.move_speed
	enemy.velocity.z = dir.z * enemy.move_speed
	face_target()

# =============================================================================
# DECISION MAKING
# =============================================================================

## Make combat decision based on situation
func make_combat_decision() -> void:
	if not is_instance_valid(target_player):
		change_state(State.IDLE)
		return

	var distance = enemy.global_position.distance_to(target_player.global_position)

	# Consider throwing if in range
	if distance >= enemy.throw_min_range and distance <= enemy.throw_range:
		if enemy.throw_cooldown <= 0 and randf() < 0.3:
			change_state(State.THROWING)
			return

	# Consider charging
	if enemy.attack_cooldown <= 0 and randf() < 0.4 + enemy.aggression * 0.3:
		change_state(State.CHARGING)
		return

	# Otherwise circle
	change_state(State.CIRCLING)

# =============================================================================
# HELPERS
# =============================================================================

## Get cached player list (updated once per frame, shared across all enemies)
static func _get_cached_players(tree: SceneTree) -> Array:
	var current_frame := Engine.get_process_frames()

	# Only refresh cache once per frame
	if current_frame != _cache_frame:
		_cache_frame = current_frame
		_cached_players = tree.get_nodes_in_group("players")

	return _cached_players

## Find nearest player (OPTIMIZED - uses cached player list)
func find_nearest_player() -> Node:
	var nearest: Node = null
	var nearest_dist = INF

	# Use cached player list instead of scanning tree every time
	var players := _get_cached_players(enemy.get_tree())

	for player in players:
		if not is_instance_valid(player):
			continue
		if player.is_dead:
			continue

		var dist = enemy.global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player

	return nearest

## Face toward target (add PI since Godot's -Z is forward)
func face_target() -> void:
	if not is_instance_valid(target_player):
		return

	var dir = (target_player.global_position - enemy.global_position).normalized()
	if dir.length() > 0.1:
		enemy.rotation.y = atan2(dir.x, dir.z) + PI

## Face movement direction (add PI since Godot's -Z is forward)
func face_movement() -> void:
	var horizontal_vel = Vector3(enemy.velocity.x, 0, enemy.velocity.z)
	if horizontal_vel.length() > 0.1:
		enemy.rotation.y = atan2(horizontal_vel.x, horizontal_vel.z) + PI

## Get current state as string
func get_state_string() -> String:
	return State.keys()[current_state]

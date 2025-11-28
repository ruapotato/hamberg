extends "res://shared/enemies/enemy.gd"

## PassiveAnimal - Base class for non-aggressive animals
## These animals:
## - Wander peacefully in IDLE state
## - Flee when damaged (RETREATING state)
## - Never attack players
## - Drop meat when killed

# Override AI states for passive animals (only IDLE and RETREATING)
enum PassiveAIState {
	IDLE,           # Peaceful wandering
	FLEEING,        # Running away from danger
}

# Fleeing parameters
var flee_target: Vector3 = Vector3.ZERO
var flee_timer: float = 0.0
var flee_from_player: CharacterBody3D = null  # Track which player to flee from
const FLEE_DURATION: float = 5.0  # How long to flee after being damaged
const FLEE_SPEED_MULTIPLIER: float = 1.5  # Run faster when fleeing

# Skittishness - how easily spooked (can be overridden in subclasses)
var flee_detection_range: float = 8.0  # Start fleeing when player is this close
var is_skittish: bool = false  # If true, flees when player gets too close

func _ready() -> void:
	# Default passive animal stats (override in subclasses)
	enemy_name = "Animal"
	max_health = 30.0
	move_speed = 3.0
	charge_speed = 0.0  # No charging
	strafe_speed = 2.0
	attack_range = 0.0  # No attacks
	detection_range = 15.0  # Aware of players but don't attack
	preferred_distance = 0.0
	throw_range = 0.0  # No throwing
	weapon_id = "fists"  # Needed for base class

	# Call parent ready
	super._ready()

	# Animals are calmer
	aggression = 0.0
	patience = 1.0

	health = max_health

	# Override group - add to animals group
	add_to_group("animals")

## Override AI update - passive animals only wander or flee
func _update_ai(delta: float) -> void:
	if is_stunned:
		velocity.x = 0
		velocity.z = 0
		return

	# Update flee timer
	if flee_timer > 0:
		flee_timer -= delta
		_update_fleeing(delta)
	else:
		_update_idle(delta)

## Override idle to use slower, more peaceful wandering
func _update_idle(delta: float) -> void:
	# Check for nearby players if skittish
	if is_skittish and is_host:
		var nearby_player = _detect_nearby_player()
		if nearby_player:
			_start_fleeing_from(nearby_player)
			return

	# Longer pauses, shorter walking periods for grazing/resting behavior
	if is_wander_paused:
		wander_pause_timer -= delta
		if wander_pause_timer <= 0:
			is_wander_paused = false
			var angle = randf() * TAU
			wander_direction = Vector3(cos(angle), 0, sin(angle))
			wander_timer = randf_range(2.0, 5.0)  # Walk for 2-5 seconds
	else:
		wander_timer -= delta
		if wander_timer <= 0:
			is_wander_paused = true
			wander_pause_timer = randf_range(4.0, 10.0)  # Pause for 4-10 seconds (grazing)
			velocity.x = 0
			velocity.z = 0
			return

	if not is_wander_paused and wander_direction.length() > 0.1:
		velocity.x = wander_direction.x * strafe_speed * 0.5  # Slow wandering
		velocity.z = wander_direction.z * strafe_speed * 0.5
		_face_movement()
	else:
		velocity.x = 0
		velocity.z = 0

	# Set AI state for animation sync
	ai_state = AIState.IDLE

## Detect nearby players within flee detection range
func _detect_nearby_player() -> CharacterBody3D:
	var players = get_tree().get_nodes_in_group("players")
	var nearest_player: CharacterBody3D = null
	var nearest_dist: float = flee_detection_range

	for player in players:
		if not is_instance_valid(player):
			continue
		var dist = global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_player = player

	return nearest_player

## Start fleeing from a specific player
func _start_fleeing_from(player: CharacterBody3D) -> void:
	flee_from_player = player
	flee_timer = FLEE_DURATION
	_update_flee_direction()

## Flee from danger - actively run away from player
func _update_fleeing(delta: float) -> void:
	# Update flee direction to always run away from player
	if flee_from_player and is_instance_valid(flee_from_player):
		_update_flee_direction()

	# Run in flee direction
	var flee_dir = flee_target.normalized()
	var flee_speed = move_speed * FLEE_SPEED_MULTIPLIER

	velocity.x = flee_dir.x * flee_speed
	velocity.z = flee_dir.z * flee_speed
	_face_movement()

	# Add slight randomness to feel more natural (small angle variation)
	if randf() < 0.03:  # 3% chance per frame
		var angle_adjust = randf_range(-0.2, 0.2)
		flee_target = flee_target.rotated(Vector3.UP, angle_adjust)

	# Use RETREATING state for animation sync (existing state in Enemy)
	ai_state = AIState.RETREATING

## Update flee direction to run away from player
func _update_flee_direction() -> void:
	if flee_from_player and is_instance_valid(flee_from_player):
		# Direction AWAY from player
		var away_dir = global_position - flee_from_player.global_position
		away_dir.y = 0
		if away_dir.length() > 0.1:
			flee_target = away_dir.normalized()
		else:
			# Too close, pick random direction
			var angle = randf() * TAU
			flee_target = Vector3(cos(angle), 0, sin(angle))

## Override take_damage to trigger fleeing
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO) -> void:
	# Call parent damage handling
	super.take_damage(damage, knockback, direction)

	# Start fleeing (run away from damage direction)
	flee_timer = FLEE_DURATION
	if direction.length() > 0.1:
		flee_target = -direction.normalized()  # Run opposite to damage direction
	else:
		# Random flee direction if no direction given
		var angle = randf() * TAU
		flee_target = Vector3(cos(angle), 0, sin(angle))

## Override combat decision - passive animals never attack
func _make_combat_decision(_distance: float) -> void:
	# Do nothing - stay in idle/wander
	pass

## Override find nearest player - passive animals don't target players
func _find_nearest_player() -> CharacterBody3D:
	return null  # Never target players

## Override melee attack - passive animals don't attack
func _do_melee_attack() -> void:
	pass  # Do nothing

## Override throwing - passive animals don't throw
func _throw_rock() -> void:
	pass  # Do nothing

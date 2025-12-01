extends CharacterBody3D
class_name AnimatedCharacter

## AnimatedCharacter - Base class for all programmatically animated characters
## Handles walking, attacking, and idle animations for players and enemies

# Animation state
var animation_phase: float = 0.0
var is_attacking: bool = false
var attack_timer: float = 0.0
var is_throwing: bool = false
var throw_timer: float = 0.0

# PERFORMANCE: Animation distance culling
const ANIMATION_CULL_DISTANCE: float = 60.0  # Skip detailed animations beyond this distance
const ANIMATION_DISABLE_DISTANCE: float = 100.0  # Skip all animations beyond this distance
var _anim_cull_check_timer: float = 0.0
const ANIM_CULL_CHECK_INTERVAL: float = 0.25  # Check distance every 0.25s
var _nearest_player_distance: float = 0.0  # Cached distance to nearest player

# Footstep tracking (for sound triggering)
var _prev_leg_sin: float = 0.0  # Previous sin(animation_phase) value for zero-crossing detection

# Stun state
var is_stunned: bool = false
var stun_timer: float = 0.0
const STUN_DURATION: float = 1.5  # How long the stun lasts
const STUN_DAMAGE_MULTIPLIER: float = 1.5  # Extra damage taken while stunned

# Animation configuration (override in subclasses)
@export var walk_speed: float = 5.0
@export var attack_animation_time: float = 0.3  # Match player attack timing
@export var throw_animation_time: float = 0.5  # Throwing animation duration

# Body part references (set by subclasses)
var body_container: Node3D = null
var left_leg: Node3D = null
var right_leg: Node3D = null
var left_arm: Node3D = null
var right_arm: Node3D = null
var torso: Node3D = null
var head: Node3D = null

# Head height (for head bobbing, set by subclasses)
var head_base_height: float = 0.0

# PERFORMANCE: Cached joint references (avoid get_node_or_null every frame)
var _left_knee: Node3D = null
var _right_knee: Node3D = null
var _left_elbow: Node3D = null
var _right_elbow: Node3D = null
var _joints_cached: bool = false

## PERFORMANCE: Cache joint references once (call after body parts are set)
func _cache_joint_nodes() -> void:
	if _joints_cached:
		return
	_joints_cached = true
	if left_leg:
		_left_knee = left_leg.get_node_or_null("Knee")
	if right_leg:
		_right_knee = right_leg.get_node_or_null("Knee")
	if left_arm:
		_left_elbow = left_arm.get_node_or_null("Elbow")
	if right_arm:
		_right_elbow = right_arm.get_node_or_null("Elbow")

## Update all animations - call this in _physics_process
func update_animations(delta: float) -> void:
	if not body_container or not left_leg or not right_leg:
		return

	# PERFORMANCE: Cache joint references on first call
	if not _joints_cached:
		_cache_joint_nodes()

	# PERFORMANCE: Update distance check periodically
	_anim_cull_check_timer += delta
	if _anim_cull_check_timer >= ANIM_CULL_CHECK_INTERVAL:
		_anim_cull_check_timer = 0.0
		_update_nearest_player_distance()

	# PERFORMANCE: Skip all animations if too far from any player
	if _nearest_player_distance > ANIMATION_DISABLE_DISTANCE:
		return

	# Update stun timer
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			stun_timer = 0.0

	# Update attack timer
	if is_attacking:
		attack_timer += delta
		if attack_timer >= attack_animation_time:
			is_attacking = false

	# Update throw timer
	if is_throwing:
		throw_timer += delta
		if throw_timer >= throw_animation_time:
			is_throwing = false

	# Stun animation overrides everything
	if is_stunned:
		_animate_stun(delta)
		return

	# Check if moving based on velocity
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = horizontal_speed > 0.1

	# PERFORMANCE: Use simplified animations when far from player
	var use_detailed_animations := _nearest_player_distance < ANIMATION_CULL_DISTANCE

	if is_moving:
		_animate_walking(delta, horizontal_speed, use_detailed_animations)
	else:
		_animate_idle(delta)

	# Throw animation (overrides arm movement) - has priority over attack
	if is_throwing:
		_animate_throw(delta)
	# Attack animation (overrides arm movement)
	elif is_attacking:
		_animate_attack(delta)

## PERFORMANCE: Cache distance to nearest player (uses EnemyAI's cached player list)
func _update_nearest_player_distance() -> void:
	_nearest_player_distance = INF
	# Use EnemyAI's static cached player list (refreshed once per frame, shared across all)
	var players := EnemyAI._get_cached_players(get_tree())
	for player in players:
		if is_instance_valid(player):
			var dist := global_position.distance_to(player.global_position)
			if dist < _nearest_player_distance:
				_nearest_player_distance = dist

## Animate walking (legs and arms swinging)
## use_detailed: if false, skip expensive secondary animations (elbows, knees, head bob)
func _animate_walking(delta: float, horizontal_speed: float, use_detailed: bool = true) -> void:
	# Accumulate animation phase based on actual movement speed
	# This ensures smooth animations that don't "scramble" during acceleration/deceleration
	var speed_multiplier = horizontal_speed / walk_speed
	animation_phase += delta * 8.0 * speed_multiplier

	var leg_sin = sin(animation_phase)
	var leg_angle = leg_sin * 0.3

	# Detect footsteps via zero-crossing of leg sine wave (only when close)
	if use_detailed and _prev_leg_sin != 0.0:
		if (_prev_leg_sin > 0 and leg_sin <= 0) or (_prev_leg_sin < 0 and leg_sin >= 0):
			_play_footstep()
	_prev_leg_sin = leg_sin
	var arm_angle = sin(animation_phase) * 0.2

	# Legs swing opposite
	left_leg.rotation.x = leg_angle
	right_leg.rotation.x = -leg_angle

	# PERFORMANCE: Skip detailed knee/elbow animations when far away
	if use_detailed:
		# Add natural knee bend - knees bend more when leg is forward
		var knee_angle = sin(animation_phase) * 0.5
		if _left_knee:
			_left_knee.rotation.x = max(0.0, knee_angle)
		if _right_knee:
			_right_knee.rotation.x = max(0.0, -knee_angle)

	# Arms swing opposite to legs
	if left_arm:
		left_arm.rotation.x = -arm_angle
		if use_detailed and _left_elbow:
			_left_elbow.rotation.x = max(0.0, arm_angle * 0.8)
	if right_arm and not is_attacking:
		right_arm.rotation.x = arm_angle
		if use_detailed and _right_elbow:
			_right_elbow.rotation.x = max(0.0, -arm_angle * 0.8)

	# Add subtle torso sway (only when close)
	if use_detailed and torso:
		var sway = sin(animation_phase) * 0.05
		torso.rotation.z = sway

	# Add subtle head bob (only when close)
	if use_detailed and head and head_base_height > 0:
		var bob = sin(animation_phase * 2.0) * 0.015
		head.position.y = head_base_height + bob

## Play a footstep sound - override in subclasses for different surfaces
func _play_footstep() -> void:
	# Default implementation uses grass sound
	if SoundManager:
		SoundManager.play_sound_varied("footstep_grass", global_position, -6.0, 0.15)

## Animate idle (return to neutral, breathing)
func _animate_idle(delta: float) -> void:
	# Standing still - return to neutral and reset animation phase
	animation_phase = 0.0

	if left_leg:
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
		if _left_knee:
			_left_knee.rotation.x = lerp(_left_knee.rotation.x, 0.0, delta * 5.0)
	if right_leg:
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
		if _right_knee:
			_right_knee.rotation.x = lerp(_right_knee.rotation.x, 0.0, delta * 5.0)
	if left_arm:
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5.0)
		if _left_elbow:
			_left_elbow.rotation.x = lerp(_left_elbow.rotation.x, 0.0, delta * 5.0)
	if right_arm:
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5.0)
		if _right_elbow:
			_right_elbow.rotation.x = lerp(_right_elbow.rotation.x, 0.0, delta * 5.0)
	if torso:
		torso.rotation.z = lerp(torso.rotation.z, 0.0, delta * 5.0)

	# Idle breathing (gentle vertical bob)
	if body_container:
		var breathe = sin(Time.get_ticks_msec() / 1000.0 * 2.0) * 0.01
		body_container.position.y = breathe

## Animate attack (arm swing)
func _animate_attack(_delta: float) -> void:
	if not right_arm:
		return

	var attack_progress = attack_timer / attack_animation_time
	# Swing down and back up
	var swing_angle = -sin(attack_progress * PI) * 1.2
	right_arm.rotation.x = swing_angle

	# Elbow extends during attack
	if _right_elbow:
		var elbow_bend = -sin(attack_progress * PI) * 0.6
		_right_elbow.rotation.x = elbow_bend

## Start an attack animation
func start_attack_animation() -> void:
	is_attacking = true
	attack_timer = 0.0

## Animate throw (overhand throwing motion)
func _animate_throw(delta: float) -> void:
	if not right_arm:
		return

	var throw_progress = throw_timer / throw_animation_time

	# Throwing motion: wind up (arm back), then throw forward
	var arm_angle: float
	var elbow_angle: float

	if throw_progress < 0.4:
		# Wind up - arm goes back
		var windup = throw_progress / 0.4
		arm_angle = -windup * 1.5  # Arm rotates backward
		elbow_angle = windup * 0.8  # Elbow bends
	else:
		# Throw - arm comes forward fast
		var throw_phase = (throw_progress - 0.4) / 0.6
		arm_angle = -1.5 + throw_phase * 2.5  # Swing from back to forward
		elbow_angle = 0.8 - throw_phase * 1.0  # Elbow extends

	right_arm.rotation.x = arm_angle

	# Elbow extends during throw
	if _right_elbow:
		_right_elbow.rotation.x = elbow_angle

	# Body leans into throw
	if torso:
		var lean = sin(throw_progress * PI) * 0.2
		torso.rotation.x = lean

## Start a throw animation
func start_throw_animation() -> void:
	is_throwing = true
	throw_timer = 0.0

## Animate stun (wobble effect)
func _animate_stun(delta: float) -> void:
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

## Apply stun to this character
func apply_stun(duration: float = STUN_DURATION) -> void:
	is_stunned = true
	stun_timer = duration
	print("[AnimatedCharacter] Stunned for %.1f seconds!" % duration)

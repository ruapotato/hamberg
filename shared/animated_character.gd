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

## Update all animations - call this in _physics_process
func update_animations(delta: float) -> void:
	if not body_container or not left_leg or not right_leg:
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

	if is_moving:
		_animate_walking(delta, horizontal_speed)
	else:
		_animate_idle(delta)

	# Throw animation (overrides arm movement) - has priority over attack
	if is_throwing:
		_animate_throw(delta)
	# Attack animation (overrides arm movement)
	elif is_attacking:
		_animate_attack(delta)

## Animate walking (legs and arms swinging)
func _animate_walking(delta: float, horizontal_speed: float) -> void:
	# Accumulate animation phase based on actual movement speed
	# This ensures smooth animations that don't "scramble" during acceleration/deceleration
	var speed_multiplier = horizontal_speed / walk_speed
	animation_phase += delta * 8.0 * speed_multiplier

	var leg_angle = sin(animation_phase) * 0.3
	var arm_angle = sin(animation_phase) * 0.2

	# Legs swing opposite with knee articulation
	left_leg.rotation.x = leg_angle
	right_leg.rotation.x = -leg_angle

	# Add natural knee bend - knees bend more when leg is forward
	var knee_angle = sin(animation_phase) * 0.5
	var left_knee = left_leg.get_node_or_null("Knee") if left_leg else null
	var right_knee = right_leg.get_node_or_null("Knee") if right_leg else null
	if left_knee:
		left_knee.rotation.x = max(0.0, knee_angle)  # Only bend forward
	if right_knee:
		right_knee.rotation.x = max(0.0, -knee_angle)  # Only bend forward

	# Arms swing opposite to legs with elbow articulation (natural walking motion)
	if left_arm:
		left_arm.rotation.x = -arm_angle  # Left arm swings opposite to left leg
		var left_elbow = left_arm.get_node_or_null("Elbow")
		if left_elbow:
			# Elbow bends slightly when arm is back
			left_elbow.rotation.x = max(0.0, arm_angle * 0.8)
	if right_arm and not is_attacking:
		right_arm.rotation.x = arm_angle   # Right arm swings opposite to right leg (unless attacking)
		var right_elbow = right_arm.get_node_or_null("Elbow")
		if right_elbow:
			# Elbow bends slightly when arm is back
			right_elbow.rotation.x = max(0.0, -arm_angle * 0.8)

	# Add subtle torso sway
	if torso:
		var sway = sin(animation_phase) * 0.05
		torso.rotation.z = sway

	# Add subtle head bob
	if head and head_base_height > 0:
		var bob = sin(animation_phase * 2.0) * 0.015
		head.position.y = head_base_height + bob

## Animate idle (return to neutral, breathing)
func _animate_idle(delta: float) -> void:
	# Standing still - return to neutral and reset animation phase
	animation_phase = 0.0

	if left_leg:
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
		var left_knee = left_leg.get_node_or_null("Knee")
		if left_knee:
			left_knee.rotation.x = lerp(left_knee.rotation.x, 0.0, delta * 5.0)
	if right_leg:
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
		var right_knee = right_leg.get_node_or_null("Knee")
		if right_knee:
			right_knee.rotation.x = lerp(right_knee.rotation.x, 0.0, delta * 5.0)
	if left_arm:
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5.0)
		var left_elbow = left_arm.get_node_or_null("Elbow")
		if left_elbow:
			left_elbow.rotation.x = lerp(left_elbow.rotation.x, 0.0, delta * 5.0)
	if right_arm:
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5.0)
		var right_elbow = right_arm.get_node_or_null("Elbow")
		if right_elbow:
			right_elbow.rotation.x = lerp(right_elbow.rotation.x, 0.0, delta * 5.0)
	if torso:
		torso.rotation.z = lerp(torso.rotation.z, 0.0, delta * 5.0)

	# Idle breathing (gentle vertical bob)
	if body_container:
		var breathe = sin(Time.get_ticks_msec() / 1000.0 * 2.0) * 0.01
		body_container.position.y = breathe

## Animate attack (arm swing)
func _animate_attack(delta: float) -> void:
	if not right_arm:
		return

	var attack_progress = attack_timer / attack_animation_time
	# Swing down and back up
	var swing_angle = -sin(attack_progress * PI) * 1.2
	right_arm.rotation.x = swing_angle

	# Elbow extends during attack
	var right_elbow = right_arm.get_node_or_null("Elbow")
	if right_elbow:
		var elbow_bend = -sin(attack_progress * PI) * 0.6
		right_elbow.rotation.x = elbow_bend

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
	var right_elbow = right_arm.get_node_or_null("Elbow")
	if right_elbow:
		right_elbow.rotation.x = elbow_angle

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

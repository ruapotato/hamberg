class_name PlayerAnimation
extends RefCounted

## PlayerAnimation - Handles procedural body animations
## Animates legs, arms, and torso based on movement and combat state
## NOTE: This is a complex module - full implementation remains in player.gd for now
## This module provides the interface and key helper functions

const PC = preload("res://shared/player/player_constants.gd")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# MAIN UPDATE (delegates to player.gd for now)
# =============================================================================

## Main animation update - call from _physics_process
## NOTE: Full implementation in player.gd::_update_body_animations()
func update_body_animations(delta: float) -> void:
	# For now, call the original function on player
	# This allows incremental migration
	if player.has_method("_update_body_animations"):
		player._update_body_animations(delta)

# =============================================================================
# ANIMATION TIMERS
# =============================================================================

## Update attack animation timer
func update_attack_timer(delta: float) -> void:
	if player.is_attacking:
		player.attack_timer += delta
		if player.attack_timer >= player.current_attack_animation_time:
			player.is_attacking = false
			player.attack_timer = 0.0
			_reset_weapon_rotation()

## Update special attack animation timer
func update_special_attack_timer(delta: float) -> void:
	if player.is_special_attacking:
		player.special_attack_timer += delta

		if player.is_spinning and player.body_container:
			player.spin_rotation = (player.special_attack_timer / player.current_special_attack_animation_time) * TAU * 1.1
			player.body_container.rotation.y += delta * 15.0
			# Check for spin hits via combat module
			if player.combat:
				player.combat.check_spin_hits()

		if player.special_attack_timer >= player.current_special_attack_animation_time:
			player.is_special_attacking = false
			player.special_attack_timer = 0.0
			if player.is_spinning:
				player.is_spinning = false
				player.spin_hit_times.clear()
				if player.weapon_wrist_pivot:
					player.weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

## Update landing animation timer
func update_landing_timer(delta: float) -> void:
	if player.is_landing:
		player.landing_timer += delta
		if player.landing_timer >= PC.LANDING_ANIMATION_TIME:
			player.is_landing = false
			player.landing_timer = 0.0

# =============================================================================
# ANIMATION HELPERS
# =============================================================================

func _reset_weapon_rotation() -> void:
	if player.equipped_weapon_visual:
		player.equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
	if player.weapon_wrist_pivot:
		player.weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

## Get body part nodes for animation
func get_body_parts() -> Dictionary:
	if not player.body_container:
		return {}

	return {
		"left_leg": player.body_container.get_node_or_null("LeftLeg"),
		"right_leg": player.body_container.get_node_or_null("RightLeg"),
		"left_arm": player.body_container.get_node_or_null("LeftArm"),
		"right_arm": player.body_container.get_node_or_null("RightArm"),
		"hips": player.body_container.get_node_or_null("Hips"),
		"torso": player.body_container.get_node_or_null("Torso"),
		"neck": player.body_container.get_node_or_null("Neck"),
		"head": player.body_container.get_node_or_null("Head"),
	}

## Animate stun wobble effect
func animate_stun(delta: float) -> void:
	if not player.body_container or not player.is_stunned:
		return

	var parts = get_body_parts()
	var wobble_speed = 15.0
	var wobble_intensity = 0.25

	var time = (PC.STUN_DURATION - player.stun_timer) * wobble_speed
	var wobble_x = sin(time) * wobble_intensity
	var wobble_z = cos(time * 1.3) * wobble_intensity

	player.body_container.rotation.x = wobble_x
	player.body_container.rotation.z = wobble_z

	if parts.left_arm:
		parts.left_arm.rotation.x = sin(time * 2.0) * 0.5
	if parts.right_arm:
		parts.right_arm.rotation.x = cos(time * 2.0) * 0.5
	if parts.left_leg:
		parts.left_leg.rotation.x = sin(time * 1.5) * 0.3
	if parts.right_leg:
		parts.right_leg.rotation.x = -sin(time * 1.5) * 0.3

# =============================================================================
# KNIFE ATTACK ANIMATIONS
# =============================================================================

## Animate knife combo attacks
func animate_knife_attack(progress: float, right_arm: Node3D, right_elbow: Node3D) -> void:
	match player.current_combo_animation:
		0:  # Right-to-left slash
			var horizontal = lerp(-1.2, 0.6, progress)
			right_arm.rotation.z = horizontal
			right_arm.rotation.x = -sin(progress * PI) * 0.8
			if right_elbow:
				right_elbow.rotation.x = -sin(progress * PI) * 0.6

		1:  # Left-to-right slash
			var horizontal = lerp(0.6, -1.2, progress)
			right_arm.rotation.z = horizontal
			right_arm.rotation.x = -sin(progress * PI) * 0.8
			if right_elbow:
				right_elbow.rotation.x = -sin(progress * PI) * 0.6

		2:  # Forward jab (finisher)
			right_arm.rotation.x = -sin(progress * PI) * 1.8
			right_arm.rotation.z = -0.3
			if right_elbow:
				right_elbow.rotation.x = -sin(progress * PI) * 0.9

# =============================================================================
# AXE ATTACK ANIMATIONS
# =============================================================================

## Animate axe combo attacks - wide sweeping arcs
func animate_axe_attack(progress: float, right_arm: Node3D, left_arm: Node3D, right_elbow: Node3D, left_elbow: Node3D) -> void:
	if player.weapon_wrist_pivot:
		player.weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

	if player.equipped_weapon_visual:
		player.equipped_weapon_visual.rotation_degrees.x = 180.0

	var windup_end = 0.25

	match player.current_combo_animation:
		0:  # SWEEP RIGHT TO LEFT
			_animate_axe_sweep(progress, windup_end, right_arm, left_arm, right_elbow, left_elbow, true)
		1:  # SWEEP LEFT TO RIGHT
			_animate_axe_sweep(progress, windup_end, right_arm, left_arm, right_elbow, left_elbow, false)
		2:  # OVERHEAD SLAM
			_animate_axe_overhead(progress, windup_end, right_arm, left_arm, right_elbow, left_elbow)

func _animate_axe_sweep(progress: float, windup_end: float, right_arm: Node3D, left_arm: Node3D, right_elbow: Node3D, left_elbow: Node3D, sweep_right: bool) -> void:
	var start_z = -1.6 if sweep_right else 1.0
	var end_z = 1.3 if sweep_right else -1.3

	if progress < windup_end:
		var t = progress / windup_end
		var t_ease = t * t * (3.0 - 2.0 * t)
		right_arm.rotation.x = lerp(0.0, -0.9, t_ease)
		right_arm.rotation.z = lerp(0.0, start_z, t_ease)
		if right_elbow:
			right_elbow.rotation.x = lerp(0.0, -0.7, t_ease)
		if left_arm:
			left_arm.rotation.x = lerp(0.0, -1.0, t_ease)
			left_arm.rotation.z = lerp(0.0, -0.8 if sweep_right else 0.8, t_ease)
		if left_elbow:
			left_elbow.rotation.x = lerp(0.0, -0.9, t_ease)
	else:
		var t = (progress - windup_end) / (1.0 - windup_end)
		var t_power = t * t
		right_arm.rotation.x = lerp(-0.9, -1.0, t_power)
		right_arm.rotation.z = lerp(start_z, end_z, t_power)
		if right_elbow:
			right_elbow.rotation.x = lerp(-0.7, -0.5, t_power)
		if left_arm:
			left_arm.rotation.x = lerp(-1.0, -0.9, t_power)
			left_arm.rotation.z = lerp(-0.8 if sweep_right else 0.8, 0.6 if sweep_right else -0.6, t_power)
		if left_elbow:
			left_elbow.rotation.x = lerp(-0.9, -0.7, t_power)

func _animate_axe_overhead(progress: float, windup_end: float, right_arm: Node3D, left_arm: Node3D, right_elbow: Node3D, left_elbow: Node3D) -> void:
	if progress < windup_end:
		var t = progress / windup_end
		var t_ease = t * t * (3.0 - 2.0 * t)
		right_arm.rotation.x = lerp(0.0, -2.5, t_ease)
		right_arm.rotation.z = lerp(0.0, 0.0, t_ease)
		if right_elbow:
			right_elbow.rotation.x = lerp(0.0, -0.4, t_ease)
		if left_arm:
			left_arm.rotation.x = lerp(0.0, -2.3, t_ease)
			left_arm.rotation.z = lerp(0.0, 0.3, t_ease)
		if left_elbow:
			left_elbow.rotation.x = lerp(0.0, -0.5, t_ease)
	else:
		var t = (progress - windup_end) / (1.0 - windup_end)
		var t_power = t * t * t
		right_arm.rotation.x = lerp(-2.5, 0.5, t_power)
		if right_elbow:
			right_elbow.rotation.x = lerp(-0.4, -0.8, t_power)
		if left_arm:
			left_arm.rotation.x = lerp(-2.3, 0.3, t_power)
		if left_elbow:
			left_elbow.rotation.x = lerp(-0.5, -0.7, t_power)

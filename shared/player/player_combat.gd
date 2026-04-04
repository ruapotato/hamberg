class_name PlayerCombat
extends RefCounted

## PlayerCombat - Handles hitbox-based combat (Valheim-style weapon collision)
## Attack logic and special attacks are in player.gd - this only handles hitbox collision

const WeaponData = preload("res://shared/weapon_data.gd")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# HELPERS
# =============================================================================

func _get_equipped_weapon():
	var weapon_data = null
	if player.equipment:
		weapon_data = player.equipment.get_equipped_weapon()
	if not weapon_data:
		weapon_data = ItemDatabase.get_item("fists")
	return weapon_data

# =============================================================================
# NETWORK DAMAGE
# =============================================================================

## Send enemy damage request to server (includes damage type for resistance calculations)
func send_enemy_damage_request(enemy_network_id: int, damage: float, knockback: float, direction: Vector3, damage_type: int = -1) -> void:
	print("[Combat] Sending damage RPC to server: net_id=%d, damage=%.1f, type=%d" % [enemy_network_id, damage, damage_type])
	var dir_array = [direction.x, direction.y, direction.z]
	NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_network_id, damage, knockback, dir_array, damage_type)

# =============================================================================
# HITBOX-BASED COMBAT (Valheim-style)
# =============================================================================

## Enable weapon hitbox for collision detection during attack swing
func enable_weapon_hitbox() -> void:
	if not player.weapon_hitbox:
		return

	# Clear hit tracking for new swing
	player.hitbox_hit_enemies.clear()
	player.hitbox_active = true

	# Enable hitbox Area3D monitoring
	player.weapon_hitbox.monitoring = true
	var collision_shape = player.weapon_hitbox.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = false

	print("[Combat] Hitbox ENABLED - global_pos: %s, shape_global_pos: %s" % [
		player.weapon_hitbox.global_position,
		collision_shape.global_position if collision_shape else "N/A"
	])

	# Immediately do a shape query to catch enemies already in range
	# (body_entered signal won't fire for bodies already overlapping when monitoring enabled)
	_check_hitbox_overlaps_immediate()

## Disable weapon hitbox after attack swing completes
func disable_weapon_hitbox() -> void:
	if not player.weapon_hitbox:
		return

	player.hitbox_active = false

	# Disable hitbox Area3D monitoring
	player.weapon_hitbox.monitoring = false
	var collision_shape = player.weapon_hitbox.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = true

## Critical hit multiplier
const CRIT_MULTIPLIER: float = 2.5

## Process a hit detected by weapon hitbox collision
func process_hitbox_hit(enemy: Node3D) -> void:
	if not player.is_local_player:
		return

	var weapon_data = _get_equipped_weapon()
	var combo_multiplier := 1.0

	# Calculate combo damage multiplier based on weapon and combo hit
	if player.current_weapon_type == "stone_knife" and player.current_combo_animation == 2:
		combo_multiplier = 1.5  # Knife jab finisher
	elif player.current_weapon_type == "stone_sword" and player.current_combo_animation == 2:
		combo_multiplier = 1.75  # Sword overhead cleave finisher
	elif player.current_weapon_type == "stone_axe" and player.current_combo_animation == 2:
		combo_multiplier = 2.0  # Axe slam finisher

	# Check for critical hit conditions
	var is_critical := false
	var crit_reason := ""

	# Crit 1: Enemy is stunned (after successful parry)
	if "is_stunned" in enemy and enemy.is_stunned:
		is_critical = true
		crit_reason = "PARRY CRIT"

	# Crit 2: Enemy is staggered (vulnerable from accumulated hits)
	if "is_staggered" in enemy and enemy.is_staggered:
		is_critical = true
		crit_reason = "STAGGER CRIT"

	# Crit 3: Stealth attack - enemy hasn't detected player (IDLE state, no target)
	if not is_critical and "ai_state" in enemy:
		# Enemy.AIState.IDLE = 0
		var is_idle = enemy.ai_state == 0
		var has_no_target = not ("target_player" in enemy and enemy.target_player != null)
		if is_idle or has_no_target:
			is_critical = true
			crit_reason = "STEALTH CRIT"

	# Apply critical multiplier
	var final_multiplier := combo_multiplier
	if is_critical:
		final_multiplier *= CRIT_MULTIPLIER

	var damage: float = weapon_data.damage * final_multiplier
	var knockback: float = weapon_data.knockback
	var damage_type: int = weapon_data.damage_type if "damage_type" in weapon_data else -1

	# Calculate hit direction from weapon to enemy
	var hit_direction: Vector3
	if player.weapon_hitbox:
		hit_direction = (enemy.global_position - player.weapon_hitbox.global_position).normalized()
	else:
		hit_direction = (enemy.global_position - player.global_position).normalized()

	# Send damage request to server
	var enemy_network_id = enemy.network_id if "network_id" in enemy else 0
	if enemy_network_id > 0:
		if is_critical:
			print("[Player] %s on %s! (%.1f damage, x%.1f)" % [crit_reason, enemy.name, damage, final_multiplier])
		else:
			print("[Player] HITBOX HIT %s! (%.1f damage)" % [enemy.name, damage])
		send_enemy_damage_request(enemy_network_id, damage, knockback, hit_direction, damage_type)

		# Play hit sound and effect (layered for impact)
		_play_layered_hit_sound(enemy.global_position, is_critical)
		if is_critical:
			_spawn_critical_hit_effect(enemy.global_position, hit_direction)
			_spawn_damage_number(enemy.global_position, damage, true)
		else:
			_spawn_blood_spark_effect(enemy.global_position, hit_direction)
			_spawn_damage_number(enemy.global_position, damage, false)

		# Trigger hit feedback (hitstop + screen shake) for satisfying combat feel
		# Scale intensity based on damage multiplier - crits get extra feedback
		var hit_intensity = clampf(final_multiplier, 1.0, 3.0)
		if is_critical:
			hit_intensity = 3.0  # Max intensity for crits
		if player.has_method("trigger_hit_feedback"):
			player.trigger_hit_feedback(hit_intensity)

## Spawn blood and spark particles at hit position
func _spawn_blood_spark_effect(position: Vector3, direction: Vector3) -> void:
	var BloodSparkScene = preload("res://shared/effects/blood_spark_effect.tscn")
	if BloodSparkScene:
		var effect = BloodSparkScene.instantiate()
		player.get_tree().root.add_child(effect)
		effect.global_position = position
		if effect.has_method("set_hit_direction"):
			effect.set_hit_direction(direction)

## Spawn critical hit effect - bigger, more dramatic particles
func _spawn_critical_hit_effect(position: Vector3, direction: Vector3) -> void:
	var CritEffectScene = preload("res://shared/effects/critical_hit_effect.tscn")
	if CritEffectScene:
		var effect = CritEffectScene.instantiate()
		player.get_tree().root.add_child(effect)
		effect.global_position = position
		if effect.has_method("set_hit_direction"):
			effect.set_hit_direction(direction)

## Get appropriate hit sound based on weapon type
func _get_weapon_hit_sound() -> String:
	match player.current_weapon_type:
		"fists":
			return "punch_hit"
		"stone_axe":
			return "sword_hit"  # Heavy chop
		"stone_knife":
			return "sword_hit"  # Quick slash
		_:
			return "sword_hit"

## Get appropriate swing sound based on weapon type
func _get_weapon_swing_sound() -> String:
	match player.current_weapon_type:
		"fists":
			return "punch_swing"
		_:
			return "sword_swing"

## Play layered impact sound for weapon hits (adds depth with overlapping sounds)
func _play_layered_hit_sound(position: Vector3, is_crit: bool) -> void:
	var hit_sound := _get_weapon_hit_sound()
	if is_crit:
		# Critical hit: dedicated crit sound + layered impact at varied pitches
		SoundManager.play_sound_varied("critical_hit", position, 2.0, 0.15)
		SoundManager.play_sound_varied(hit_sound, position, 1.0, 0.2)
	else:
		# Normal hit: base hit + subtle layered thud for weight
		SoundManager.play_sound_varied(hit_sound, position, 0.0, 0.15)
		# Layer a low-pitched punch_hit for bass impact on heavy weapons
		match player.current_weapon_type:
			"stone_axe":
				SoundManager.play_sound("punch_hit", position, -4.0, randf_range(0.6, 0.75))
			"stone_sword":
				SoundManager.play_sound("punch_hit", position, -6.0, randf_range(0.7, 0.85))

## Spawn floating damage number at hit position
func _spawn_damage_number(position: Vector3, damage: float, is_crit: bool) -> void:
	var DamageNumberScene = preload("res://shared/effects/damage_number.tscn")
	if DamageNumberScene:
		var number = DamageNumberScene.instantiate()
		player.get_tree().root.add_child(number)
		number.global_position = position + Vector3(0, 0.5, 0)  # Offset above hit point
		if number.has_method("setup"):
			number.setup(damage, is_crit)

## Update hitbox state during attack animation
## Called each physics frame during attack
func update_hitbox_during_attack() -> void:
	if not player.is_attacking and not player.is_special_attacking:
		if player.hitbox_active:
			disable_weapon_hitbox()
		return

	# Calculate attack progress
	var progress: float
	if player.is_attacking:
		progress = player.attack_timer / player.current_attack_animation_time
	else:
		progress = player.special_attack_timer / player.current_special_attack_animation_time

	# Define hitbox active window based on weapon type
	# This is when the weapon is actually swinging through the arc
	# Widened windows for more forgiving hit detection
	var active_start: float
	var active_end: float

	match player.current_weapon_type:
		"stone_knife":
			# Knife is fast - active most of swing
			active_start = 0.10
			active_end = 0.90
		"stone_axe":
			# Axe has windup then powerful swing
			active_start = 0.15  # Earlier start for better feel
			active_end = 0.95
		_:
			# Default (sword) - balanced timing
			active_start = 0.10
			active_end = 0.90

	# Enable or disable hitbox based on attack progress
	var should_be_active = progress >= active_start and progress <= active_end

	if should_be_active and not player.hitbox_active:
		enable_weapon_hitbox()
	elif not should_be_active and player.hitbox_active:
		disable_weapon_hitbox()

	# DEBUG: Periodically check for overlapping bodies during active window
	if player.hitbox_active and player.weapon_hitbox:
		# Force physics update to ensure overlaps are detected
		player.weapon_hitbox.force_update_transform()
		var overlapping = player.weapon_hitbox.get_overlapping_bodies()
		if overlapping.size() > 0:
			print("[Combat] Overlapping bodies during attack: %s" % str(overlapping))
			for body in overlapping:
				if body.has_method("take_damage") and body.collision_layer & 4:
					var enemy_id = body.get_instance_id()
					if not enemy_id in player.hitbox_hit_enemies:
						player.hitbox_hit_enemies.append(enemy_id)
						print("[Combat] Manual overlap hit: %s" % body.name)
						process_hitbox_hit(body)

		# Also do a manual shape query using the ACTUAL hitbox shape and transform
		var space_state = player.get_world_3d().direct_space_state
		if space_state:
			var collision_shape = player.weapon_hitbox.get_node_or_null("CollisionShape3D")
			if collision_shape and collision_shape.shape:
				# Force transform update on collision shape too
				collision_shape.force_update_transform()

				var query = PhysicsShapeQueryParameters3D.new()
				# Use the actual shape from the weapon's CollisionShape3D
				query.shape = collision_shape.shape
				# Use the CollisionShape3D's GLOBAL transform (includes rotation and position)
				query.transform = collision_shape.global_transform
				query.collision_mask = 4  # Enemies layer
				query.exclude = [player]

				var results = space_state.intersect_shape(query, 8)
				for result in results:
					var body = result.collider
					if body and body.has_method("take_damage"):
						var enemy_id = body.get_instance_id()
						if not enemy_id in player.hitbox_hit_enemies:
							player.hitbox_hit_enemies.append(enemy_id)
							print("[Combat] Shape query hit: %s" % body.name)
							process_hitbox_hit(body)

## Immediate shape query when hitbox is first enabled
## This catches enemies that are already in the hitbox area before Area3D monitoring started
func _check_hitbox_overlaps_immediate() -> void:
	if not player.weapon_hitbox:
		return

	var space_state = player.get_world_3d().direct_space_state
	if not space_state:
		return

	var collision_shape = player.weapon_hitbox.get_node_or_null("CollisionShape3D")
	if not collision_shape or not collision_shape.shape:
		return

	# Force transform update to get current position after animation
	player.weapon_hitbox.force_update_transform()
	collision_shape.force_update_transform()

	# Debug: Check nearest enemies and distances
	var enemies = EnemyAI._get_cached_enemies(player.get_tree())
	var shape_pos = collision_shape.global_position
	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist = enemy.global_position.distance_to(shape_pos)
			if dist < 3.0:  # Only log nearby enemies
				print("[Combat DEBUG] Nearby enemy %s at dist %.2f, enemy_pos: %s, shape_pos: %s" % [
					enemy.name, dist, enemy.global_position, shape_pos
				])

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = 4  # Enemies layer
	query.exclude = [player]

	var results = space_state.intersect_shape(query, 8)
	if results.size() == 0:
		# Debug: no hits - check what the shape actually covers
		if collision_shape.shape is CapsuleShape3D:
			var cap = collision_shape.shape as CapsuleShape3D
			print("[Combat DEBUG] Capsule query: radius=%.2f, height=%.2f, transform=%s" % [
				cap.radius, cap.height, collision_shape.global_transform
			])

	for result in results:
		var body = result.collider
		if body and body.has_method("take_damage"):
			var enemy_id = body.get_instance_id()
			if not enemy_id in player.hitbox_hit_enemies:
				player.hitbox_hit_enemies.append(enemy_id)
				print("[Combat] Immediate shape query hit: %s" % body.name)
				process_hitbox_hit(body)

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
		print("[Combat] WARNING: No weapon hitbox to enable!")
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

## Process a hit detected by weapon hitbox collision
func process_hitbox_hit(enemy: Node3D) -> void:
	if not player.is_local_player:
		return

	var weapon_data = _get_equipped_weapon()
	var combo_multiplier := 1.0

	# Calculate combo damage multiplier
	if player.current_weapon_type == "stone_knife" and player.current_combo_animation == 2:
		combo_multiplier = 1.5
	elif player.current_weapon_type == "stone_axe" and player.current_combo_animation == 2:
		combo_multiplier = 2.0

	var damage: float = weapon_data.damage * combo_multiplier
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
		print("[Player] HITBOX HIT %s! (%.1f damage)" % [enemy.name, damage])
		send_enemy_damage_request(enemy_network_id, damage, knockback, hit_direction, damage_type)

		# Play hit sound and effect
		SoundManager.play_sound_varied("sword_hit", enemy.global_position)
		_spawn_hit_effect(enemy.global_position)

## Spawn hit effect at position
func _spawn_hit_effect(position: Vector3) -> void:
	var HitEffectScene = preload("res://shared/effects/hit_effect.tscn")
	if HitEffectScene:
		var effect = HitEffectScene.instantiate()
		player.get_tree().root.add_child(effect)
		effect.global_position = position

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
	var active_start: float
	var active_end: float

	match player.current_weapon_type:
		"stone_knife":
			# Knife is fast - active most of swing
			active_start = 0.15
			active_end = 0.85
		"stone_axe":
			# Axe has windup then powerful swing
			active_start = 0.25  # After windup
			active_end = 0.90
		_:
			# Default (sword) - balanced timing
			active_start = 0.20
			active_end = 0.80

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

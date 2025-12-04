class_name PlayerCombat
extends RefCounted

## PlayerCombat - Handles attacks, combos, special attacks, and damage dealing
## Works with weapons, projectiles, and melee combat

const PC = preload("res://shared/player/player_constants.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const Projectile = preload("res://shared/projectiles/projectile.gd")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# MAIN ATTACK HANDLING
# =============================================================================

## Handle attack input (CLIENT-SIDE)
func handle_attack() -> void:
	if not player.is_local_player or player.is_dead:
		return

	# Check if blocking (can't attack while blocking)
	if player.is_blocking:
		return

	# Get equipped weapon (or default to fists)
	var weapon_data = _get_equipped_weapon()

	# Handle combo system
	var combo_multiplier := _handle_combo_system(weapon_data)

	# Set animation speed based on weapon type
	_set_attack_animation_time(weapon_data)

	# Use weapon stats
	var damage: float = weapon_data.damage * combo_multiplier
	var knockback: float = weapon_data.knockback
	var stamina_cost: float = weapon_data.stamina_cost
	var attack_range: float = 5.0

	# Check resource cost
	if not _consume_attack_resource(weapon_data, stamina_cost):
		return

	# Trigger attack animation
	player.is_attacking = true
	player.attack_timer = 0.0

	# Play attack sound
	_play_attack_sound(weapon_data)

	# Get camera for raycasting/aiming
	var camera := _get_camera()
	if not camera:
		print("[Player] No camera found for attack")
		return

	# Rotate player mesh to face attack direction
	_rotate_to_attack_direction()

	# Perform attack based on weapon type
	var is_ranged = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC or weapon_data.weapon_type == WeaponData.WeaponType.RANGED

	if is_ranged:
		spawn_projectile(weapon_data, camera)
	else:
		_perform_melee_area_attack(camera, attack_range, damage, knockback, weapon_data)

## Handle special attack input (CLIENT-SIDE) - Middle mouse button
func handle_special_attack() -> void:
	if not player.is_local_player or player.is_dead:
		return

	if player.is_blocking:
		return

	var weapon_data = _get_equipped_weapon()

	var camera := _get_camera()
	if not camera:
		return

	# Reset combo on special attack
	player.combo_count = 0
	player.combo_timer = 0.0

	# Different special attacks based on weapon type
	match weapon_data.item_id:
		"stone_knife":
			_special_attack_knife_lunge(weapon_data, camera)
		"stone_sword":
			_special_attack_sword_stab(weapon_data, camera)
		"stone_axe":
			_special_attack_axe_spin(weapon_data, camera)
		"fire_wand":
			_special_attack_fire_wand_area(weapon_data)
		_:
			_special_attack_default(weapon_data, camera)

# =============================================================================
# COMBO SYSTEM
# =============================================================================

## Handle combo logic for weapons, returns damage multiplier
func _handle_combo_system(weapon_data) -> float:
	var is_knife = weapon_data.item_id == "stone_knife"
	var is_axe = weapon_data.item_id == "stone_axe"
	var combo_multiplier: float = 1.0

	player.current_weapon_type = weapon_data.item_id

	if is_knife:
		player.current_combo_animation = player.combo_count

		if player.combo_count == 2:
			combo_multiplier = 1.5
			print("[Player] Knife combo FINISHER - Forward JAB!")
			if player.equipped_weapon_visual:
				player.equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)
		else:
			if player.equipped_weapon_visual:
				player.equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)

		player.combo_count = (player.combo_count + 1) % PC.MAX_COMBO
		player.combo_timer = PC.COMBO_WINDOW

	elif is_axe:
		player.current_combo_animation = player.combo_count

		if player.combo_count == 2:
			combo_multiplier = 2.0
			print("[Player] Axe combo FINISHER - OVERHEAD SLAM!")

		player.combo_count = (player.combo_count + 1) % PC.MAX_COMBO
		player.combo_timer = PC.COMBO_WINDOW

	else:
		player.current_combo_animation = 0
		player.combo_count = 0
		player.combo_timer = 0.0

		if player.equipped_weapon_visual:
			player.equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
		if player.weapon_wrist_pivot:
			player.weapon_wrist_pivot.rotation_degrees = Vector3.ZERO

	return combo_multiplier

## Update combo timer
func update_combo(delta: float) -> void:
	if player.combo_timer > 0:
		player.combo_timer -= delta
		if player.combo_timer <= 0:
			player.combo_count = 0
			player.combo_timer = 0.0

# =============================================================================
# SPECIAL ATTACKS
# =============================================================================

## Knife special: Lunge forward jab
func _special_attack_knife_lunge(weapon_data, camera: Camera3D) -> void:
	var stamina_cost: float = 25.0
	var damage: float = weapon_data.damage * 2.5
	var knockback: float = weapon_data.knockback * 1.5

	if not player.resources.consume_stamina(stamina_cost):
		print("[Player] Not enough stamina for knife lunge!")
		return

	# LEAP forward
	var camera_forward = -camera.global_transform.basis.z
	var horizontal_direction = Vector3(camera_forward.x, 0, camera_forward.z).normalized()

	player.lunge_direction = horizontal_direction
	player.lunge_damage = damage
	player.lunge_knockback = knockback
	player.lunge_hit_enemies.clear()

	player.velocity = horizontal_direction * 5.0
	player.velocity.y = 9.0

	player.is_special_attacking = true
	player.is_lunging = true
	player.was_in_air_lunging = false
	player.special_attack_timer = 0.0
	player.current_special_attack_animation_time = PC.KNIFE_SPECIAL_ANIMATION_TIME

	_rotate_to_attack_direction()

	if player.equipped_weapon_visual:
		player.equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)

## Sword special: Stab forward
func _special_attack_sword_stab(weapon_data, camera: Camera3D) -> void:
	var stamina_cost: float = 20.0
	var damage: float = weapon_data.damage * 2.2
	var knockback: float = weapon_data.knockback * 0.5
	var attack_range: float = 6.5

	if not player.resources.consume_stamina(stamina_cost):
		return

	player.is_special_attacking = true
	player.special_attack_timer = 0.0
	player.current_special_attack_animation_time = PC.SWORD_SPECIAL_ANIMATION_TIME

	_rotate_to_attack_direction()

	if player.equipped_weapon_visual:
		player.equipped_weapon_visual.rotation_degrees = Vector3(0, 0, 0)

	perform_melee_attack(camera, attack_range, damage, knockback, weapon_data)

## Axe special: Spinning whirlwind attack
func _special_attack_axe_spin(weapon_data, _camera: Camera3D) -> void:
	var stamina_cost: float = 35.0
	var damage: float = weapon_data.damage * 1.5
	var knockback: float = weapon_data.knockback * 2.0

	if not player.resources.consume_stamina(stamina_cost):
		return

	player.is_special_attacking = true
	player.is_spinning = true
	player.spin_rotation = 0.0
	player.spin_hit_times.clear()
	player.special_attack_timer = 0.0
	player.current_special_attack_animation_time = PC.AXE_SPECIAL_ANIMATION_TIME

	player.lunge_damage = damage
	player.lunge_knockback = knockback

	_rotate_to_attack_direction()
	SoundManager.play_sound_varied("sword_swing", player.global_position)

## Fire wand special: Area fire effect
func _special_attack_fire_wand_area(weapon_data) -> void:
	var brain_power_cost: float = 25.0
	var damage: float = weapon_data.damage * 0.4
	var area_radius: float = 3.5
	var duration: float = 3.0

	if not player.resources.consume_brain_power(brain_power_cost):
		return

	player.is_special_attacking = true
	player.special_attack_timer = 0.0

	var fire_area_scene = load("res://shared/effects/fire_area.tscn")
	var fire_area = fire_area_scene.instantiate()
	fire_area.radius = area_radius
	fire_area.damage = damage
	fire_area.duration = duration
	player.get_tree().root.add_child(fire_area)
	fire_area.global_position = player.global_position

## Default special attack (1.5x damage)
func _special_attack_default(weapon_data, camera: Camera3D) -> void:
	var resource_cost: float = weapon_data.stamina_cost * 2.0
	var damage: float = weapon_data.damage * 1.5
	var knockback: float = weapon_data.knockback
	var attack_range: float = 5.0

	var is_magic = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC
	if is_magic:
		if not player.resources.consume_brain_power(resource_cost):
			return
		SoundManager.play_sound_varied("fire_cast", player.global_position)
	else:
		if not player.resources.consume_stamina(resource_cost):
			return

	player.is_special_attacking = true
	player.special_attack_timer = 0.0

	_rotate_to_attack_direction()

	var is_ranged = is_magic or weapon_data.weapon_type == WeaponData.WeaponType.RANGED
	if is_ranged:
		spawn_projectile(weapon_data, camera)
	else:
		perform_melee_attack(camera, attack_range, damage, knockback, weapon_data)

# =============================================================================
# MELEE ATTACKS
# =============================================================================

## Perform area-based melee attack
## Enemies are now detected via hitbox collision (Valheim-style)
## This function now handles environmental objects (trees, rocks) via raycast
func _perform_melee_area_attack(camera: Camera3D, attack_range: float, damage: float, _knockback: float, weapon_data) -> void:
	var viewport_size := player.get_viewport().get_visible_rect().size
	var crosshair_offset := Vector2(-41.0, -50.0)
	var crosshair_pos := viewport_size / 2 + crosshair_offset
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	# Enemy detection is now handled by weapon hitbox collision (Valheim-style)
	# Only check environmental objects here (trees, rocks, etc.)
	_check_environmental_hit(ray_origin, ray_direction, attack_range, damage, weapon_data)

## Perform raycast melee attack for environmental objects
## Enemies are now detected via hitbox collision (Valheim-style)
func perform_melee_attack(camera: Camera3D, attack_range: float, damage: float, _knockback: float, weapon_data = null) -> void:
	var viewport_size := player.get_viewport().get_visible_rect().size
	var crosshair_offset := Vector2(-41.0, -50.0)
	var crosshair_pos := viewport_size / 2 + crosshair_offset
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	# Enemy detection is now handled by weapon hitbox collision (Valheim-style)
	# Only check environmental objects here
	_check_environmental_hit(ray_origin, ray_direction, attack_range, damage, weapon_data)

## Check for environmental object hits
func _check_environmental_hit(ray_origin: Vector3, ray_direction: Vector3, attack_range: float, damage: float, weapon_data) -> void:
	var ray_end := ray_origin + ray_direction * attack_range

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # World layer only
	query.exclude = [player]

	var result := space_state.intersect_ray(query)
	if not result:
		return

	var hit_object: Object = result.collider
	if not hit_object.has_method("get_object_type"):
		return

	var object_type: String = hit_object.get_object_type()
	var tool_type: String = weapon_data.tool_type if "tool_type" in weapon_data else ""

	# Check tool requirement
	if hit_object.has_method("can_be_damaged_by"):
		if not hit_object.can_be_damaged_by(tool_type):
			var required_tool: String = hit_object.get_required_tool_type() if hit_object.has_method("get_required_tool_type") else "unknown"
			print("[Player] Cannot damage %s - requires %s!" % [object_type, required_tool])
			SoundManager.play_sound_varied("wrong_tool", player.global_position)
			return

	var hit_node := hit_object as Node3D
	var object_name: String = hit_node.name if hit_node else ""
	var is_dynamic := object_name.begins_with("FallenLog_") or object_name.begins_with("SplitLog_")

	if is_dynamic:
		send_dynamic_damage_request(object_name, damage, result.position)
	elif hit_object.has_method("get_object_id"):
		var object_id: int = hit_object.get_object_id()
		var chunk_pos: Vector2i = hit_object.chunk_position if "chunk_position" in hit_object else Vector2i.ZERO
		send_damage_request(chunk_pos, object_id, damage, result.position)

# =============================================================================
# LUNGE & SPIN ATTACKS
# =============================================================================

## Check for enemy collisions during lunge
func check_lunge_collision() -> void:
	if player.lunge_damage <= 0:
		return

	var weapon_data = _get_equipped_weapon()
	var damage_type: int = weapon_data.damage_type if weapon_data and "damage_type" in weapon_data else -1

	var enemies = EnemyAI._get_cached_enemies(player.get_tree())
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var enemy_id = enemy.get_instance_id()
		if enemy_id in player.lunge_hit_enemies:
			continue

		var distance = enemy.global_position.distance_to(player.global_position)
		if distance <= PC.LUNGE_HIT_RADIUS:
			player.lunge_hit_enemies.append(enemy_id)

			var direction = player.lunge_direction if player.lunge_direction != Vector3.ZERO else (enemy.global_position - player.global_position).normalized()
			var enemy_network_id = enemy.network_id if "network_id" in enemy else 0
			if enemy_network_id > 0:
				print("[Player] LUNGE HIT %s! (%.1f damage)" % [enemy.name, player.lunge_damage])
				send_enemy_damage_request(enemy_network_id, player.lunge_damage, player.lunge_knockback, direction, damage_type)

## Check for hits during axe spin attack
func check_spin_hits() -> void:
	if not player.is_local_player:
		return

	var spin_radius = 3.5
	var hit_cooldown = 0.25
	var spin_damage = player.lunge_damage * 0.4
	var current_time = Time.get_ticks_msec() / 1000.0

	var weapon_data = _get_equipped_weapon()
	var tool_type: String = weapon_data.tool_type if weapon_data and "tool_type" in weapon_data else ""
	var damage_type: int = weapon_data.damage_type if weapon_data and "damage_type" in weapon_data else -1

	# Check enemies (using cached list)
	var enemies = EnemyAI._get_cached_enemies(player.get_tree())
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var distance = enemy.global_position.distance_to(player.global_position)
		if distance <= spin_radius:
			var enemy_id = enemy.get_instance_id()
			var enemy_network_id = enemy.network_id if "network_id" in enemy else 0
			var last_hit_time = player.spin_hit_times.get(enemy_id, 0.0)

			if current_time - last_hit_time >= hit_cooldown:
				player.spin_hit_times[enemy_id] = current_time
				if enemy_network_id > 0:
					var hit_direction = (enemy.global_position - player.global_position).normalized()
					send_enemy_damage_request(enemy_network_id, spin_damage, player.lunge_knockback, hit_direction, damage_type)
					SoundManager.play_sound_varied("sword_swing", player.global_position)

	# Check environmental objects
	_check_spin_environmental_hits(spin_radius, hit_cooldown, spin_damage, current_time, tool_type)

func _check_spin_environmental_hits(spin_radius: float, hit_cooldown: float, spin_damage: float, current_time: float, tool_type: String) -> void:
	var space_state = player.get_world_3d().direct_space_state
	var shape = SphereShape3D.new()
	shape.radius = spin_radius
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3(0, 1, 0))
	query.collision_mask = 1

	var results = space_state.intersect_shape(query, 32)
	for result in results:
		var hit_object = result.collider
		if not is_instance_valid(hit_object):
			continue

		if not hit_object.has_method("get_object_type"):
			continue

		var obj_id = hit_object.get_instance_id()
		var last_hit_time = player.spin_hit_times.get(obj_id, 0.0)
		if current_time - last_hit_time < hit_cooldown:
			continue

		if hit_object.has_method("can_be_damaged_by"):
			if not hit_object.can_be_damaged_by(tool_type):
				continue

		player.spin_hit_times[obj_id] = current_time

		var hit_node := hit_object as Node3D
		var object_name: String = hit_node.name if hit_node else ""
		var is_dynamic := object_name.begins_with("FallenLog_") or object_name.begins_with("SplitLog_")

		if is_dynamic:
			send_dynamic_damage_request(object_name, spin_damage, hit_node.global_position)
		elif hit_object.has_method("get_object_id"):
			var object_id: int = hit_object.get_object_id()
			var chunk_pos: Vector2i = hit_object.chunk_position if "chunk_position" in hit_object else Vector2i.ZERO
			send_damage_request(chunk_pos, object_id, spin_damage, hit_node.global_position)

		SoundManager.play_sound_varied("wood_hit", player.global_position)

# =============================================================================
# PROJECTILES
# =============================================================================

## Spawn a projectile for ranged weapons
func spawn_projectile(weapon_data, camera: Camera3D) -> void:
	if not weapon_data.projectile_scene:
		return

	var spawn_pos := player.global_position + Vector3(0, 1.5, 0)

	if player.equipped_weapon_visual and is_instance_valid(player.equipped_weapon_visual):
		if player.equipped_weapon_visual.has_node("Tip"):
			spawn_pos = player.equipped_weapon_visual.get_node("Tip").global_position
		else:
			spawn_pos = player.equipped_weapon_visual.global_position
			spawn_pos += player.equipped_weapon_visual.global_transform.basis.z * 0.3

	var viewport_size := player.get_viewport().get_visible_rect().size
	var crosshair_offset := Vector2(-41.0, -50.0)
	var crosshair_pos := viewport_size / 2 + crosshair_offset
	var ray_origin := camera.project_ray_origin(crosshair_pos)
	var ray_direction := camera.project_ray_normal(crosshair_pos)

	var target_pos := ray_origin + ray_direction * 100.0

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 100.0)
	query.collision_mask = 1 | 2 | 4
	query.exclude = [player]

	var result := space_state.intersect_ray(query)
	if result:
		target_pos = result.position

	var direction := (target_pos - spawn_pos).normalized()
	var projectile: Projectile = weapon_data.projectile_scene.instantiate()
	player.get_tree().root.add_child(projectile)

	var speed: float = weapon_data.projectile_speed if weapon_data.projectile_speed > 0 else 30.0
	var damage_type: int = weapon_data.damage_type if "damage_type" in weapon_data else -1
	projectile.setup(spawn_pos, direction, speed, weapon_data.damage, player.get_instance_id(), damage_type)

# =============================================================================
# NETWORK DAMAGE
# =============================================================================

## Send damage request to server for environmental objects
func send_damage_request(chunk_pos: Vector2i, object_id: int, damage: float, hit_position: Vector3) -> void:
	NetworkManager.rpc_damage_environmental_object.rpc_id(1, [chunk_pos.x, chunk_pos.y], object_id, damage, hit_position)

## Send damage request for dynamic objects
func send_dynamic_damage_request(object_name: String, damage: float, hit_position: Vector3) -> void:
	NetworkManager.rpc_damage_dynamic_object.rpc_id(1, object_name, damage, hit_position)

## Send enemy damage request to server (includes damage type for resistance calculations)
func send_enemy_damage_request(enemy_network_id: int, damage: float, knockback: float, direction: Vector3, damage_type: int = -1) -> void:
	var dir_array = [direction.x, direction.y, direction.z]
	NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_network_id, damage, knockback, dir_array, damage_type)

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

func _get_camera() -> Camera3D:
	var camera_controller := player.get_node_or_null("CameraController")
	if camera_controller and camera_controller.has_method("get_camera"):
		return camera_controller.get_camera()
	return null

func _consume_attack_resource(weapon_data, cost: float) -> bool:
	var is_magic = weapon_data.weapon_type == WeaponData.WeaponType.MAGIC
	if is_magic:
		if not player.resources.consume_brain_power(cost):
			print("[Player] Not enough brain power to attack!")
			return false
	else:
		if not player.resources.consume_stamina(cost):
			print("[Player] Not enough stamina to attack!")
			return false
	return true

func _set_attack_animation_time(weapon_data) -> void:
	match weapon_data.item_id:
		"stone_knife":
			player.current_attack_animation_time = PC.KNIFE_ANIMATION_TIME
		"stone_sword":
			player.current_attack_animation_time = PC.SWORD_ANIMATION_TIME
		"stone_axe":
			player.current_attack_animation_time = PC.AXE_ANIMATION_TIME
		_:
			player.current_attack_animation_time = PC.ATTACK_ANIMATION_TIME

func _play_attack_sound(weapon_data) -> void:
	if player.equipped_weapon_visual:
		if weapon_data.weapon_type == WeaponData.WeaponType.MAGIC:
			SoundManager.play_sound_varied("fire_cast", player.global_position)
		else:
			SoundManager.play_sound_varied("sword_swing", player.global_position)
	else:
		SoundManager.play_sound_varied("punch_swing", player.global_position)

func _rotate_to_attack_direction() -> void:
	if not player.is_local_player or not player.body_container:
		return
	var camera_controller = player.get_node_or_null("CameraController")
	if camera_controller and "camera_rotation" in camera_controller:
		var camera_yaw = camera_controller.camera_rotation.x
		player.body_container.rotation.y = camera_yaw + PI

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

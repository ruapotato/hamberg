class_name EnemyCombat
extends RefCounted

## EnemyCombat - Handles enemy attack logic and damage dealing

var enemy: CharacterBody3D

# Cooldowns
var attack_cooldown: float = 0.0
var throw_cooldown: float = 0.0

# Projectile scene
const ThrownRock = preload("res://shared/projectiles/thrown_rock.tscn")

func _init(e: CharacterBody3D) -> void:
	enemy = e

# =============================================================================
# UPDATE
# =============================================================================

## Update cooldowns
func update(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if throw_cooldown > 0:
		throw_cooldown -= delta

# =============================================================================
# MELEE ATTACK
# =============================================================================

## Perform melee attack (called when in ATTACKING state)
func do_melee_attack() -> void:
	if attack_cooldown > 0:
		return

	attack_cooldown = enemy.attack_cooldown_time

	# Play attack animation
	if enemy.has_method("play_attack_animation"):
		enemy.play_attack_animation()

	# Find target player
	var target = get_attack_target()
	if not target:
		return

	var distance = enemy.global_position.distance_to(target.global_position)
	if distance > enemy.attack_range:
		return

	# Deal damage
	var damage = enemy.weapon_data.damage if enemy.weapon_data else 10.0
	var knockback = enemy.weapon_data.knockback if enemy.weapon_data else 5.0

	var knockback_dir = (target.global_position - enemy.global_position).normalized()

	# For host client, deal damage directly
	if enemy.is_host:
		if target.has_method("take_damage"):
			target.take_damage(damage, enemy.get_instance_id(), knockback_dir * knockback)
			print("[Enemy] Dealt %.1f damage to %s" % [damage, target.name])

## Check for melee damage (for non-host clients)
func check_local_melee_damage() -> void:
	var local_player = get_local_player()
	if not local_player:
		return

	var distance = enemy.global_position.distance_to(local_player.global_position)
	if distance > enemy.attack_range * 1.2:
		return

	# Send damage notification to server
	var damage = enemy.weapon_data.damage if enemy.weapon_data else 10.0
	var knockback_dir = (local_player.global_position - enemy.global_position).normalized()

	NetworkManager.rpc_enemy_damage_player.rpc_id(1, enemy.network_id, damage, [knockback_dir.x, knockback_dir.y, knockback_dir.z])

# =============================================================================
# RANGED ATTACK
# =============================================================================

## Throw a rock at target
func throw_rock() -> void:
	if throw_cooldown > 0:
		return

	throw_cooldown = enemy.throw_cooldown_time

	var target = get_attack_target()
	if not target:
		return

	# Calculate throw direction (aim at target with some prediction)
	var spawn_pos = enemy.global_position + Vector3(0, 1.5, 0)
	var target_pos = target.global_position + Vector3(0, 1.0, 0)

	# Add prediction based on target velocity
	if "velocity" in target:
		var flight_time = spawn_pos.distance_to(target_pos) / enemy.rock_speed
		target_pos += target.velocity * flight_time * 0.5

	var direction = (target_pos - spawn_pos).normalized()

	# Spawn projectile
	var rock = ThrownRock.instantiate()
	enemy.get_tree().root.add_child(rock)

	rock.setup(spawn_pos, direction, enemy.rock_speed, enemy.rock_damage, enemy.get_instance_id())

	print("[Enemy] Threw rock at %s" % target.name)

# =============================================================================
# HELPERS
# =============================================================================

## Get current attack target
func get_attack_target() -> Node:
	if enemy.ai and enemy.ai.target_player:
		return enemy.ai.target_player
	return get_local_player()

## Get local player (uses cached player list)
func get_local_player() -> Node:
	for player in EnemyAI._get_cached_players(enemy.get_tree()):
		if player.is_local_player:
			return player
	return null

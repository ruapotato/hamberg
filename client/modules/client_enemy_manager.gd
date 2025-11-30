class_name ClientEnemyManager
extends RefCounted

## ClientEnemyManager - Handles enemy spawning, despawning, and state sync

var client: Node
var spawned_enemies: Dictionary = {}  # network_id -> enemy node

func _init(c: Node) -> void:
	client = c

# =============================================================================
# ENEMY SPAWNING
# =============================================================================

## Spawn an enemy
func spawn_enemy(network_id: int, enemy_type: String, position: Array, host_peer_id: int) -> void:
	if network_id in spawned_enemies:
		print("[Client] Enemy %d already spawned" % network_id)
		return

	var spawn_pos = Vector3(position[0], position[1], position[2])

	# Load enemy scene based on type
	var scene_path = get_enemy_scene(enemy_type)
	if scene_path.is_empty():
		print("[Client] Unknown enemy type: %s" % enemy_type)
		return

	var scene = load(scene_path)
	if not scene:
		return

	var enemy = scene.instantiate()
	enemy.name = "Enemy_%d" % network_id
	enemy.network_id = network_id
	enemy.host_peer_id = host_peer_id
	enemy.global_position = spawn_pos

	# Determine if we're the host
	enemy.is_host = (host_peer_id == multiplayer.get_unique_id())
	enemy.is_remote = not enemy.is_host

	client.world.add_child(enemy)
	spawned_enemies[network_id] = enemy

	print("[Client] Spawned enemy %d (%s) at %s, host=%d, is_host=%s" % [
		network_id, enemy_type, spawn_pos, host_peer_id, enemy.is_host
	])

## Get enemy scene path
func get_enemy_scene(enemy_type: String) -> String:
	match enemy_type:
		"goblin":
			return "res://shared/enemies/goblin.tscn"
		"skeleton":
			return "res://shared/enemies/skeleton.tscn"
		_:
			return "res://shared/enemies/enemy.tscn"

## Despawn an enemy
func despawn_enemy(network_id: int) -> void:
	if network_id in spawned_enemies:
		var enemy = spawned_enemies[network_id]
		enemy.queue_free()
		spawned_enemies.erase(network_id)
		print("[Client] Despawned enemy %d" % network_id)

# =============================================================================
# ENEMY STATE SYNC
# =============================================================================

## Update enemy states from server
func update_enemy_states(states: Array) -> void:
	for state in states:
		var network_id = state.get("network_id", 0)
		if network_id in spawned_enemies:
			var enemy = spawned_enemies[network_id]

			# Only apply sync to non-host enemies
			if not enemy.is_host:
				enemy.apply_sync_state(state)

## Apply damage to an enemy
func apply_enemy_damage(network_id: int, damage: float, new_health: float, knockback_dir: Vector3) -> void:
	if network_id not in spawned_enemies:
		return

	var enemy = spawned_enemies[network_id]

	# Update health
	enemy.health = new_health

	# Apply knockback
	if knockback_dir.length() > 0:
		enemy.velocity += knockback_dir

	# Show damage effect
	if enemy.has_method("show_damage_effect"):
		enemy.show_damage_effect(damage)

	# Check for death
	if new_health <= 0:
		if enemy.has_method("die"):
			enemy.die()

## Update enemy host assignment
func update_enemy_host(network_id: int, new_host_peer_id: int) -> void:
	if network_id not in spawned_enemies:
		return

	var enemy = spawned_enemies[network_id]
	enemy.host_peer_id = new_host_peer_id
	enemy.is_host = (new_host_peer_id == multiplayer.get_unique_id())
	enemy.is_remote = not enemy.is_host

	print("[Client] Enemy %d host changed to %d (is_host=%s)" % [
		network_id, new_host_peer_id, enemy.is_host
	])

# =============================================================================
# HELPERS
# =============================================================================

## Get enemy by network ID
func get_enemy(network_id: int) -> Node:
	return spawned_enemies.get(network_id, null)

## Get all spawned enemies
func get_all_enemies() -> Array:
	return spawned_enemies.values()

## Clear all enemies
func clear_all_enemies() -> void:
	for enemy in spawned_enemies.values():
		enemy.queue_free()
	spawned_enemies.clear()

class_name ServerDebug
extends RefCounted

## ServerDebug - Debug console commands for testing

var server: Node

func _init(s: Node) -> void:
	server = s

# =============================================================================
# DEBUG COMMANDS
# =============================================================================

## Give item to player
func handle_give_item(peer_id: int, item_id: String, quantity: int) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory:
		return

	var remaining = player.inventory.add_item(item_id, quantity)
	var added = quantity - remaining

	if added > 0:
		print("[Server] Gave %d %s to player %d" % [added, item_id, peer_id])
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())

## Spawn entity for testing
func handle_spawn_entity(peer_id: int, entity_type: String, position: Array) -> void:
	var spawn_pos = Vector3(position[0], position[1], position[2])

	match entity_type:
		"enemy":
			var enemy_spawner = server.get_node_or_null("EnemySpawner")
			if enemy_spawner:
				enemy_spawner.spawn_enemy_at(spawn_pos)
				print("[Server] Spawned enemy at %s" % spawn_pos)
		_:
			print("[Server] Unknown entity type: %s" % entity_type)

## Teleport player
func handle_teleport(peer_id: int, position: Array) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	player.global_position = Vector3(position[0], position[1], position[2])
	print("[Server] Teleported player %d to %s" % [peer_id, player.global_position])

## Heal player
func handle_heal(peer_id: int, amount: float) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	player.health = min(player.health + amount, player.MAX_HEALTH)
	print("[Server] Healed player %d for %.1f (now %.1f)" % [peer_id, amount, player.health])

## Toggle god mode
func handle_god_mode(peer_id: int, enabled: bool) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	player.god_mode = enabled
	print("[Server] God mode %s for player %d" % ["enabled" if enabled else "disabled", peer_id])

## Clear player inventory
func handle_clear_inventory(peer_id: int) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if player.inventory:
		player.inventory.clear()
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())
		print("[Server] Cleared inventory for player %d" % peer_id)

## Kill nearby enemies
func handle_kill_nearby(peer_id: int, radius: float) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	var player_pos = player.global_position
	var killed = 0

	for enemy in server.get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(player_pos) <= radius:
			enemy.take_damage(9999)
			killed += 1

	print("[Server] Killed %d enemies within %.1fm of player %d" % [killed, radius, peer_id])

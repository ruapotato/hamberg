class_name ServerPlayerManager
extends RefCounted

## ServerPlayerManager - Handles player connections, spawning, and management

var server: Node

func _init(s: Node) -> void:
	server = s

# =============================================================================
# PLAYER JOIN/LEAVE
# =============================================================================

## Handle player joining the server
func on_player_joined(peer_id: int) -> void:
	print("[Server] Player %d joined" % peer_id)

	# Send world configuration to the new player
	NetworkManager.rpc_send_world_config.rpc_id(peer_id,
		server.world_config.seed,
		server.world_config.world_name)

	# Send character selection list
	send_character_list(peer_id)

## Handle player leaving the server
func on_player_left(peer_id: int) -> void:
	print("[Server] Player %d left" % peer_id)

	# Handle enemies that were hosted by this player
	handle_disconnected_host_enemies(peer_id)

	# Save and despawn player
	despawn_player(peer_id)

## Handle enemies hosted by a disconnected player
func handle_disconnected_host_enemies(peer_id: int) -> void:
	var enemy_spawner = server.get_node_or_null("EnemySpawner")
	if not enemy_spawner:
		return

	# Get all enemies hosted by this peer
	var orphaned_enemies = []
	for enemy in server.get_tree().get_nodes_in_group("enemies"):
		if enemy.host_peer_id == peer_id:
			orphaned_enemies.append(enemy)

	if orphaned_enemies.is_empty():
		return

	print("[Server] Handling %d enemies from disconnected host %d" % [orphaned_enemies.size(), peer_id])

	# Get remaining connected players
	var remaining_players = NetworkManager.connected_players.keys()
	remaining_players.erase(peer_id)

	for enemy in orphaned_enemies:
		if remaining_players.is_empty():
			# No players left, despawn
			print("[Server] No players left, despawning enemy %d" % enemy.network_id)
			enemy_spawner.despawn_enemy(enemy.network_id)
		else:
			# Assign to closest remaining player
			var closest_peer = remaining_players[0]
			var closest_dist = INF

			for other_peer in remaining_players:
				if other_peer in server.spawned_players:
					var other_player = server.spawned_players[other_peer]
					var dist = other_player.global_position.distance_to(enemy.global_position)
					if dist < closest_dist:
						closest_dist = dist
						closest_peer = other_peer

			print("[Server] Reassigning enemy %d to peer %d" % [enemy.network_id, closest_peer])
			enemy.host_peer_id = closest_peer
			enemy.is_host = false
			enemy.is_remote = true

			# Notify all clients
			NetworkManager.rpc_update_enemy_host.rpc(enemy.network_id, closest_peer)

# =============================================================================
# SPAWNING
# =============================================================================

## Spawn a player entity
func spawn_player(peer_id: int, player_name: String, spawn_pos: Vector3) -> void:
	if peer_id in server.spawned_players:
		push_warning("[Server] Player %d already spawned" % peer_id)
		return

	var player = server.player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	player.player_name = player_name
	player.global_position = spawn_pos

	server.world.add_child(player)
	server.spawned_players[peer_id] = player

	print("[Server] Spawned player %s at %s" % [player_name, spawn_pos])

	# Notify all clients
	NetworkManager.rpc_spawn_player.rpc(peer_id, player_name, spawn_pos)

## Despawn a player and save their data
func despawn_player(peer_id: int) -> void:
	if peer_id in server.spawned_players:
		var player = server.spawned_players[peer_id]

		# Save player data before despawning
		if peer_id in server.player_characters:
			var character_id = server.player_characters[peer_id]
			save_player_data(peer_id, character_id, player)

		player.queue_free()
		server.spawned_players.erase(peer_id)
		server.player_characters.erase(peer_id)
		server.player_map_pins.erase(peer_id)

		# Close any open chests
		if peer_id in server.player_open_chests:
			server.player_open_chests.erase(peer_id)

		print("[Server] Despawned player %d" % peer_id)

		# Notify all clients
		NetworkManager.rpc_despawn_player.rpc(peer_id)

## Get a spawn position for new player
func get_spawn_point() -> Vector3:
	var spawn_range: float = 10.0
	var random_offset := Vector2(
		randf_range(-spawn_range, spawn_range),
		randf_range(-spawn_range, spawn_range)
	)

	var spawn_x: float = server.player_spawn_area_center.x + random_offset.x
	var spawn_z: float = server.player_spawn_area_center.y + random_offset.y
	var spawn_y: float = 50.0  # Start high

	# Get terrain height if available
	if server.terrain_world and server.terrain_world.has_method("get_height_at"):
		spawn_y = server.terrain_world.get_height_at(spawn_x, spawn_z) + 2.0

	return Vector3(spawn_x, spawn_y, spawn_z)

# =============================================================================
# CHARACTER SELECTION
# =============================================================================

## Send character list to player for selection
func send_character_list(peer_id: int) -> void:
	var characters = server.player_data_manager.get_character_list()
	print("[Server] Sending %d characters to player %d" % [characters.size(), peer_id])
	NetworkManager.rpc_receive_character_list.rpc_id(peer_id, characters)

## Load a character for a player
func load_player_character(peer_id: int, character_id: String, is_new: bool = false) -> void:
	var player_name: String
	var spawn_pos: Vector3
	var character_data: Dictionary = {}

	if is_new:
		player_name = character_id  # For new characters, ID is the name
		spawn_pos = get_spawn_point()

		# Create new character data
		character_data = {
			"name": player_name,
			"position": [spawn_pos.x, spawn_pos.y, spawn_pos.z],
			"inventory": [],
			"equipment": {},
			"map_pins": []
		}

		# Generate unique character ID
		character_id = server.player_data_manager.generate_character_id(player_name)
		server.player_data_manager.save_character(character_id, character_data)
	else:
		character_data = server.player_data_manager.load_character(character_id)
		if character_data.is_empty():
			push_error("[Server] Failed to load character: %s" % character_id)
			return

		player_name = character_data.get("name", "Unknown")
		var pos_array = character_data.get("position", [0, 50, 0])
		spawn_pos = Vector3(pos_array[0], pos_array[1], pos_array[2])

	# Track which character this player is using
	server.player_characters[peer_id] = character_id

	# Spawn the player
	spawn_player(peer_id, player_name, spawn_pos)

	# Apply saved data after spawn
	await server.get_tree().process_frame

	if peer_id in server.spawned_players:
		spawn_player_with_data(peer_id, character_data)

## Spawn player with saved inventory/equipment data
func spawn_player_with_data(peer_id: int, character_data: Dictionary) -> void:
	var player = server.spawned_players.get(peer_id)
	if not player:
		return

	# Load inventory
	var inventory_data = character_data.get("inventory", [])
	if player.inventory:
		player.inventory.load_from_array(inventory_data)

		# Sync inventory to client
		var inv_array = player.inventory.get_as_array()
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inv_array)

	# Load equipment
	var equipment_data = character_data.get("equipment", {})
	if player.equipment:
		player.equipment.load_from_dict(equipment_data)

		# Sync equipment to client
		var equip_dict = player.equipment.get_as_dict()
		NetworkManager.rpc_sync_equipment.rpc_id(peer_id, equip_dict)

	# Load map pins
	var map_pins = character_data.get("map_pins", [])
	server.player_map_pins[peer_id] = map_pins

	# Send full character data including pins
	NetworkManager.rpc_send_character_data.rpc_id(peer_id, character_data)

	# Send loaded chunks and buildables
	server._send_loaded_chunks_to_player(peer_id)
	server._send_buildables_to_player(peer_id)
	server._send_terrain_chunks_to_player(peer_id)
	server._send_enemies_to_player(peer_id)

# =============================================================================
# PLAYER DATA PERSISTENCE
# =============================================================================

## Save player data
func save_player_data(peer_id: int, character_id: String, player: Node) -> void:
	var character_data = {
		"name": player.player_name,
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"inventory": player.inventory.get_as_array() if player.inventory else [],
		"equipment": player.equipment.get_as_dict() if player.equipment else {},
		"map_pins": server.player_map_pins.get(peer_id, [])
	}

	server.player_data_manager.save_character(character_id, character_data)
	print("[Server] Saved player data for %s" % character_id)

## Save all connected players
func save_all_players() -> void:
	for peer_id in server.spawned_players:
		if peer_id in server.player_characters:
			var character_id = server.player_characters[peer_id]
			var player = server.spawned_players[peer_id]
			save_player_data(peer_id, character_id, player)

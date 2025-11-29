extends Node

## Server - Server-side game logic and player management
## This handles all server-authoritative systems

# Preload WorldConfig
const WorldConfig = preload("res://shared/world_config.gd")
const PlayerDataManager = preload("res://shared/player_data_manager.gd")
const WorldStateManager = preload("res://shared/world_state_manager.gd")
const CombinedInventory = preload("res://shared/combined_inventory.gd")

# Player management
var player_scene := preload("res://shared/player.tscn")
var spawned_players: Dictionary = {} # peer_id -> Player node
var player_characters: Dictionary = {} # peer_id -> character_id (for saving on disconnect)
var player_map_pins: Dictionary = {} # peer_id -> Array of map pins
var player_open_chests: Dictionary = {} # peer_id -> chest network_id (tracks which chest each player has open)
var player_spawn_area_center: Vector2 = Vector2(0, 0) # Center of spawn area

# Buildable management
var placed_buildables: Dictionary = {} # network_id -> {piece_name, position, rotation_y}

# Resource item pickup tracking (prevents duplicate pickups)
var picked_up_items: Dictionary = {} # network_id -> true (items that have already been picked up)

# Terrain chunks are now saved directly to disk via ChunkManager
# No need for in-memory modified_terrain_chunks dictionary

# Persistence managers
var player_data_manager: PlayerDataManager = null
var world_state_manager: WorldStateManager = null

# World configuration
var world_config = null  # Will be WorldConfig instance
const DEFAULT_WORLD_NAME: String = "world"

# Auto-save system
var auto_save_timer: float = 0.0
const AUTO_SAVE_INTERVAL: float = 300.0  # Save every 5 minutes

# Server state
var is_running: bool = false
var server_tick: int = 0
const TICK_RATE: float = 1.0 / 30.0 # 30 ticks per second
var tick_accumulator: float = 0.0

# World root for spawning entities
@onready var world: Node3D = $World
@onready var terrain_world = $World/TerrainWorld

func _ready() -> void:
	print("[Server] Server node ready")

	# Connect to network events
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)

	# Wait for terrain_world to finish initialization
	await get_tree().process_frame

	# Initialize enemy spawner
	_setup_enemy_spawner()

	# Set up console input (for dedicated servers)
	if DisplayServer.get_name() == "headless":
		_setup_console_input()

func _notification(what: int) -> void:
	# Handle shutdown notifications to ensure data is saved
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if is_running:
			print("[Server] Received shutdown signal, saving data...")
			stop_server()

## Setup enemy spawner (server-only)
func _setup_enemy_spawner() -> void:
	var EnemySpawner = preload("res://server/enemy_spawner.gd")
	var spawner = EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	print("[Server] Enemy spawner initialized")

## Load or create world configuration
func _load_or_create_world() -> void:
	# Check environment variable for custom world name
	var env_world_name := OS.get_environment("WORLD_NAME")
	var world_name := env_world_name if env_world_name else DEFAULT_WORLD_NAME

	# Try to load existing world
	world_config = WorldConfig.load_from_file(world_name)

	if world_config:
		print("[Server] Loaded existing world: %s (seed: %d)" % [world_config.world_name, world_config.seed])
	else:
		# Create new world with random seed
		var env_world_seed := OS.get_environment("WORLD_SEED")
		var seed_value := env_world_seed.to_int() if env_world_seed else -1

		world_config = WorldConfig.create_new(world_name, seed_value)
		world_config.save_to_file()
		print("[Server] Created new world: %s (seed: %d)" % [world_config.world_name, world_config.seed])

	# Initialize terrain_world with config
	if terrain_world:
		# Initialize world - this sets up biome generator, materials, chunk manager
		terrain_world.initialize_world(world_config.seed, world_config.world_name)

		# Connect to chunk manager signals after world is initialized
		await get_tree().process_frame
		if terrain_world.chunk_manager:
			terrain_world.chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
			terrain_world.chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
			print("[Server] Connected to chunk manager signals")

func start_server(port: int = 7777, max_players: int = 10) -> void:
	if is_running:
		push_warning("[Server] Server already running")
		return

	# Load or create world configuration
	_load_or_create_world()

	# Initialize persistence managers
	player_data_manager = PlayerDataManager.new()
	player_data_manager.initialize(world_config.world_name)

	world_state_manager = WorldStateManager.new()
	world_state_manager.initialize(world_config.world_name)

	# Load world state (buildables, etc.)
	_load_world_state()

	if NetworkManager.start_server(port, max_players):
		is_running = true
		print("[Server] ===========================================")
		print("[Server] Server is now running!")
		print("[Server] Port: %d" % port)
		print("[Server] Max players: %d" % max_players)
		print("[Server] World: %s (seed: %d)" % [world_config.world_name, world_config.seed])
		print("[Server] Loaded %d buildables from save" % placed_buildables.size())
		print("[Server] ===========================================")
		print("[Server] Available commands: save, kick <id>, shutdown, players")
	else:
		push_error("[Server] Failed to start server")

func stop_server() -> void:
	if not is_running:
		return

	print("[Server] Shutting down server...")

	# Save all player data before shutdown
	_save_all_players()

	# Save world state
	_save_world_state()

	# Save environmental chunks (trees, rocks, etc.)
	_save_environmental_chunks()

	# Kick all players
	for peer_id in spawned_players.keys():
		_despawn_player(peer_id)

	NetworkManager.disconnect_network()
	is_running = false

	print("[Server] Server stopped")

func _process(delta: float) -> void:
	if not is_running:
		return

	# Fixed tick rate for server simulation
	tick_accumulator += delta
	while tick_accumulator >= TICK_RATE:
		tick_accumulator -= TICK_RATE
		_server_tick()

func _server_tick() -> void:
	server_tick += 1

	# Update player positions in chunk manager for environmental object loading
	_update_environmental_chunks()

	# Broadcast player states to all clients
	_broadcast_player_states()

	# Auto-save timer
	auto_save_timer += TICK_RATE
	if auto_save_timer >= AUTO_SAVE_INTERVAL:
		auto_save_timer = 0.0
		_auto_save()

func _auto_save() -> void:
	print("[Server] Auto-saving...")
	_save_all_players()
	_save_world_state()
	_save_environmental_chunks()
	print("[Server] Auto-save complete")

func _broadcast_player_states() -> void:
	# Collect all player states
	var states: Array[Dictionary] = []

	for peer_id in spawned_players:
		var player: Node3D = spawned_players[peer_id]
		if player and is_instance_valid(player):
			var pos = player.global_position
			states.append({
				"peer_id": peer_id,
				"position": pos,
				"rotation": player.rotation.y,
				"velocity": player.get("velocity") if player.has_method("get") else Vector3.ZERO,
				"animation_state": player.get("current_animation_state") if player.has_method("get") else "idle"
			})


	# Broadcast to all clients through NetworkManager
	if states.size() > 0:
		NetworkManager.rpc_broadcast_player_states.rpc(states)

# ============================================================================
# ENVIRONMENTAL OBJECT MANAGEMENT (SERVER-AUTHORITATIVE)
# ============================================================================

func _update_environmental_chunks() -> void:
	# Update player positions in chunk manager
	if terrain_world and terrain_world.chunk_manager:
		for peer_id in spawned_players:
			var player = spawned_players[peer_id]
			if player and is_instance_valid(player):
				terrain_world.update_player_spawn_position(peer_id, player.global_position)

## Extract object data from a MultimeshChunk for network transmission
func _get_chunk_objects_data(mm_chunk) -> Array:
	var objects_data: Array = []
	var id_counter := 0

	# MultimeshChunk stores instances in a dict: object_type -> Array[InstanceData]
	for object_type in mm_chunk.instances.keys():
		var inst_array: Array = mm_chunk.instances[object_type]
		var transform_array: Array = mm_chunk.instance_transforms[object_type]

		for i in inst_array.size():
			var inst = inst_array[i]
			if not inst.destroyed:
				var transform: Transform3D = transform_array[i]
				objects_data.append({
					"id": id_counter,
					"type": object_type,
					"pos": [transform.origin.x, transform.origin.y, transform.origin.z],
					"rot": [inst.rotation.x, inst.rotation.y, inst.rotation.z],
					"scale": [inst.scale.x, inst.scale.y, inst.scale.z]
				})
			id_counter += 1

	return objects_data

func _on_chunk_loaded(chunk_pos: Vector2i) -> void:
	# When server loads a chunk, broadcast its objects to all clients
	if not terrain_world or not terrain_world.chunk_manager:
		return

	var chunk_manager = terrain_world.chunk_manager
	var objects_data: Array = []

	# Get objects in this chunk (now a MultimeshChunk)
	if chunk_manager.loaded_chunks.has(chunk_pos):
		var mm_chunk = chunk_manager.loaded_chunks[chunk_pos]
		objects_data = _get_chunk_objects_data(mm_chunk)
		print("[Server] Chunk %s has %d instances dict entries" % [chunk_pos, mm_chunk.instances.size()])

	# Broadcast to all clients
	if objects_data.size() > 0:
		print("[Server] Sending %d objects for chunk %s to clients" % [objects_data.size(), chunk_pos])
		NetworkManager.rpc_spawn_environmental_objects.rpc([chunk_pos.x, chunk_pos.y], objects_data)
	else:
		print("[Server] No objects to send for chunk %s" % chunk_pos)

func _on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	# When server unloads a chunk, tell clients to despawn it
	NetworkManager.rpc_despawn_environmental_objects.rpc([chunk_pos.x, chunk_pos.y])

## Send all currently loaded chunks to a specific player (for when they join)
func _send_loaded_chunks_to_player(peer_id: int) -> void:
	if not terrain_world or not terrain_world.chunk_manager:
		return

	var chunk_manager = terrain_world.chunk_manager
	var chunks_sent := 0

	# Iterate through all loaded chunks and send them to the new player
	for chunk_pos in chunk_manager.loaded_chunks.keys():
		var mm_chunk = chunk_manager.loaded_chunks[chunk_pos]
		var objects_data = _get_chunk_objects_data(mm_chunk)

		# Send this chunk to the new player only
		if objects_data.size() > 0:
			NetworkManager.rpc_spawn_environmental_objects.rpc_id(peer_id, [chunk_pos.x, chunk_pos.y], objects_data)
			chunks_sent += 1

	print("[Server] Sent %d loaded chunks to player %d" % [chunks_sent, peer_id])

func _send_buildables_to_player(peer_id: int) -> void:
	if placed_buildables.is_empty():
		print("[Server] No buildables to send to player %d" % peer_id)
		return

	var buildables_sent := 0

	# Send each buildable to the new player
	for net_id in placed_buildables.keys():
		var buildable_data = placed_buildables[net_id]
		var piece_name = buildable_data.piece_name
		var position = buildable_data.position
		var rotation_y = buildable_data.rotation_y

		# Send to this specific client only
		NetworkManager.rpc_spawn_buildable.rpc_id(peer_id, piece_name, position, rotation_y, net_id)
		buildables_sent += 1

	print("[Server] Sent %d buildables to player %d" % [buildables_sent, peer_id])

func _send_terrain_chunks_to_player(peer_id: int) -> void:
	if not terrain_world:
		return

	var modified_chunks: Array = terrain_world.get_all_modified_chunks()
	if modified_chunks.is_empty():
		print("[Server] No modified terrain chunks to send to player %d" % peer_id)
		return

	print("[Server] Sending %d modified terrain chunks to player %d..." % [modified_chunks.size(), peer_id])

	for chunk_info in modified_chunks:
		NetworkManager.rpc_sync_terrain_chunk.rpc_id(
			peer_id,
			chunk_info["chunk_x"],
			chunk_info["chunk_z"],
			chunk_info["data"]
		)

	print("[Server] Sent %d modified terrain chunks to player %d" % [modified_chunks.size(), peer_id])

func _send_enemies_to_player(peer_id: int) -> void:
	# Get enemy spawner
	var enemy_spawner = get_node_or_null("EnemySpawner")
	if not enemy_spawner or not "spawned_enemies" in enemy_spawner:
		print("[Server] No enemies to send to player %d" % peer_id)
		return

	var enemies = enemy_spawner.spawned_enemies
	if enemies.is_empty():
		print("[Server] No enemies to send to player %d" % peer_id)
		return

	var enemies_sent := 0

	# Send each enemy to the new player
	for enemy in enemies:
		if not enemy or not is_instance_valid(enemy):
			continue

		var enemy_path = enemy.get_path()
		var enemy_name = enemy.enemy_name if "enemy_name" in enemy else "Enemy"
		# IMPORTANT: Use enemy_name not node.name (which changes at runtime)
		var enemy_type = enemy_name  # Always "Gahnome", not "@CharacterBody3D@5366"

		# Get network_id and host_peer_id from the enemy
		var net_id = enemy.network_id if "network_id" in enemy else 0
		var host_peer = enemy.host_peer_id if "host_peer_id" in enemy else 0

		# Position array must include network_id and host_peer_id for client to work properly
		var position = [enemy.global_position.x, enemy.global_position.y, enemy.global_position.z, net_id, host_peer]

		# Send to this specific client only
		NetworkManager.rpc_spawn_enemy.rpc_id(peer_id, enemy_path, enemy_type, position, enemy_name)
		enemies_sent += 1

	print("[Server] Sent %d enemies to player %d" % [enemies_sent, peer_id])

# ============================================================================
# PLAYER MANAGEMENT (SERVER-AUTHORITATIVE)
# ============================================================================

func _on_player_joined(peer_id: int, player_name: String) -> void:
	print("[Server] Player joined: %s (ID: %d)" % [player_name, peer_id])

	# Send world config to the new client
	if world_config:
		var world_data: Dictionary = world_config.to_dict()
		NetworkManager.rpc_send_world_config.rpc_id(peer_id, world_data)
		print("[Server] Sent world config to player %d" % peer_id)

	# Note: Player spawning is now handled by load_player_character() after character selection

func _on_player_left(peer_id: int) -> void:
	print("[Server] Player left (ID: %d)" % peer_id)

	# Despawn player entity
	_despawn_player(peer_id)

func _spawn_player(peer_id: int, player_name: String) -> void:
	if spawned_players.has(peer_id):
		push_warning("[Server] Player %d already spawned" % peer_id)
		return

	# Instantiate player
	var player: Node3D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	# Get spawn position
	var spawn_pos := _get_spawn_point()

	# Add to world FIRST (required before setting global_position)
	world.add_child(player, true)
	spawned_players[peer_id] = player

	# Set spawn position AFTER adding to tree
	player.global_position = spawn_pos

	print("[Server] Spawned player %d at %s" % [peer_id, spawn_pos])

	# Register player with chunk manager for environmental object spawning
	if terrain_world:
		terrain_world.register_player_for_spawning(peer_id, player)

		# Send all currently loaded chunks to the new player
		_send_loaded_chunks_to_player(peer_id)

	# Send all existing buildables to the new player
	_send_buildables_to_player(peer_id)

	# Send all modified terrain chunks to the new player
	_send_terrain_chunks_to_player(peer_id)

	# Send all existing enemies to the new player
	_send_enemies_to_player(peer_id)

	# Notify all clients to spawn this player through NetworkManager
	print("[Server] Broadcasting spawn for player %d to all clients" % peer_id)
	NetworkManager.rpc_spawn_player.rpc(peer_id, player_name, spawn_pos)

	# Send existing players to the new client
	for existing_peer_id in spawned_players:
		if existing_peer_id != peer_id:
			var existing_player: Node3D = spawned_players[existing_peer_id]
			var existing_name: String = NetworkManager.get_player_info(existing_peer_id).get("name", "Unknown")
			print("[Server] Sending existing player %d to new client %d" % [existing_peer_id, peer_id])
			NetworkManager.rpc_spawn_player.rpc_id(peer_id, existing_peer_id, existing_name, existing_player.global_position)

func _despawn_player(peer_id: int) -> void:
	if not spawned_players.has(peer_id):
		return

	# Save player data before despawning
	if player_data_manager and player_characters.has(peer_id):
		var player = spawned_players[peer_id]
		var character_id = player_characters[peer_id]

		if player and is_instance_valid(player):
			var player_data = PlayerDataManager.serialize_player(player)

			# Debug: Check inventory contents
			if player_data.has("inventory"):
				var item_count = 0
				for slot in player_data["inventory"]:
					if slot is Dictionary and slot.has("item") and not slot["item"].is_empty():
						item_count += 1
						print("[Server] Saving inventory slot with: %s x %d" % [slot["item"], slot.get("amount", 0)])
				print("[Server] Saving %d non-empty inventory slots" % item_count)

			# Preserve important fields from existing save
			var existing_data = player_data_manager.load_player_data(character_id)
			if existing_data.has("character_name"):
				player_data["character_name"] = existing_data["character_name"]
			if existing_data.has("created_at"):
				player_data["created_at"] = existing_data["created_at"]
			if existing_data.has("play_time"):
				player_data["play_time"] = existing_data["play_time"]

			player_data_manager.save_player_data(character_id, player_data)
			print("[Server] Saved character data for player %d before disconnect" % peer_id)

		player_characters.erase(peer_id)

	# Unregister player from chunk manager
	if terrain_world:
		terrain_world.unregister_player_from_spawning(peer_id)

	# Clean up player
	var player: Node3D = spawned_players[peer_id]
	if player and is_instance_valid(player):
		player.queue_free()

	spawned_players.erase(peer_id)

	# Notify all clients to despawn through NetworkManager
	NetworkManager.rpc_despawn_player.rpc(peer_id)

	print("[Server] Despawned player %d" % peer_id)

func _get_spawn_point() -> Vector3:
	# Generate random spawn position within spawn area
	var random_offset := Vector2(randf_range(-10, 10), randf_range(-10, 10))
	var spawn_xz := player_spawn_area_center + random_offset

	# Get terrain height at this position
	var spawn_height: float = terrain_world.get_terrain_height_at(spawn_xz)

	# Spawn a bit above the surface to avoid clipping
	return Vector3(spawn_xz.x, spawn_height + 3.0, spawn_xz.y)

# ============================================================================
# SERVER METHODS - Called by NetworkManager RPC relay
# ============================================================================

## Receive player input from NetworkManager (already has peer_id) - DEPRECATED
func receive_player_input(peer_id: int, input_data: Dictionary) -> void:
	# Forward input to the player's entity
	if spawned_players.has(peer_id):
		var player = spawned_players[peer_id]
		if player.has_method("apply_server_input"):
			player.apply_server_input(input_data)

## Receive player position from NetworkManager (client-authoritative)
func receive_player_position(peer_id: int, position_data: Dictionary) -> void:
	if not spawned_players.has(peer_id):
		return

	var player: Node3D = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	var new_position: Vector3 = position_data.get("position", player.global_position)

	# Accept position update (clients are trusted)
	player.global_position = new_position
	player.rotation.y = position_data.get("rotation", player.rotation.y)

	# Store velocity and animation state for broadcasting
	if player.has_method("set"):
		player.set("velocity", position_data.get("velocity", Vector3.ZERO))
		player.set("current_animation_state", position_data.get("animation_state", "idle"))

## Handle hit report from NetworkManager (already has peer_id)
func handle_hit_report(peer_id: int, target_id: int, damage: float, hit_position: Vector3) -> void:
	print("[Server] Player %d reported hit on %d (damage: %.1f)" % [peer_id, target_id, damage])

	# TODO: Apply damage to target
	# For now, just broadcast the hit to all clients through NetworkManager
	NetworkManager.rpc_broadcast_hit.rpc(target_id, damage, hit_position)

## Handle environmental object damage from NetworkManager
## Uses position-based lookup to find the nearest instance in the MultimeshChunk
func handle_environmental_damage(peer_id: int, chunk_pos: Vector2i, object_id: int, damage: float, hit_position: Vector3) -> void:
	print("[Server] Player %d damaged object at position %s in chunk %s (damage: %.1f)" % [peer_id, hit_position, chunk_pos, damage])

	if not terrain_world or not terrain_world.chunk_manager:
		push_error("[Server] Cannot handle damage - terrain_world not initialized!")
		return

	var chunk_manager = terrain_world.chunk_manager

	# Check if chunk is loaded
	if not chunk_manager.loaded_chunks.has(chunk_pos):
		push_warning("[Server] Chunk %s not loaded, ignoring damage" % chunk_pos)
		return

	# Get the MultimeshChunk and find the nearest instance to the hit position
	var mm_chunk = chunk_manager.loaded_chunks[chunk_pos]
	var result = mm_chunk.get_instance_at_position(hit_position, 3.0)  # 3m max distance

	if result.index < 0:
		print("[Server] No instance found near hit position %s" % hit_position)
		return

	var object_type: String = result.object_type
	var instance_index: int = result.index

	# Apply damage through the MultimeshChunk
	var was_destroyed: bool = mm_chunk.apply_damage(object_type, instance_index, damage)

	if was_destroyed:
		print("[Server] Instance %s #%d in chunk %s destroyed!" % [object_type, instance_index, chunk_pos])

		# Get resource drops from the mesh library
		var mesh_library = mm_chunk.mesh_library
		var obj_def = mesh_library.get_object_def(object_type) if mesh_library else null
		var resource_drops: Dictionary = obj_def.resource_drops.duplicate() if obj_def else {}

		# Broadcast destruction to all clients (use object_id from client for compatibility)
		NetworkManager.rpc_destroy_environmental_object.rpc([chunk_pos.x, chunk_pos.y], object_id)

		# Broadcast resource drops to all clients (including position)
		if not resource_drops.is_empty():
			var pos_array = [hit_position.x, hit_position.y, hit_position.z]

			# Generate network IDs for each item on the server
			var network_ids: Array = []
			for resource_type in resource_drops:
				var amount: int = resource_drops[resource_type]
				for i in amount:
					# Use server time and chunk/object info for unique IDs
					var net_id = "%s_%d_%d_%d" % [chunk_pos, instance_index, Time.get_ticks_msec(), i]
					network_ids.append(net_id)

			NetworkManager.rpc_spawn_resource_drops.rpc(resource_drops, pos_array, network_ids)

			# Mark chunk as modified
			chunk_manager.modified_chunks[chunk_pos] = true
		else:
			# Object took damage but not destroyed
			# TODO: Could broadcast damage effect to clients
			pass
	# If not destroyed, the object just took damage - no action needed

## Handle buildable placement request from NetworkManager
func handle_place_buildable(peer_id: int, piece_name: String, position: Vector3, rotation_y: float) -> void:
	print("[Server] Player %d requesting to place %s at %s" % [peer_id, piece_name, position])

	# Validate placement (can add more checks here later)
	# TODO: Check if position is valid, not colliding, etc.

	# Check if player exists and has inventory
	if not spawned_players.has(peer_id):
		push_warning("[Server] Player %d not found for buildable placement" % peer_id)
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		push_warning("[Server] Player %d has no inventory" % peer_id)
		return

	var inventory = player.get_node("Inventory")

	# Get resource costs
	var costs = CraftingRecipes.BUILDING_COSTS.get(piece_name, {})

	# Check if player has required resources
	for resource in costs:
		var required = costs[resource]
		if not inventory.has_item(resource, required):
			print("[Server] Player %d doesn't have enough %s to place %s" % [peer_id, resource, piece_name])
			# TODO: Send error message to client
			return

	# Remove resources from inventory
	for resource in costs:
		var required = costs[resource]
		if not inventory.remove_item(resource, required):
			push_error("[Server] Failed to remove %d %s from player %d inventory!" % [required, resource, peer_id])
			# This shouldn't happen since we already checked
			return

	print("[Server] Consumed %s from player %d inventory" % [costs, peer_id])

	# Sync inventory back to client (to fix any client-side prediction errors)
	var inventory_data = inventory.get_inventory_data()
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

	# Generate unique network ID for this buildable
	var net_id = "%d_%s_%d" % [peer_id, piece_name, Time.get_ticks_msec()]

	# Store buildable for persistence and new client sync
	var buildable_data = {
		"piece_name": piece_name,
		"position": [position.x, position.y, position.z],
		"rotation_y": rotation_y
	}
	# Initialize chest inventory if this is a chest
	if piece_name == "chest":
		var chest_inv: Array = []
		chest_inv.resize(20)  # CHEST_SLOTS
		for i in 20:
			chest_inv[i] = {"item_name": "", "quantity": 0}
		buildable_data["inventory"] = chest_inv
	placed_buildables[net_id] = buildable_data

	# Broadcast to all clients to spawn the buildable
	var pos_array = [position.x, position.y, position.z]
	NetworkManager.rpc_spawn_buildable.rpc(piece_name, pos_array, rotation_y, net_id)

	print("[Server] Buildable %s placed successfully (ID: %s)" % [piece_name, net_id])

func handle_destroy_buildable(peer_id: int, network_id: String) -> void:
	print("[Server] Player %d requesting to destroy buildable %s" % [peer_id, network_id])

	# Check if buildable exists
	if not placed_buildables.has(network_id):
		print("[Server] WARNING: Buildable %s not found in placed_buildables" % network_id)
		return

	# Get buildable info to determine resource refund
	var buildable_info = placed_buildables[network_id]
	var piece_name = buildable_info.get("piece_name", "")

	# Get resource costs from crafting recipes
	var costs = CraftingRecipes.BUILDING_COSTS.get(piece_name, {})

	# Return resources to the player's server-side inventory
	if not costs.is_empty() and spawned_players.has(peer_id):
		var player = spawned_players[peer_id]
		if player and is_instance_valid(player) and player.has_node("Inventory"):
			var inventory = player.get_node("Inventory")

			for resource in costs:
				var amount = costs[resource]
				inventory.add_item(resource, amount)
				print("[Server] Returning %d %s to player %d" % [amount, resource, peer_id])

			# Sync inventory to client
			var inventory_data = inventory.get_inventory_data()
			NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

	# Remove from placed buildables dictionary
	placed_buildables.erase(network_id)

	# Broadcast to all clients to remove the buildable
	NetworkManager.rpc_remove_buildable.rpc(network_id)

	print("[Server] Buildable %s destroyed successfully" % network_id)


## Handle terrain modification request (server-authoritative)
func handle_terrain_modification(peer_id: int, operation: String, position: Vector3, data: Dictionary) -> void:
	print("[Server] ========================================")
	print("[Server] Player %d requesting terrain modification: %s at %s" % [peer_id, operation, position])
	print("[Server] Tool: %s, Data: %s" % [data.get("tool", "unknown"), data])

	# Check if terrain_world exists
	if not terrain_world:
		push_error("[Server] terrain_world is null! Cannot modify terrain")
		return

	print("[Server] TerrainWorld found: %s" % terrain_world)

	# Check if player exists
	if not spawned_players.has(peer_id):
		push_warning("[Server] Player %d not found for terrain modification" % peer_id)
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		push_warning("[Server] Player %d is invalid" % peer_id)
		return

	if not player.has_node("Inventory"):
		push_warning("[Server] Player %d has no inventory" % peer_id)
		return

	var inventory = player.get_node("Inventory")
	var tool_name: String = data.get("tool", "stone_pickaxe")

	print("[Server] Performing operation: %s" % operation)

	# Perform the operation
	match operation:
		"dig_square":
			# Dig and collect earth
			print("[Server] Calling terrain_world.dig_square...")
			var earth_collected: int = terrain_world.dig_square(position, tool_name)
			print("[Server] dig_square returned: %d earth" % earth_collected)
			if earth_collected > 0:
				inventory.add_item("earth", earth_collected)
				print("[Server] Player %d collected %d earth from digging" % [peer_id, earth_collected])
				# Sync inventory to client
				var inventory_data = inventory.get_inventory_data()
				NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)
			else:
				print("[Server] No earth collected from dig_square")

		"flatten_square":
			# Flatten terrain to target height
			var target_height: float = data.get("target_height", position.y)
			terrain_world.flatten_square(position, target_height)
			print("[Server] Player %d flattened terrain at %s to height %f" % [peer_id, position, target_height])

		"place_square":
			# Check if player has earth
			var earth_amount: int = inventory.get_item_count("earth")
			if earth_amount <= 0:
				print("[Server] Player %d has no earth to place" % peer_id)
				return

			var earth_used: int = terrain_world.place_square(position, earth_amount)
			if earth_used > 0:
				inventory.remove_item("earth", earth_used)
				print("[Server] Player %d placed %d earth" % [peer_id, earth_used])
				# Add earth_amount to data for client broadcast
				data["earth_amount"] = earth_amount
				# Sync inventory to client
				var inventory_data = inventory.get_inventory_data()
				NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

		_:
			push_warning("[Server] Unknown terrain modification operation: %s" % operation)
			return  # Don't broadcast unknown operations

	# Broadcast terrain modification to all clients for explicit sync
	# This ensures all clients apply the same modification locally
	print("[Server] Broadcasting terrain modification to all clients...")
	var position_array := [position.x, position.y, position.z]
	NetworkManager.rpc_apply_terrain_modification.rpc(operation, position_array, data)

	print("[Server] Terrain modification complete - broadcasted to all clients")
	print("[Server] ========================================")

## Handle manual save request from client
func handle_manual_save_request(peer_id: int) -> void:
	print("[Server] Player %d requested manual save" % peer_id)

	# Perform full save
	print("[Server] Executing manual save...")
	_save_all_players()
	_save_world_state()
	_save_environmental_chunks()
	print("[Server] Manual save complete")

	# Notify all clients that save is complete
	NetworkManager.rpc_save_completed.rpc()

# ============================================================================
# CONSOLE COMMANDS (for dedicated server)
# ============================================================================

func _setup_console_input() -> void:
	print("[Server] Console input enabled. Type 'help' for commands.")
	# Note: Reading stdin in Godot requires using OS.execute or a custom thread
	# For simplicity, we'll just document the commands
	# In production, you'd implement a proper console input system

func _execute_console_command(command: String) -> void:
	var parts := command.split(" ", false)
	if parts.is_empty():
		return

	var cmd := parts[0].to_lower()

	match cmd:
		"help":
			print("[Server] Available commands:")
			print("  players - List connected players")
			print("  kick <id> - Kick a player by peer ID")
			print("  save - Save the world")
			print("  shutdown - Stop the server")

		"players":
			print("[Server] Connected players (%d):" % NetworkManager.connected_players.size())
			for peer_id in NetworkManager.connected_players:
				var info: Dictionary = NetworkManager.get_player_info(peer_id)
				print("  [%d] %s" % [peer_id, info.get("name", "Unknown")])

		"kick":
			if parts.size() < 2:
				print("[Server] Usage: kick <peer_id>")
				return

			var peer_id := parts[1].to_int()
			if NetworkManager.connected_players.has(peer_id):
				multiplayer.multiplayer_peer.disconnect_peer(peer_id)
				print("[Server] Kicked player %d" % peer_id)
			else:
				print("[Server] Player %d not found" % peer_id)

		"save":
			print("[Server] Saving world...")
			_save_all_players()
			_save_world_state()
			_save_environmental_chunks()
			print("[Server] Save complete")

		"shutdown":
			print("[Server] Shutting down...")
			stop_server()
			get_tree().quit()

		_:
			print("[Server] Unknown command: %s" % cmd)

# ============================================================================
# PERSISTENCE METHODS
# ============================================================================

func _load_world_state() -> void:
	if not world_state_manager:
		return

	var state_data = world_state_manager.load_world_state()

	# Load buildables
	if state_data.has("buildables"):
		placed_buildables = state_data["buildables"]
		print("[Server] Loaded %d buildables from disk" % placed_buildables.size())

	# Terrain chunks are now loaded directly from ChunkManager
	# No need to load modified_terrain_chunks from world state

	# TODO: Load other world state (time_of_day, global_events, etc.)

func _save_world_state() -> void:
	if not world_state_manager:
		return

	var additional_data = {
		# Terrain chunks are saved directly by ChunkManager
		# No need to save modified_terrain_chunks here
		# TODO: Add time_of_day, global_events, etc. when implemented
	}

	world_state_manager.save_world_state(placed_buildables, additional_data)

func _save_all_players() -> void:
	if not player_data_manager:
		return

	var saved_count := 0

	for peer_id in spawned_players:
		var player = spawned_players[peer_id]
		if not player or not is_instance_valid(player):
			continue

		# Get character_id for this player
		var character_id = player_characters.get(peer_id, "")
		if character_id.is_empty():
			continue

		# Get map pins for this player
		var pins = player_map_pins.get(peer_id, [])

		# Serialize player data (including map pins)
		var player_data = PlayerDataManager.serialize_player(player, pins)

		# Preserve important fields from existing save
		var existing_data = player_data_manager.load_player_data(character_id)
		if existing_data.has("character_name"):
			player_data["character_name"] = existing_data["character_name"]
		if existing_data.has("created_at"):
			player_data["created_at"] = existing_data["created_at"]
		if existing_data.has("play_time"):
			player_data["play_time"] = existing_data["play_time"]

		# Save
		if player_data_manager.save_player_data(character_id, player_data):
			saved_count += 1

	print("[Server] Saved %d player characters" % saved_count)

func _save_environmental_chunks() -> void:
	if terrain_world:
		terrain_world.save_environmental_chunks()
	else:
		print("[Server] No terrain world to save chunks")

## Send list of characters to client (called via RPC)
func send_character_list(peer_id: int) -> void:
	if not player_data_manager:
		return

	var characters = player_data_manager.get_all_characters()

	# Convert character data to simple format for network transmission
	var character_list: Array = []
	for char_data in characters:
		character_list.append({
			"character_id": char_data.get("character_id", ""),
			"character_name": char_data.get("character_name", "Unknown"),
			"last_played": char_data.get("last_played", 0),
			"created_at": char_data.get("created_at", 0),
			"play_time": char_data.get("play_time", 0)
		})

	NetworkManager.rpc_receive_character_list.rpc_id(peer_id, character_list)
	print("[Server] Sent %d characters to peer %d" % [character_list.size(), peer_id])

## Load player character and spawn them (called via RPC)
func load_player_character(peer_id: int, character_id: String, character_name: String, is_new: bool) -> void:
	if not player_data_manager:
		return

	var player_data: Dictionary

	if is_new:
		# Create new character
		player_data = player_data_manager.create_new_character(character_name)
		if player_data.is_empty():
			push_error("[Server] Failed to create new character for peer %d" % peer_id)
			return
		character_id = player_data["character_id"]
		print("[Server] Created new character '%s' (ID: %s) for peer %d" % [character_name, character_id, peer_id])
	else:
		# Load existing character
		player_data = player_data_manager.load_player_data(character_id)
		if player_data.is_empty():
			push_error("[Server] Failed to load character %s for peer %d" % [character_id, peer_id])
			return
		print("[Server] Loaded character '%s' for peer %d" % [player_data["character_name"], peer_id])

	# Store character_id for this peer
	player_characters[peer_id] = character_id

	# Register player with NetworkManager
	NetworkManager.register_player(peer_id, player_data["character_name"])

	# Spawn player with loaded data
	_spawn_player_with_data(peer_id, player_data)

## Spawn player with loaded character data
func _spawn_player_with_data(peer_id: int, player_data: Dictionary) -> void:
	if spawned_players.has(peer_id):
		push_warning("[Server] Player %d already spawned" % peer_id)
		return

	# Instantiate player
	var player: Node3D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	# Set player name from character data
	if player_data.has("character_name"):
		player.player_name = player_data["character_name"]

	# Get spawn position - always use safe spawn point for now
	# TODO: Validate saved positions are safe before using them
	var spawn_pos: Vector3 = _get_spawn_point()

	# If player has a saved position with valid Y coordinate, use XZ but recalculate Y
	if player_data.has("position"):
		var pos = player_data["position"]
		var saved_xz = Vector2(pos[0], pos[2])
		# Only use saved XZ if Y was reasonable (not falling through world)
		if pos[1] > -100 and pos[1] < 1000:
			var terrain_height = terrain_world.get_terrain_height_at(saved_xz)
			spawn_pos = Vector3(pos[0], terrain_height + 3.0, pos[2])

	# Add to world FIRST (required before setting global_position)
	world.add_child(player, true)
	spawned_players[peer_id] = player

	# Set position and rotation AFTER adding to tree
	player.global_position = spawn_pos

	if player_data.has("rotation_y"):
		player.rotation.y = player_data["rotation_y"]

	# Load inventory
	if player_data.has("inventory") and player.has_node("Inventory"):
		var inventory = player.get_node("Inventory")
		inventory.set_inventory_data(player_data["inventory"])

	print("[Server] Spawned player %d at %s" % [peer_id, spawn_pos])

	# Register player with chunk manager for environmental object spawning
	if terrain_world:
		terrain_world.register_player_for_spawning(peer_id, player)
		_send_loaded_chunks_to_player(peer_id)

	# Send all existing buildables to the new player
	_send_buildables_to_player(peer_id)

	# Send all modified terrain chunks to the new player (deferred to ensure chunks are loaded first)
	call_deferred("_send_terrain_chunks_to_player", peer_id)

	# Send all existing enemies to the new player
	_send_enemies_to_player(peer_id)

	# Notify all clients to spawn this player through NetworkManager
	var player_name = player_data.get("character_name", "Unknown")
	print("[Server] Broadcasting spawn for player %d to all clients" % peer_id)
	NetworkManager.rpc_spawn_player.rpc(peer_id, player_name, spawn_pos)

	# Send existing players to the new client
	for existing_peer_id in spawned_players:
		if existing_peer_id != peer_id:
			var existing_player: Node3D = spawned_players[existing_peer_id]
			var existing_name: String = NetworkManager.get_player_info(existing_peer_id).get("name", "Unknown")
			print("[Server] Sending existing player %d to new client %d" % [existing_peer_id, peer_id])
			NetworkManager.rpc_spawn_player.rpc_id(peer_id, existing_peer_id, existing_name, existing_player.global_position)

	# Send inventory to client
	if player_data.has("inventory"):
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player_data["inventory"])

	# Send full character data (including map pins) to client
	NetworkManager.rpc_send_character_data.rpc_id(peer_id, player_data)

	# Load map pins for this player
	player_map_pins[peer_id] = player_data.get("map_pins", [])

## Handle item pickup request (server-authoritative)
func handle_pickup_request(peer_id: int, item_name: String, amount: int, network_id: String) -> void:
	# Check if item was already picked up (prevents duplicate pickups)
	if picked_up_items.has(network_id):
		print("[Server] Ignoring duplicate pickup request for item: %s" % network_id)
		return

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")

	# Mark item as picked up BEFORE adding to inventory (prevents race conditions)
	picked_up_items[network_id] = true

	# Try to add item to inventory
	var remaining = inventory.add_item(item_name, amount)

	if remaining < amount:
		# Successfully added at least some items
		var added_amount = amount - remaining

		# Debug: Check what's in inventory after adding
		var inventory_data = inventory.get_inventory_data()
		var item_count = 0
		for slot in inventory_data:
			if slot is Dictionary and slot.has("item") and not slot["item"].is_empty():
				item_count += 1
		print("[Server] Player %d picked up %d %s (inventory now has %d occupied slots)" % [peer_id, added_amount, item_name, item_count])

		# Broadcast to all clients to remove the resource item
		NetworkManager.rpc_pickup_resource_item.rpc(network_id)

		# Sync inventory to client
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)
	else:
		# Inventory full - do nothing
		print("[Server] Player %d inventory full, cannot pick up %s" % [peer_id, item_name])

## Handle crafting request (server-authoritative)
## Uses CombinedInventory to draw resources from player inventory + nearby chests
func handle_craft_request(peer_id: int, recipe_name: String) -> void:
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var player_inventory = player.get_node("Inventory")

	# Get the recipe
	var recipe = CraftingRecipes.get_recipe_by_name(recipe_name)
	if recipe.is_empty():
		print("[Server] Player %d requested invalid recipe: %s" % [peer_id, recipe_name])
		return

	# Get nearby chests for combined inventory (magic chest feature)
	var nearby_chests = _get_nearby_chests(player.global_position, 15.0)

	# Create combined inventory (player + nearby chests)
	var combined_inventory = CombinedInventory.new(player_inventory, nearby_chests)

	# TODO: Get actual nearby stations from player
	# For now, allow all crafting (no station restrictions)
	var stations = ["workbench"]

	# Attempt to craft using combined inventory
	if CraftingRecipes.craft_item(recipe, combined_inventory, stations):
		print("[Server] Player %d crafted %s (using %d nearby chests)" % [peer_id, recipe_name, nearby_chests.size()])

		# Sync player inventory to client
		var inventory_data = player_inventory.get_inventory_data()
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

		# Sync any modified chest inventories to all players who have them open
		for chest_wrapper in nearby_chests:
			if chest_wrapper:
				var chest_network_id = chest_wrapper.network_id
				# Find any players who have this chest open
				for other_peer_id in player_open_chests:
					if player_open_chests[other_peer_id] == chest_network_id:
						var chest_inv_data = chest_wrapper.get_inventory_data()
						NetworkManager.rpc_sync_chest_inventory.rpc_id(other_peer_id, chest_network_id, chest_inv_data)
	else:
		print("[Server] Player %d failed to craft %s (missing resources or station)" % [peer_id, recipe_name])

## Handle manual save request (server-authoritative)
func handle_save_request(peer_id: int) -> void:
	print("[Server] Player %d requested manual save" % peer_id)
	_save_all_players()
	_save_world_state()
	_save_environmental_chunks()
	print("[Server] Manual save complete")

## Handle equipment request (server-authoritative)
## Valheim-style: Items stay in inventory when equipped, just track equipped item_id
func handle_equip_request(peer_id: int, equip_slot: int, item_id: String) -> void:
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Equipment") or not player.has_node("Inventory"):
		return

	var equipment = player.get_node("Equipment")
	var inventory = player.get_node("Inventory")

	# Validate player has the item in inventory (Valheim-style: item stays in inventory)
	if not inventory.has_item(item_id, 1):
		print("[Server] Player %d doesn't have %s to equip" % [peer_id, item_id])
		return

	# Equip the new item (item remains in inventory)
	if equipment.equip_item(equip_slot, item_id):
		print("[Server] Player %d equipped %s to equipment slot %d (item stays in inventory)" % [peer_id, item_id, equip_slot])

		# Sync equipment to client (inventory unchanged)
		var equipment_data = equipment.get_equipment_data()
		NetworkManager.rpc_sync_equipment.rpc_id(peer_id, equipment_data)
	else:
		print("[Server] Player %d failed to equip %s to slot %d" % [peer_id, item_id, equip_slot])

## Handle unequip request (server-authoritative)
## Valheim-style: Items stay in inventory, just clear the equipped slot
func handle_unequip_request(peer_id: int, equip_slot: int) -> void:
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Equipment"):
		return

	var equipment = player.get_node("Equipment")

	# Get current equipped item
	var item_id = equipment.get_equipped_item(equip_slot)
	if item_id.is_empty():
		print("[Server] Player %d tried to unequip empty slot %d" % [peer_id, equip_slot])
		return

	# Unequip the item (item stays in inventory)
	equipment.unequip_slot(equip_slot)

	print("[Server] Player %d unequipped slot %d (%s, item stays in inventory)" % [peer_id, equip_slot, item_id])

	# Sync equipment to client (inventory unchanged)
	var equipment_data = equipment.get_equipment_data()
	NetworkManager.rpc_sync_equipment.rpc_id(peer_id, equipment_data)

## Handle swap inventory slots request
func handle_swap_slots_request(peer_id: int, slot_a: int, slot_b: int) -> void:
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")

	# Swap the slots
	inventory.swap_slots(slot_a, slot_b)

	print("[Server] Player %d swapped inventory slots %d and %d" % [peer_id, slot_a, slot_b])

	# Sync inventory to client
	var inventory_data = inventory.get_inventory_data()
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

## Handle item drop request from inventory
func handle_drop_item_request(peer_id: int, slot: int, amount: int) -> void:
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")
	var inventory_data = inventory.get_inventory_data()

	# Validate slot
	if slot < 0 or slot >= inventory_data.size():
		return

	var slot_data = inventory_data[slot]
	if slot_data.is_empty():
		return

	var item_id: String = slot_data.get("item", "")
	var slot_amount: int = slot_data.get("amount", 0)

	if item_id.is_empty() or slot_amount <= 0:
		return

	# Remove item from inventory
	inventory.remove_item(item_id, slot_amount)

	print("[Server] Player %d dropping %d x %s from slot %d" % [peer_id, slot_amount, item_id, slot])

	# Get player position for spawning the dropped item - in front of player at same height
	var player_forward = -player.global_transform.basis.z.normalized()
	var drop_pos: Vector3 = player.global_position + player_forward * 2.0
	drop_pos.y = player.global_position.y + 1.0  # Drop at player height + small offset

	# Generate network IDs for the dropped items
	var network_ids: Array = []
	for i in slot_amount:
		var net_id = "drop_%d_%d_%d" % [peer_id, Time.get_ticks_msec(), i]
		network_ids.append(net_id)

	# Create resource drops dictionary
	var resource_drops: Dictionary = {item_id: slot_amount}
	var pos_array = [drop_pos.x, drop_pos.y, drop_pos.z]

	# Broadcast the dropped items to all clients
	NetworkManager.rpc_spawn_resource_drops.rpc(resource_drops, pos_array, network_ids)

	# Sync inventory to client
	inventory_data = inventory.get_inventory_data()
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

## Handle enemy damage request (client-authoritative hits using network_id)
func handle_enemy_damage(peer_id: int, enemy_network_id: int, damage: float, knockback: float, direction: Vector3) -> void:
	# Look up enemy by network_id using EnemySpawner's lookup table
	var enemy_spawner = get_node_or_null("EnemySpawner")
	if not enemy_spawner:
		print("[Server] EnemySpawner not found!")
		return

	var enemy = enemy_spawner.network_id_to_enemy.get(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		print("[Server] Enemy with network_id %d not found" % enemy_network_id)
		return

	# Get the host_peer_id for this enemy - they run the actual AI
	var host_peer_id = enemy.host_peer_id if "host_peer_id" in enemy else 0

	print("[Server] Player %d hit enemy %d for %.1f damage (forwarding to host %d)" % [peer_id, enemy_network_id, damage, host_peer_id])

	# Apply damage on server copy (for tracking)
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, knockback, direction)

	# Forward damage to the HOST client so they can apply it to their authoritative copy
	if host_peer_id > 0:
		var dir_array = [direction.x, direction.y, direction.z]
		NetworkManager.rpc_apply_enemy_damage.rpc_id(host_peer_id, enemy_network_id, damage, knockback, dir_array)

## Handle enemy death notification from host client (host has already dropped loot)
func handle_enemy_died(peer_id: int, enemy_network_id: int) -> void:
	var enemy_spawner = get_node_or_null("EnemySpawner")
	if not enemy_spawner:
		print("[Server] EnemySpawner not found for enemy death!")
		return

	var enemy = enemy_spawner.network_id_to_enemy.get(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		print("[Server] Enemy with network_id %d not found for death notification" % enemy_network_id)
		return

	# Verify sender is the host for this enemy
	var host_peer_id = enemy_spawner.enemy_host_peers.get(enemy_network_id, 0)
	if host_peer_id != peer_id:
		print("[Server] Warning: Death notification from peer %d but host is %d" % [peer_id, host_peer_id])
		# Still process it - host may have changed

	print("[Server] Enemy %d died (notified by host %d)" % [enemy_network_id, peer_id])

	# Broadcast despawn to all clients
	var enemy_path = enemy_spawner.enemy_paths.get(enemy, enemy.get_path())
	NetworkManager.rpc_despawn_enemy.rpc(enemy_path)

	# Clean up enemy from spawner tracking
	enemy_spawner.spawned_enemies.erase(enemy)
	if enemy in enemy_spawner.enemy_paths:
		enemy_spawner.enemy_paths.erase(enemy)
	if enemy in enemy_spawner.enemy_network_ids:
		enemy_spawner.enemy_network_ids.erase(enemy)
	enemy_spawner.network_id_to_enemy.erase(enemy_network_id)
	enemy_spawner.enemy_host_peers.erase(enemy_network_id)
	enemy_spawner.host_position_reports.erase(enemy_network_id)

	# Queue free the server's enemy copy
	enemy.queue_free()

## Handle player death (server-authoritative)
func handle_player_death(peer_id: int) -> void:
	print("[Server] Player %d died" % peer_id)

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	# Mark player as dead on server
	if "is_dead" in player:
		player.is_dead = true

	# TODO: Drop items on death?
	# TODO: Apply death penalty?

## Handle respawn request (server-authoritative)
func handle_respawn_request(peer_id: int) -> void:
	print("[Server] Player %d requested respawn" % peer_id)

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	# Determine spawn position (default spawn point for now)
	var spawn_position = _get_spawn_point()

	# Respawn the player on server
	if player.has_method("respawn_at"):
		player.respawn_at(spawn_position)
		print("[Server] Player %d respawned at %s" % [peer_id, spawn_position])

	# Notify the client to respawn their local player
	var pos_array = [spawn_position.x, spawn_position.y, spawn_position.z]
	NetworkManager.rpc_player_respawned.rpc_id(peer_id, pos_array)

# ============================================================================
# TERRAIN CHUNK DATA - Removed old replay system
# ============================================================================
# Terrain chunks are now saved/loaded directly via ChunkManager to disk
# No need to sync over network - clients load from disk when connecting

# ============================================================================
# MAP SYSTEM - PINS
# ============================================================================

func update_player_map_pins(peer_id: int, pins_data: Array) -> void:
	"""Update map pins for a player (called from NetworkManager)"""
	print("[Server] Updating map pins for peer %d (%d pins)" % [peer_id, pins_data.size()])

	# Store pins for this player
	player_map_pins[peer_id] = pins_data

	# Pins will be saved when player disconnects or server saves

# ============================================================================
# CHEST STORAGE HANDLERS
# ============================================================================

## Wrapper class that provides CombinedInventory-compatible interface for server-side chest data
class ServerChestWrapper extends RefCounted:
	var network_id: String = ""
	var inventory: Array = []  # Reference to the actual inventory in placed_buildables

	func _init(p_network_id: String, p_inventory: Array) -> void:
		network_id = p_network_id
		inventory = p_inventory

	func get_item_count(item_name: String) -> int:
		var total = 0
		for slot in inventory:
			if slot.item_name == item_name:
				total += slot.quantity
		return total

	func remove_item(item_name: String, quantity: int) -> int:
		var removed = 0
		for i in inventory.size():
			if removed >= quantity:
				break
			if inventory[i].item_name == item_name:
				var to_remove = min(inventory[i].quantity, quantity - removed)
				inventory[i].quantity -= to_remove
				removed += to_remove
				if inventory[i].quantity <= 0:
					inventory[i] = {"item_name": "", "quantity": 0}
		return removed

	func get_inventory_data() -> Array:
		return inventory

## Get chest inventory from network_id (returns inventory array or null)
func _get_chest_inventory(network_id: String) -> Array:
	if not placed_buildables.has(network_id):
		return []
	var buildable_data = placed_buildables[network_id]
	if buildable_data.get("piece_name") != "chest":
		return []
	# Initialize inventory if missing (for chests placed before this update)
	if not buildable_data.has("inventory"):
		var inventory: Array = []
		inventory.resize(20)
		for i in 20:
			inventory[i] = {"item_name": "", "quantity": 0}
		buildable_data["inventory"] = inventory
	return buildable_data.get("inventory", [])

## Set chest inventory slot
func _set_chest_slot(network_id: String, slot: int, item_name: String, quantity: int) -> bool:
	if not placed_buildables.has(network_id):
		return false
	var buildable_data = placed_buildables[network_id]
	if buildable_data.get("piece_name") != "chest":
		return false
	var inventory = _get_chest_inventory(network_id)
	if slot < 0 or slot >= inventory.size():
		return false
	inventory[slot] = {"item_name": item_name, "quantity": quantity}
	return true

## Add item to chest inventory with stacking (returns amount that couldn't fit)
func _add_item_to_chest(network_id: String, item_name: String, quantity: int) -> int:
	var chest_inventory = _get_chest_inventory(network_id)
	if chest_inventory.is_empty():
		return quantity

	var remaining = quantity
	var max_stack = 64

	# First try to stack with existing items
	for i in chest_inventory.size():
		if remaining <= 0:
			break
		if chest_inventory[i].item_name == item_name:
			var can_add = max_stack - chest_inventory[i].quantity
			var to_add = min(can_add, remaining)
			chest_inventory[i].quantity += to_add
			remaining -= to_add

	# Then try empty slots
	for i in chest_inventory.size():
		if remaining <= 0:
			break
		if chest_inventory[i].item_name == "" or chest_inventory[i].quantity <= 0:
			var to_add = min(max_stack, remaining)
			chest_inventory[i] = {"item_name": item_name, "quantity": to_add}
			remaining -= to_add

	return remaining

## Get all chest wrappers within radius of a position (for combined inventory crafting)
## Returns Array of ServerChestWrapper objects that implement CombinedInventory interface
func _get_nearby_chests(position: Vector3, radius: float) -> Array:
	var nearby_chests: Array = []

	for buildable_id in placed_buildables:
		var buildable_data = placed_buildables[buildable_id]
		if buildable_data.piece_name == "chest":
			# Check distance
			var chest_pos = buildable_data.position
			var distance = position.distance_to(chest_pos)
			if distance <= radius:
				# Create wrapper with reference to actual inventory data
				var chest_inventory = _get_chest_inventory(buildable_id)
				if not chest_inventory.is_empty():
					var wrapper = ServerChestWrapper.new(buildable_id, chest_inventory)
					nearby_chests.append(wrapper)

	return nearby_chests

## Handle player opening a chest
func handle_open_chest(peer_id: int, chest_network_id: String) -> void:
	print("[Server] Player %d opening chest %s" % [peer_id, chest_network_id])

	# Close any previously open chest
	if player_open_chests.has(peer_id):
		handle_close_chest(peer_id)

	# Store the open chest reference
	player_open_chests[peer_id] = chest_network_id

	# Find and sync chest inventory to player
	var inventory_data = _get_chest_inventory(chest_network_id)
	if not inventory_data.is_empty():
		NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, inventory_data)
	else:
		print("[Server] WARNING: Could not find chest inventory for %s" % chest_network_id)

## Handle player closing a chest
func handle_close_chest(peer_id: int) -> void:
	if player_open_chests.has(peer_id):
		var chest_id = player_open_chests[peer_id]
		print("[Server] Player %d closing chest %s" % [peer_id, chest_id])
		player_open_chests.erase(peer_id)

## Handle transfer from chest to player inventory
func handle_chest_to_player(peer_id: int, chest_slot: int, player_slot: int) -> void:
	if not spawned_players.has(peer_id):
		return

	if not player_open_chests.has(peer_id):
		print("[Server] Player %d tried to transfer but has no chest open" % peer_id)
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")
	var chest_network_id = player_open_chests[peer_id]
	var chest_inventory = _get_chest_inventory(chest_network_id)

	if chest_inventory.is_empty():
		print("[Server] Chest %s not found" % chest_network_id)
		return

	# Get chest item
	if chest_slot < 0 or chest_slot >= chest_inventory.size():
		return

	var chest_data = chest_inventory[chest_slot]
	if chest_data.item_name.is_empty() or chest_data.quantity <= 0:
		return

	var item_name = chest_data.item_name
	var quantity = chest_data.quantity

	# Check player slot
	var player_inventory = inventory.get_inventory_data()
	if player_slot < 0 or player_slot >= player_inventory.size():
		return

	var player_data = player_inventory[player_slot]

	# Can we transfer to this slot?
	if player_data.is_empty():
		# Empty slot - full transfer
		inventory.set_slot(player_slot, item_name, quantity)
		_set_chest_slot(chest_network_id, chest_slot, "", 0)
	elif player_data.get("item", "") == item_name:
		# Same item - stack
		var current_amount = player_data.get("amount", 0)
		var new_amount = current_amount + quantity
		inventory.set_slot(player_slot, item_name, new_amount)
		_set_chest_slot(chest_network_id, chest_slot, "", 0)
	else:
		# Different item - swap
		var player_item = player_data.get("item", "")
		var player_amount = player_data.get("amount", 0)
		inventory.set_slot(player_slot, item_name, quantity)
		_set_chest_slot(chest_network_id, chest_slot, player_item, player_amount)

	print("[Server] Transferred %s x%d from chest[%d] to player[%d]" % [item_name, quantity, chest_slot, player_slot])

	# Sync both inventories
	var new_player_inventory = inventory.get_inventory_data()
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, new_player_inventory)

	var new_chest_inventory = _get_chest_inventory(chest_network_id)
	NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, new_chest_inventory)

## Handle transfer from player inventory to chest
func handle_player_to_chest(peer_id: int, player_slot: int, chest_slot: int) -> void:
	if not spawned_players.has(peer_id):
		return

	if not player_open_chests.has(peer_id):
		print("[Server] Player %d tried to transfer but has no chest open" % peer_id)
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")
	var chest_network_id = player_open_chests[peer_id]
	var chest_inventory = _get_chest_inventory(chest_network_id)

	if chest_inventory.is_empty():
		print("[Server] Chest %s not found" % chest_network_id)
		return

	# Get player item
	var player_inventory = inventory.get_inventory_data()
	if player_slot < 0 or player_slot >= player_inventory.size():
		return

	var player_data = player_inventory[player_slot]
	if player_data.is_empty():
		return

	var item_name = player_data.get("item", "")
	var quantity = player_data.get("amount", 0)

	if item_name.is_empty() or quantity <= 0:
		return

	# Check chest slot
	if chest_slot < 0 or chest_slot >= chest_inventory.size():
		return

	var chest_data = chest_inventory[chest_slot]

	# Can we transfer to this slot?
	if chest_data.item_name.is_empty() or chest_data.quantity <= 0:
		# Empty slot - full transfer
		_set_chest_slot(chest_network_id, chest_slot, item_name, quantity)
		inventory.set_slot(player_slot, "", 0)
	elif chest_data.item_name == item_name:
		# Same item - stack
		var new_amount = chest_data.quantity + quantity
		_set_chest_slot(chest_network_id, chest_slot, item_name, new_amount)
		inventory.set_slot(player_slot, "", 0)
	else:
		# Different item - swap
		_set_chest_slot(chest_network_id, chest_slot, item_name, quantity)
		inventory.set_slot(player_slot, chest_data.item_name, chest_data.quantity)

	print("[Server] Transferred %s x%d from player[%d] to chest[%d]" % [item_name, quantity, player_slot, chest_slot])

	# Sync both inventories
	var new_player_inventory = inventory.get_inventory_data()
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, new_player_inventory)

	var new_chest_inventory = _get_chest_inventory(chest_network_id)
	NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, new_chest_inventory)

## Handle swapping two slots within the chest
func handle_chest_swap(peer_id: int, slot_a: int, slot_b: int) -> void:
	if not player_open_chests.has(peer_id):
		print("[Server] Player %d tried to swap but has no chest open" % peer_id)
		return

	var chest_network_id = player_open_chests[peer_id]
	var chest_inventory = _get_chest_inventory(chest_network_id)

	if chest_inventory.is_empty():
		print("[Server] Chest %s not found" % chest_network_id)
		return

	# Swap slots
	if slot_a < 0 or slot_a >= chest_inventory.size() or slot_b < 0 or slot_b >= chest_inventory.size():
		return

	var data_a = chest_inventory[slot_a]
	var data_b = chest_inventory[slot_b]

	_set_chest_slot(chest_network_id, slot_a, data_b.item_name, data_b.quantity)
	_set_chest_slot(chest_network_id, slot_b, data_a.item_name, data_a.quantity)

	print("[Server] Swapped chest slots %d and %d" % [slot_a, slot_b])

	# Sync chest inventory
	var new_chest_inventory = _get_chest_inventory(chest_network_id)
	NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, new_chest_inventory)

## Handle quick-deposit from player to chest
func handle_quick_deposit(peer_id: int, player_slot: int) -> void:
	if not spawned_players.has(peer_id):
		return

	if not player_open_chests.has(peer_id):
		print("[Server] Player %d tried to quick-deposit but has no chest open" % peer_id)
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")
	var chest_network_id = player_open_chests[peer_id]
	var chest_inventory = _get_chest_inventory(chest_network_id)

	if chest_inventory.is_empty():
		print("[Server] Chest %s not found" % chest_network_id)
		return

	# Get player item
	var player_inventory = inventory.get_inventory_data()
	if player_slot < 0 or player_slot >= player_inventory.size():
		return

	var player_data = player_inventory[player_slot]
	if player_data.is_empty():
		return

	var item_name = player_data.get("item", "")
	var quantity = player_data.get("amount", 0)

	if item_name.is_empty() or quantity <= 0:
		return

	# Try to add to chest (find existing stack or empty slot)
	var remaining = _add_item_to_chest(chest_network_id, item_name, quantity)
	var deposited = quantity - remaining

	if deposited > 0:
		# Update player inventory
		if remaining > 0:
			inventory.set_slot(player_slot, item_name, remaining)
		else:
			inventory.set_slot(player_slot, "", 0)

		print("[Server] Quick-deposited %d %s (remaining: %d)" % [deposited, item_name, remaining])

		# Sync both inventories
		var new_player_inventory = inventory.get_inventory_data()
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, new_player_inventory)

		var new_chest_inventory = _get_chest_inventory(chest_network_id)
		NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, new_chest_inventory)

# ============================================================================
# DEBUG CONSOLE HANDLERS
# ============================================================================

## Debug: Give item to player
func handle_debug_give_item(peer_id: int, item_name: String, amount: int) -> void:
	print("[Server] DEBUG: Give %d x %s to player %d" % [amount, item_name, peer_id])

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")

	# Try to add item
	if inventory.add_item(item_name, amount):
		print("[Server] DEBUG: Gave %d x %s to player %d" % [amount, item_name, peer_id])
		# Sync inventory
		var inventory_data = inventory.get_inventory_data()
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)
	else:
		print("[Server] DEBUG: Failed to give %s - inventory full or invalid item" % item_name)

## Debug: Spawn entity near player
func handle_debug_spawn_entity(peer_id: int, entity_type: String, count: int) -> void:
	print("[Server] DEBUG: Spawn %d x %s near player %d" % [count, entity_type, peer_id])

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	var player_pos = player.global_position
	var enemy_spawner = get_node_or_null("EnemySpawner")
	if not enemy_spawner:
		print("[Server] DEBUG: EnemySpawner not found")
		return

	# Map entity type to scene path
	var scene_path = ""
	match entity_type.to_lower():
		"gahnome":
			scene_path = "res://shared/enemies/gahnome.tscn"
		"sporeling":
			scene_path = "res://shared/enemies/sporeling.tscn"
		"deer":
			scene_path = "res://shared/animals/deer.tscn"
		"pig":
			scene_path = "res://shared/animals/pig.tscn"
		"sheep":
			scene_path = "res://shared/animals/sheep.tscn"
		_:
			print("[Server] DEBUG: Unknown entity type: %s" % entity_type)
			return

	# Spawn enemies near player
	for i in range(count):
		var offset = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		var spawn_pos = player_pos + offset
		enemy_spawner.spawn_enemy_at_position(scene_path, spawn_pos, peer_id)

	print("[Server] DEBUG: Spawned %d x %s" % [count, entity_type])

## Debug: Teleport player
func handle_debug_teleport(peer_id: int, position: Vector3) -> void:
	print("[Server] DEBUG: Teleport player %d to %s" % [peer_id, position])

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	# Update server-side position
	player.global_position = position

	# Client handles their own teleport locally

## Debug: Heal player to full
func handle_debug_heal(peer_id: int) -> void:
	print("[Server] DEBUG: Heal player %d" % peer_id)

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if "health" in player and "max_health" in player:
		player.health = player.max_health

## Debug: Toggle god mode
func handle_debug_god_mode(peer_id: int, enabled: bool) -> void:
	print("[Server] DEBUG: God mode %s for player %d" % ["ENABLED" if enabled else "disabled", peer_id])

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if "god_mode" in player:
		player.god_mode = enabled

## Debug: Clear player inventory
func handle_debug_clear_inventory(peer_id: int) -> void:
	print("[Server] DEBUG: Clear inventory for player %d" % peer_id)

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")
	inventory.clear()

	# Sync inventory
	var inventory_data = inventory.get_inventory_data()
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

## Debug: Kill nearby enemies
func handle_debug_kill_nearby(peer_id: int) -> void:
	print("[Server] DEBUG: Kill nearby enemies for player %d" % peer_id)

	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	var player_pos = player.global_position
	var enemy_spawner = get_node_or_null("EnemySpawner")
	if not enemy_spawner:
		return

	# Kill enemies within 50 units
	var kill_range = 50.0
	var killed_count = 0

	for enemy in enemy_spawner.spawned_enemies.duplicate():
		if not is_instance_valid(enemy):
			continue

		var dist = enemy.global_position.distance_to(player_pos)
		if dist <= kill_range:
			# Broadcast despawn
			var enemy_path = enemy_spawner.enemy_paths.get(enemy, enemy.get_path())
			NetworkManager.rpc_despawn_enemy.rpc(enemy_path)

			# Clean up from spawner
			var net_id = enemy_spawner.enemy_network_ids.get(enemy, 0)
			enemy_spawner.spawned_enemies.erase(enemy)
			enemy_spawner.enemy_paths.erase(enemy)
			enemy_spawner.enemy_network_ids.erase(enemy)
			enemy_spawner.network_id_to_enemy.erase(net_id)
			enemy_spawner.enemy_host_peers.erase(net_id)
			enemy_spawner.host_position_reports.erase(net_id)

			enemy.queue_free()
			killed_count += 1

	print("[Server] DEBUG: Killed %d enemies near player %d" % [killed_count, peer_id])

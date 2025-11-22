extends Node

## Server - Server-side game logic and player management
## This handles all server-authoritative systems

# Preload WorldConfig
const WorldConfig = preload("res://shared/world_config.gd")
const PlayerDataManager = preload("res://shared/player_data_manager.gd")
const WorldStateManager = preload("res://shared/world_state_manager.gd")

# Player management
var player_scene := preload("res://shared/player.tscn")
var spawned_players: Dictionary = {} # peer_id -> Player node
var player_viewers: Dictionary = {} # peer_id -> VoxelViewer node
var player_characters: Dictionary = {} # peer_id -> character_id (for saving on disconnect)
var player_map_pins: Dictionary = {} # peer_id -> Array of map pins
var player_spawn_area_center: Vector2 = Vector2(0, 0) # Center of spawn area

# Buildable management
var placed_buildables: Dictionary = {} # network_id -> {piece_name, position, rotation_y}

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
@onready var voxel_world = $World/VoxelWorld
@onready var voxel_terrain = $World/VoxelWorld/VoxelLodTerrain

func _ready() -> void:
	print("[Server] Server node ready")

	# Connect to network events
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)

	# Wait for voxel_world to finish initialization
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

	# Wait for voxel_world to be fully initialized
	if voxel_world:
		# Wait until voxel_world's _ready() has completed
		while not voxel_world.is_initialized:
			await get_tree().process_frame

		# Now initialize world with config
		voxel_world.initialize_world(world_config.seed, world_config.world_name)

		# Connect to chunk manager signals after world is initialized
		await get_tree().process_frame
		if voxel_world.chunk_manager:
			voxel_world.chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
			voxel_world.chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
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

	# Load terrain modification history
	_load_terrain_history()

	if NetworkManager.start_server(port, max_players):
		is_running = true
		print("[Server] ===========================================")
		print("[Server] Server is now running!")
		print("[Server] Port: %d" % port)
		print("[Server] Max players: %d" % max_players)

		# Start timer to periodically check for unapplied chunks near players
		_start_unapplied_chunk_checker()
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

	# Save terrain modification history
	_save_terrain_history()

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
	_save_terrain_history()
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
	if voxel_world and voxel_world.chunk_manager:
		for peer_id in spawned_players:
			var player = spawned_players[peer_id]
			if player and is_instance_valid(player):
				voxel_world.update_player_spawn_position(peer_id, player.global_position)

				# Check if player has moved near any unapplied chunks
				# This ensures terrain modifications are applied as soon as player is in VoxelTool range
				_check_unapplied_chunks_near_player(peer_id, player.global_position)

func _on_chunk_loaded(chunk_pos: Vector2i) -> void:
	# When server loads a chunk, broadcast its objects to all clients
	if not voxel_world or not voxel_world.chunk_manager:
		return

	var chunk_manager = voxel_world.chunk_manager
	var objects_data: Array = []

	# Get objects in this chunk
	if chunk_manager.loaded_chunks.has(chunk_pos):
		var objects = chunk_manager.loaded_chunks[chunk_pos]

		for i in objects.size():
			var obj = objects[i]
			if is_instance_valid(obj):
				var obj_type = "unknown"
				if obj.has_method("get_object_type"):
					obj_type = obj.get_object_type()

				var obj_pos = obj.global_position
				objects_data.append({
					"id": i,  # Local ID within chunk
					"type": obj_type,
					"pos": [obj_pos.x, obj_pos.y, obj_pos.z],
					"rot": [obj.rotation.x, obj.rotation.y, obj.rotation.z],
					"scale": [obj.scale.x, obj.scale.y, obj.scale.z]
				})

	# Broadcast to all clients
	if objects_data.size() > 0:
		NetworkManager.rpc_spawn_environmental_objects.rpc([chunk_pos.x, chunk_pos.y], objects_data)

	# Apply terrain modifications after a delay to let LOD fully load
	# The voxel LOD system needs time to load high-resolution detail
	_apply_terrain_modifications_for_chunk_deferred(chunk_pos)

func _on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	# When server unloads a chunk, tell clients to despawn it
	NetworkManager.rpc_despawn_environmental_objects.rpc([chunk_pos.x, chunk_pos.y])

## Send all currently loaded chunks to a specific player (for when they join)
func _send_loaded_chunks_to_player(peer_id: int) -> void:
	if not voxel_world or not voxel_world.chunk_manager:
		return

	var chunk_manager = voxel_world.chunk_manager
	var chunks_sent := 0

	# Iterate through all loaded chunks and send them to the new player
	for chunk_pos in chunk_manager.loaded_chunks.keys():
		var objects = chunk_manager.loaded_chunks[chunk_pos]
		var objects_data: Array = []

		for i in objects.size():
			var obj = objects[i]
			if is_instance_valid(obj):
				var obj_type = "unknown"
				if obj.has_method("get_object_type"):
					obj_type = obj.get_object_type()

				objects_data.append({
					"id": i,
					"type": obj_type,
					"pos": [obj.global_position.x, obj.global_position.y, obj.global_position.z],
					"rot": [obj.rotation.x, obj.rotation.y, obj.rotation.z],
					"scale": [obj.scale.x, obj.scale.y, obj.scale.z]
				})

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
		var position = [enemy.global_position.x, enemy.global_position.y, enemy.global_position.z]

		# Send to this specific client only
		NetworkManager.rpc_spawn_enemy.rpc_id(peer_id, enemy_path, enemy_type, position, enemy_name)
		enemies_sent += 1

	print("[Server] Sent %d enemies to player %d" % [enemies_sent, peer_id])

## Deferred application of terrain modifications (waits for LOD to fully load)
func _apply_terrain_modifications_for_chunk_deferred(chunk_pos: Vector2i) -> void:
	# Wait longer for voxel LOD system to load high-resolution detail
	# Square operations especially need full detail to work correctly
	await get_tree().create_timer(2.0).timeout  # Wait 2 seconds for voxel detail to fully load

	# Only apply if a player is very close to this chunk
	# VoxelTool only works within the voxel viewer camera's active range
	if not _is_player_near_chunk(chunk_pos):
		print("[Server] Chunk %s loaded but no player nearby - marking for later application" % chunk_pos)
		unapplied_chunks[chunk_pos] = true
		return

	_apply_terrain_modifications_for_chunk(chunk_pos)
	# Remove from unapplied list if it was there
	unapplied_chunks.erase(chunk_pos)

## Check if any player is close enough to a chunk for voxel operations to work
func _is_player_near_chunk(chunk_pos: Vector2i) -> bool:
	const MAX_DISTANCE := 48.0  # VoxelTool requires player to be very close (1.5 chunks = 48 units)
	# Square operations especially need the player to be nearby for proper detail

	var chunk_center := Vector3(chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE / 2.0, 0, chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE / 2.0)

	# Use spawned_players dictionary directly (more reliable than NetworkManager.get_player_info)
	for peer_id in spawned_players:
		var player = spawned_players[peer_id]
		if player and is_instance_valid(player):
			var player_pos: Vector3 = player.global_position
			var distance := Vector2(player_pos.x, player_pos.z).distance_to(Vector2(chunk_center.x, chunk_center.z))
			if distance <= MAX_DISTANCE:
				return true

	return false

## Periodically check for unapplied chunks that now have players nearby
func _start_unapplied_chunk_checker() -> void:
	while is_running:
		await get_tree().create_timer(2.0).timeout  # Check every 2 seconds
		_check_unapplied_chunks()

func _check_unapplied_chunks() -> void:
	if unapplied_chunks.is_empty():
		return

	var chunks_to_apply: Array[Vector2i] = []

	# Find unapplied chunks that now have players nearby
	for chunk_pos in unapplied_chunks.keys():
		if _is_player_near_chunk(chunk_pos):
			chunks_to_apply.append(chunk_pos)

	# Apply modifications to these chunks
	for chunk_pos in chunks_to_apply:
		print("[Server] Player now near chunk %s - applying pending terrain modifications" % chunk_pos)
		_apply_terrain_modifications_for_chunk(chunk_pos)
		unapplied_chunks.erase(chunk_pos)

## Check and apply unapplied chunks near a specific position (e.g., spawn point)
func _check_unapplied_chunks_near_position(position: Vector3) -> void:
	if unapplied_chunks.is_empty():
		return

	const MAX_DISTANCE := 48.0  # Match _is_player_near_chunk distance
	var chunks_to_apply: Array[Vector2i] = []

	# Find unapplied chunks near this position
	for chunk_pos in unapplied_chunks.keys():
		var chunk_center := Vector3(chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE / 2.0, 0, chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE / 2.0)
		var distance := Vector2(position.x, position.z).distance_to(Vector2(chunk_center.x, chunk_center.z))

		if distance <= MAX_DISTANCE:
			chunks_to_apply.append(chunk_pos)

	# Apply modifications to these chunks
	for chunk_pos in chunks_to_apply:
		print("[Server] Position %s near chunk %s - applying pending terrain modifications" % [position, chunk_pos])
		_apply_terrain_modifications_for_chunk(chunk_pos)
		unapplied_chunks.erase(chunk_pos)

## Check and apply unapplied chunks near a specific player (called every server tick)
## Uses per-player tracking to avoid re-applying the same chunks
func _check_unapplied_chunks_near_player(peer_id: int, position: Vector3) -> void:
	if unapplied_chunks.is_empty():
		return

	# Initialize tracking for this player if needed
	if not player_applied_chunks.has(peer_id):
		player_applied_chunks[peer_id] = {}

	const MAX_DISTANCE := 48.0  # VoxelTool range
	var player_applied: Dictionary = player_applied_chunks[peer_id]
	var chunks_to_apply: Array[Vector2i] = []

	# Find unapplied chunks near this player that haven't been applied yet
	for chunk_pos in unapplied_chunks.keys():
		# Skip if this player already triggered application for this chunk
		if player_applied.has(chunk_pos):
			continue

		var chunk_center := Vector3(chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE / 2.0, 0, chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE / 2.0)
		var distance := Vector2(position.x, position.z).distance_to(Vector2(chunk_center.x, chunk_center.z))

		if distance <= MAX_DISTANCE:
			chunks_to_apply.append(chunk_pos)
			# Mark as applied for this player
			player_applied[chunk_pos] = true

	# Apply modifications to these chunks
	for chunk_pos in chunks_to_apply:
		print("[Server] Player %d moved near chunk %s - applying pending terrain modifications" % [peer_id, chunk_pos])
		_apply_terrain_modifications_for_chunk(chunk_pos)
		unapplied_chunks.erase(chunk_pos)

		# Clear this chunk from all players' tracking since it's now applied
		for p_id in player_applied_chunks.keys():
			player_applied_chunks[p_id].erase(chunk_pos)

## Apply terrain modifications for a specific chunk (called when chunk loads)
func _apply_terrain_modifications_for_chunk(chunk_pos: Vector2i) -> void:
	if not terrain_modification_history.has(chunk_pos):
		return  # No modifications for this chunk

	var chunk_mods = terrain_modification_history[chunk_pos]
	print("[Server] Applying %d terrain modifications for chunk %s" % [chunk_mods.size(), chunk_pos])

	for modification in chunk_mods:
		var operation: String = modification.operation
		var position: Array = modification.position
		var pos_v3 := Vector3(position[0], position[1], position[2])
		var data: Dictionary = modification.data

		print("[Server] Replaying: %s at %s with data: %s" % [operation, pos_v3, data])

		# Apply modification to server's terrain
		match operation:
			"dig_circle":
				var tool_name: String = data.get("tool", "stone_pickaxe")
				print("[Server] -> dig_circle with tool: %s" % tool_name)
				voxel_world.dig_circle(pos_v3, tool_name)
			"dig_square":
				var tool_name: String = data.get("tool", "stone_pickaxe")
				print("[Server] -> dig_square with tool: %s" % tool_name)
				voxel_world.dig_square(pos_v3, tool_name)
			"level_circle":
				var target_height: float = data.get("target_height", pos_v3.y)
				print("[Server] -> level_circle at height: %f" % target_height)
				voxel_world.level_circle(pos_v3, target_height)
			"place_circle":
				print("[Server] -> place_circle with unlimited earth")
				voxel_world.place_circle(pos_v3, 999999)
			"place_square":
				print("[Server] -> place_square with unlimited earth")
				voxel_world.place_square(pos_v3, 999999)

	# Broadcast these modifications to all clients
	for modification in chunk_mods:
		var operation: String = modification.operation
		var position: Array = modification.position
		var data: Dictionary = modification.data
		NetworkManager.rpc_apply_terrain_modification.rpc(operation, position, data)

	print("[Server] Applied and broadcasted %d modifications for chunk %s" % [chunk_mods.size(), chunk_pos])

## Replay all terrain modifications to a newly connected player
## Only replays modifications for currently loaded chunks
func _replay_terrain_modifications_to_player(peer_id: int) -> void:
	if terrain_modification_history.is_empty():
		print("[Server] No terrain modifications to replay to player %d" % peer_id)
		return

	# Get loaded chunks from chunk_manager
	var loaded_chunks := []
	if voxel_world and voxel_world.chunk_manager:
		loaded_chunks = voxel_world.chunk_manager.loaded_chunks.keys()

	var total_replayed := 0

	# Only replay modifications for chunks that are currently loaded
	for chunk_pos in loaded_chunks:
		if terrain_modification_history.has(chunk_pos):
			var chunk_mods = terrain_modification_history[chunk_pos]
			for modification in chunk_mods:
				var operation: String = modification.operation
				var position: Array = modification.position
				var data: Dictionary = modification.data

				# Send to this specific client only
				NetworkManager.rpc_apply_terrain_modification.rpc_id(peer_id, operation, position, data)
				total_replayed += 1

	print("[Server] Replayed %d terrain modifications from %d loaded chunks to player %d" % [total_replayed, loaded_chunks.size(), peer_id])

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

	# Create VoxelViewer for this player (server-side terrain streaming)
	# VoxelViewer will stream terrain data around the player's position
	var viewer := VoxelViewer.new()
	viewer.name = "VoxelViewer_%d" % peer_id
	viewer.view_distance = 256  # Match or slightly exceed client view distance
	viewer.requires_collisions = true
	viewer.requires_visuals = false  # Server doesn't need visual meshes
	# Note: VoxelTerrainMultiplayerSynchronizer will handle associating this viewer with the peer
	player.add_child(viewer)
	player_viewers[peer_id] = viewer

	print("[Server] Spawned player %d at %s with VoxelViewer" % [peer_id, spawn_pos])

	# Check for unapplied chunks near the spawn position (chunks that loaded before player connected)
	_check_unapplied_chunks()

	# Register player with chunk manager for environmental object spawning
	if voxel_world:
		voxel_world.register_player_for_spawning(peer_id, player)

		# Send all currently loaded chunks to the new player
		_send_loaded_chunks_to_player(peer_id)

	# Send all existing buildables to the new player
	_send_buildables_to_player(peer_id)

	# Send all existing enemies to the new player
	_send_enemies_to_player(peer_id)

	# Replay all terrain modifications to the new player
	_replay_terrain_modifications_to_player(peer_id)

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
	if voxel_world:
		voxel_world.unregister_player_from_spawning(peer_id)

	# Clean up VoxelViewer
	if player_viewers.has(peer_id):
		var viewer = player_viewers[peer_id]
		if viewer and is_instance_valid(viewer):
			viewer.queue_free()
		player_viewers.erase(peer_id)

	# Clean up player
	var player: Node3D = spawned_players[peer_id]
	if player and is_instance_valid(player):
		player.queue_free()

	spawned_players.erase(peer_id)

	# Clean up player terrain modification tracking
	player_applied_chunks.erase(peer_id)

	# Notify all clients to despawn through NetworkManager
	NetworkManager.rpc_despawn_player.rpc(peer_id)

	print("[Server] Despawned player %d" % peer_id)

func _get_spawn_point() -> Vector3:
	# Generate random spawn position within spawn area
	var random_offset := Vector2(randf_range(-10, 10), randf_range(-10, 10))
	var spawn_xz := player_spawn_area_center + random_offset

	# Get terrain height at this position
	var spawn_height: float = voxel_world.get_terrain_height_at(spawn_xz)

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
	var old_position: Vector3 = player.global_position

	# Validate: Check if movement is reasonable (prevent teleporting)
	var distance_moved := old_position.distance_to(new_position)
	const MAX_MOVEMENT_PER_TICK: float = 15.0  # ~8 m/s sprint * 2 = 16m margin

	if distance_moved > MAX_MOVEMENT_PER_TICK:
		# Reject invalid movement
		push_warning("[Server] Player %d attempted invalid movement: %.2fm in one tick" % [peer_id, distance_moved])
		return

	# Accept position update
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
func handle_environmental_damage(peer_id: int, chunk_pos: Vector2i, object_id: int, damage: float, hit_position: Vector3) -> void:
	print("[Server] Player %d damaged object %d in chunk %s (damage: %.1f)" % [peer_id, object_id, chunk_pos, damage])

	if not voxel_world or not voxel_world.chunk_manager:
		push_error("[Server] Cannot handle damage - voxel_world not initialized!")
		return

	var chunk_manager = voxel_world.chunk_manager

	# Check if chunk is loaded
	if not chunk_manager.loaded_chunks.has(chunk_pos):
		push_warning("[Server] Chunk %s not loaded, ignoring damage" % chunk_pos)
		return

	var objects: Array = chunk_manager.loaded_chunks[chunk_pos]

	# Validate object ID
	if object_id < 0 or object_id >= objects.size():
		push_error("[Server] Invalid object ID %d in chunk %s" % [object_id, chunk_pos])
		return

	var obj = objects[object_id]
	if not is_instance_valid(obj):
		push_warning("[Server] Object %d in chunk %s is not valid" % [object_id, chunk_pos])
		return

	# Apply damage
	if obj.has_method("take_damage"):
		var was_destroyed: bool = obj.take_damage(damage)

		if was_destroyed:
			print("[Server] Object %d in chunk %s destroyed!" % [object_id, chunk_pos])

			# Get resource drops before object is destroyed
			var resource_drops: Dictionary = obj.get_resource_drops() if obj.has_method("get_resource_drops") else {}

			# Broadcast destruction to all clients
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
						var net_id = "%s_%d_%d_%d" % [chunk_pos, object_id, Time.get_ticks_msec(), i]
						network_ids.append(net_id)

				NetworkManager.rpc_spawn_resource_drops.rpc(resource_drops, pos_array, network_ids)

			# Mark chunk as modified
			chunk_manager.modified_chunks[chunk_pos] = true
		else:
			# Object took damage but not destroyed
			# TODO: Could broadcast damage effect to clients
			pass
	else:
		push_warning("[Server] Object doesn't have take_damage method")

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
	placed_buildables[net_id] = {
		"piece_name": piece_name,
		"position": [position.x, position.y, position.z],
		"rotation_y": rotation_y
	}

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

## Track all terrain modifications for replication to new clients
## Changed to chunk-based storage: Dictionary[Vector2i, Array] where key is chunk position
var terrain_modification_history: Dictionary = {}  # chunk_pos -> Array of {operation, position, data}
var unapplied_chunks: Dictionary = {}  # chunk_pos -> bool (chunks that need mods applied when player gets close)
var player_applied_chunks: Dictionary = {}  # peer_id -> Dictionary[chunk_pos -> bool] (tracks which chunks each player has triggered application for)
const TERRAIN_HISTORY_FILE := "user://worlds/%s/terrain_history.json"
const CHUNK_SIZE: float = 32.0  # Must match chunk_manager.chunk_size

## Convert world position to chunk position
func _world_to_chunk_pos(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / CHUNK_SIZE),
		floori(world_pos.z / CHUNK_SIZE)
	)

## Handle terrain modification request (server-authoritative)
func handle_terrain_modification(peer_id: int, operation: String, position: Vector3, data: Dictionary) -> void:
	print("[Server] ========================================")
	print("[Server] Player %d requesting terrain modification: %s at %s" % [peer_id, operation, position])
	print("[Server] Tool: %s, Data: %s" % [data.get("tool", "unknown"), data])

	# Check if voxel_world exists
	if not voxel_world:
		push_error("[Server] voxel_world is null! Cannot modify terrain")
		return

	print("[Server] VoxelWorld found: %s" % voxel_world)

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
		"dig_circle":
			# Dig and collect earth
			print("[Server] Calling voxel_world.dig_circle...")
			var earth_collected: int = voxel_world.dig_circle(position, tool_name)
			print("[Server] dig_circle returned: %d earth" % earth_collected)
			if earth_collected > 0:
				inventory.add_item("earth", earth_collected)
				print("[Server] Player %d collected %d earth from digging" % [peer_id, earth_collected])
				# Sync inventory to client
				var inventory_data = inventory.get_inventory_data()
				NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)
			else:
				print("[Server] No earth collected from dig_circle")

		"dig_square":
			# Dig and collect earth
			print("[Server] Calling voxel_world.dig_square...")
			var earth_collected: int = voxel_world.dig_square(position, tool_name)
			print("[Server] dig_square returned: %d earth" % earth_collected)
			if earth_collected > 0:
				inventory.add_item("earth", earth_collected)
				print("[Server] Player %d collected %d earth from digging" % [peer_id, earth_collected])
				# Sync inventory to client
				var inventory_data = inventory.get_inventory_data()
				NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)
			else:
				print("[Server] No earth collected from dig_square")

		"level_circle":
			# Level terrain to target height
			var target_height: float = data.get("target_height", position.y)
			voxel_world.level_circle(position, target_height)
			print("[Server] Player %d leveled terrain at %s to height %f" % [peer_id, position, target_height])

		"place_circle":
			# Check if player has earth
			var earth_amount: int = inventory.get_item_count("earth")
			if earth_amount <= 0:
				print("[Server] Player %d has no earth to place" % peer_id)
				return

			var earth_used: int = voxel_world.place_circle(position, earth_amount)
			if earth_used > 0:
				inventory.remove_item("earth", earth_used)
				print("[Server] Player %d placed %d earth" % [peer_id, earth_used])
				# Add earth_amount to data for client broadcast
				data["earth_amount"] = earth_amount
				# Sync inventory to client
				var inventory_data = inventory.get_inventory_data()
				NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)

		"place_square":
			# Check if player has earth
			var earth_amount: int = inventory.get_item_count("earth")
			if earth_amount <= 0:
				print("[Server] Player %d has no earth to place" % peer_id)
				return

			var earth_used: int = voxel_world.place_square(position, earth_amount)
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

	# Add to chunk-based history for replaying to new clients
	var chunk_pos := _world_to_chunk_pos(position)
	if not terrain_modification_history.has(chunk_pos):
		terrain_modification_history[chunk_pos] = []

	terrain_modification_history[chunk_pos].append({
		"operation": operation,
		"position": position_array,
		"data": data
	})
	var total_modifications = 0
	for chunk_mods in terrain_modification_history.values():
		total_modifications += chunk_mods.size()
	print("[Server] Added modification to chunk %s history (total across all chunks: %d)" % [chunk_pos, total_modifications])

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
	_save_terrain_history()
	print("[Server] Manual save complete")

	# Notify all clients that save is complete
	NetworkManager.rpc_save_completed.rpc()

## Save terrain modification history to disk
func _save_terrain_history() -> void:
	if terrain_modification_history.is_empty():
		print("[Server] No terrain modifications to save")
		return

	var history_file_path := TERRAIN_HISTORY_FILE % world_config.world_name
	var file := FileAccess.open(history_file_path, FileAccess.WRITE)

	if not file:
		push_error("[Server] Failed to open terrain history file for writing: %s" % history_file_path)
		return

	# Convert chunk-based dictionary to saveable format
	# Format: {chunk_key: [modifications], ...} where chunk_key is "x,z"
	var save_data := {}
	for chunk_pos in terrain_modification_history.keys():
		var chunk_key := "%d,%d" % [chunk_pos.x, chunk_pos.y]
		save_data[chunk_key] = terrain_modification_history[chunk_pos]

	var json_string := JSON.stringify(save_data, "\t")
	file.store_string(json_string)
	file.close()

	var total_mods = 0
	for chunk_mods in terrain_modification_history.values():
		total_mods += chunk_mods.size()
	print("[Server] Saved %d terrain modifications across %d chunks to %s" % [total_mods, terrain_modification_history.size(), history_file_path])

## Load terrain modification history from disk
func _load_terrain_history() -> void:
	var history_file_path := TERRAIN_HISTORY_FILE % world_config.world_name

	if not FileAccess.file_exists(history_file_path):
		print("[Server] No terrain history file found at %s - starting fresh" % history_file_path)
		terrain_modification_history = {}
		return

	var file := FileAccess.open(history_file_path, FileAccess.READ)

	if not file:
		push_error("[Server] Failed to open terrain history file for reading: %s" % history_file_path)
		terrain_modification_history = {}
		return

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_string)

	if parse_result != OK:
		push_error("[Server] Failed to parse terrain history JSON: %s" % json.get_error_message())
		terrain_modification_history = {}
		return

	var loaded_data = json.get_data()
	if loaded_data is Dictionary:
		# New format: Dictionary with string keys "x,z"
		# Convert string keys "x,z" back to Vector2i
		terrain_modification_history = {}
		for key_str in loaded_data.keys():
			var coords = key_str.split(",")
			if coords.size() == 2:
				var chunk_pos = Vector2i(int(coords[0]), int(coords[1]))
				terrain_modification_history[chunk_pos] = loaded_data[key_str]

		var total_mods = 0
		for chunk_mods in terrain_modification_history.values():
			total_mods += chunk_mods.size()
		print("[Server] Loaded %d terrain modifications across %d chunks from %s" % [total_mods, terrain_modification_history.size(), history_file_path])

		# Note: Modifications will be applied per-chunk when chunks load via _apply_terrain_modifications_for_chunk()
	elif loaded_data is Array:
		# Old format: Array of modifications - convert to chunk-based Dictionary
		print("[Server] Converting old terrain history format to chunk-based format...")
		terrain_modification_history = {}

		for modification in loaded_data:
			var position: Array = modification.get("position", [0, 0, 0])
			var pos_v3 := Vector3(position[0], position[1], position[2])
			var chunk_pos := _world_to_chunk_pos(pos_v3)

			if not terrain_modification_history.has(chunk_pos):
				terrain_modification_history[chunk_pos] = []
			terrain_modification_history[chunk_pos].append(modification)

		var total_mods = loaded_data.size()
		print("[Server] Converted %d terrain modifications to %d chunks from %s" % [total_mods, terrain_modification_history.size(), history_file_path])

		# Save in new format immediately
		_save_terrain_history()
	else:
		push_error("[Server] Terrain history file contains invalid data (expected Dictionary or Array)")
		terrain_modification_history = {}

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
			_save_terrain_history()
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

	# TODO: Load other world state (time_of_day, global_events, etc.)

func _save_world_state() -> void:
	if not world_state_manager:
		return

	var additional_data = {
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
	if voxel_world:
		voxel_world.save_environmental_chunks()
	else:
		print("[Server] No voxel world to save chunks")

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
			var terrain_height = voxel_world.get_terrain_height_at(saved_xz)
			spawn_pos = Vector3(pos[0], terrain_height + 3.0, pos[2])

	# Check for unapplied chunks near spawn position before spawning
	# This ensures terrain modifications are applied before player spawns
	_check_unapplied_chunks_near_position(spawn_pos)

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

	# Create VoxelViewer for this player (server-side terrain streaming)
	var viewer := VoxelViewer.new()
	viewer.name = "VoxelViewer_%d" % peer_id
	viewer.view_distance = 256
	viewer.requires_collisions = true
	viewer.requires_visuals = false
	player.add_child(viewer)
	player_viewers[peer_id] = viewer

	print("[Server] Spawned player %d at %s with VoxelViewer" % [peer_id, spawn_pos])

	# Register player with chunk manager for environmental object spawning
	if voxel_world:
		voxel_world.register_player_for_spawning(peer_id, player)
		_send_loaded_chunks_to_player(peer_id)

	# Send all existing buildables to the new player
	_send_buildables_to_player(peer_id)

	# Replay all terrain modifications to the new player
	_replay_terrain_modifications_to_player(peer_id)

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
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")

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
func handle_craft_request(peer_id: int, recipe_name: String) -> void:
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if not player or not is_instance_valid(player):
		return

	if not player.has_node("Inventory"):
		return

	var inventory = player.get_node("Inventory")

	# Get the recipe
	var recipe = CraftingRecipes.get_recipe_by_name(recipe_name)
	if recipe.is_empty():
		print("[Server] Player %d requested invalid recipe: %s" % [peer_id, recipe_name])
		return

	# TODO: Get actual nearby stations from player
	# For now, allow all crafting (no station restrictions)
	var stations = ["workbench"]

	# Attempt to craft
	if CraftingRecipes.craft_item(recipe, inventory, stations):
		print("[Server] Player %d crafted %s" % [peer_id, recipe_name])

		# Sync inventory to client
		var inventory_data = inventory.get_inventory_data()
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, inventory_data)
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

## Handle enemy damage request (server-authoritative)
func handle_enemy_damage(peer_id: int, enemy_path: NodePath, damage: float, knockback: float, direction: Vector3) -> void:
	# Get the enemy node
	var enemy = get_node_or_null(enemy_path)
	if not enemy or not is_instance_valid(enemy):
		print("[Server] Enemy not found: %s" % enemy_path)
		return

	# Validate enemy has take_damage method
	if not enemy.has_method("take_damage"):
		print("[Server] Enemy %s doesn't have take_damage method" % enemy_path)
		return

	# Apply damage
	print("[Server] Applying %d damage to enemy %s" % [damage, enemy_path])
	enemy.take_damage(damage, knockback, direction)

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

	# Check for unapplied chunks near spawn position before respawning
	# This ensures terrain modifications are applied before player spawns
	_check_unapplied_chunks_near_position(spawn_position)

	# Respawn the player on server
	if player.has_method("respawn_at"):
		player.respawn_at(spawn_position)
		print("[Server] Player %d respawned at %s" % [peer_id, spawn_position])

	# Notify the client to respawn their local player
	var pos_array = [spawn_position.x, spawn_position.y, spawn_position.z]
	NetworkManager.rpc_player_respawned.rpc_id(peer_id, pos_array)

# ============================================================================
# MAP SYSTEM - PINS
# ============================================================================

func update_player_map_pins(peer_id: int, pins_data: Array) -> void:
	"""Update map pins for a player (called from NetworkManager)"""
	print("[Server] Updating map pins for peer %d (%d pins)" % [peer_id, pins_data.size()])

	# Store pins for this player
	player_map_pins[peer_id] = pins_data

	# Pins will be saved when player disconnects or server saves

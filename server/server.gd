extends Node

## Server - Server-side game logic and player management
## This handles all server-authoritative systems

# Preload WorldConfig
const WorldConfig = preload("res://shared/world_config.gd")

# Player management
var player_scene := preload("res://shared/player.tscn")
var spawned_players: Dictionary = {} # peer_id -> Player node
var player_viewers: Dictionary = {} # peer_id -> VoxelViewer node
var player_spawn_area_center: Vector2 = Vector2(0, 0) # Center of spawn area

# Buildable management
var placed_buildables: Dictionary = {} # network_id -> {piece_name, position, rotation_y}

# World configuration
var world_config = null  # Will be WorldConfig instance
const DEFAULT_WORLD_NAME: String = "world"

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

	# Set up console input (for dedicated servers)
	if DisplayServer.get_name() == "headless":
		_setup_console_input()

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

	if NetworkManager.start_server(port, max_players):
		is_running = true
		print("[Server] ===========================================")
		print("[Server] Server is now running!")
		print("[Server] Port: %d" % port)
		print("[Server] Max players: %d" % max_players)
		print("[Server] World: %s (seed: %d)" % [world_config.world_name, world_config.seed])
		print("[Server] ===========================================")
		print("[Server] Available commands: save, kick <id>, shutdown, players")
	else:
		push_error("[Server] Failed to start server")

func stop_server() -> void:
	if not is_running:
		return

	print("[Server] Shutting down server...")

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

# ============================================================================
# PLAYER MANAGEMENT (SERVER-AUTHORITATIVE)
# ============================================================================

func _on_player_joined(peer_id: int, player_name: String) -> void:
	print("[Server] Player joined: %s (ID: %d)" % [player_name, peer_id])

	# Send world config to the new client first
	if world_config:
		var world_data: Dictionary = world_config.to_dict()
		NetworkManager.rpc_send_world_config.rpc_id(peer_id, world_data)
		print("[Server] Sent world config to player %d" % peer_id)

	# Spawn player entity
	_spawn_player(peer_id, player_name)

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

	# Register player with chunk manager for environmental object spawning
	if voxel_world:
		voxel_world.register_player_for_spawning(peer_id, player)

		# Send all currently loaded chunks to the new player
		_send_loaded_chunks_to_player(peer_id)

	# Send all existing buildables to the new player
	_send_buildables_to_player(peer_id)

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
				var info := NetworkManager.get_player_info(peer_id)
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
			# TODO: Implement world saving
			print("[Server] Save complete (not implemented yet)")

		"shutdown":
			print("[Server] Shutting down...")
			stop_server()
			get_tree().quit()

		_:
			print("[Server] Unknown command: %s" % cmd)

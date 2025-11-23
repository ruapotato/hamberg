extends Node

## NetworkManager - Core networking utilities and state management
## This is an autoload singleton that manages network state across client and server

enum NetworkMode {
	NONE,
	SERVER,
	CLIENT,
	SINGLEPLAYER
}

# Network state
var current_mode: NetworkMode = NetworkMode.NONE
var is_server: bool = false
var is_client: bool = false

# Server configuration
const DEFAULT_PORT: int = 7777
const DEFAULT_MAX_PLAYERS: int = 10
var server_port: int = DEFAULT_PORT
var max_players: int = DEFAULT_MAX_PLAYERS

# Player tracking
var connected_players: Dictionary = {} # peer_id -> player_info
var local_player_id: int = 0

# Network stats
var ping: float = 0.0
var packet_loss: float = 0.0
var last_ping_time: float = 0.0

# Signals for network events
signal server_started()
signal server_stopped()
signal client_connected()
signal client_disconnected()
signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)

func _ready() -> void:
	# Set up multiplayer callbacks
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	print("[NetworkManager] Ready")

## Start a dedicated server
func start_server(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_PLAYERS) -> bool:
	if current_mode != NetworkMode.NONE:
		push_error("[NetworkManager] Cannot start server - already in mode: %s" % NetworkMode.keys()[current_mode])
		return false

	server_port = port
	max_players = max_clients

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_clients)

	if error != OK:
		push_error("[NetworkManager] Failed to create server on port %d: %s" % [port, error_string(error)])
		return false

	multiplayer.multiplayer_peer = peer
	current_mode = NetworkMode.SERVER
	is_server = true
	is_client = false

	print("[NetworkManager] Server started on port %d (max players: %d)" % [port, max_clients])
	server_started.emit()

	return true

## Connect to a server as a client
func connect_to_server(address: String, port: int) -> bool:
	if current_mode != NetworkMode.NONE:
		push_error("[NetworkManager] Cannot connect - already in mode: %s" % NetworkMode.keys()[current_mode])
		return false

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)

	if error != OK:
		push_error("[NetworkManager] Failed to connect to %s:%d: %s" % [address, port, error_string(error)])
		return false

	multiplayer.multiplayer_peer = peer
	current_mode = NetworkMode.CLIENT
	is_server = false
	is_client = true

	print("[NetworkManager] Connecting to %s:%d..." % [address, port])

	return true

## Start singleplayer (local server + client)
func start_singleplayer() -> bool:
	if current_mode != NetworkMode.NONE:
		push_error("[NetworkManager] Cannot start singleplayer - already in mode: %s" % NetworkMode.keys()[current_mode])
		return false

	# Start a local server
	if not start_server(DEFAULT_PORT, 1):
		return false

	current_mode = NetworkMode.SINGLEPLAYER

	print("[NetworkManager] Singleplayer mode started")

	return true

## Disconnect from network
func disconnect_network() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	connected_players.clear()
	local_player_id = 0

	var old_mode := current_mode
	current_mode = NetworkMode.NONE
	is_server = false
	is_client = false

	if old_mode == NetworkMode.SERVER or old_mode == NetworkMode.SINGLEPLAYER:
		print("[NetworkManager] Server stopped")
		server_stopped.emit()
	elif old_mode == NetworkMode.CLIENT:
		print("[NetworkManager] Disconnected from server")
		client_disconnected.emit()

## Register a player (server-side)
func register_player(peer_id: int, player_name: String) -> void:
	if not is_server:
		push_error("[NetworkManager] Only server can register players")
		return

	connected_players[peer_id] = {
		"name": player_name,
		"connected_at": Time.get_ticks_msec()
	}

	print("[NetworkManager] Player registered: %s (ID: %d)" % [player_name, peer_id])
	player_joined.emit(peer_id, player_name)

## Unregister a player (server-side)
func unregister_player(peer_id: int) -> void:
	if not is_server:
		push_error("[NetworkManager] Only server can unregister players")
		return

	if connected_players.has(peer_id):
		var player_name: String = connected_players[peer_id].get("name", "Unknown")
		connected_players.erase(peer_id)

		print("[NetworkManager] Player unregistered: %s (ID: %d)" % [player_name, peer_id])
		player_left.emit(peer_id)

## Get player info
func get_player_info(peer_id: int) -> Dictionary:
	return connected_players.get(peer_id, {})

## Get all connected players
func get_all_players() -> Dictionary:
	return connected_players

## Update network stats (call from _process)
func update_network_stats(delta: float) -> void:
	if not is_client or not multiplayer.multiplayer_peer:
		return

	last_ping_time += delta
	if last_ping_time >= 1.0:
		last_ping_time = 0.0
		# TODO: Implement actual ping measurement
		# For now, we can estimate from ENet if available
		ping = 0.0 # Placeholder

# ============================================================================
# MULTIPLAYER CALLBACKS
# ============================================================================

func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] Peer connected: %d" % peer_id)

	if is_server:
		# Server: A new client connected
		# Configure peer timeout to prevent disconnects during heavy processing
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if peer:
			var enet_peer := peer.get_peer(peer_id)
			if enet_peer:
				# Set timeout values (in milliseconds): limit, minimum, maximum
				# Values must satisfy: limit < minimum < maximum
				# Setting generous timeouts to handle world map generation and heavy processing
				enet_peer.set_timeout(10000, 20000, 60000)  # 10s limit, 20s min, 60s max
				print("[NetworkManager] Configured timeout for peer %d (10s limit, 20s min, 60s max)" % peer_id)

		# Wait for them to send their player info
		pass

func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer disconnected: %d" % peer_id)

	if is_server:
		# Server: Client disconnected, clean up their data
		unregister_player(peer_id)

func _on_connected_to_server() -> void:
	local_player_id = multiplayer.get_unique_id()
	print("[NetworkManager] Connected to server! Local ID: %d" % local_player_id)
	client_connected.emit()

func _on_connection_failed() -> void:
	push_error("[NetworkManager] Connection to server failed!")
	disconnect_network()

func _on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected")
	disconnect_network()

# ============================================================================
# RPC METHODS - These exist on all peers for network communication
# ============================================================================

## CLIENT -> SERVER: Register player name
@rpc("any_peer", "call_remote", "reliable")
func rpc_register_player(player_name: String) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	print("[NetworkManager] Received registration from peer %d: %s" % [peer_id, player_name])
	register_player(peer_id, player_name)

## CLIENT -> SERVER: Send player input (deprecated - use rpc_send_player_position)
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_send_player_input(input_data: Dictionary) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	# Forward to server's player management
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("receive_player_input"):
		server_node.receive_player_input(peer_id, input_data)

## CLIENT -> SERVER: Send player position (client-authoritative)
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_send_player_position(position_data: Dictionary) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	# Forward to server's player management
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("receive_player_position"):
		server_node.receive_player_position(peer_id, position_data)

## CLIENT -> SERVER: Report hit (trust-based)
@rpc("any_peer", "call_remote", "reliable")
func rpc_report_hit(target_id: int, damage: float, hit_position: Vector3) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_hit_report"):
		server_node.handle_hit_report(peer_id, target_id, damage, hit_position)

## CLIENT -> SERVER: Damage environmental object
@rpc("any_peer", "call_remote", "reliable")
func rpc_damage_environmental_object(chunk_pos: Array, object_id: int, damage: float, hit_position: Vector3) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_environmental_damage"):
		var chunk_pos_v2i := Vector2i(chunk_pos[0], chunk_pos[1])
		server_node.handle_environmental_damage(peer_id, chunk_pos_v2i, object_id, damage, hit_position)

## CLIENT -> SERVER: Damage enemy
@rpc("any_peer", "call_remote", "reliable")
func rpc_damage_enemy(enemy_path: NodePath, damage: float, knockback: float, direction: Vector3) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_enemy_damage"):
		server_node.handle_enemy_damage(peer_id, enemy_path, damage, knockback, direction)

## CLIENT -> SERVER: Place a buildable object
@rpc("any_peer", "call_remote", "reliable")
func rpc_place_buildable(piece_name: String, position: Array, rotation_y: float) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_place_buildable"):
		var pos_v3 := Vector3(position[0], position[1], position[2])
		server_node.handle_place_buildable(peer_id, piece_name, pos_v3, rotation_y)

@rpc("any_peer", "call_remote", "reliable")
func rpc_destroy_buildable(network_id: String) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_destroy_buildable"):
		server_node.handle_destroy_buildable(peer_id, network_id)

## CLIENT -> SERVER: Modify terrain (dig, place, level)
@rpc("any_peer", "call_remote", "reliable")
func rpc_modify_terrain(operation: String, position: Array, data: Dictionary) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_terrain_modification"):
		var pos_v3 := Vector3(position[0], position[1], position[2])
		server_node.handle_terrain_modification(peer_id, operation, pos_v3, data)

## SERVER -> ALL CLIENTS: Apply terrain modification
@rpc("authority", "call_remote", "reliable")
func rpc_apply_terrain_modification(operation: String, position: Array, data: Dictionary) -> void:
	print("[NetworkManager] Received terrain modification from server: %s at %s" % [operation, position])

	# Check if client is still loading
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.get("is_loading"):
		# Queue modification for later application
		if client_node.has_method("queue_terrain_modification"):
			client_node.queue_terrain_modification(operation, position, data)
		return

	# Get the voxel world on the client
	var voxel_world = get_node_or_null("/root/Main/Client/World/VoxelWorld")
	if not voxel_world:
		push_warning("[NetworkManager] Client: VoxelWorld not found at /root/Main/Client/World/VoxelWorld")
		return

	var pos_v3 := Vector3(position[0], position[1], position[2])

	# Check if player is near enough for VoxelTool to work (closer = more reliable)
	# VoxelTool needs player VERY close for terrain detail to be loaded
	const MAX_DISTANCE := 32.0  # 1 chunk = 32 units
	var local_player = client_node.get("local_player") if client_node else null
	if local_player and is_instance_valid(local_player):
		var player_pos: Vector3 = local_player.global_position
		var distance := Vector2(player_pos.x, player_pos.z).distance_to(Vector2(pos_v3.x, pos_v3.z))

		if distance > MAX_DISTANCE:
			# Player too far - queue for later application
			print("[NetworkManager] Player too far (%.1fm) - queuing terrain modification at %s" % [distance, pos_v3])
			if client_node.has_method("queue_terrain_modification"):
				client_node.queue_terrain_modification(operation, position, data)
			return

	var tool_name: String = data.get("tool", "stone_pickaxe")

	# Apply the modification locally on the client
	match operation:
		"dig_circle":
			voxel_world.dig_circle(pos_v3, tool_name)
		"dig_square":
			voxel_world.dig_square(pos_v3, tool_name)
		"level_circle":
			var target_height: float = data.get("target_height", pos_v3.y)
			voxel_world.level_circle(pos_v3, target_height)
		"place_circle":
			var earth_amount: int = data.get("earth_amount", 100)
			voxel_world.place_circle(pos_v3, earth_amount)
		"place_square":
			var earth_amount: int = data.get("earth_amount", 100)
			voxel_world.place_square(pos_v3, earth_amount)
		"grow_sphere":
			var strength: float = data.get("strength", 5.0)
			var radius: float = data.get("radius", 3.0)
			voxel_world.grow_sphere(pos_v3, radius, strength)
		"erode_sphere":
			var strength: float = data.get("strength", 5.0)
			var radius: float = data.get("radius", 3.0)
			voxel_world.erode_sphere(pos_v3, radius, strength)

	print("[NetworkManager] Client applied terrain modification: %s" % operation)

@rpc("authority", "call_remote", "reliable")
func rpc_remove_buildable(network_id: String) -> void:
	print("[NetworkManager] RPC received: remove_buildable(%s)" % network_id)

	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("remove_buildable"):
		client_node.remove_buildable(network_id)
	else:
		print("[NetworkManager] WARNING: Client node not found or doesn't have remove_buildable method")

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

## Get the local player's network ID
func get_local_player_id() -> int:
	return multiplayer.get_unique_id()

## Check if we're the server
func am_i_server() -> bool:
	return is_server

## Check if we're a client
func am_i_client() -> bool:
	return is_client

## Get current mode as string
func get_mode_string() -> String:
	return NetworkMode.keys()[current_mode]

# ============================================================================
# SERVER → CLIENT BROADCAST RPCs
# ============================================================================

## SERVER → CLIENTS: Spawn a player
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_player(peer_id: int, player_name: String, spawn_pos: Vector3) -> void:
	print("[NetworkManager] RPC received: spawn_player(%d, %s, %s)" % [peer_id, player_name, spawn_pos])

	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_player"):
		client_node.spawn_player(peer_id, player_name, spawn_pos)
	else:
		print("[NetworkManager] WARNING: Client node not found or doesn't have spawn_player method")

## SERVER → CLIENTS: Despawn a player
@rpc("authority", "call_remote", "reliable")
func rpc_despawn_player(peer_id: int) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("despawn_player"):
		client_node.despawn_player(peer_id)

## SERVER → CLIENTS: Broadcast player states
@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_broadcast_player_states(states: Array) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_player_states"):
		client_node.receive_player_states(states)

## SERVER → CLIENTS: Broadcast hit
@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_hit(target_id: int, damage: float, hit_position: Vector3) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_hit"):
		client_node.receive_hit(target_id, damage, hit_position)

## SERVER → CLIENTS: Spawn environmental objects for a chunk
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_environmental_objects(chunk_pos: Array, objects_data: Array) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_environmental_objects"):
		var chunk_pos_v2i := Vector2i(chunk_pos[0], chunk_pos[1])
		client_node.receive_environmental_objects(chunk_pos_v2i, objects_data)

## SERVER → CLIENTS: Despawn environmental objects for a chunk
@rpc("authority", "call_remote", "reliable")
func rpc_despawn_environmental_objects(chunk_pos: Array) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("despawn_environmental_objects"):
		var chunk_pos_v2i := Vector2i(chunk_pos[0], chunk_pos[1])
		client_node.despawn_environmental_objects(chunk_pos_v2i)

## SERVER → CLIENTS: Destroy a specific environmental object
@rpc("authority", "call_remote", "reliable")
func rpc_destroy_environmental_object(chunk_pos: Array, object_id: int) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("destroy_environmental_object"):
		var chunk_pos_v2i := Vector2i(chunk_pos[0], chunk_pos[1])
		client_node.destroy_environmental_object(chunk_pos_v2i, object_id)

## SERVER → CLIENTS: Spawn resource items at a position with server-generated network IDs
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_resource_drops(resources: Dictionary, position: Array, network_ids: Array) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_resource_drops"):
		var pos_v3 := Vector3(position[0], position[1], position[2])
		client_node.spawn_resource_drops(resources, pos_v3, network_ids)

## ANY_PEER → ALL: Resource item picked up (broadcast to all clients)
@rpc("any_peer", "call_remote", "reliable")
func rpc_pickup_resource_item(network_id: String) -> void:
	# Broadcast to all clients to remove the item
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("remove_resource_item"):
		client_node.remove_resource_item(network_id)

## SERVER → CLIENT: Send world configuration (seed, name)
@rpc("authority", "call_remote", "reliable")
func rpc_send_world_config(world_data: Dictionary) -> void:
	print("[NetworkManager] RPC received: send_world_config(%s)" % [world_data])

	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_world_config"):
		client_node.receive_world_config(world_data)
	else:
		print("[NetworkManager] WARNING: Client node not found or doesn't have receive_world_config method")

## SERVER → CLIENTS: Spawn a buildable object
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_buildable(piece_name: String, position: Array, rotation_y: float, network_id: String) -> void:
	print("[NetworkManager] RPC received: spawn_buildable(%s, %s, %f, %s)" % [piece_name, position, rotation_y, network_id])

	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_buildable"):
		var pos_v3 := Vector3(position[0], position[1], position[2])
		client_node.spawn_buildable(piece_name, pos_v3, rotation_y, network_id)
	else:
		print("[NetworkManager] WARNING: Client node not found or doesn't have spawn_buildable method")

# ============================================================================
# PERSISTENCE RPCs - Character and Inventory Management
# ============================================================================

## CLIENT -> SERVER: Request list of available characters for this world
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_character_list() -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("send_character_list"):
		server_node.send_character_list(peer_id)

## SERVER -> CLIENT: Send available characters
@rpc("authority", "call_remote", "reliable")
func rpc_receive_character_list(characters: Array) -> void:
	print("[NetworkManager] RPC received: receive_character_list with ", characters.size(), " characters")

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_character_list"):
		client_node.receive_character_list(characters)

## CLIENT -> SERVER: Load a character (or create new)
@rpc("any_peer", "call_remote", "reliable")
func rpc_load_character(character_id: String, character_name: String, is_new: bool) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("load_player_character"):
		server_node.load_player_character(peer_id, character_id, character_name, is_new)

## SERVER -> CLIENT: Send full inventory data
@rpc("authority", "call_remote", "reliable")
func rpc_sync_inventory(inventory_data: Array) -> void:
	print("[NetworkManager] RPC received: sync_inventory")

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_inventory_sync"):
		client_node.receive_inventory_sync(inventory_data)

## SERVER -> CLIENT: Update a single inventory slot (for efficiency)
@rpc("authority", "call_remote", "reliable")
func rpc_update_inventory_slot(slot: int, item: String, amount: int) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_inventory_slot_update"):
		client_node.receive_inventory_slot_update(slot, item, amount)

## SERVER -> CLIENT: Send full equipment data
@rpc("authority", "call_remote", "reliable")
func rpc_sync_equipment(equipment_data: Dictionary) -> void:
	print("[NetworkManager] RPC received: sync_equipment")

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_equipment_sync"):
		client_node.receive_equipment_sync(equipment_data)

## CLIENT -> SERVER: Request to pick up an item (server validates and updates inventory)
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pickup_item(item_name: String, amount: int, network_id: String) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_pickup_request"):
		server_node.handle_pickup_request(peer_id, item_name, amount, network_id)

## CLIENT -> SERVER: Request to craft an item (server validates and updates inventory)
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_craft(recipe_name: String) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_craft_request"):
		server_node.handle_craft_request(peer_id, recipe_name)

## CLIENT -> SERVER: Request manual save
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_save() -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	print("[NetworkManager] Player %d requested manual save" % peer_id)

	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_manual_save_request"):
		server_node.handle_manual_save_request(peer_id)

## SERVER -> CLIENT: Confirm save completed
@rpc("authority", "call_remote", "reliable")
func rpc_save_completed() -> void:
	print("[NetworkManager] Server save completed")

	# Show notification to client
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("show_save_notification"):
		client_node.show_save_notification()

## CLIENT -> SERVER: Request to equip an item
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_equip_item(slot: int, item_id: String) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_equip_request"):
		server_node.handle_equip_request(peer_id, slot, item_id)

## CLIENT -> SERVER: Request to unequip a slot
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_unequip_slot(slot: int) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_unequip_request"):
		server_node.handle_unequip_request(peer_id, slot)

## CLIENT -> SERVER: Request to swap two inventory slots
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_swap_slots(slot_a: int, slot_b: int) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_swap_slots_request"):
		server_node.handle_swap_slots_request(peer_id, slot_a, slot_b)

## CLIENT -> SERVER: Player died
@rpc("any_peer", "call_remote", "reliable")
func rpc_player_died() -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_player_death"):
		server_node.handle_player_death(peer_id)

## CLIENT -> SERVER: Request respawn
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_respawn() -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_respawn_request"):
		server_node.handle_respawn_request(peer_id)

## SERVER -> CLIENT: Tell client their player respawned
@rpc("authority", "call_remote", "reliable")
func rpc_player_respawned(spawn_position: Array) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("handle_player_respawned"):
		var pos = Vector3(spawn_position[0], spawn_position[1], spawn_position[2])
		client_node.handle_player_respawned(pos)

## SERVER -> CLIENTS: Spawn an enemy
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_enemy(enemy_path: NodePath, enemy_type: String, position: Array, enemy_name: String) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_enemy"):
		client_node.spawn_enemy(enemy_path, enemy_type, Vector3(position[0], position[1], position[2]), enemy_name)

## SERVER -> CLIENTS: Despawn an enemy
@rpc("authority", "call_remote", "reliable")
func rpc_despawn_enemy(enemy_path: NodePath) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("despawn_enemy"):
		client_node.despawn_enemy(enemy_path)

## SERVER -> CLIENTS: Update enemy states (position, animation)
@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_update_enemy_states(states: Array) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("update_enemy_states"):
		client_node.update_enemy_states(states)

# ============================================================================
# MAP SYSTEM - PINGS
# ============================================================================

## CLIENT -> SERVER: Send a ping at world position
@rpc("any_peer", "call_remote", "reliable")
func rpc_send_ping(world_pos: Array) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if is_server:
		# Server received ping from client - broadcast to all clients
		print("[NetworkManager] Broadcasting ping from peer %d at %s" % [sender_id, world_pos])
		rpc_receive_ping.rpc(world_pos, sender_id)
	else:
		# Client sending to server (should be sent to server ID 1)
		pass

## SERVER -> CLIENTS: Receive a ping from another player
@rpc("authority", "call_remote", "reliable")
func rpc_receive_ping(world_pos: Array, from_peer: int) -> void:
	if is_server:
		return

	print("[NetworkManager] Received ping from peer %d at %s" % [from_peer, world_pos])

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_ping"):
		client_node.receive_ping(Vector2(world_pos[0], world_pos[1]), from_peer)

# ============================================================================
# MAP SYSTEM - PINS
# ============================================================================

## CLIENT -> SERVER: Update map pins for persistence
@rpc("any_peer", "call_remote", "reliable")
func rpc_update_map_pins(pins_data: Array) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if is_server:
		# Server received pins update from client
		print("[NetworkManager] Received map pins update from peer %d (%d pins)" % [sender_id, pins_data.size()])

		# Forward to server for saving
		var server_node := get_node_or_null("/root/Main/Server")
		if server_node and server_node.has_method("update_player_map_pins"):
			server_node.update_player_map_pins(sender_id, pins_data)

## SERVER -> CLIENT: Send character data (including map pins)
@rpc("authority", "call_remote", "reliable")
func rpc_send_character_data(character_data: Dictionary) -> void:
	if is_server:
		return

	print("[NetworkManager] Received character data")

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_character_data"):
		client_node.receive_character_data(character_data)

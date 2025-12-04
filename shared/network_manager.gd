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
	if not multiplayer.is_server():
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
	if not multiplayer.is_server():
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
	client_disconnected.emit()
	disconnect_network()

# ============================================================================
# RPC METHODS - These exist on all peers for network communication
# ============================================================================

## CLIENT -> SERVER: Register player name
@rpc("any_peer", "call_remote", "reliable")
func rpc_register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	print("[NetworkManager] Received registration from peer %d: %s" % [peer_id, player_name])
	register_player(peer_id, player_name)

## CLIENT -> SERVER: Send player input (deprecated - use rpc_send_player_position)
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_send_player_input(input_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	# Forward to server's player management
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("receive_player_input"):
		server_node.receive_player_input(peer_id, input_data)

## CLIENT -> SERVER: Send player position (client-authoritative)
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_send_player_position(position_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	# Forward to server's player management
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("receive_player_position"):
		server_node.receive_player_position(peer_id, position_data)

## CLIENT -> SERVER: Report hit (trust-based)
@rpc("any_peer", "call_remote", "reliable")
func rpc_report_hit(target_id: int, damage: float, hit_position: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_hit_report"):
		server_node.handle_hit_report(peer_id, target_id, damage, hit_position)

## CLIENT -> SERVER: Damage environmental object
@rpc("any_peer", "call_remote", "reliable")
func rpc_damage_environmental_object(chunk_pos: Array, object_id: int, damage: float, hit_position: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_environmental_damage"):
		var chunk_pos_v2i := Vector2i(chunk_pos[0], chunk_pos[1])
		server_node.handle_environmental_damage(peer_id, chunk_pos_v2i, object_id, damage, hit_position)

## CLIENT -> SERVER: Damage a dynamic spawned object (fallen logs, split logs, etc.)
@rpc("any_peer", "call_remote", "reliable")
func rpc_damage_dynamic_object(object_name: String, damage: float, hit_position: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_dynamic_object_damage"):
		server_node.handle_dynamic_object_damage(peer_id, object_name, damage, hit_position)

## CLIENT -> SERVER: Damage enemy (client-authoritative hits using network_id)
## damage_type: WeaponData.DamageType enum (-1 = unspecified, uses base damage)
@rpc("any_peer", "call_remote", "reliable")
func rpc_damage_enemy(enemy_network_id: int, damage: float, knockback: float, direction: Array, damage_type: int = -1) -> void:
	print("[NetworkManager] rpc_damage_enemy received: net_id=%d, damage=%.1f, type=%d, is_server=%s" % [enemy_network_id, damage, damage_type, is_server])
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_enemy_damage"):
		# Defensive check for direction array
		var dir_v3 := Vector3.FORWARD
		if direction.size() >= 3:
			dir_v3 = Vector3(direction[0], direction[1], direction[2])
		else:
			print("[NetworkManager] WARNING: direction array invalid size: %d" % direction.size())
		server_node.handle_enemy_damage(peer_id, enemy_network_id, damage, knockback, dir_v3, damage_type)
	else:
		print("[NetworkManager] ERROR: Server node not found or missing handle_enemy_damage")

## CLIENT -> SERVER: Place a buildable object
@rpc("any_peer", "call_remote", "reliable")
func rpc_place_buildable(piece_name: String, position: Array, rotation_y: float) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_place_buildable"):
		var pos_v3 := Vector3(position[0], position[1], position[2])
		server_node.handle_place_buildable(peer_id, piece_name, pos_v3, rotation_y)

@rpc("any_peer", "call_remote", "reliable")
func rpc_destroy_buildable(network_id: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_destroy_buildable"):
		server_node.handle_destroy_buildable(peer_id, network_id)

## CLIENT -> SERVER: Modify terrain (dig, place, level)
@rpc("any_peer", "call_remote", "reliable")
func rpc_modify_terrain(operation: String, position: Array, data: Dictionary) -> void:
	if not multiplayer.is_server():
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

	# Get the terrain world on the client
	var terrain_world = get_node_or_null("/root/Main/Client/World/TerrainWorld")
	if not terrain_world:
		push_warning("[NetworkManager] Client: TerrainWorld not found at /root/Main/Client/World/TerrainWorld")
		return

	var pos_v3 := Vector3(position[0], position[1], position[2])
	var tool_name: String = data.get("tool", "stone_pickaxe")

	# Apply the modification locally on the client (custom terrain handles chunk loading)
	match operation:
		"dig_square":
			terrain_world.dig_square(pos_v3, tool_name)
		"place_square":
			var earth_amount: int = data.get("earth_amount", 100)
			terrain_world.place_square(pos_v3, earth_amount)
		"flatten_square":
			var target_height: float = data.get("target_height", pos_v3.y)
			terrain_world.flatten_square(pos_v3, target_height)

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

## Check if we're in singleplayer mode (server exists in same process)
## This is useful because RPCs don't work properly in singleplayer
func is_singleplayer() -> bool:
	return get_node_or_null("/root/Main/Server") != null

## Get the server node if running in singleplayer mode
## Returns null if running as dedicated client
func get_local_server() -> Node:
	return get_node_or_null("/root/Main/Server")

## Call a server method - handles both singleplayer (direct) and multiplayer (RPC)
## Returns true if in singleplayer and method was called directly
## In multiplayer, returns false and you should use RPC instead
func call_server_method(method_name: String, args: Array = []) -> bool:
	var server = get_local_server()
	if server and server.has_method(method_name):
		# Singleplayer - call directly with peer_id
		var peer_id = multiplayer.get_unique_id()
		server.callv(method_name, [peer_id] + args)
		return true
	return false

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

## CLIENT → SERVER: Request resource drops (e.g., from enemy loot)
## Server will broadcast to all clients
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_resource_drops(resources: Dictionary, position: Array, network_ids: Array) -> void:
	# Only server handles this
	if not multiplayer.is_server():
		return

	# Broadcast to all clients (including the requester)
	rpc_spawn_resource_drops.rpc(resources, position, network_ids)

## SERVER → CLIENTS: Spawn resource items at a position with server-generated network IDs
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_resource_drops(resources: Dictionary, position: Array, network_ids: Array) -> void:
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_resource_drops"):
		var pos_v3 := Vector3(position[0], position[1], position[2])
		client_node.spawn_resource_drops(resources, pos_v3, network_ids)

## SERVER → CLIENTS: Spawn a fallen log (from chopped truffula tree)
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_fallen_log(position: Array, rotation_y: float, network_id: String) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_fallen_log"):
		var pos_v3 := Vector3(position[0], position[1], position[2])
		client_node.spawn_fallen_log(pos_v3, rotation_y, network_id)
	else:
		print("[NetworkManager] WARNING: Cannot spawn fallen log - no Client node or method")

## SERVER → CLIENTS: Spawn split logs (from chopped fallen log)
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_split_logs(positions: Array, network_ids: Array, rotation_y: float = 0.0) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_split_logs"):
		client_node.spawn_split_logs(positions, network_ids, rotation_y)
	else:
		print("[NetworkManager] WARNING: Cannot spawn split logs - no Client node or method")

## SERVER → CLIENTS: Destroy a dynamic object (fallen log, split log, etc.)
@rpc("authority", "call_remote", "reliable")
func rpc_destroy_dynamic_object(object_name: String) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("destroy_dynamic_object"):
		client_node.destroy_dynamic_object(object_name)
	else:
		print("[NetworkManager] WARNING: Cannot destroy dynamic object - no Client node or method")

## SERVER → CLIENTS: Dynamic object took damage (update health bar and play effects)
@rpc("authority", "call_remote", "reliable")
func rpc_dynamic_object_damaged(object_name: String, damage: float, current_health: float, max_health: float) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("on_dynamic_object_damaged"):
		client_node.on_dynamic_object_damaged(object_name, damage, current_health, max_health)

## SERVER → CLIENTS: Resource item picked up (broadcast to all clients)
@rpc("authority", "call_remote", "reliable")
func rpc_pickup_resource_item(network_id: String) -> void:
	print("[NetworkManager] RPC received: pickup_resource_item(%s)" % network_id)
	# Broadcast to all clients to remove the item
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("remove_resource_item"):
		client_node.remove_resource_item(network_id)
	else:
		print("[NetworkManager] WARNING: Cannot remove item - no Client node or method")

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
	if not multiplayer.is_server():
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
	if not multiplayer.is_server():
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

## SERVER -> CLIENT: Send food buff data (after eating or on spawn)
@rpc("authority", "call_remote", "reliable")
func rpc_sync_food(food_data: Array) -> void:
	print("[NetworkManager] RPC received: sync_food (%d items)" % food_data.size())

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_food_sync"):
		client_node.receive_food_sync(food_data)

## SERVER -> CLIENT: Sync gold amount (after buy/sell/upgrade)
@rpc("authority", "call_remote", "reliable")
func rpc_sync_gold(gold_amount: int) -> void:
	print("[NetworkManager] RPC received: sync_gold (%d)" % gold_amount)

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_gold_sync"):
		client_node.receive_gold_sync(gold_amount)

## CLIENT -> SERVER: Request to pick up an item (server validates and updates inventory)
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pickup_item(item_name: String, amount: int, network_id: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_pickup_request"):
		server_node.handle_pickup_request(peer_id, item_name, amount, network_id)

## CLIENT -> SERVER: Request to craft an item (server validates and updates inventory)
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_craft(recipe_name: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_craft_request"):
		server_node.handle_craft_request(peer_id, recipe_name)

## CLIENT -> SERVER: Request manual save
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_save() -> void:
	if not multiplayer.is_server():
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

## SERVER -> CLIENT: Sync modified terrain chunk
@rpc("authority", "call_remote", "reliable")
func rpc_sync_terrain_chunk(chunk_x: int, chunk_z: int, chunk_data: Dictionary) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_terrain_chunk"):
		client_node.receive_terrain_chunk(chunk_x, chunk_z, chunk_data)

## CLIENT -> SERVER: Request to equip an item
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_equip_item(slot: int, item_id: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_equip_request"):
		server_node.handle_equip_request(peer_id, slot, item_id)

## CLIENT -> SERVER: Request to unequip a slot
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_unequip_slot(slot: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_unequip_request"):
		server_node.handle_unequip_request(peer_id, slot)

## CLIENT -> SERVER: Request to eat food (server-authoritative)
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_eat_food(food_id: String, inventory_slot: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_eat_food_request"):
		server_node.handle_eat_food_request(peer_id, food_id, inventory_slot)

## CLIENT -> SERVER: Request to take item from cooking station
## Client runs the cooking simulation, tells server what cooked item to give
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_cooking_station_take(item_id: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_cooking_station_take"):
		server_node.handle_cooking_station_take(peer_id, item_id)

## CLIENT -> SERVER: Request to add raw meat to cooking station
## Server removes item from inventory, client handles the cooking simulation
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_cooking_station_add(item_id: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_cooking_station_add"):
		server_node.handle_cooking_station_add(peer_id, item_id)

## CLIENT -> SERVER: Request to swap two inventory slots
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_swap_slots(slot_a: int, slot_b: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_swap_slots_request"):
		server_node.handle_swap_slots_request(peer_id, slot_a, slot_b)

## CLIENT -> SERVER: Request to drop item from inventory
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_drop_item(slot: int, amount: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_drop_item_request"):
		server_node.handle_drop_item_request(peer_id, slot, amount)

## CLIENT -> SERVER: Request to transfer item from chest to player inventory
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_chest_to_player(chest_slot: int, player_slot: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_chest_to_player"):
		server_node.handle_chest_to_player(peer_id, chest_slot, player_slot)

## CLIENT -> SERVER: Request to transfer item from player inventory to chest
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_player_to_chest(player_slot: int, chest_slot: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_player_to_chest"):
		server_node.handle_player_to_chest(peer_id, player_slot, chest_slot)

## CLIENT -> SERVER: Request to swap two slots within chest
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_chest_swap(slot_a: int, slot_b: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_chest_swap"):
		server_node.handle_chest_swap(peer_id, slot_a, slot_b)

## CLIENT -> SERVER: Request quick-deposit (auto-deposit matching items)
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_quick_deposit(player_slot: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_quick_deposit"):
		server_node.handle_quick_deposit(peer_id, player_slot)

## CLIENT -> SERVER: Open chest (track which chest player is using)
@rpc("any_peer", "call_remote", "reliable")
func rpc_open_chest(chest_network_id: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_open_chest"):
		server_node.handle_open_chest(peer_id, chest_network_id)

## CLIENT -> SERVER: Close chest
@rpc("any_peer", "call_remote", "reliable")
func rpc_close_chest() -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_close_chest"):
		server_node.handle_close_chest(peer_id)

## SERVER -> CLIENT: Sync chest inventory
@rpc("authority", "call_remote", "reliable")
func rpc_sync_chest_inventory(chest_network_id: String, inventory_data: Array) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("handle_chest_sync"):
		client_node.handle_chest_sync(chest_network_id, inventory_data)

## CLIENT -> SERVER: Player died
@rpc("any_peer", "call_remote", "reliable")
func rpc_player_died() -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_player_death"):
		server_node.handle_player_death(peer_id)

## CLIENT -> SERVER: Request respawn
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_respawn() -> void:
	if not multiplayer.is_server():
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
## position array: [x, y, z, network_id, host_peer_id]
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_enemy(enemy_path: NodePath, enemy_type: String, position: Array, enemy_name: String) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_enemy"):
		var pos = Vector3(position[0], position[1], position[2])
		var net_id = position[3] if position.size() > 3 else 0
		var host_peer_id = position[4] if position.size() > 4 else 0
		client_node.spawn_enemy(enemy_path, enemy_type, pos, enemy_name, net_id, host_peer_id)

## SERVER -> CLIENTS: Despawn an enemy
@rpc("authority", "call_remote", "reliable")
func rpc_despawn_enemy(enemy_path: NodePath) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("despawn_enemy"):
		client_node.despawn_enemy(enemy_path)

## SERVER -> CLIENTS: Update enemy states (position, animation)
## Compact format: { "path": [px, py, pz, rot, state, hp], ... }
@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_update_enemy_states(states: Dictionary) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("update_enemy_states"):
		client_node.update_enemy_states(states)

## HOST CLIENT -> SERVER: Notify server that enemy died (host has dropped loot)
@rpc("any_peer", "call_remote", "reliable")
func rpc_notify_enemy_died(enemy_network_id: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if not multiplayer.is_server():
		return

	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_enemy_died"):
		server_node.handle_enemy_died(sender_id, enemy_network_id)

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

# ============================================================================
# ENEMY DAMAGE TO PLAYER
# ============================================================================

## SERVER -> CLIENT: Enemy deals damage to player (server-authoritative)
@rpc("authority", "call_remote", "reliable")
func rpc_enemy_damage_player(damage: float, attacker_id: int, knockback_dir: Array) -> void:
	if is_server:
		return

	print("[NetworkManager] Received enemy damage: %.1f" % damage)

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_enemy_damage"):
		var kb_vector = Vector3(knockback_dir[0], knockback_dir[1], knockback_dir[2])
		client_node.receive_enemy_damage(damage, attacker_id, kb_vector)

# ============================================================================
# TERRAIN MODIFICATION SYNC
# ============================================================================

## SERVER -> CLIENT: Sync all terrain modifications (sent on connect)
@rpc("authority", "call_remote", "reliable")
func rpc_sync_terrain_modifications(modifications: Array) -> void:
	if is_server:
		return

	print("[NetworkManager] Received %d terrain modifications from server" % modifications.size())

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_terrain_modifications"):
		client_node.receive_terrain_modifications(modifications)
	else:
		push_warning("[NetworkManager] Client node not found or doesn't have receive_terrain_modifications method")

# ============================================================================
# CLIENT-SIDE ENEMY SIMULATION WITH SERVER CONSENSUS
# ============================================================================

## CLIENT -> SERVER: Host client reports enemy position/state/target at 10Hz
## Server relays this to all other clients for Valheim-style sync
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_report_enemy_position(enemy_network_id: int, position: Array, rotation_y: float, ai_state: int, target_peer: int = 0) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_node("EnemySpawner"):
		var spawner = server_node.get_node("EnemySpawner")
		if spawner.has_method("receive_enemy_position_report"):
			var pos_v3 := Vector3(position[0], position[1], position[2])
			spawner.receive_enemy_position_report(peer_id, enemy_network_id, pos_v3, rotation_y, ai_state, target_peer)

## SERVER -> CLIENTS: Broadcast consensus enemy positions
## Format: { network_id: [px, py, pz, rot_y, state, hp], ... }
@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_broadcast_enemy_consensus(states: Dictionary) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_enemy_consensus"):
		client_node.receive_enemy_consensus(states)

## SERVER -> HOST CLIENT: Apply damage to enemy (forwarded from attacking player)
## This is called by server to tell the HOST client to damage their authoritative enemy copy
## damage_type: WeaponData.DamageType enum (-1 = unspecified)
## attacker_peer_id: The peer ID of the player who dealt the damage (for threat tracking)
@rpc("authority", "call_remote", "reliable")
func rpc_apply_enemy_damage(enemy_network_id: int, damage: float, knockback: float, direction: Array, damage_type: int = -1, attacker_peer_id: int = 0) -> void:
	if is_server:
		return

	print("[NetworkManager] rpc_apply_enemy_damage received: net_id=%d, damage=%.1f, type=%d, attacker=%d" % [enemy_network_id, damage, damage_type, attacker_peer_id])

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("apply_enemy_damage"):
		var dir_v3 := Vector3.FORWARD
		if direction.size() >= 3:
			dir_v3 = Vector3(direction[0], direction[1], direction[2])
		client_node.apply_enemy_damage(enemy_network_id, damage, knockback, dir_v3, damage_type, attacker_peer_id)

## SERVER -> ALL CLIENTS: Update enemy host (when original host disconnects)
@rpc("authority", "call_remote", "reliable")
func rpc_update_enemy_host(enemy_network_id: int, new_host_peer_id: int) -> void:
	if is_server:
		return

	print("[NetworkManager] Enemy %d host changed to peer %d" % [enemy_network_id, new_host_peer_id])

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("update_enemy_host"):
		client_node.update_enemy_host(enemy_network_id, new_host_peer_id)

# ============================================================================
# BOSS ACTION RPCs
# ============================================================================

## HOST CLIENT -> SERVER: Report boss action (stomp, boulder, eye beam, etc.)
## action_data: { "type": "stomp"|"boulder"|"eye_beam", "target_pos": [x,y,z], ... }
@rpc("any_peer", "call_remote", "reliable")
func rpc_report_boss_action(enemy_network_id: int, action_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	# Server broadcasts to all clients
	rpc_broadcast_boss_action.rpc(enemy_network_id, action_data)

## SERVER -> ALL CLIENTS: Broadcast boss action to all clients
@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_boss_action(enemy_network_id: int, action_data: Dictionary) -> void:
	if is_server:
		return

	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("receive_boss_action"):
		client_node.receive_boss_action(enemy_network_id, action_data)

# ============================================================================
# DEBUG CONSOLE RPCs
# ============================================================================

## CLIENT -> SERVER: Debug give item
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_give_item(item_name: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_give_item"):
		server_node.handle_debug_give_item(peer_id, item_name, amount)

## CLIENT -> SERVER: Debug spawn entity
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_spawn_entity(entity_type: String, count: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_spawn_entity"):
		server_node.handle_debug_spawn_entity(peer_id, entity_type, count)

## CLIENT -> SERVER: Debug teleport
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_teleport(position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_teleport"):
		server_node.handle_debug_teleport(peer_id, position)

## CLIENT -> SERVER: Debug heal
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_heal() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_heal"):
		server_node.handle_debug_heal(peer_id)

## CLIENT -> SERVER: Debug god mode
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_god_mode(enabled: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_god_mode"):
		server_node.handle_debug_god_mode(peer_id, enabled)

## CLIENT -> SERVER: Debug clear inventory
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_clear_inventory() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_clear_inventory"):
		server_node.handle_debug_clear_inventory(peer_id)

## CLIENT -> SERVER: Debug kill nearby enemies
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_kill_nearby() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_kill_nearby"):
		server_node.handle_debug_kill_nearby(peer_id)

## CLIENT -> SERVER: Debug give gold
@rpc("any_peer", "call_remote", "reliable")
func rpc_debug_give_gold(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_debug_give_gold"):
		server_node.handle_debug_give_gold(peer_id, amount)

# ============================================================================
# GRAPHICS SETTINGS
# ============================================================================

## CLIENT -> SERVER: Set player's preferred object render distance
## Server uses this to determine which chunks to load/send for this player
@rpc("any_peer", "call_remote", "reliable")
func rpc_set_object_distance(distance: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_set_object_distance"):
		server_node.handle_set_object_distance(peer_id, distance)

# ============================================================================
# SHNARKEN SHOP SYSTEM
# ============================================================================

## CLIENT -> SERVER: Request to buy an item from Shnarken shop
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_shop_buy(item_id: String, price: int) -> void:
	# Use multiplayer.is_server() for singleplayer compatibility
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_shop_buy"):
		server_node.handle_shop_buy(peer_id, item_id, price)

## CLIENT -> SERVER: Request to sell items from inventory
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_shop_sell(slot_index: int, amount: int, total_price: int) -> void:
	# Use multiplayer.is_server() for singleplayer compatibility
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_shop_sell"):
		server_node.handle_shop_sell(peer_id, slot_index, amount, total_price)

## CLIENT -> SERVER: Request to upgrade armor piece
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_shop_upgrade(equipment_slot: int, cost: int) -> void:
	# Use multiplayer.is_server() for singleplayer compatibility
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_shop_upgrade"):
		server_node.handle_shop_upgrade(peer_id, equipment_slot, cost)

# ============================================================================
# FIRE AREA VISUAL EFFECTS SYNC
# ============================================================================

## CLIENT -> SERVER: Report fire area creation for visual sync
@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_fire_area(position: Array, radius: float, duration: float) -> void:
	print("[NetworkManager] rpc_spawn_fire_area received: is_server=%s" % multiplayer.is_server())
	if not multiplayer.is_server():
		return
	var from_peer := multiplayer.get_remote_sender_id()
	var peers = multiplayer.get_peers()
	print("[NetworkManager] Broadcasting fire area to %d peers (from peer %d)" % [peers.size(), from_peer])
	# Broadcast to all other clients
	for peer in peers:
		if peer != from_peer:
			print("[NetworkManager] Sending fire area to peer %d" % peer)
			rpc_broadcast_fire_area.rpc_id(peer, position, radius, duration)

## SERVER -> CLIENT: Broadcast fire area visual effect
@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_fire_area(position: Array, radius: float, duration: float) -> void:
	print("[NetworkManager] rpc_broadcast_fire_area received: radius=%.1f, duration=%.1f" % [radius, duration])
	# Create visual-only fire area on receiving client
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_visual_fire_area"):
		var pos = Vector3(position[0], position[1], position[2])
		client_node.spawn_visual_fire_area(pos, radius, duration)
	else:
		print("[NetworkManager] ERROR: Could not find Client node or spawn_visual_fire_area method")

# ============================================================================
# PROJECTILE VISUAL EFFECTS SYNC
# ============================================================================

## CLIENT -> SERVER: Report projectile spawn for visual sync
@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_projectile(projectile_type: String, position: Array, direction: Array, speed: float) -> void:
	print("[NetworkManager] rpc_spawn_projectile received: type=%s, is_server=%s" % [projectile_type, multiplayer.is_server()])
	if not multiplayer.is_server():
		return
	var from_peer := multiplayer.get_remote_sender_id()
	var peers = multiplayer.get_peers()
	print("[NetworkManager] Broadcasting projectile to %d peers (from peer %d)" % [peers.size(), from_peer])
	# Broadcast to all other clients
	for peer in peers:
		if peer != from_peer:
			print("[NetworkManager] Sending projectile to peer %d" % peer)
			rpc_broadcast_projectile.rpc_id(peer, projectile_type, position, direction, speed)

## SERVER -> CLIENT: Broadcast projectile visual effect
@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_projectile(projectile_type: String, position: Array, direction: Array, speed: float) -> void:
	print("[NetworkManager] rpc_broadcast_projectile received: type=%s" % projectile_type)
	# Create visual-only projectile on receiving client
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_visual_projectile"):
		var pos = Vector3(position[0], position[1], position[2])
		var dir = Vector3(direction[0], direction[1], direction[2])
		client_node.spawn_visual_projectile(projectile_type, pos, dir, speed)
	else:
		print("[NetworkManager] ERROR: Could not find Client node or spawn_visual_projectile method")

# ============================================================================
# HIT/PARRY EFFECT SYNC
# ============================================================================

## CLIENT -> SERVER: Report hit effect at position
@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_hit_effect(position: Array) -> void:
	# Server broadcasts to all other clients
	rpc_broadcast_hit_effect.rpc([position[0], position[1], position[2]])

## SERVER -> CLIENT: Broadcast hit effect to all clients
@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_hit_effect(position: Array) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_visual_hit_effect"):
		var pos = Vector3(position[0], position[1], position[2])
		client_node.spawn_visual_hit_effect(pos)

## CLIENT -> SERVER: Report parry effect at position
@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_parry_effect(position: Array) -> void:
	# Server broadcasts to all other clients
	rpc_broadcast_parry_effect.rpc([position[0], position[1], position[2]])

## SERVER -> CLIENT: Broadcast parry effect to all clients
@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_parry_effect(position: Array) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_visual_parry_effect"):
		var pos = Vector3(position[0], position[1], position[2])
		client_node.spawn_visual_parry_effect(pos)

# ============================================================================
# THROWN ROCK SYNC
# ============================================================================

## CLIENT -> SERVER: Report thrown rock for sync
@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_thrown_rock(position: Array, direction: Array, speed: float, damage: float, thrower_network_id: int) -> void:
	# Server broadcasts to all other clients
	var from_peer = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != from_peer:
			rpc_broadcast_thrown_rock.rpc_id(peer, position, direction, speed, damage, thrower_network_id)

## SERVER -> CLIENT: Broadcast thrown rock to all clients
@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_thrown_rock(position: Array, direction: Array, speed: float, damage: float, thrower_network_id: int) -> void:
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_visual_thrown_rock"):
		var pos = Vector3(position[0], position[1], position[2])
		var dir = Vector3(direction[0], direction[1], direction[2])
		client_node.spawn_visual_thrown_rock(pos, dir, speed, damage, thrower_network_id)

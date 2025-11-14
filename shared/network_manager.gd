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

## CLIENT -> SERVER: Send player input
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_send_player_input(input_data: Dictionary) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	# Forward to server's player management
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("receive_player_input"):
		server_node.receive_player_input(peer_id, input_data)

## CLIENT -> SERVER: Report hit (trust-based)
@rpc("any_peer", "call_remote", "reliable")
func rpc_report_hit(target_id: int, damage: float, hit_position: Vector3) -> void:
	if not is_server:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var server_node := get_node_or_null("/root/Main/Server")
	if server_node and server_node.has_method("handle_hit_report"):
		server_node.handle_hit_report(peer_id, target_id, damage, hit_position)

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
	# Forward to client node if it exists
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.has_method("spawn_player"):
		client_node.spawn_player(peer_id, player_name, spawn_pos)

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

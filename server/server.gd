extends Node

## Server - Server-side game logic and player management
## This handles all server-authoritative systems

# Player management
var player_scene := preload("res://shared/player.tscn")
var spawned_players: Dictionary = {} # peer_id -> Player node
var player_spawn_points: Array[Vector3] = [Vector3(0, 50, 0)] # Default spawn

# Server state
var is_running: bool = false
var server_tick: int = 0
const TICK_RATE: float = 1.0 / 30.0 # 30 ticks per second
var tick_accumulator: float = 0.0

# World root for spawning entities
@onready var world: Node3D = $World

func _ready() -> void:
	print("[Server] Server node ready")

	# Connect to network events
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)

	# Set up console input (for dedicated servers)
	if DisplayServer.get_name() == "headless":
		_setup_console_input()

func start_server(port: int = 7777, max_players: int = 10) -> void:
	if is_running:
		push_warning("[Server] Server already running")
		return

	if NetworkManager.start_server(port, max_players):
		is_running = true
		print("[Server] ===========================================")
		print("[Server] Server is now running!")
		print("[Server] Port: %d" % port)
		print("[Server] Max players: %d" % max_players)
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

	# Broadcast player states to all clients
	_broadcast_player_states()

func _broadcast_player_states() -> void:
	# Collect all player states
	var states: Array[Dictionary] = []

	for peer_id in spawned_players:
		var player: Node3D = spawned_players[peer_id]
		if player and is_instance_valid(player):
			states.append({
				"peer_id": peer_id,
				"position": player.global_position,
				"rotation": player.rotation.y,
				"velocity": player.get("velocity") if player.has_method("get") else Vector3.ZERO,
				"animation_state": player.get("current_animation_state") if player.has_method("get") else "idle"
			})

	# Broadcast to all clients through NetworkManager
	if states.size() > 0:
		NetworkManager.rpc_broadcast_player_states.rpc(states)

# ============================================================================
# PLAYER MANAGEMENT (SERVER-AUTHORITATIVE)
# ============================================================================

func _on_player_joined(peer_id: int, player_name: String) -> void:
	print("[Server] Player joined: %s (ID: %d)" % [player_name, peer_id])

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

	print("[Server] Spawned player %d at %s" % [peer_id, spawn_pos])

	# Notify all clients to spawn this player through NetworkManager
	NetworkManager.rpc_spawn_player.rpc(peer_id, player_name, spawn_pos)

	# Send existing players to the new client
	for existing_peer_id in spawned_players:
		if existing_peer_id != peer_id:
			var existing_player: Node3D = spawned_players[existing_peer_id]
			var existing_name: String = NetworkManager.get_player_info(existing_peer_id).get("name", "Unknown")
			NetworkManager.rpc_spawn_player.rpc_id(peer_id, existing_peer_id, existing_name, existing_player.global_position)

func _despawn_player(peer_id: int) -> void:
	if not spawned_players.has(peer_id):
		return

	var player: Node3D = spawned_players[peer_id]
	if player and is_instance_valid(player):
		player.queue_free()

	spawned_players.erase(peer_id)

	# Notify all clients to despawn through NetworkManager
	NetworkManager.rpc_despawn_player.rpc(peer_id)

	print("[Server] Despawned player %d" % peer_id)

func _get_spawn_point() -> Vector3:
	# Simple spawn point selection
	# TODO: Implement proper spawn point system
	return player_spawn_points[0] + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))

# ============================================================================
# SERVER METHODS - Called by NetworkManager RPC relay
# ============================================================================

## Receive player input from NetworkManager (already has peer_id)
func receive_player_input(peer_id: int, input_data: Dictionary) -> void:
	# Forward input to the player's entity
	if spawned_players.has(peer_id):
		var player = spawned_players[peer_id]
		if player.has_method("apply_server_input"):
			player.apply_server_input(input_data)

## Handle hit report from NetworkManager (already has peer_id)
func handle_hit_report(peer_id: int, target_id: int, damage: float, hit_position: Vector3) -> void:
	print("[Server] Player %d reported hit on %d (damage: %.1f)" % [peer_id, target_id, damage])

	# TODO: Apply damage to target
	# For now, just broadcast the hit to all clients through NetworkManager
	NetworkManager.rpc_broadcast_hit.rpc(target_id, damage, hit_position)

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

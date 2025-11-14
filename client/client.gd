extends Node

## Client - Client-side game logic and UI
## This handles client-specific systems like UI, local player camera, and rendering

# Scene references
var player_scene := preload("res://shared/player.tscn")
var camera_controller_scene := preload("res://shared/camera_controller.tscn")

# Client state
var is_connected: bool = false
var local_player: Node3D = null
var remote_players: Dictionary = {} # peer_id -> Player node

# Environmental objects
var environmental_chunks: Dictionary = {} # Vector2i -> Dictionary of objects
var environmental_objects_container: Node3D

# UI references
@onready var connection_ui: Control = $CanvasLayer/ConnectionUI
@onready var hud: Control = $CanvasLayer/HUD
@onready var ip_input: LineEdit = $CanvasLayer/ConnectionUI/Panel/VBox/IPInput
@onready var port_input: LineEdit = $CanvasLayer/ConnectionUI/Panel/VBox/PortInput
@onready var name_input: LineEdit = $CanvasLayer/ConnectionUI/Panel/VBox/NameInput
@onready var connect_button: Button = $CanvasLayer/ConnectionUI/Panel/VBox/ConnectButton
@onready var status_label: Label = $CanvasLayer/ConnectionUI/Panel/VBox/StatusLabel
@onready var ping_label: Label = $CanvasLayer/HUD/PingLabel
@onready var players_label: Label = $CanvasLayer/HUD/PlayersLabel

# World and camera
@onready var world: Node3D = $World
@onready var voxel_world = $World/VoxelWorld
@onready var viewer: VoxelViewer = $VoxelViewer  # For voxel terrain - will attach to player

func _ready() -> void:
	print("[Client] Client node ready")

	# Create environmental objects container
	environmental_objects_container = Node3D.new()
	environmental_objects_container.name = "EnvironmentalObjects"
	world.add_child(environmental_objects_container)

	# Hide HUD initially
	hud.visible = false

	# Connect UI signals
	connect_button.pressed.connect(_on_connect_button_pressed)

	# Connect to network events
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.client_disconnected.connect(_on_client_disconnected)

	# Set default values
	ip_input.text = "127.0.0.1"
	port_input.text = str(NetworkManager.DEFAULT_PORT)
	name_input.text = "Player" + str(randi() % 1000)

func _process(_delta: float) -> void:
	if is_connected:
		_update_hud()

func auto_connect_to_localhost() -> void:
	"""Auto-connect to localhost for singleplayer mode"""
	await get_tree().create_timer(0.1).timeout

	ip_input.text = "127.0.0.1"
	port_input.text = str(NetworkManager.DEFAULT_PORT)
	_on_connect_button_pressed()

func _on_connect_button_pressed() -> void:
	var address := ip_input.text
	var port := port_input.text.to_int()
	var player_name := name_input.text

	if address.is_empty():
		_update_status("Please enter server address", true)
		return

	if player_name.is_empty():
		_update_status("Please enter player name", true)
		return

	_update_status("Connecting to %s:%d..." % [address, port], false)
	connect_button.disabled = true

	# Connect to server
	if NetworkManager.connect_to_server(address, port):
		# Wait for connection result
		pass
	else:
		_update_status("Failed to start connection", true)
		connect_button.disabled = false

func _on_client_connected() -> void:
	print("[Client] Successfully connected to server!")
	is_connected = true

	# Register with server through NetworkManager
	var player_name := name_input.text
	NetworkManager.rpc_register_player.rpc_id(1, player_name)

	# Hide connection UI, show HUD
	connection_ui.visible = false
	hud.visible = true

	_update_status("Connected!", false)

func _on_client_disconnected() -> void:
	print("[Client] Disconnected from server")
	is_connected = false

	# Clean up players
	if local_player:
		local_player.queue_free()
		local_player = null

	for peer_id in remote_players:
		var player = remote_players[peer_id]
		if player and is_instance_valid(player):
			player.queue_free()

	remote_players.clear()

	# Clean up environmental objects
	_cleanup_environmental_objects()

	# Show connection UI, hide HUD
	connection_ui.visible = true
	hud.visible = false
	connect_button.disabled = false

	_update_status("Disconnected from server", true)

func _update_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.modulate = Color.RED if is_error else Color.WHITE

func _update_hud() -> void:
	# Update ping
	ping_label.text = "Ping: %.0f ms" % NetworkManager.ping

	# Update player count
	var player_count := 1 # Local player
	player_count += remote_players.size()
	players_label.text = "Players: %d" % player_count

# ============================================================================
# PLAYER MANAGEMENT (CLIENT-SIDE)
# ============================================================================

## Spawn a player on the client (called by NetworkManager)
func spawn_player(peer_id: int, player_name: String, spawn_pos: Vector3) -> void:
	print("[Client] Spawning player: %s (ID: %d)" % [player_name, peer_id])

	var is_local := peer_id == NetworkManager.get_local_player_id()

	# Check if player already exists
	if is_local and local_player:
		print("[Client] Local player already exists, skipping spawn")
		return
	if not is_local and remote_players.has(peer_id):
		print("[Client] Remote player %d already exists, skipping spawn" % peer_id)
		return

	# Instantiate player
	var player: Node3D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	# Add to world FIRST (required before setting global_position)
	world.add_child(player)

	# Set spawn position AFTER adding to tree
	player.global_position = spawn_pos

	if is_local:
		# This is our local player
		local_player = player
		print("[Client] Local player spawned at %s" % spawn_pos)

		# Attach camera to follow local player
		_setup_camera_follow(player)
	else:
		# This is a remote player
		remote_players[peer_id] = player
		print("[Client] Remote player %d spawned at %s" % [peer_id, spawn_pos])

## Despawn a player on the client (called by NetworkManager)
func despawn_player(peer_id: int) -> void:
	print("[Client] Despawning player ID: %d" % peer_id)

	if peer_id == NetworkManager.get_local_player_id():
		if local_player:
			local_player.queue_free()
			local_player = null
	else:
		if remote_players.has(peer_id):
			var player = remote_players[peer_id]
			if player and is_instance_valid(player):
				player.queue_free()
			remote_players.erase(peer_id)

## Receive player states from server for interpolation (called by NetworkManager)
func receive_player_states(states: Array) -> void:
	# Apply states to remote players (not local player, which uses prediction)
	for state in states:
		var peer_id: int = state.get("peer_id", 0)

		# Skip local player (we use client prediction for that)
		if peer_id == NetworkManager.get_local_player_id():
			continue

		if remote_players.has(peer_id):
			var player = remote_players[peer_id]
			if player and is_instance_valid(player) and player.has_method("apply_server_state"):
				player.apply_server_state(state)

## Receive hit broadcast from server (called by NetworkManager)
func receive_hit(target_id: int, damage: float, hit_position: Vector3) -> void:
	print("[Client] Hit received: target %d, damage %.1f" % [target_id, damage])

	# TODO: Play hit effects
	# For Phase 1, just log it

# ============================================================================
# CAMERA MANAGEMENT
# ============================================================================

func _setup_camera_follow(player: Node3D) -> void:
	"""Set up camera to follow the player"""
	# Instance camera controller and attach to player
	var camera_controller: Node3D = camera_controller_scene.instantiate()
	camera_controller.name = "CameraController"
	player.add_child(camera_controller)

	# Position camera controller at eye height
	camera_controller.position = Vector3(0, 1.5, 0)

	print("[Client] Camera controller attached to local player")

	# Move VoxelViewer to player (for terrain streaming around player)
	if viewer:
		var viewer_parent := viewer.get_parent()
		if viewer_parent:
			viewer_parent.remove_child(viewer)
			player.add_child(viewer)
			print("[Client] VoxelViewer attached to local player")

# ============================================================================
# ENVIRONMENTAL OBJECT MANAGEMENT (CLIENT-SIDE VISUAL ONLY)
# ============================================================================

## Receive environmental objects from server
func receive_environmental_objects(chunk_pos: Vector2i, objects_data: Array) -> void:

	# Create chunk entry if it doesn't exist
	if not environmental_chunks.has(chunk_pos):
		environmental_chunks[chunk_pos] = {}

	var chunk_objects = environmental_chunks[chunk_pos]

	# Spawn each object
	for obj_data in objects_data:
		var obj_id = obj_data.get("id", -1)
		var obj_type = obj_data.get("type", "unknown")
		var pos_array = obj_data.get("pos", [0, 0, 0])
		var rot_array = obj_data.get("rot", [0, 0, 0])
		var scale_array = obj_data.get("scale", [1, 1, 1])

		# Instantiate the appropriate scene based on type
		var obj_scene: PackedScene = null
		match obj_type:
			"tree":
				obj_scene = load("res://shared/environmental/tree.tscn")
			"rock":
				obj_scene = load("res://shared/environmental/rock.tscn")
			"grass":
				obj_scene = load("res://shared/environmental/grass_clump.tscn")
			_:
				push_error("[Client] Unknown environmental object type: %s" % obj_type)
				continue

		if not obj_scene:
			continue

		# Spawn the object
		var obj = obj_scene.instantiate()
		environmental_objects_container.add_child(obj)

		# Set transform from server data
		var server_pos = Vector3(pos_array[0], pos_array[1], pos_array[2])
		obj.global_position = server_pos
		obj.rotation = Vector3(rot_array[0], rot_array[1], rot_array[2])
		obj.scale = Vector3(scale_array[0], scale_array[1], scale_array[2])

		# Set object type
		if obj.has_method("set_object_type"):
			obj.set_object_type(obj_type)

		# Store in chunk
		chunk_objects[obj_id] = obj

## Despawn environmental objects for a chunk
func despawn_environmental_objects(chunk_pos: Vector2i) -> void:
	if not environmental_chunks.has(chunk_pos):
		return

	print("[Client] Despawning objects for chunk %s" % chunk_pos)

	var chunk_objects = environmental_chunks[chunk_pos]

	# Remove all objects in this chunk
	for obj_id in chunk_objects:
		var obj = chunk_objects[obj_id]
		if obj and is_instance_valid(obj):
			obj.queue_free()

	environmental_chunks.erase(chunk_pos)

## Destroy a specific environmental object
func destroy_environmental_object(chunk_pos: Vector2i, object_id: int) -> void:
	if not environmental_chunks.has(chunk_pos):
		return

	var chunk_objects = environmental_chunks[chunk_pos]

	if chunk_objects.has(object_id):
		var obj = chunk_objects[object_id]
		if obj and is_instance_valid(obj):
			obj.queue_free()
		chunk_objects.erase(object_id)
		print("[Client] Destroyed environmental object %d in chunk %s" % [object_id, chunk_pos])

## Clean up all environmental objects
func _cleanup_environmental_objects() -> void:
	for chunk_pos in environmental_chunks.keys():
		despawn_environmental_objects(chunk_pos)
	environmental_chunks.clear()

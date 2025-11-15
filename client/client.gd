extends Node

## Client - Client-side game logic and UI
## This handles client-specific systems like UI, local player camera, and rendering

# Scene references
var player_scene := preload("res://shared/player.tscn")
var camera_controller_scene := preload("res://shared/camera_controller.tscn")
var hotbar_scene := preload("res://client/ui/hotbar.tscn")
var inventory_panel_scene := preload("res://client/ui/inventory_panel.tscn")
var build_menu_scene := preload("res://client/ui/build_menu.tscn")

# Client state
var is_connected: bool = false
var local_player: Node3D = null
var remote_players: Dictionary = {} # peer_id -> Player node

# Inventory UI
var hotbar_ui: Control = null
var inventory_panel_ui: Control = null
var build_menu_ui: Control = null

# Build mode
var build_mode: Node = null
var placement_mode: Node = null
var current_equipped_item: String = ""

# Environmental objects
var environmental_chunks: Dictionary = {} # Vector2i -> Dictionary of objects
var environmental_objects_container: Node3D

# UI references
@onready var canvas_layer: CanvasLayer = $CanvasLayer
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

	# Create build mode
	var BuildMode = preload("res://client/build_mode.gd")
	build_mode = BuildMode.new()
	add_child(build_mode)
	build_mode.build_piece_placed.connect(_on_build_piece_placed)

	# Create placement mode
	var PlacementMode = preload("res://client/placement_mode.gd")
	placement_mode = PlacementMode.new()
	add_child(placement_mode)
	placement_mode.item_placed.connect(_on_item_placed)

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
		_handle_build_input()

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

func _handle_build_input() -> void:
	# Don't handle build input if inventory or build menu is open
	if inventory_panel_ui and inventory_panel_ui.is_inventory_open():
		return
	if build_menu_ui and build_menu_ui.is_open:
		return

	# Right-click to open build menu when hammer is equipped
	if Input.is_action_just_pressed("secondary_action"):
		if current_equipped_item == "hammer" and build_mode and build_mode.is_active:
			if build_menu_ui:
				build_menu_ui.toggle_menu()

	# Middle mouse button to destroy objects (when hammer equipped)
	if Input.is_action_just_pressed("destroy_object"):
		if current_equipped_item == "hammer":
			_destroy_object_under_cursor()

func _destroy_object_under_cursor() -> void:
	var camera = _get_camera()
	if not camera:
		return

	# Raycast from camera forward
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * 5.0)

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World layer

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var hit_object = result.collider
		# Check if it's a buildable object (has a parent BuildableObject or BuildingPiece)
		var buildable = hit_object
		while buildable:
			if buildable.has_method("get_piece_name") or buildable.has_method("is_position_in_range"):
				# Found a buildable - request server to destroy it
				print("[Client] Requesting destruction of buildable at %s" % result.position)
				# TODO: NetworkManager.rpc_destroy_buildable.rpc_id(1, buildable.global_position)
				return
			buildable = buildable.get_parent()

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

		# Setup inventory UI
		_setup_inventory_ui(player)
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

	# Position camera controller at shoulder/neck height for better third-person view
	camera_controller.position = Vector3(0, 1.2, 0)

	print("[Client] Camera controller attached to local player")

	# Setup viewmodel after camera is ready
	if player.has_method("setup_viewmodel"):
		player.setup_viewmodel()

	# Move VoxelViewer to player (for terrain streaming around player)
	if viewer:
		var viewer_parent := viewer.get_parent()
		if viewer_parent:
			viewer_parent.remove_child(viewer)
			player.add_child(viewer)
			print("[Client] VoxelViewer attached to local player")

func _setup_inventory_ui(player: Node3D) -> void:
	"""Set up inventory UI and link to player's inventory"""
	if not canvas_layer:
		push_error("[Client] Cannot setup inventory UI - canvas_layer not found")
		return

	if not player.has_node("Inventory"):
		push_error("[Client] Cannot setup inventory UI - player has no inventory")
		return

	var player_inventory = player.get_node("Inventory")

	# Create hotbar UI (always visible)
	hotbar_ui = hotbar_scene.instantiate()
	canvas_layer.add_child(hotbar_ui)
	hotbar_ui.set_player_inventory(player_inventory)
	hotbar_ui.hotbar_selection_changed.connect(_on_hotbar_selection_changed)
	print("[Client] Hotbar UI created and linked to player inventory")

	# Create inventory panel UI (toggle with Tab)
	inventory_panel_ui = inventory_panel_scene.instantiate()
	canvas_layer.add_child(inventory_panel_ui)
	inventory_panel_ui.set_player_inventory(player_inventory)
	inventory_panel_ui.hide_inventory()  # Start hidden
	print("[Client] Inventory panel UI created and linked to player inventory")

	# Create build menu UI (opens with right-click when hammer equipped)
	build_menu_ui = build_menu_scene.instantiate()
	canvas_layer.add_child(build_menu_ui)
	build_menu_ui.piece_selected.connect(_on_build_piece_selected)
	build_menu_ui.hide_menu()  # Start hidden
	print("[Client] Build menu UI created")

	# Refresh displays periodically to sync with inventory changes
	var refresh_timer = Timer.new()
	refresh_timer.wait_time = 0.1  # Refresh every 100ms
	refresh_timer.timeout.connect(func():
		if hotbar_ui and is_instance_valid(hotbar_ui):
			hotbar_ui.refresh_display()
		if inventory_panel_ui and is_instance_valid(inventory_panel_ui) and inventory_panel_ui.is_inventory_open():
			inventory_panel_ui.refresh_display()
	)
	add_child(refresh_timer)
	refresh_timer.start()

## Handle hotbar selection changes (for build mode toggling)
func _on_hotbar_selection_changed(slot_index: int, item_name: String) -> void:
	current_equipped_item = item_name

	var camera = _get_camera()

	# Deactivate all modes first
	if build_mode.is_active:
		build_mode.deactivate()
	if placement_mode.is_active:
		placement_mode.deactivate()

	# Activate appropriate mode based on equipped item
	if item_name == "hammer":
		if camera and local_player:
			build_mode.activate(local_player, camera, world)
	elif item_name == "workbench":
		if camera and local_player:
			placement_mode.activate(local_player, camera, world, item_name)

## Handle build piece selection from build menu
func _on_build_piece_selected(piece_name: String) -> void:
	if build_mode and build_mode.is_active:
		build_mode.set_piece(piece_name)

## Handle build piece placement from build mode
func _on_build_piece_placed(piece_name: String, position: Vector3, rotation_y: float) -> void:
	print("[Client] Requesting placement of %s at %s" % [piece_name, position])
	# TODO: Request server to place the buildable
	# For now, just log it
	# NetworkManager.rpc_place_buildable.rpc_id(1, piece_name, position, rotation_y)

## Handle item placement from placement mode
func _on_item_placed(item_name: String, position: Vector3, rotation_y: float) -> void:
	print("[Client] Requesting placement of %s at %s" % [item_name, position])
	# TODO: Request server to place the item as a buildable
	# For now, just log it
	# NetworkManager.rpc_place_buildable.rpc_id(1, item_name, position, rotation_y)

## Get the current camera
func _get_camera() -> Camera3D:
	if local_player:
		var camera_controller = local_player.get_node_or_null("CameraController")
		if camera_controller:
			return camera_controller.get_node_or_null("Camera3D")
	return null

# ============================================================================
# WORLD CONFIGURATION
# ============================================================================

## Receive world configuration from server
func receive_world_config(world_data: Dictionary) -> void:
	print("[Client] Received world config: %s" % world_data)

	var world_name: String = world_data.get("world_name", "unknown")
	var world_seed: int = world_data.get("seed", 0)

	# Initialize voxel world with server's seed and name
	if voxel_world:
		voxel_world.initialize_world(world_seed, world_name)
		print("[Client] Initialized world '%s' with seed %d" % [world_name, world_seed])
	else:
		push_error("[Client] VoxelWorld not found!")

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

		# Set object type and ID
		if obj.has_method("set_object_type"):
			obj.set_object_type(obj_type)
		if obj.has_method("set_object_id"):
			obj.set_object_id(obj_id)
		if obj.has_method("set_chunk_position"):
			obj.set_chunk_position(chunk_pos)

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

## Spawn resource items at a position with server-provided network IDs
func spawn_resource_drops(resources: Dictionary, position: Vector3, network_ids: Array) -> void:
	print("[Client] Spawning resource drops: %s at %s" % [resources, position])

	var resource_scene = preload("res://shared/resource_item.tscn")

	var id_index = 0
	for resource_type in resources:
		var amount: int = resources[resource_type]

		# Spawn individual items
		for i in amount:
			var item = resource_scene.instantiate()
			item.set_item_data(resource_type, 1)

			# Random spawn offset around hit position
			var offset = Vector3(
				randf_range(-0.5, 0.5),
				0.0,  # Don't offset vertically - let item handle its own height
				randf_range(-0.5, 0.5)
			)

			# Spawn at ground level (use hit position X/Z but lower Y)
			var spawn_pos = position + offset
			spawn_pos.y = position.y - 1.0  # Spawn about 1m below hit point (roughly ground level)

			# Use server-provided network ID for consistency across all clients
			var net_id = network_ids[id_index]
			item.network_id = net_id
			item.name = "Item_%s" % net_id

			# Add to world first, then set position
			world.add_child(item)
			item.global_position = spawn_pos

			id_index += 1

## Remove a resource item by network ID (when another player picks it up)
func remove_resource_item(net_id: String) -> void:
	# Find item by network_id in the world
	var item_name = "Item_%s" % net_id
	var item = world.get_node_or_null(item_name)

	if item and is_instance_valid(item):
		print("[Client] Removing picked up item: %s" % item_name)
		item.queue_free()

## Clean up all environmental objects
func _cleanup_environmental_objects() -> void:
	for chunk_pos in environmental_chunks.keys():
		despawn_environmental_objects(chunk_pos)
	environmental_chunks.clear()

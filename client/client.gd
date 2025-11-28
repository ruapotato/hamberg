extends Node

## Client - Client-side game logic and UI
## This handles client-specific systems like UI, local player camera, and rendering

# Scene references
var player_scene := preload("res://shared/player.tscn")
var camera_controller_scene := preload("res://shared/camera_controller.tscn")
var hotbar_scene := preload("res://client/ui/hotbar.tscn")
var inventory_panel_scene := preload("res://client/ui/inventory_panel.tscn")
var player_hud_scene := preload("res://client/ui/player_hud.tscn")
var build_menu_scene := preload("res://client/ui/build_menu.tscn")
var crafting_menu_scene := preload("res://client/ui/crafting_menu.tscn")
var character_selection_scene := preload("res://client/ui/character_selection.tscn")
var pause_menu_scene := preload("res://client/ui/pause_menu.tscn")
var loading_screen_scene := preload("res://client/ui/loading_screen.tscn")
var world_map_scene := preload("res://client/ui/world_map.tscn")
var mini_map_scene := preload("res://client/ui/mini_map.tscn")

# Enemy scenes
var gahnome_scene := preload("res://shared/enemies/gahnome.tscn")

# Environmental object scenes (preloaded to avoid blocking main thread)
var environmental_scenes: Dictionary = {
	"tree": preload("res://shared/environmental/tree.tscn"),
	"rock": preload("res://shared/environmental/rock.tscn"),
	"grass": preload("res://shared/environmental/grass_clump.tscn"),
	"mushroom_tree": preload("res://shared/environmental/mushroom_tree.tscn"),
	"glowing_mushroom": preload("res://shared/environmental/glowing_mushroom.tscn"),
	"giant_mushroom": preload("res://shared/environmental/giant_mushroom.tscn"),
	"spore_cluster": preload("res://shared/environmental/spore_cluster.tscn"),
}

# Environmental object spawn queue (for non-blocking spawning)
var environmental_spawn_queue: Array = []
var environmental_queue_needs_sort: bool = false
const ENVIRONMENTAL_SPAWN_BATCH_SIZE: int = 8  # Objects to spawn per frame

# Client state
var is_connected: bool = false
var is_in_game: bool = false
var is_loading: bool = false
var local_player: Node3D = null
var remote_players: Dictionary = {} # peer_id -> Player node
var spawned_enemies: Dictionary = {} # NodePath -> Enemy node (visual only)

# Loading state
var loading_screen_ui: Control = null
var queued_terrain_modifications: Array = []
var queued_mods_check_timer: float = 0.0
const QUEUED_MODS_CHECK_INTERVAL: float = 2.0  # Check every 2 seconds
var loading_steps_complete: Dictionary = {
	"world_config": false,
	"buildables": false,
	"player_spawned": false,
	"terrain_ready": false,
	"environmental_objects": false,
	"terrain_modifications": false,
	"world_map": false
}

# Inventory UI
var hotbar_ui: Control = null
var inventory_panel_ui: Control = null
var build_menu_ui: Control = null
var crafting_menu_ui: Control = null
var character_selection_ui: Control = null
var pause_menu_ui: Control = null
var player_hud_ui: Control = null

# Map UI
var world_map_ui: Control = null
var mini_map_ui: Control = null
var ping_indicator_script = preload("res://client/ping_indicator.gd")
var active_ping_indicators: Array = []  # 3D ping indicators in the world

# Build mode
var build_mode: Node = null
var placement_mode: Node = null
var current_equipped_item: String = ""

# Item discovery tracker
var item_discovery_tracker: Node = null

# Music manager
var music_manager: Node = null
var current_biome: String = ""
var biome_check_timer: float = 0.0
const BIOME_CHECK_INTERVAL: float = 2.0  # Check biome every 2 seconds

# Environmental objects
var environmental_chunks: Dictionary = {} # Vector2i -> Dictionary of objects
var environmental_objects_container: Node3D

# UI references
@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var connection_ui: Control = $CanvasLayer/ConnectionUI
@onready var hud: Control = $CanvasLayer/HUD
@onready var ip_input: LineEdit = $CanvasLayer/ConnectionUI/Panel/VBox/IPInput
@onready var port_input: LineEdit = $CanvasLayer/ConnectionUI/Panel/VBox/PortInput
@onready var connect_button: Button = $CanvasLayer/ConnectionUI/Panel/VBox/ConnectButton
@onready var status_label: Label = $CanvasLayer/ConnectionUI/Panel/VBox/StatusLabel
@onready var ping_label: Label = $CanvasLayer/HUD/PingLabel
@onready var players_label: Label = $CanvasLayer/HUD/PlayersLabel
@onready var build_status_label: Label = $CanvasLayer/HUD/StatusLabel
@onready var notification_label: Label = $CanvasLayer/HUD/NotificationLabel

# World and camera
@onready var world: Node3D = $World
@onready var terrain_world = $World/TerrainWorld

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

	# Create item discovery tracker
	var ItemDiscoveryTracker = preload("res://client/item_discovery_tracker.gd")
	item_discovery_tracker = ItemDiscoveryTracker.new()
	item_discovery_tracker.name = "ItemDiscoveryTracker"
	add_child(item_discovery_tracker)
	item_discovery_tracker.recipes_unlocked.connect(_on_recipes_unlocked)

	# Create music manager
	var MusicManager = preload("res://client/music_manager.gd")
	music_manager = MusicManager.new()
	music_manager.name = "MusicManager"
	add_child(music_manager)

	# Create crafting menu UI
	crafting_menu_ui = crafting_menu_scene.instantiate()
	canvas_layer.add_child(crafting_menu_ui)
	crafting_menu_ui.set_discovery_tracker(item_discovery_tracker)

	# Create character selection UI
	character_selection_ui = character_selection_scene.instantiate()
	canvas_layer.add_child(character_selection_ui)
	character_selection_ui.character_selected.connect(_on_character_selected)

	# Create pause menu
	pause_menu_ui = pause_menu_scene.instantiate()
	canvas_layer.add_child(pause_menu_ui)
	pause_menu_ui.resume_pressed.connect(_on_pause_resume)
	pause_menu_ui.save_pressed.connect(_on_pause_save)
	pause_menu_ui.quit_pressed.connect(_on_pause_quit)

	# Create loading screen
	loading_screen_ui = loading_screen_scene.instantiate()
	canvas_layer.add_child(loading_screen_ui)

	# Create map UI (will be initialized after world config is received)
	world_map_ui = world_map_scene.instantiate()
	canvas_layer.add_child(world_map_ui)
	if world_map_ui.has_signal("ping_sent"):
		world_map_ui.ping_sent.connect(_on_map_ping_sent)

	# Create mini-map UI
	mini_map_ui = mini_map_scene.instantiate()
	canvas_layer.add_child(mini_map_ui)

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

func _process(_delta: float) -> void:
	# Handle connection UI controller input (when visible)
	if connection_ui and connection_ui.visible:
		_handle_connection_ui_input()

	# Handle character selection controller input (when visible)
	if character_selection_ui and character_selection_ui.visible:
		_handle_character_selection_input()

	if is_in_game:
		_update_hud()
		_handle_build_input()
		_handle_interaction_input()
		_update_biome_music(_delta)

		# Check queued terrain modifications periodically
		queued_mods_check_timer += _delta
		if queued_mods_check_timer >= QUEUED_MODS_CHECK_INTERVAL:
			queued_mods_check_timer = 0.0
			_check_queued_terrain_modifications()

	# Process environmental object spawn queue (runs even during loading)
	_process_environmental_queue()

	# Handle pause menu (Escape or Button 6)
	if (Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("toggle_pause")) and is_in_game:
		_toggle_pause_menu()

	# Handle manual save
	if Input.is_action_just_pressed("manual_save") and is_in_game:
		_request_server_save()

	# Handle map toggle
	if Input.is_action_just_pressed("toggle_map") and is_in_game:
		_toggle_world_map()

func auto_connect_to_localhost() -> void:
	"""Auto-connect to localhost for singleplayer mode"""
	await get_tree().create_timer(0.1).timeout

	ip_input.text = "127.0.0.1"
	port_input.text = str(NetworkManager.DEFAULT_PORT)
	_on_connect_button_pressed()

func _on_connect_button_pressed() -> void:
	var address := ip_input.text
	var port := port_input.text.to_int()

	if address.is_empty():
		_update_status("Please enter server address", true)
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

	# Hide connection UI
	connection_ui.visible = false

	# Request character list from server
	NetworkManager.rpc_request_character_list.rpc_id(1)

	_update_status("Connected! Loading characters...", false)

func _on_client_disconnected() -> void:
	print("[Client] Disconnected from server")
	is_connected = false
	is_in_game = false

	# Show disconnect message to user
	if loading_screen_ui:
		loading_screen_ui.show()
		loading_screen_ui.set_status("Disconnected from server")
		loading_screen_ui.set_detail("Connection to the server was lost. Please restart the client.")
		loading_screen_ui.set_progress(0.0)

	# Pause the game tree to prevent further gameplay
	get_tree().paused = true

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

	# Stop music
	if music_manager:
		music_manager.stop_music()
	current_biome = ""

	# Show connection UI, hide HUD and character selection
	connection_ui.visible = true
	hud.visible = false
	if character_selection_ui:
		character_selection_ui.visible = false
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

	# Right-click or X button to open build menu when hammer is equipped
	if Input.is_action_just_pressed("secondary_action") or Input.is_action_just_pressed("open_build_menu"):
		print("[Client] Build menu button pressed!")
		print("[Client] current_equipped_item=%s, build_mode=%s, build_mode.is_active=%s, build_menu_ui=%s" % [
			current_equipped_item,
			build_mode != null,
			build_mode.is_active if build_mode else "N/A",
			build_menu_ui != null
		])
		if current_equipped_item == "hammer" and build_mode and build_mode.is_active:
			if build_menu_ui:
				print("[Client] Calling build_menu_ui.toggle_menu()")
				build_menu_ui.toggle_menu()
			else:
				print("[Client] ERROR: build_menu_ui is null!")

	# Y button opens build menu when hammer equipped (blocks inventory)
	if Input.is_action_just_pressed("toggle_inventory"):
		if current_equipped_item == "hammer" and build_mode and build_mode.is_active:
			if build_menu_ui:
				build_menu_ui.toggle_menu()
			# Consume the input so inventory doesn't open
			Input.action_release("toggle_inventory")

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
				# Found a buildable - extract network ID from its name
				var buildable_name = buildable.name
				if buildable_name.begins_with("Buildable_"):
					var network_id = buildable_name.substr(10)  # Remove "Buildable_" prefix
					print("[Client] Requesting destruction of buildable %s" % network_id)
					NetworkManager.rpc_destroy_buildable.rpc_id(1, network_id)
				else:
					print("[Client] WARNING: Buildable found but doesn't have proper network ID in name: %s" % buildable_name)
				return
			buildable = buildable.get_parent()

func _handle_interaction_input() -> void:
	# Don't handle interaction if inventory or crafting menu is open
	if inventory_panel_ui and inventory_panel_ui.is_inventory_open():
		return
	if crafting_menu_ui and crafting_menu_ui.is_open:
		return

	# Check for E key press to interact with objects
	if Input.is_action_just_pressed("interact"):
		_interact_with_object_under_cursor()

func _interact_with_object_under_cursor() -> void:
	var camera = _get_camera()
	if not camera:
		return

	# Raycast from camera forward
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * 5.0)  # 5m interaction range

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World layer

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var hit_object = result.collider
		# Check if it's a buildable object (workbench, etc.)
		var buildable = hit_object
		while buildable:
			# Check if it's a crafting station (workbench)
			if buildable.has_method("is_position_in_range") and buildable.get("is_crafting_station"):
				var station_type = buildable.get("station_type")
				if station_type == "workbench":
					print("[Client] Interacting with workbench")
					_open_crafting_menu()
					return
			buildable = buildable.get_parent()

func _open_crafting_menu() -> void:
	if not crafting_menu_ui:
		push_error("[Client] Crafting menu UI not found!")
		return

	if not local_player:
		push_error("[Client] No local player!")
		return

	# Set player inventory reference
	if local_player.has_node("Inventory"):
		var inventory = local_player.get_node("Inventory")
		crafting_menu_ui.set_player_inventory(inventory)

	# Open the menu
	crafting_menu_ui.show_menu()
	print("[Client] Opened crafting menu")

# ============================================================================
# PLAYER MANAGEMENT (CLIENT-SIDE)
# ============================================================================

## Spawn a player on the client (called by NetworkManager)
func spawn_player(peer_id: int, player_name: String, spawn_pos: Vector3) -> void:
	print("[Client] Spawning player: %s (ID: %d)" % [player_name, peer_id])

	var is_local: bool = peer_id == NetworkManager.get_local_player_id()

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

		# Show HUD
		hud.visible = true

		# Attach camera to follow local player
		_setup_camera_follow(player)

		# Setup inventory UI
		_setup_inventory_ui(player)

		# Initialize map system with player
		_initialize_maps_with_player(player)

		# Connect to equipment changes to track what's actually equipped
		if player.has_node("Equipment"):
			var equipment = player.get_node("Equipment")
			if equipment and equipment.has_signal("equipment_changed"):
				equipment.equipment_changed.connect(_on_equipment_changed)
				print("[Client] Connected to equipment_changed signal")

		# Mark loading step complete and start waiting for terrain
		_mark_loading_step_complete("player_spawned")

		# Wait for buildables (give server time to send them)
		await get_tree().create_timer(0.5).timeout
		_mark_loading_step_complete("buildables")

		# Wait for environmental objects (assume first chunk loads quickly)
		await get_tree().create_timer(1.0).timeout
		_mark_loading_step_complete("environmental_objects")

		# Start checking if terrain is ready
		_check_terrain_ready()
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

## Handle local player respawn (called by NetworkManager)
func handle_player_respawned(spawn_position: Vector3) -> void:
	print("[Client] Local player respawning at %s" % spawn_position)

	if local_player and is_instance_valid(local_player):
		if local_player.has_method("respawn_at"):
			local_player.respawn_at(spawn_position)
	else:
		print("[Client] ERROR: No local player to respawn!")

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

## Receive enemy damage to local player (called by NetworkManager)
func receive_enemy_damage(damage: float, attacker_id: int, knockback_dir: Vector3) -> void:
	print("[Client] Received enemy damage: %.1f from attacker %d" % [damage, attacker_id])

	# Apply damage to local player
	if local_player and is_instance_valid(local_player):
		if local_player.has_method("take_damage"):
			local_player.take_damage(damage, attacker_id, knockback_dir)
			print("[Client] Applied %.1f damage to local player" % damage)
		else:
			push_warning("[Client] Local player doesn't have take_damage method")
	else:
		push_warning("[Client] No valid local player to apply damage to")

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

	# Register player with terrain world for chunk loading
	if terrain_world:
		terrain_world.register_player_for_spawning(NetworkManager.get_local_player_id(), player)
		print("[Client] Player registered with terrain world for chunk loading")

func _setup_inventory_ui(player: Node3D) -> void:
	"""Set up inventory UI and link to player's inventory"""
	if not canvas_layer:
		push_error("[Client] Cannot setup inventory UI - canvas_layer not found")
		return

	if not player.has_node("Inventory"):
		push_error("[Client] Cannot setup inventory UI - player has no inventory")
		return

	var player_inventory = player.get_node("Inventory")

	# Create player HUD (health and stamina bars)
	player_hud_ui = player_hud_scene.instantiate()
	canvas_layer.add_child(player_hud_ui)
	player_hud_ui.set_player(player)
	print("[Client] Player HUD created and linked to player")

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

## Handle hotbar selection changes (called when D-pad cycles or number key pressed)
## NOTE: This does NOT mean the item is equipped! Use _on_equipment_changed for that.
func _on_hotbar_selection_changed(slot_index: int, item_name: String) -> void:
	# Do nothing here - we track equipped items via _on_equipment_changed instead
	pass

## Handle equipment changes (called when item is actually equipped)
func _on_equipment_changed(equipment_slot: int) -> void:
	if not local_player or not local_player.has_node("Equipment"):
		return

	var equipment = local_player.get_node("Equipment")
	var camera = _get_camera()

	# Get what's equipped in main hand (where hammer/tools go)
	const MAIN_HAND = 0  # Equipment.EquipmentSlot.MAIN_HAND
	var main_hand_item = equipment.get_equipped_item(MAIN_HAND)
	current_equipped_item = main_hand_item

	print("[Client] Equipment changed - Main hand now has: %s" % main_hand_item)

	# Deactivate all modes first
	if build_mode.is_active:
		build_mode.deactivate()
	if placement_mode.is_active:
		placement_mode.deactivate()

	# Activate appropriate mode based on equipped item
	if main_hand_item == "hammer":
		if camera and local_player:
			build_mode.activate(local_player, camera, world, build_menu_ui, build_status_label)
			print("[Client] Build mode activated")
		else:
			print("[Client] Cannot activate build mode - camera or player missing")
	elif main_hand_item == "workbench":
		if camera and local_player:
			placement_mode.activate(local_player, camera, world, main_hand_item)
			print("[Client] Placement mode activated for workbench")

## Handle build piece selection from build menu
func _on_build_piece_selected(piece_name: String) -> void:
	if build_mode and build_mode.is_active:
		build_mode.set_piece(piece_name)

## Handle build piece placement from build mode
func _on_build_piece_placed(piece_name: String, position: Vector3, rotation_y: float) -> void:
	print("[Client] Requesting placement of %s at %s" % [piece_name, position])

	# Consume resources from inventory (client-side prediction)
	if local_player:
		var player_inventory = local_player.get_node_or_null("Inventory")
		if player_inventory:
			var costs = CraftingRecipes.BUILDING_COSTS.get(piece_name, {})
			for resource in costs:
				var required = costs[resource]
				if not player_inventory.remove_item(resource, required):
					push_error("[Client] Failed to remove %d %s from inventory!" % [required, resource])
					return
			print("[Client] Consumed resources for %s" % piece_name)

	# Request server to place the buildable
	var pos_array = [position.x, position.y, position.z]
	NetworkManager.rpc_place_buildable.rpc_id(1, piece_name, pos_array, rotation_y)

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
			var spring_arm = camera_controller.get_node_or_null("SpringArm3D")
			if spring_arm:
				return spring_arm.get_node_or_null("Camera3D")
	return null

# ============================================================================
# PAUSE MENU
# ============================================================================

func _toggle_pause_menu() -> void:
	if not pause_menu_ui:
		return

	if pause_menu_ui.visible:
		pause_menu_ui.hide_menu()
	else:
		pause_menu_ui.show_menu()

func _on_pause_resume() -> void:
	# Menu already hidden by resume button
	pass

func _on_pause_save() -> void:
	# Send save request to server (just triggers a save, server is always authoritative)
	print("[Client] Requesting manual save...")
	NetworkManager.rpc_request_save.rpc_id(1)
	# Note: Server auto-saves every 5 minutes anyway

func _on_pause_quit() -> void:
	print("[Client] Quitting to menu...")

	# Hide pause menu before disconnecting
	if pause_menu_ui and pause_menu_ui.visible:
		pause_menu_ui.hide_menu()

	# Disconnect from server
	NetworkManager.disconnect_network()

# ============================================================================
# MUSIC SYSTEM
# ============================================================================

## Update biome music based on player position
func _update_biome_music(delta: float) -> void:
	if not local_player or not music_manager or not terrain_world:
		return

	# Only check periodically (every 2 seconds)
	biome_check_timer += delta
	if biome_check_timer < BIOME_CHECK_INTERVAL:
		return

	biome_check_timer = 0.0

	# Get player's current position
	var player_pos = local_player.global_position
	var xz_pos = Vector2(player_pos.x, player_pos.z)

	# Get biome at player position
	var biome = terrain_world.get_biome_at(xz_pos)

	# Update music if biome changed
	if biome != current_biome:
		print("[Client] Biome changed: %s -> %s" % [current_biome, biome])
		current_biome = biome
		music_manager.set_biome(biome)
		_update_terrain_color(biome)

## Update terrain material color based on current biome
func _update_terrain_color(biome_name: String) -> void:
	if not terrain_world or not terrain_world.terrain_material:
		return

	# Map biome name to index (0=valley, 1=forest, 2=swamp, 3=mountain, 4=desert, 5=wizardland, 6=hell)
	var biome_index := 0
	match biome_name:
		"valley": biome_index = 0
		"forest": biome_index = 1
		"swamp": biome_index = 2
		"mountain": biome_index = 3
		"desert": biome_index = 4
		"wizardland": biome_index = 5
		"hell": biome_index = 6

	# Update shader parameter
	var material = terrain_world.terrain_material
	if material and material is ShaderMaterial:
		material.set_shader_parameter("current_biome", biome_index)
		print("[Client] Updated terrain color to biome index %d (%s)" % [biome_index, biome_name])

# ============================================================================
# ITEM DISCOVERY
# ============================================================================

func _on_recipes_unlocked(recipe_names: Array) -> void:
	# Show notification for newly unlocked recipes
	for recipe_name in recipe_names:
		var item_data = ItemDatabase.get_item(recipe_name)
		var display_name = item_data.display_name if item_data else CraftingRecipes.get_item_display_name(recipe_name)
		_show_discovery_notification("New item available at workbench: %s" % display_name)

func _show_discovery_notification(message: String) -> void:
	print("[Client] Discovery: %s" % message)
	if notification_label:
		notification_label.text = message
		notification_label.visible = true
		# Clear the message after 5 seconds
		await get_tree().create_timer(5.0).timeout
		if notification_label and notification_label.text == message:
			notification_label.visible = false
			notification_label.text = ""

# ============================================================================
# WORLD CONFIGURATION
# ============================================================================

## Receive world configuration from server
func receive_world_config(world_data: Dictionary) -> void:
	print("[Client] Received world config: %s" % world_data)

	var world_name: String = world_data.get("world_name", "unknown")
	var world_seed: int = world_data.get("seed", 0)

	# Initialize terrain world with server's seed and name
	if terrain_world:
		terrain_world.initialize_world(world_seed, world_name)
		print("[Client] Initialized world '%s' with seed %d" % [world_name, world_seed])

		# Initialize map system with BiomeGenerator
		_initialize_map_system()
	else:
		push_error("[Client] TerrainWorld not found!")

	# Mark loading step complete
	_mark_loading_step_complete("world_config")

func _initialize_map_system() -> void:
	"""Initialize map and mini-map with BiomeGenerator"""
	if not terrain_world or not terrain_world.biome_generator:
		push_error("[Client] Cannot initialize map - terrain world not ready")
		return

	var generator = terrain_world.biome_generator
	if not generator or not generator.has_method("get_height_at_position"):
		push_error("[Client] Cannot initialize map - BiomeGenerator not found")
		return

	print("[Client] Map system ready - waiting for player spawn")

func _initialize_maps_with_player(player: Node3D) -> void:
	"""Initialize maps with BiomeGenerator and player reference"""
	if not terrain_world or not terrain_world.biome_generator:
		return

	var generator = terrain_world.biome_generator
	if not generator:
		return

	print("[Client] Initializing maps with player and BiomeGenerator")

	# Initialize world map (uses procedural biome calculation - no texture needed)
	if world_map_ui and world_map_ui.has_method("initialize"):
		world_map_ui.initialize(generator, player)
		if world_map_ui.has_signal("pin_placed"):
			world_map_ui.pin_placed.connect(_on_pin_placed)
		print("[Client] World map initialized")

	# Initialize mini-map (uses procedural biome calculation - no texture needed)
	if mini_map_ui and mini_map_ui.has_method("initialize"):
		mini_map_ui.initialize(generator, player)
		# Generate the initial map
		if mini_map_ui.has_method("generate_initial_map"):
			mini_map_ui.generate_initial_map()
		print("[Client] Mini-map initialized")

func _on_pin_placed(world_pos: Vector2, pin_name: String) -> void:
	"""Called when a pin is placed on the map"""
	print("[Client] Pin placed at %s: %s" % [world_pos, pin_name])

	# Sync pins to mini-map
	if world_map_ui and mini_map_ui:
		var pins = world_map_ui.get_pins()
		mini_map_ui.set_pins(pins)

	# Send to server for persistence
	var pins_data = []
	if world_map_ui:
		pins_data = world_map_ui.get_pins()

	NetworkManager.rpc_update_map_pins.rpc_id(1, pins_data)

# ============================================================================
# CHARACTER SELECTION AND PERSISTENCE
# ============================================================================

## Receive character list from server
func receive_character_list(characters: Array) -> void:
	print("[Client] Received %d characters from server" % characters.size())

	if character_selection_ui:
		character_selection_ui.show_characters(characters)

## Handle character selection
func _on_character_selected(character_id: String, character_name: String, is_new: bool) -> void:
	print("[Client] Character selected: %s (%s), new: %s" % [character_name, character_id, is_new])

	# Start loading sequence
	_start_loading()

	# Set character name in discovery tracker
	if item_discovery_tracker:
		item_discovery_tracker.set_character(character_name)

	# Send character load request to server
	NetworkManager.rpc_load_character.rpc_id(1, character_id, character_name, is_new)

## Receive inventory sync from server
func receive_inventory_sync(inventory_data: Array) -> void:
	print("[Client] Received inventory sync with %d slots" % inventory_data.size())

	if local_player and local_player.has_node("Inventory"):
		var inventory = local_player.get_node("Inventory")
		inventory.set_inventory_data(inventory_data)
		print("[Client] Updated local player inventory")

		# Track discovered items
		if item_discovery_tracker:
			for slot in inventory_data:
				if slot is Dictionary and slot.has("item"):
					var item_id = slot["item"]
					if not item_id.is_empty():
						item_discovery_tracker.discover_item(item_id)

		# Update hotbar UI if it exists
		if hotbar_ui:
			hotbar_ui.refresh_display()

## Receive character data including map pins
func receive_character_data(character_data: Dictionary) -> void:
	"""Called when character is fully loaded from server"""
	print("[Client] Received full character data")

	# Load map pins if they exist
	if character_data.has("map_pins"):
		var pins = character_data.get("map_pins", [])
		print("[Client] Loading %d map pins" % pins.size())

		if world_map_ui:
			world_map_ui.load_pins(pins)

		if mini_map_ui:
			mini_map_ui.set_pins(pins)

## Receive inventory slot update from server
func receive_inventory_slot_update(slot: int, item: String, amount: int) -> void:
	if local_player and local_player.has_node("Inventory"):
		var inventory = local_player.get_node("Inventory")
		if slot >= 0 and slot < inventory.slots.size():
			inventory.slots[slot] = {"item": item, "amount": amount}

			# Update hotbar UI if it exists
			if hotbar_ui:
				hotbar_ui.refresh_display()

## Receive equipment sync from server
func receive_equipment_sync(equipment_data: Dictionary) -> void:
	print("[Client] Received equipment sync")

	if local_player and local_player.has_node("Equipment"):
		var equipment = local_player.get_node("Equipment")
		equipment.set_equipment_data(equipment_data)
		print("[Client] Updated local player equipment")

		# TODO: Update equipment UI when we create it
		# Update inventory panel to show equipped items with visual indicators

# ============================================================================
# TERRAIN MODIFICATION SYNC
# ============================================================================

## Receive all terrain modifications from server on connect
## These are queued and applied when chunks are loaded (using existing queue system)
func receive_terrain_modifications(modifications: Array) -> void:
	print("[Client] Received %d terrain modifications from server - queuing for later application" % modifications.size())

	# Queue all modifications - they'll be applied by _check_queued_terrain_modifications
	# when the player is close enough and chunks are loaded
	for mod in modifications:
		var operation: String = mod.get("operation", "")
		var position: Array = mod.get("position", [0, 0, 0])
		var data: Dictionary = mod.get("data", {})

		queued_terrain_modifications.append({
			"operation": operation,
			"position": position,
			"data": data
		})

	print("[Client] Queued %d terrain modifications (total in queue: %d)" % [modifications.size(), queued_terrain_modifications.size()])

## Receive a modified terrain chunk from server
func receive_terrain_chunk(chunk_x: int, chunk_z: int, chunk_data: Dictionary) -> void:
	if not terrain_world:
		push_warning("[Client] Received terrain chunk but TerrainWorld not ready!")
		return

	print("[Client] Received modified terrain chunk (%d, %d) from server" % [chunk_x, chunk_z])
	terrain_world.apply_received_chunk(chunk_x, chunk_z, chunk_data)

# ============================================================================
# ENVIRONMENTAL OBJECT MANAGEMENT (CLIENT-SIDE VISUAL ONLY)
# ============================================================================

## Receive environmental objects from server - queues for batch spawning
func receive_environmental_objects(chunk_pos: Vector2i, objects_data: Array) -> void:
	# Create chunk entry if it doesn't exist
	if not environmental_chunks.has(chunk_pos):
		environmental_chunks[chunk_pos] = {}

	# Queue each object for spawning (instead of spawning immediately)
	for obj_data in objects_data:
		var obj_type = obj_data.get("type", "unknown")

		# Validate type exists in our preloaded scenes
		if not environmental_scenes.has(obj_type):
			push_error("[Client] Unknown environmental object type: %s" % obj_type)
			continue

		# Add to spawn queue with chunk info
		environmental_spawn_queue.append({
			"chunk_pos": chunk_pos,
			"obj_data": obj_data
		})

	# Mark queue as needing sort (will sort once before processing)
	environmental_queue_needs_sort = true

## Process environmental spawn queue - spawns ENVIRONMENTAL_SPAWN_BATCH_SIZE objects per frame
## Prioritizes objects closest to the player
func _process_environmental_queue() -> void:
	if environmental_spawn_queue.is_empty():
		return

	# Sort queue by distance to player (closest first) - only when new items added
	if environmental_queue_needs_sort and local_player and is_instance_valid(local_player):
		var player_pos: Vector3 = local_player.global_position
		environmental_spawn_queue.sort_custom(func(a, b):
			var pos_a = a.obj_data.get("pos", [0, 0, 0])
			var pos_b = b.obj_data.get("pos", [0, 0, 0])
			var dist_a = Vector2(pos_a[0] - player_pos.x, pos_a[2] - player_pos.z).length_squared()
			var dist_b = Vector2(pos_b[0] - player_pos.x, pos_b[2] - player_pos.z).length_squared()
			return dist_a < dist_b
		)
		environmental_queue_needs_sort = false

	var spawned_count := 0
	while spawned_count < ENVIRONMENTAL_SPAWN_BATCH_SIZE and not environmental_spawn_queue.is_empty():
		var queue_item = environmental_spawn_queue.pop_front()
		var chunk_pos: Vector2i = queue_item.chunk_pos
		var obj_data = queue_item.obj_data

		# Skip if chunk was already despawned
		if not environmental_chunks.has(chunk_pos):
			continue

		var obj_id = obj_data.get("id", -1)
		var obj_type = obj_data.get("type", "unknown")
		var pos_array = obj_data.get("pos", [0, 0, 0])
		var rot_array = obj_data.get("rot", [0, 0, 0])
		var scale_array = obj_data.get("scale", [1, 1, 1])

		# Use preloaded scene (no blocking load!)
		var obj_scene: PackedScene = environmental_scenes.get(obj_type)
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
		environmental_chunks[chunk_pos][obj_id] = obj
		spawned_count += 1

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

## Spawn a buildable object (called by server)
func spawn_buildable(piece_name: String, position: Vector3, rotation_y: float, network_id: String) -> void:
	print("[Client] Spawning buildable: %s at %s (ID: %s)" % [piece_name, position, network_id])

	# Get the scene for this piece
	if not build_mode or not build_mode.available_pieces.has(piece_name):
		push_error("[Client] Unknown buildable piece: %s" % piece_name)
		return

	var piece_scene = build_mode.available_pieces[piece_name]
	var buildable = piece_scene.instantiate()
	buildable.name = "Buildable_%s" % network_id
	buildable.is_preview = false  # This is a real placed object

	# Add to world and set position/rotation
	world.add_child(buildable)
	buildable.global_position = position
	buildable.rotation.y = rotation_y

	print("[Client] Buildable %s placed successfully" % piece_name)

func remove_buildable(network_id: String) -> void:
	print("[Client] Removing buildable: %s" % network_id)

	# Find the buildable by its network ID
	var buildable_name = "Buildable_%s" % network_id
	var buildable = world.get_node_or_null(buildable_name)

	if buildable:
		buildable.queue_free()
		print("[Client] Buildable %s removed from world" % network_id)
	else:
		print("[Client] WARNING: Buildable %s not found in world" % network_id)

## Clean up all environmental objects
func _cleanup_environmental_objects() -> void:
	for chunk_pos in environmental_chunks.keys():
		despawn_environmental_objects(chunk_pos)
	environmental_chunks.clear()
	environmental_spawn_queue.clear()

## Spawn an enemy (client-host model: one client runs AI, others interpolate)
func spawn_enemy(enemy_path: NodePath, enemy_type: String, position: Vector3, enemy_name: String, network_id: int = 0, host_peer_id: int = 0) -> void:
	# Don't spawn if already exists
	if spawned_enemies.has(enemy_path):
		return

	# Get the correct scene based on enemy type
	var enemy_scene: PackedScene = null
	match enemy_type:
		"Gahnome":
			enemy_scene = gahnome_scene
		_:
			print("[Client] Unknown enemy type: %s" % enemy_type)
			return

	# Instantiate enemy
	var enemy = enemy_scene.instantiate()
	enemy.name = str(enemy_path).get_file()  # Use the path's last part as name

	# Set network_id BEFORE adding to tree (so it's available in _ready)
	if "network_id" in enemy:
		enemy.network_id = network_id

	# Determine if this client is the host for this enemy
	var my_peer_id = multiplayer.get_unique_id()
	var am_host = (host_peer_id > 0 and my_peer_id == host_peer_id)

	# Set host/remote flags
	enemy.is_host = am_host
	enemy.is_remote = true  # All client enemies are "remote" (not server-spawned)
	enemy.host_peer_id = host_peer_id
	enemy.sync_position = position  # Initial sync position for non-host interpolation

	world.add_child(enemy)
	enemy.global_position = position

	# Track enemy (also store by string path for update lookups)
	spawned_enemies[enemy_path] = enemy
	spawned_enemies[str(enemy_path)] = enemy  # Duplicate for string lookup

	var role = "HOST" if am_host else "remote"
	print("[Client] Spawned enemy %s at %s (network_id=%d, %s)" % [enemy_name, position, network_id, role])

## Despawn an enemy
func despawn_enemy(enemy_path: NodePath) -> void:
	var enemy = spawned_enemies.get(enemy_path)
	if enemy and is_instance_valid(enemy):
		enemy.queue_free()
		spawned_enemies.erase(enemy_path)
		spawned_enemies.erase(str(enemy_path))
		print("[Client] Despawned enemy %s" % enemy_path)

## Update enemy states from server (called at 10Hz)
## Compact format: { "path_string": [px, py, pz, rot_y, state, hp, target_peer], ... }
func update_enemy_states(states: Dictionary) -> void:
	for path_str in states:
		# Find enemy by path string
		var enemy = spawned_enemies.get(path_str)
		if not enemy or not is_instance_valid(enemy):
			continue

		# Extract state data from compact array [px, py, pz, rot_y, state, hp, target_peer]
		var state_arr: Array = states[path_str]
		if state_arr.size() < 6:
			continue

		var pos = Vector3(state_arr[0], state_arr[1], state_arr[2])
		var rot_y: float = state_arr[3]
		var ai_state: int = int(state_arr[4])
		var hp: float = state_arr[5]
		var target_peer: int = int(state_arr[6]) if state_arr.size() > 6 else 0

		# Apply server state to enemy (includes target_peer for Valheim-style sync)
		if enemy.has_method("apply_server_state"):
			enemy.apply_server_state(pos, rot_y, ai_state, hp, target_peer)

## Apply enemy damage forwarded from server (for HOST client)
## Called when another player hits an enemy that this client hosts
func apply_enemy_damage(enemy_network_id: int, damage: float, knockback: float, direction: Vector3) -> void:
	print("[Client] apply_enemy_damage: net_id=%d, damage=%.1f" % [enemy_network_id, damage])

	# Find enemy by network_id
	var enemy: Node = null
	for key in spawned_enemies.keys():
		var e = spawned_enemies[key]
		if e and is_instance_valid(e) and "network_id" in e and e.network_id == enemy_network_id:
			enemy = e
			break

	if not enemy:
		print("[Client] ERROR: Enemy with network_id %d not found!" % enemy_network_id)
		return

	# Only apply if we are the host for this enemy
	if not enemy.is_host:
		print("[Client] WARNING: Received damage for enemy %d but we are not the host" % enemy_network_id)
		return

	# Apply damage to the enemy
	if enemy.has_method("take_damage"):
		print("[Client] Applying %.1f damage to hosted enemy %d" % [damage, enemy_network_id])
		enemy.take_damage(damage, knockback, direction)
	else:
		print("[Client] ERROR: Enemy %d has no take_damage method!" % enemy_network_id)

## Request server to perform a manual save (triggered by F5 key)
func _request_server_save() -> void:
	print("[Client] Requesting manual save (F5 pressed)...")
	NetworkManager.rpc_request_save.rpc_id(1)

## Show save notification when server completes the save
func show_save_notification() -> void:
	print("[Client] Server save completed!")
	_show_discovery_notification("Game Saved")

# ============================================================================
# MAP SYSTEM
# ============================================================================

func _toggle_world_map() -> void:
	if world_map_ui:
		world_map_ui.toggle_map()

		# Update remote players reference
		if world_map_ui.visible:
			world_map_ui.set_remote_players(remote_players)

	# Also update mini-map remote players reference
	if mini_map_ui:
		mini_map_ui.set_remote_players(remote_players)

func _on_map_ping_sent(world_pos: Vector2) -> void:
	"""Called when player sends a ping from the map"""
	print("[Client] Sending ping to server at %s" % world_pos)

	# Send to server
	NetworkManager.rpc_send_ping.rpc_id(1, [world_pos.x, world_pos.y])

	# Create local 3D ping indicator
	_create_ping_indicator(world_pos, NetworkManager.get_local_player_id())

func receive_ping(world_pos: Vector2, from_peer: int) -> void:
	"""Called by NetworkManager when receiving a ping from another player"""
	print("[Client] Received ping from peer %d at %s" % [from_peer, world_pos])

	# Add to map UIs
	if world_map_ui:
		world_map_ui.add_ping(world_pos, from_peer)

	if mini_map_ui:
		mini_map_ui.add_ping(world_pos, from_peer)

	# Create 3D ping indicator
	_create_ping_indicator(world_pos, from_peer)

func _create_ping_indicator(world_pos: Vector2, from_peer: int) -> void:
	"""Create a 3D ping indicator in the world"""
	var indicator = Node3D.new()
	indicator.set_script(ping_indicator_script)
	world.add_child(indicator)

	# Initialize after adding to tree
	if indicator.has_method("initialize"):
		indicator.initialize(world_pos, from_peer)

	active_ping_indicators.append(indicator)

	# Clean up expired indicators
	for i in range(active_ping_indicators.size() - 1, -1, -1):
		var ping = active_ping_indicators[i]
		if not is_instance_valid(ping):
			active_ping_indicators.remove_at(i)

# ============================================================================
# LOADING SCREEN MANAGEMENT
# ============================================================================

## Start loading sequence
func _start_loading() -> void:
	print("[Client] Starting loading sequence")
	is_loading = true

	# Reset loading state
	for key in loading_steps_complete.keys():
		loading_steps_complete[key] = false

	queued_terrain_modifications.clear()

	# Show loading screen
	if loading_screen_ui:
		loading_screen_ui.show_loading()
		# Debug skip disabled - was causing premature loading completion
		# loading_screen_ui.enable_skip()  # Allow ESC to skip for debugging

	# Disable player physics and input if spawned
	if local_player:
		_disable_player_physics()
		# Disable game loaded state to prevent input and gravity
		if local_player.has_method("set_game_loaded"):
			local_player.set_game_loaded(false)

## Mark a loading step as complete
func _mark_loading_step_complete(step: String) -> void:
	if not loading_steps_complete.has(step):
		push_warning("[Client] Unknown loading step: %s" % step)
		return

	loading_steps_complete[step] = true
	print("[Client] Loading step complete: %s" % step)
	_update_loading_progress()
	_check_loading_complete()

## Update loading progress bar
func _update_loading_progress() -> void:
	if not loading_screen_ui or not is_loading:
		return

	var completed_steps: int = 0
	var total_steps: int = loading_steps_complete.size()

	for step in loading_steps_complete.keys():
		if loading_steps_complete[step]:
			completed_steps += 1

	var progress: float = float(completed_steps) / float(total_steps)
	loading_screen_ui.set_progress(progress)

	# Update status based on current step
	if not loading_steps_complete["world_config"]:
		loading_screen_ui.set_status("Receiving world configuration...")
	elif not loading_steps_complete["buildables"]:
		loading_screen_ui.set_status("Loading structures...")
	elif not loading_steps_complete["player_spawned"]:
		loading_screen_ui.set_status("Spawning player...")
	elif not loading_steps_complete["terrain_ready"]:
		loading_screen_ui.set_status("Generating terrain...")
	elif not loading_steps_complete["environmental_objects"]:
		loading_screen_ui.set_status("Spawning environmental objects...")
	elif not loading_steps_complete["terrain_modifications"]:
		loading_screen_ui.set_status("Applying terrain modifications...")
	elif not loading_steps_complete["world_map"]:
		loading_screen_ui.set_status("Generating world map...")

## Check if all loading steps are complete
func _check_loading_complete() -> void:
	if not is_loading:
		return

	# Check if all steps are done
	var all_complete: bool = true
	for step in loading_steps_complete.keys():
		if not loading_steps_complete[step]:
			all_complete = false
			break

	if all_complete:
		_finish_loading()

## Finish loading and enter game
func _finish_loading() -> void:
	print("[Client] Loading complete!")
	is_loading = false

	# Enable player physics and gameplay
	if local_player:
		_enable_player_physics()
		# Enable game loaded state to allow input and gravity
		if local_player.has_method("set_game_loaded"):
			local_player.set_game_loaded(true)

	# Hide loading screen
	if loading_screen_ui:
		loading_screen_ui.hide_loading()

	# Show HUD and enable gameplay
	is_in_game = true

## Debug skip loading screen
func loading_screen_skipped() -> void:
	print("[Client] Loading screen skipped (debug)")
	_finish_loading()

## Disable player physics during loading
func _disable_player_physics() -> void:
	if not local_player:
		return

	# Disable player's CharacterBody3D physics
	if local_player.has_method("set_physics_process"):
		local_player.set_physics_process(false)

	# Freeze position
	if local_player is CharacterBody3D:
		local_player.set_physics_process(false)

	print("[Client] Player physics disabled during loading")

## Enable player physics after loading
func _enable_player_physics() -> void:
	if not local_player:
		return

	# Enable player's CharacterBody3D physics
	if local_player.has_method("set_physics_process"):
		local_player.set_physics_process(true)

	if local_player is CharacterBody3D:
		local_player.set_physics_process(true)

	print("[Client] Player physics enabled")

## Check if terrain is ready (chunks loaded around player)
func _check_terrain_ready() -> void:
	if not local_player or not is_loading:
		return

	# Wait a moment for initial terrain generation
	await get_tree().create_timer(2.0).timeout

	if is_loading:  # Still loading
		print("[Client] Terrain ready")
		_mark_loading_step_complete("terrain_ready")

		# Don't apply queued modifications immediately - let the periodic checker handle it
		# This way modifications only apply when player is close enough (distance-based)
		# The periodic checker runs every 2 seconds and will apply them when in range
		print("[Client] %d terrain modifications queued - will apply when player is near" % queued_terrain_modifications.size())

		# Mark terrain modifications step complete and generate world map
		_mark_loading_step_complete("terrain_modifications")
		_generate_world_map_cache()

## Queue terrain modification for later application
func queue_terrain_modification(operation: String, position: Array, data: Dictionary) -> void:
	queued_terrain_modifications.append({
		"operation": operation,
		"position": position,
		"data": data
	})
	print("[Client] Queued terrain modification: %s (total: %d)" % [operation, queued_terrain_modifications.size()])

## Apply all queued terrain modifications
func _apply_queued_terrain_modifications() -> void:
	if queued_terrain_modifications.is_empty():
		print("[Client] No queued terrain modifications to apply")
		_mark_loading_step_complete("terrain_modifications")
		_generate_world_map_cache()
		return

	print("[Client] Applying %d queued terrain modifications..." % queued_terrain_modifications.size())

	var failed_mods: Array = []
	for mod in queued_terrain_modifications:
		var success = _apply_terrain_modification_internal(mod.operation, mod.position, mod.data)
		if not success:
			# Re-queue modifications that failed (area not editable yet)
			failed_mods.append(mod)

	if not failed_mods.is_empty():
		print("[Client] %d terrain modifications failed (area not editable) - will retry later" % failed_mods.size())
		queued_terrain_modifications = failed_mods
	else:
		queued_terrain_modifications.clear()

	_mark_loading_step_complete("terrain_modifications")
	_generate_world_map_cache()

## Check queued terrain modifications and apply ones that are now in range
func _check_queued_terrain_modifications() -> void:
	if queued_terrain_modifications.is_empty() or not local_player:
		return

	var player_pos: Vector3 = local_player.global_position
	var mods_to_apply: Array = []
	var mods_to_keep: Array = []

	# VoxelTool needs player VERY close for reliable operation
	# Reduced to 29m to ensure far edges of large builds load reliably
	const MAX_DISTANCE := 29.0  # Safety margin below 1 chunk (32 units)

	# Check each queued modification
	for mod in queued_terrain_modifications:
		var pos_array: Array = mod.position
		var pos_v3 := Vector3(pos_array[0], pos_array[1], pos_array[2])
		var distance := Vector2(player_pos.x, player_pos.z).distance_to(Vector2(pos_v3.x, pos_v3.z))

		if distance <= MAX_DISTANCE:  # Within VoxelTool range
			mods_to_apply.append(mod)
		else:
			mods_to_keep.append(mod)

	# Apply modifications that are now in range
	if not mods_to_apply.is_empty():
		print("[Client] Applying %d queued terrain modifications (player in range)" % mods_to_apply.size())
		var failed_count = 0
		for mod in mods_to_apply:
			var success = _apply_terrain_modification_internal(mod.operation, mod.position, mod.data)
			if not success:
				# Re-queue if still not editable (terrain detail not loaded yet)
				mods_to_keep.append(mod)
				failed_count += 1

		if failed_count > 0:
			print("[Client] %d modifications still not editable - will retry" % failed_count)

	# Keep modifications that are still out of range or failed
	queued_terrain_modifications = mods_to_keep

## Internal terrain modification application
## Returns true if successful, false if area not editable (should re-queue)
func _apply_terrain_modification_internal(operation: String, position: Array, data: Dictionary) -> bool:
	if not terrain_world:
		return false

	var pos_v3 := Vector3(position[0], position[1], position[2])
	var tool_name: String = data.get("tool", "stone_pickaxe")
	var earth_amount: int = data.get("earth_amount", 0)
	var success: bool = true

	match operation:
		"dig_square":
			var result = terrain_world.dig_square(pos_v3, tool_name)
			success = result > 0
		"place_square":
			var result = terrain_world.place_square(pos_v3, earth_amount)
			success = result > 0
		"flatten_square":
			var target_height: float = data.get("target_height", pos_v3.y)
			terrain_world.flatten_square(pos_v3, target_height)
			success = true
		_:
			# Unknown or deprecated operation (dig_circle, place_circle, level_circle, etc.)
			print("[Client] Skipping unknown/deprecated terrain operation: %s" % operation)
			success = false

	return success

## Generate world map cache during loading
func _generate_world_map_cache() -> void:
	# OPTIMIZATION: Skip world map generation during loading
	# Maps now generate on-demand showing only the visible area
	# This prevents blocking the loading screen
	_mark_loading_step_complete("world_map")

## Handle controller input for connection UI
func _handle_connection_ui_input() -> void:
	# A button to connect
	if Input.is_action_just_pressed("interact"):
		if not connect_button.disabled:
			_on_connect_button_pressed()

## Handle controller input for character selection
func _handle_character_selection_input() -> void:
	# Let character selection handle its own controller input
	pass

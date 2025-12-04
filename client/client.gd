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
var debug_console_scene := preload("res://client/ui/debug_console.tscn")
var chest_ui_scene := preload("res://client/ui/chest_ui.tscn")
var shop_ui_scene := preload("res://client/ui/shop_ui.tscn")
var build_controls_hint_scene := preload("res://client/ui/build_controls_hint.tscn")

# Enemy scenes
var gahnome_scene := preload("res://shared/enemies/gahnome.tscn")
var sporeling_scene := preload("res://shared/enemies/sporeling.tscn")

# Boss scenes
var cyclops_scene := preload("res://shared/enemies/bosses/cyclops.tscn")

# Animal scenes
var deer_scene := preload("res://shared/animals/deer.tscn")
var pig_scene := preload("res://shared/animals/pig.tscn")
var sheep_scene := preload("res://shared/animals/sheep.tscn")

# Environmental object scenes (preloaded to avoid blocking main thread)
var environmental_scenes: Dictionary = {
	"tree": preload("res://shared/environmental/tree.tscn"),  # Legacy tree
	"truffula_tree": preload("res://shared/environmental/truffula_tree.tscn"),  # New Valheim-style tree
	"tree_sprout": preload("res://shared/environmental/tree_sprout.tscn"),  # Punchable sapling
	"rock": preload("res://shared/environmental/rock.tscn"),
	"grass": preload("res://shared/environmental/grass_clump.tscn"),
	"mushroom_tree": preload("res://shared/environmental/mushroom_tree.tscn"),
	"glowing_mushroom": preload("res://shared/environmental/glowing_mushroom.tscn"),
	"giant_mushroom": preload("res://shared/environmental/giant_mushroom.tscn"),
	"spore_cluster": preload("res://shared/environmental/spore_cluster.tscn"),
}

# Environmental object spawn queue (for non-blocking spawning)
# Dictionary of chunk_pos -> Array of obj_data, so we can prioritize closest chunks
var environmental_spawn_queues: Dictionary = {}
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

# Debug console
var debug_console_ui: Control = null

# Chest UI
var chest_ui: Control = null

# Shop UI (Shnarken NPC)
var shop_ui: Control = null
var interact_held_time: float = 0.0

# Build controls hint UI
var build_controls_hint_ui: Control = null
var interact_target_chest: Node = null
const QUICK_SORT_HOLD_TIME: float = 0.5  # Hold E for 0.5s to quick-sort
var ping_indicator_script = preload("res://client/ping_indicator.gd")
var ping_screen_indicator_script = preload("res://client/ui/ping_screen_indicator.gd")
var map_marker_script = preload("res://client/map_marker_indicator.gd")
var active_ping_indicators: Array = []  # 3D ping indicators in the world
var active_ping_screen_indicators: Array = []  # Screen-space ping direction indicators
var active_map_markers: Dictionary = {}  # 3D map markers {pos_key: Node3D}

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

# Fog wall manager
var fog_wall_manager: Node3D = null

# Cached Shnarken NPCs (avoid expensive tree traversal every frame)
var cached_shnarkens: Array = []
var shnarken_cache_timer: float = 0.0
const SHNARKEN_CACHE_INTERVAL: float = 1.0  # Rebuild cache every 1 second

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
@onready var interact_prompt_label: Label = $CanvasLayer/HUD/Crosshair/InteractPrompt

# World and camera
@onready var world: Node3D = $World
@onready var terrain_world = $World/TerrainWorld

func _ready() -> void:
	print("[Client] Client node ready")

	# Create environmental objects container
	environmental_objects_container = Node3D.new()
	environmental_objects_container.name = "EnvironmentalObjects"
	world.add_child(environmental_objects_container)

	# Create fog wall manager for render distance fog
	var FogWallManager = preload("res://client/fog_wall_manager.gd")
	fog_wall_manager = FogWallManager.new()
	fog_wall_manager.name = "FogWallManager"
	world.add_child(fog_wall_manager)

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

	# Create debug console (F5 to toggle)
	debug_console_ui = debug_console_scene.instantiate()
	canvas_layer.add_child(debug_console_ui)

	# Create chest UI
	chest_ui = chest_ui_scene.instantiate()
	canvas_layer.add_child(chest_ui)

	# Create shop UI (Shnarken NPC)
	shop_ui = shop_ui_scene.instantiate()
	canvas_layer.add_child(shop_ui)

	# Create build controls hint UI
	build_controls_hint_ui = build_controls_hint_scene.instantiate()
	canvas_layer.add_child(build_controls_hint_ui)

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
		# Block gameplay input while debug console is open
		if not (debug_console_ui and debug_console_ui.visible):
			_handle_build_input()
			_handle_interaction_input()
			_update_interact_prompt()
		_update_biome_music(_delta)

		# Rebuild Shnarken cache periodically (avoid expensive tree traversal every frame)
		shnarken_cache_timer += _delta
		if shnarken_cache_timer >= SHNARKEN_CACHE_INTERVAL:
			shnarken_cache_timer = 0.0
			_rebuild_shnarken_cache()

		# Check queued terrain modifications periodically
		queued_mods_check_timer += _delta
		if queued_mods_check_timer >= QUEUED_MODS_CHECK_INTERVAL:
			queued_mods_check_timer = 0.0
			_check_queued_terrain_modifications()

	# Process environmental object spawn queue (runs even during loading)
	_process_environmental_queue()

	# Handle pause menu (Escape or Button 6)
	# But first check if UI panels are open - ESC should close them without opening pause menu
	if (Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("toggle_pause")) and is_in_game:
		# Check if debug console is open - if so, close it and don't toggle pause
		if debug_console_ui and debug_console_ui.visible:
			debug_console_ui.hide_console()
		# Check if world map is open - if so, close it and don't toggle pause
		elif world_map_ui and world_map_ui.visible:
			world_map_ui.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Check if inventory is open - if so, close it and don't toggle pause
		elif inventory_panel_ui and inventory_panel_ui.is_inventory_open():
			inventory_panel_ui.hide_inventory()
		# Check if chest UI is open - if so, close it and don't toggle pause
		elif chest_ui and chest_ui.is_ui_open():
			chest_ui.hide_ui()
		# Check if shop UI is open - if so, close it and don't toggle pause
		elif shop_ui and shop_ui.is_shop_open():
			shop_ui.hide_ui()
		else:
			_toggle_pause_menu()

	# Handle manual save
	if Input.is_action_just_pressed("manual_save") and is_in_game:
		_request_server_save()

	# Handle map open (M only opens, ESC closes - so you can type M in pin names)
	if Input.is_action_just_pressed("toggle_map") and is_in_game:
		if world_map_ui and not world_map_ui.visible:
			_toggle_world_map()

	# Handle debug console toggle (F5)
	if Input.is_action_just_pressed("toggle_debug_console"):
		if debug_console_ui:
			if debug_console_ui.visible:
				debug_console_ui.hide_console()
			else:
				debug_console_ui.show_console()

func auto_connect_to_localhost() -> void:
	"""Auto-connect to localhost for singleplayer mode"""
	auto_connect_to_address("127.0.0.1:%d" % NetworkManager.DEFAULT_PORT)

func auto_connect_to_address(address_port: String) -> void:
	"""Auto-connect to a specific address:port"""
	await get_tree().create_timer(0.1).timeout

	var parts = address_port.split(":")
	if parts.size() >= 2:
		ip_input.text = parts[0]
		port_input.text = parts[1]
	else:
		ip_input.text = address_port
		port_input.text = str(NetworkManager.DEFAULT_PORT)

	print("[Client] Auto-connecting to %s:%s" % [ip_input.text, port_input.text])
	_on_connect_button_pressed()

## Connect to server with a custom multiplayer API (for singleplayer mode)
func connect_with_multiplayer(address: String, port: int, custom_multiplayer: SceneMultiplayer) -> void:
	print("[Client] Connecting to %s:%d with custom multiplayer..." % [address, port])

	# Create ENet client peer
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)

	if error != OK:
		push_error("[Client] Failed to connect to %s:%d: %s" % [address, port, error_string(error)])
		return

	# Set up the custom multiplayer
	custom_multiplayer.multiplayer_peer = peer

	# Connect multiplayer signals
	custom_multiplayer.connected_to_server.connect(_on_client_connected)
	custom_multiplayer.connection_failed.connect(_on_connection_failed)
	custom_multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Hide connection UI since we're auto-connecting
	connection_ui.visible = false

	print("[Client] Waiting for connection...")

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
	if chest_ui and chest_ui.is_ui_open():
		return
	if shop_ui and shop_ui.is_shop_open():
		return

	# Check for number keys 1-9 when looking at cooking station
	_handle_cooking_station_hotbar_input()

	# Track E key hold for quick-sort chest interaction
	if Input.is_action_just_pressed("interact"):
		interact_held_time = 0.0
		interact_target_chest = _get_chest_under_cursor()

	if Input.is_action_pressed("interact"):
		interact_held_time += get_process_delta_time()
		# Visual feedback could be added here

	if Input.is_action_just_released("interact"):
		if interact_target_chest:
			# Check if held long enough for quick-sort
			var quick_sort = interact_held_time >= QUICK_SORT_HOLD_TIME
			_open_chest_ui(interact_target_chest, quick_sort)
			interact_target_chest = null
		else:
			# Check for nearby Shnarken NPC first
			var nearby_shnarken = _get_nearby_shnarken()
			if nearby_shnarken:
				_open_shop_ui(nearby_shnarken)
			else:
				# Normal interaction (workbench, etc.)
				_interact_with_object_under_cursor()
		interact_held_time = 0.0

func _interact_with_object_under_cursor() -> void:
	var camera = _get_camera()
	if not camera:
		return

	# Raycast from crosshair position (offset from center - see crosshair.tscn)
	# Crosshair is at center + (-41, -50) pixels offset
	var viewport_size = get_viewport().get_visible_rect().size
	var crosshair_screen_pos = viewport_size / 2.0 + Vector2(-41, -50)

	var from = camera.project_ray_origin(crosshair_screen_pos)
	var ray_dir = camera.project_ray_normal(crosshair_screen_pos)
	var to = from + ray_dir * 5.0  # 5m interaction range

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World layer
	query.collide_with_areas = true  # Detect Area3D for door interaction zones

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var hit_object = result.collider
		# Check if it's a buildable object (workbench, door, cooking station, etc.)
		var buildable = hit_object
		while buildable:
			# Check if it's a door
			if buildable.has_method("interact") and buildable.get("is_interactable"):
				print("[Client] Interacting with door")
				buildable.interact()
				return
			# Check if it's a cooking station (server handles inventory, client handles cooking)
			if buildable.is_in_group("cooking_station") and buildable.has_method("interact"):
				print("[Client] Interacting with cooking station")
				_interact_with_cooking_station(buildable)
				return
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

	# Set local player reference (for finding nearby chests)
	crafting_menu_ui.set_local_player(local_player)

	# Set player inventory reference
	if local_player.has_node("Inventory"):
		var inventory = local_player.get_node("Inventory")
		crafting_menu_ui.set_player_inventory(inventory)

	# Open the menu
	crafting_menu_ui.show_menu()
	print("[Client] Opened crafting menu")

## Update the interaction prompt based on what the player is looking at
func _update_interact_prompt() -> void:
	if not interact_prompt_label:
		return

	# Hide prompt if UI is open
	if (inventory_panel_ui and inventory_panel_ui.is_inventory_open()) or \
	   (crafting_menu_ui and crafting_menu_ui.is_open) or \
	   (chest_ui and chest_ui.is_ui_open()) or \
	   (shop_ui and shop_ui.is_shop_open()):
		interact_prompt_label.text = ""
		return

	# Check for nearby Shnarken NPC first
	var nearby_shnarken = _get_nearby_shnarken()
	if nearby_shnarken:
		interact_prompt_label.text = "Trade [E]"
		return

	var camera = _get_camera()
	if not camera:
		interact_prompt_label.text = ""
		return

	# Raycast from crosshair position
	var viewport_size = get_viewport().get_visible_rect().size
	var crosshair_screen_pos = viewport_size / 2.0 + Vector2(-41, -50)
	var from = camera.project_ray_origin(crosshair_screen_pos)
	var ray_dir = camera.project_ray_normal(crosshair_screen_pos)
	var to = from + ray_dir * 5.0  # 5m interaction range

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = true

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var hit_object = result.collider
		var buildable = hit_object
		while buildable:
			# Cooking station
			if buildable.is_in_group("cooking_station") and buildable.has_method("get_interact_prompt"):
				interact_prompt_label.text = buildable.get_interact_prompt()
				return
			# Door
			if buildable.has_method("get_interaction_prompt") and buildable.get("is_interactable"):
				interact_prompt_label.text = buildable.get_interaction_prompt() + " [E]"
				return
			# Workbench
			if buildable.has_method("is_position_in_range") and buildable.get("is_crafting_station"):
				var station_type = buildable.get("station_type")
				if station_type == "workbench":
					interact_prompt_label.text = "Open workbench [E]"
					return
			# Chest
			if buildable.is_in_group("chest"):
				interact_prompt_label.text = "Open chest [E] / Quick-sort [Hold E]"
				return
			buildable = buildable.get_parent()

	interact_prompt_label.text = ""

## Interact with cooking station - server handles inventory, client handles cooking simulation
func _interact_with_cooking_station(station: Node) -> void:
	if not local_player:
		return

	# First, check if any slot has cooked/burned food to take
	for slot_idx in station.cooking_slots.size():
		var slot = station.cooking_slots[slot_idx]
		if slot.state == station.CookState.COOKED or slot.state == station.CookState.BURNED:
			var result_item = station.remove_item(slot_idx)
			if not result_item.is_empty():
				# Tell server to add item to inventory
				NetworkManager.rpc_request_cooking_station_take.rpc_id(1, result_item)
				print("[Client] Took %s from cooking station" % result_item)
				return

	# No cooked food - try to add raw meat
	# Check local player's inventory (will be synced from server)
	var inventory = local_player.get_node_or_null("Inventory")
	if not inventory:
		return

	for raw_item in station.COOKING_RECIPES.keys():
		if inventory.has_item(raw_item, 1):
			var slot_idx = station.add_item_to_cook(raw_item)
			if slot_idx >= 0:
				# Tell server to remove from inventory
				NetworkManager.rpc_request_cooking_station_add.rpc_id(1, raw_item)
				print("[Client] Added %s to cooking station" % raw_item)
				return

	print("[Client] No raw meat to cook")

## Handle number key input when looking at a cooking station
func _handle_cooking_station_hotbar_input() -> void:
	if not local_player:
		return

	# Check if any hotbar key was just pressed
	var pressed_slot = -1
	for i in range(1, 10):
		if Input.is_action_just_pressed("hotbar_" + str(i)):
			pressed_slot = i - 1  # Convert to 0-indexed
			break

	if pressed_slot < 0:
		return

	# Check if looking at a cooking station
	var cooking_station = _get_cooking_station_under_cursor()
	if not cooking_station:
		return

	# Get the item in the pressed hotbar slot
	var inventory = local_player.get_node_or_null("Inventory")
	if not inventory:
		return

	var inventory_data = inventory.get_inventory_data()
	if pressed_slot >= inventory_data.size():
		return

	var slot_data = inventory_data[pressed_slot]
	if slot_data.is_empty():
		return

	var item_id = slot_data.get("item", "")
	if item_id.is_empty():
		return

	# Check if this item can be cooked
	if not cooking_station.COOKING_RECIPES.has(item_id):
		print("[Client] %s cannot be cooked" % item_id)
		return

	# Add to local cooking station and tell server to remove from inventory
	var slot_idx = cooking_station.add_item_to_cook(item_id)
	if slot_idx >= 0:
		NetworkManager.rpc_request_cooking_station_add.rpc_id(1, item_id)
		print("[Client] Added %s to cooking station from hotbar slot %d" % [item_id, pressed_slot + 1])
	else:
		print("[Client] No empty cooking slots")

## Get cooking station under cursor (returns null if not looking at one)
func _get_cooking_station_under_cursor() -> Node:
	var camera = _get_camera()
	if not camera:
		return null

	var viewport_size = get_viewport().get_visible_rect().size
	var crosshair_screen_pos = viewport_size / 2.0 + Vector2(-41, -50)

	var from = camera.project_ray_origin(crosshair_screen_pos)
	var ray_dir = camera.project_ray_normal(crosshair_screen_pos)
	var to = from + ray_dir * 5.0

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var buildable = result.collider
		while buildable:
			if buildable.is_in_group("cooking_station"):
				return buildable
			buildable = buildable.get_parent()

	return null

## Get chest under cursor for interaction (returns null if no chest)
func _get_chest_under_cursor() -> Node:
	var camera = _get_camera()
	if not camera:
		return null

	# Raycast from crosshair position (offset from center - see crosshair.tscn)
	var viewport_size = get_viewport().get_visible_rect().size
	var crosshair_screen_pos = viewport_size / 2.0 + Vector2(-41, -50)

	var from = camera.project_ray_origin(crosshair_screen_pos)
	var ray_dir = camera.project_ray_normal(crosshair_screen_pos)
	var to = from + ray_dir * 5.0  # 5m interaction range

	var space_state = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World layer

	var result = space_state.intersect_ray(query)

	if result and result.collider:
		var hit_object = result.collider
		# Walk up the tree to find a storage buildable
		var buildable = hit_object
		while buildable:
			if buildable.get("is_storage"):
				return buildable
			buildable = buildable.get_parent()

	return null

## Open chest UI
func _open_chest_ui(chest: Node, quick_sort: bool = false) -> void:
	if not chest_ui:
		push_error("[Client] Chest UI not found!")
		return

	if not local_player:
		push_error("[Client] No local player!")
		return

	# Get the network_id from the parent buildable's name (format: "Buildable_<network_id>")
	var chest_network_id := ""
	var parent = chest.get_parent()
	if parent and parent.name.begins_with("Buildable_"):
		chest_network_id = parent.name.substr(10)  # Remove "Buildable_" prefix
	elif chest.name.begins_with("Buildable_"):
		chest_network_id = chest.name.substr(10)

	if chest_network_id.is_empty():
		push_error("[Client] Could not find chest network_id!")
		return

	# Notify server that we're opening this chest
	NetworkManager.rpc_open_chest.rpc_id(1, chest_network_id)
	print("[Client] Sent rpc_open_chest for chest %s" % chest_network_id)

	# Set player inventory reference
	if local_player.has_node("Inventory"):
		var inventory = local_player.get_node("Inventory")
		chest_ui.set_player_inventory(inventory)

	# Connect to chest_ui.closed signal to notify server when closing
	if not chest_ui.closed.is_connected(_on_chest_ui_closed):
		chest_ui.closed.connect(_on_chest_ui_closed)

	# Open the chest UI
	chest_ui.show_ui(chest, quick_sort)
	if quick_sort:
		print("[Client] Opened chest with quick-sort")
	else:
		print("[Client] Opened chest")

## Called when chest UI is closed
func _on_chest_ui_closed() -> void:
	NetworkManager.rpc_close_chest.rpc_id(1)
	print("[Client] Sent rpc_close_chest")

## Get nearby Shnarken NPC (within interaction range)
func _get_nearby_shnarken() -> Node:
	if not local_player:
		return null

	var player_pos = local_player.global_position

	# Use cached Shnarken list (rebuilt periodically, not every frame)
	for shnarken in cached_shnarkens:
		if not is_instance_valid(shnarken):
			continue
		var dist = player_pos.distance_to(shnarken.global_position)
		if dist < 3.5:  # Interaction range (slightly more than the Area3D radius)
			return shnarken

	return null

## Rebuild the cached list of Shnarken NPCs (called periodically, not every frame)
func _rebuild_shnarken_cache() -> void:
	cached_shnarkens.clear()

	# Find all Shnarken NPCs in the scene via groups (fast)
	cached_shnarkens = get_tree().get_nodes_in_group("shnarken").duplicate()

	# Also search for Shnarken class instances in npc group
	for node in get_tree().get_nodes_in_group("npc"):
		if node.get_script() and node.get_script().get_global_name() == "Shnarken":
			if not node in cached_shnarkens:
				cached_shnarkens.append(node)

	# Search in world for ShnarkenHut which contains Shnarken
	for child in world.get_children():
		_find_shnarkens_recursive(child, cached_shnarkens)

## Recursively find Shnarken NPCs in node tree
func _find_shnarkens_recursive(node: Node, shnarkens: Array) -> void:
	if node.has_method("get_greeting_dialogue"):  # Check for Shnarken methods
		if not node in shnarkens:
			shnarkens.append(node)
	for child in node.get_children():
		_find_shnarkens_recursive(child, shnarkens)

## Open shop UI for a Shnarken NPC
func _open_shop_ui(shnarken: Node) -> void:
	if not shop_ui:
		push_error("[Client] Shop UI not found!")
		return

	if not local_player:
		push_error("[Client] No local player!")
		return

	# Open the shop UI
	shop_ui.show_ui(shnarken)
	print("[Client] Opened Shnarken shop")

## Handle chest inventory sync from server
func handle_chest_sync(chest_network_id: String, inventory_data: Array) -> void:
	print("[Client] Received chest sync for %s: %d items" % [chest_network_id, inventory_data.size()])

	# Update the chest's inventory data and refresh the UI
	if chest_ui and chest_ui.is_ui_open() and chest_ui.current_chest:
		# Update the chest node's inventory
		var chest = chest_ui.current_chest
		if chest.has_method("set_inventory_data"):
			chest.set_inventory_data(inventory_data)
		# Refresh the chest UI display
		chest_ui.refresh_display()

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
		# Hide build controls hint
		if build_controls_hint_ui and build_controls_hint_ui.has_method("hide_hint"):
			build_controls_hint_ui.hide_hint()
	if placement_mode.is_active:
		placement_mode.deactivate()

	# Activate appropriate mode based on equipped item
	if main_hand_item == "hammer":
		if camera and local_player:
			build_mode.activate(local_player, camera, world, build_menu_ui, build_status_label)
			print("[Client] Build mode activated")
			# Show build controls hint
			if build_controls_hint_ui and build_controls_hint_ui.has_method("show_hint"):
				build_controls_hint_ui.show_hint()
		else:
			print("[Client] Cannot activate build mode - camera or player missing")
	elif main_hand_item == "workbench":
		if camera and local_player:
			placement_mode.activate(local_player, camera, world, main_hand_item)
			print("[Client] Placement mode activated for %s" % main_hand_item)

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

	# Consume the item from inventory (client-side prediction)
	if local_player:
		var player_inventory = local_player.get_node_or_null("Inventory")
		if player_inventory:
			if not player_inventory.remove_item(item_name, 1):
				push_error("[Client] Failed to remove %s from inventory!" % item_name)
				return
			print("[Client] Consumed %s from inventory" % item_name)

	# Request server to place the buildable
	var pos_array = [position.x, position.y, position.z]
	NetworkManager.rpc_place_buildable.rpc_id(1, item_name, pos_array, rotation_y)

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

	# Send our preferred object render distance to the server
	_send_graphics_settings_to_server()

	# Mark loading step complete
	_mark_loading_step_complete("world_config")

## Send graphics settings to server so it uses our preferred render distances
func _send_graphics_settings_to_server() -> void:
	# Load settings from config
	var config = ConfigFile.new()
	var err = config.load("user://graphics_settings.cfg")
	if err != OK:
		# No saved settings, use default
		print("[Client] No graphics settings saved, using default object distance")
		return

	var objects_dist = config.get_value("graphics", "objects_distance", 4)
	print("[Client] Sending object distance preference to server: %d" % objects_dist)
	NetworkManager.rpc_set_object_distance.rpc_id(1, objects_dist)

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
		if world_map_ui.has_signal("pin_removed"):
			world_map_ui.pin_removed.connect(_on_pin_removed)
		if world_map_ui.has_signal("pin_renamed"):
			world_map_ui.pin_renamed.connect(_on_pin_renamed)
		print("[Client] World map initialized")

		# Add special markers for known locations (Shnarken huts, etc.)
		_add_known_location_markers()

	# Initialize mini-map (uses procedural biome calculation - no texture needed)
	if mini_map_ui and mini_map_ui.has_method("initialize"):
		mini_map_ui.initialize(generator, player)
		# Generate the initial map
		if mini_map_ui.has_method("generate_initial_map"):
			mini_map_ui.generate_initial_map()
		print("[Client] Mini-map initialized")

## Add special markers for known locations (Shnarken huts, dungeons, etc.)
func _add_known_location_markers() -> void:
	# Shnarken hut at world origin (meadow biome shop)
	var shnarken_pos := Vector2(0, 0)
	var shnarken_name := "Shnarken's Shop"
	var shnarken_color := Color(0.4, 0.8, 0.3)  # Frog green

	# Add to world map
	if world_map_ui and world_map_ui.has_method("add_special_marker"):
		world_map_ui.add_special_marker(shnarken_pos, shnarken_name, "shnarken", shnarken_color)

	# Add to mini-map
	if mini_map_ui and mini_map_ui.has_method("add_special_marker"):
		mini_map_ui.add_special_marker(shnarken_pos, shnarken_name, "shnarken", shnarken_color)

	print("[Client] Added known location markers to maps")

func _on_pin_placed(world_pos: Vector2, pin_name: String) -> void:
	"""Called when a pin is placed on the map"""
	print("[Client] Pin placed at %s: %s" % [world_pos, pin_name])

	# Create 3D marker in world
	_create_map_marker(world_pos, pin_name)

	# Sync pins to mini-map and server
	_sync_pins_to_mini_map_and_server()

func _on_pin_removed(world_pos: Vector2) -> void:
	"""Called when a pin is removed from the map"""
	print("[Client] Pin removed at %s" % world_pos)

	# Remove 3D marker from world
	_remove_map_marker(world_pos)

	# Sync pins to mini-map and server
	_sync_pins_to_mini_map_and_server()

func _on_pin_renamed(world_pos: Vector2, new_name: String) -> void:
	"""Called when a pin is renamed on the map"""
	print("[Client] Pin renamed at %s to: %s" % [world_pos, new_name])

	# Update 3D marker name
	var pos_key = "%d_%d" % [int(world_pos.x), int(world_pos.y)]
	if active_map_markers.has(pos_key):
		var marker = active_map_markers[pos_key]
		if is_instance_valid(marker) and marker.has_method("set_marker_name"):
			marker.set_marker_name(new_name)

	# Sync pins to mini-map and server
	_sync_pins_to_mini_map_and_server()

func _sync_pins_to_mini_map_and_server() -> void:
	"""Sync pins to mini-map and send to server for persistence"""
	if world_map_ui and mini_map_ui:
		var pins = world_map_ui.get_pins()
		mini_map_ui.set_pins(pins)

	# Send to server for persistence
	var pins_data = []
	if world_map_ui:
		pins_data = world_map_ui.get_pins()

	NetworkManager.rpc_update_map_pins.rpc_id(1, pins_data)

func _create_map_marker(world_pos: Vector2, marker_name: String, color: Color = Color.RED) -> void:
	"""Create a 3D map marker in the world"""
	var pos_key = "%d_%d" % [int(world_pos.x), int(world_pos.y)]

	# Don't create duplicate markers
	if active_map_markers.has(pos_key):
		return

	var indicator := Node3D.new()
	indicator.set_script(map_marker_script)
	world.add_child(indicator)
	indicator.initialize(world_pos, marker_name, color)

	active_map_markers[pos_key] = indicator
	print("[Client] Created 3D map marker at %s" % world_pos)

func _remove_map_marker(world_pos: Vector2) -> void:
	"""Remove a 3D map marker from the world"""
	var pos_key = "%d_%d" % [int(world_pos.x), int(world_pos.y)]

	if active_map_markers.has(pos_key):
		var marker = active_map_markers[pos_key]
		if is_instance_valid(marker):
			marker.queue_free()
		active_map_markers.erase(pos_key)
		print("[Client] Removed 3D map marker at %s" % world_pos)

func _sync_map_markers_from_pins() -> void:
	"""Sync 3D markers with map pins (for loading saved pins)"""
	if not world_map_ui:
		return

	var pins = world_map_ui.get_pins()
	for pin in pins:
		# get_pins() returns arrays for JSON serialization, convert to Vector2
		var pos_data = pin.get("pos", [0, 0])
		var pos: Vector2 = Vector2(pos_data[0], pos_data[1]) if pos_data is Array else pos_data
		_create_map_marker(pos, pin.get("name", "Pin"))

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

		# Also refresh chest UI if open (for player-to-player slot swaps)
		if chest_ui and chest_ui.is_ui_open():
			chest_ui.refresh_display()

## Receive character data including map pins and food buffs
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

		# Create 3D markers for loaded pins
		for pin in pins:
			if pin.has("pos") and pin.has("name"):
				# Pins from server use array format [x, y] for JSON
				var pos_data = pin.get("pos", [0, 0])
				var pos: Vector2 = Vector2(pos_data[0], pos_data[1]) if pos_data is Array else pos_data
				_create_map_marker(pos, pin.get("name", "Pin"))

	# Load active food buffs if they exist
	if character_data.has("active_foods"):
		var foods = character_data.get("active_foods", [])
		print("[Client] Character data has active_foods: %d items" % foods.size())

		if local_player:
			print("[Client] local_player exists")
			if local_player.has_node("PlayerFood"):
				var player_food = local_player.get_node("PlayerFood")
				print("[Client] Loading %d food buffs to PlayerFood" % foods.size())
				player_food.load_save_data(foods)
			else:
				print("[Client] ERROR: local_player has no PlayerFood node!")
		else:
			print("[Client] ERROR: local_player is null when receiving character data!")
	else:
		print("[Client] No active_foods in character data")

	# Load health if it exists
	if character_data.has("health") and local_player and "health" in local_player:
		local_player.health = character_data.get("health", 100.0)
		print("[Client] Loaded health: %.1f" % local_player.health)

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

## Receive gold sync from server (after buy/sell/upgrade)
func receive_gold_sync(gold_amount: int) -> void:
	print("[Client] Received gold sync: %d" % gold_amount)

	if local_player:
		local_player.gold = gold_amount

## Receive food buff sync from server (after eating or on spawn)
func receive_food_sync(food_data: Array) -> void:
	print("[Client] Received food sync (%d items)" % food_data.size())

	if local_player and local_player.has_node("PlayerFood"):
		var player_food = local_player.get_node("PlayerFood")
		player_food.load_save_data(food_data)
		print("[Client] Updated local player food buffs")

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

	# Create queue entry for this chunk if it doesn't exist
	if not environmental_spawn_queues.has(chunk_pos):
		environmental_spawn_queues[chunk_pos] = []

	# Queue each object for spawning (instead of spawning immediately)
	for obj_data in objects_data:
		var obj_type = obj_data.get("type", "unknown")

		# Validate type exists in our preloaded scenes
		if not environmental_scenes.has(obj_type):
			push_error("[Client] Unknown environmental object type: %s" % obj_type)
			continue

		# Add to this chunk's spawn queue
		environmental_spawn_queues[chunk_pos].append(obj_data)

## Process environmental spawn queue - spawns ENVIRONMENTAL_SPAWN_BATCH_SIZE objects per frame
## Prioritizes chunks closest to player (cheap O(n_chunks) operation)
func _process_environmental_queue() -> void:
	if environmental_spawn_queues.is_empty():
		return

	# Find closest chunk with queued objects (only ~10-20 chunks, very fast)
	var closest_chunk: Vector2i = Vector2i.ZERO
	var closest_dist_sq: float = INF
	var player_chunk: Vector2i = Vector2i.ZERO

	if local_player:
		var player_pos = local_player.global_position
		# Assume 32 unit chunk size (matches environmental_spawner.gd)
		player_chunk = Vector2i(int(player_pos.x / 32.0), int(player_pos.z / 32.0))

	for chunk_pos in environmental_spawn_queues.keys():
		var queue: Array = environmental_spawn_queues[chunk_pos]
		if queue.is_empty():
			continue
		# Calculate distance squared (cheaper than sqrt)
		var dx = chunk_pos.x - player_chunk.x
		var dy = chunk_pos.y - player_chunk.y
		var dist_sq = dx * dx + dy * dy
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			closest_chunk = chunk_pos

	# No chunks with objects to spawn
	if closest_dist_sq == INF:
		return

	# Spawn objects from the closest chunk
	var chunk_queue: Array = environmental_spawn_queues[closest_chunk]
	var spawned_count := 0

	while spawned_count < ENVIRONMENTAL_SPAWN_BATCH_SIZE and not chunk_queue.is_empty():
		var obj_data = chunk_queue.pop_front()

		# Skip if chunk was already despawned
		if not environmental_chunks.has(closest_chunk):
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
			obj.set_chunk_position(closest_chunk)

		# Store in chunk
		environmental_chunks[closest_chunk][obj_id] = obj
		spawned_count += 1

	# Clean up empty chunk queues
	if chunk_queue.is_empty():
		environmental_spawn_queues.erase(closest_chunk)

## Despawn environmental objects for a chunk
func despawn_environmental_objects(chunk_pos: Vector2i) -> void:
	# Clear any queued objects for this chunk
	if environmental_spawn_queues.has(chunk_pos):
		environmental_spawn_queues.erase(chunk_pos)

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
				0.0,
				randf_range(-0.5, 0.5)
			)

			# Get XZ position with offset
			var spawn_xz = Vector2(position.x + offset.x, position.z + offset.z)

			# Query actual terrain height to ensure item appears above ground
			var terrain_height = position.y - 1.0  # Fallback
			if terrain_world and terrain_world.has_method("get_terrain_height_at"):
				terrain_height = terrain_world.get_terrain_height_at(spawn_xz)

			# Spawn slightly above terrain surface so item is visible
			var spawn_pos = Vector3(spawn_xz.x, terrain_height + 0.5, spawn_xz.y)

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
	print("[Client] remove_resource_item called with net_id: %s" % net_id)
	# Find item by network_id in the world
	var item_name = "Item_%s" % net_id
	var item = world.get_node_or_null(item_name)

	if item and is_instance_valid(item):
		print("[Client] Removing picked up item: %s" % item_name)
		item.queue_free()
	else:
		print("[Client] WARNING: Could not find item %s to remove (world children: %d)" % [item_name, world.get_child_count()])

## Spawn a fallen log at the given position (from a chopped truffula tree)
func spawn_fallen_log(position: Vector3, rotation_y: float, network_id: String) -> void:
	print("[Client] Spawning fallen log at %s (ID: %s)" % [position, network_id])

	var fallen_log_scene = preload("res://shared/environmental/fallen_log.tscn")
	var log_instance = fallen_log_scene.instantiate()
	log_instance.name = "FallenLog_%s" % network_id

	# Set fall direction from the rotation angle (before adding to tree)
	# This tells the log which way to tip over
	var fall_dir := Vector3(sin(rotation_y), 0, cos(rotation_y))
	if log_instance.has_method("set_fall_direction"):
		log_instance.set_fall_direction(fall_dir)

	# IMPORTANT: Set position BEFORE adding to tree so _ready() has correct position
	log_instance.position = position

	# Add to world - log will start vertical and animate falling
	world.add_child(log_instance)

	print("[Client] Fallen log spawned at %s" % log_instance.global_position)

## Spawn split logs at multiple positions (from a chopped fallen log)
func spawn_split_logs(positions: Array, network_ids: Array, fall_angle: float = 0.0) -> void:
	print("[Client] Spawning %d split logs (fall angle: %.2f)" % [positions.size(), fall_angle])

	var split_log_scene = preload("res://shared/environmental/split_log.tscn")

	for i in positions.size():
		var pos_data = positions[i]
		var pos = Vector3(pos_data[0], pos_data[1], pos_data[2])
		var net_id = network_ids[i] if i < network_ids.size() else "split_%d" % i

		var log_instance = split_log_scene.instantiate()
		log_instance.name = "SplitLog_%s" % net_id

		world.add_child(log_instance)
		log_instance.global_position = pos

		# Rotate split log to match fallen log orientation
		# Cylinder starts vertical (Y-up), tip it forward (-X rotation) then rotate to face fall direction (Y)
		# -PI/2 on X tips cylinder to point along +Z, then Y rotation aims it in fall_angle direction
		log_instance.rotation = Vector3(-PI / 2, fall_angle, 0)

	print("[Client] Split logs spawned successfully")

## Destroy a dynamic object (fallen log, split log, etc.)
func destroy_dynamic_object(object_name: String) -> void:
	print("[Client] Destroying dynamic object: %s" % object_name)

	var target = world.get_node_or_null(object_name)
	if target and is_instance_valid(target):
		target.queue_free()
		print("[Client] Dynamic object %s destroyed" % object_name)
	else:
		print("[Client] WARNING: Dynamic object %s not found" % object_name)

## Handle damage to a dynamic object (from server)
func on_dynamic_object_damaged(object_name: String, damage: float, current_health: float, max_health: float) -> void:
	var target = world.get_node_or_null(object_name)
	if target and is_instance_valid(target):
		# Update health and play effects via the object's method
		if target.has_method("apply_server_damage"):
			target.apply_server_damage(damage, current_health, max_health)
		else:
			# Fallback: directly update health bar if it exists
			if "current_health" in target:
				target.current_health = current_health
			if "health_bar" in target and target.health_bar:
				target.health_bar.update_health(current_health, max_health)

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
	environmental_spawn_queues.clear()

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
		"Sporeling":
			enemy_scene = sporeling_scene
		"Cyclops":
			enemy_scene = cyclops_scene
		"Deer":
			enemy_scene = deer_scene
		"Pig", "Flying Pig":
			enemy_scene = pig_scene
		"Sheep", "Unicorn Sheep":
			enemy_scene = sheep_scene
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
## damage_type: WeaponData.DamageType enum (-1 = unspecified)
func apply_enemy_damage(enemy_network_id: int, damage: float, knockback: float, direction: Vector3, damage_type: int = -1) -> void:
	print("[Client] apply_enemy_damage: net_id=%d, damage=%.1f, type=%d" % [enemy_network_id, damage, damage_type])

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

	# Apply damage to the enemy (with damage type for resistance calculations)
	if enemy.has_method("take_damage"):
		print("[Client] Applying %.1f damage (type=%d) to hosted enemy %d" % [damage, damage_type, enemy_network_id])
		enemy.take_damage(damage, knockback, direction, damage_type)
	else:
		print("[Client] ERROR: Enemy %d has no take_damage method!" % enemy_network_id)

## Update enemy host when server reassigns (e.g., original host disconnected)
func update_enemy_host(enemy_network_id: int, new_host_peer_id: int) -> void:
	print("[Client] Updating enemy %d host to peer %d" % [enemy_network_id, new_host_peer_id])

	# Find enemy by network_id
	var enemy: Node = null
	for key in spawned_enemies.keys():
		var e = spawned_enemies[key]
		if e and is_instance_valid(e) and "network_id" in e and e.network_id == enemy_network_id:
			enemy = e
			break

	if not enemy:
		print("[Client] Enemy with network_id %d not found for host update" % enemy_network_id)
		return

	# Update the host peer ID
	if "host_peer_id" in enemy:
		enemy.host_peer_id = new_host_peer_id

	# Update is_host flag based on whether we are the new host
	var my_peer_id = multiplayer.get_unique_id()
	if "is_host" in enemy:
		var was_host = enemy.is_host
		enemy.is_host = (new_host_peer_id == my_peer_id)
		if enemy.is_host and not was_host:
			print("[Client] We are now the host for enemy %d!" % enemy_network_id)

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
	"""Create a 3D ping indicator in the world and screen-space direction indicator"""
	# Create 3D world indicator (light beam)
	var indicator = Node3D.new()
	indicator.set_script(ping_indicator_script)
	world.add_child(indicator)

	# Initialize after adding to tree
	if indicator.has_method("initialize"):
		indicator.initialize(world_pos, from_peer)

	active_ping_indicators.append(indicator)

	# Create screen-space direction indicator
	var camera = _get_camera()
	if camera and local_player:
		var screen_indicator = Control.new()
		screen_indicator.set_script(ping_screen_indicator_script)
		canvas_layer.add_child(screen_indicator)

		if screen_indicator.has_method("initialize"):
			screen_indicator.initialize(world_pos, from_peer, camera, local_player)

		active_ping_screen_indicators.append(screen_indicator)

	# Clean up expired 3D indicators
	for i in range(active_ping_indicators.size() - 1, -1, -1):
		var ping = active_ping_indicators[i]
		if not is_instance_valid(ping):
			active_ping_indicators.remove_at(i)

	# Clean up expired screen indicators
	for i in range(active_ping_screen_indicators.size() - 1, -1, -1):
		var ping = active_ping_screen_indicators[i]
		if not is_instance_valid(ping):
			active_ping_screen_indicators.remove_at(i)

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

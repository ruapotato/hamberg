extends Control

signal resume_pressed
signal save_pressed
signal quit_pressed

# Main menu
@onready var main_panel: PanelContainer = $Panel
@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var graphics_button: Button = $Panel/VBox/GraphicsButton
@onready var quit_button: Button = $Panel/VBox/QuitButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

# Graphics panel
@onready var graphics_panel: PanelContainer = $GraphicsPanel
@onready var terrain_label: Label = $GraphicsPanel/VBox/TerrainLabel
@onready var terrain_slider: HSlider = $GraphicsPanel/VBox/TerrainSlider
@onready var objects_label: Label = $GraphicsPanel/VBox/ObjectsLabel
@onready var objects_slider: HSlider = $GraphicsPanel/VBox/ObjectsSlider
@onready var fog_check: CheckButton = $GraphicsPanel/VBox/FogCheck
@onready var back_button: Button = $GraphicsPanel/VBox/BackButton

# Chunk size for calculating fog distance
const CHUNK_SIZE: float = 32.0

var selected_index: int = 0  # For controller D-pad navigation
var buttons: Array[Button] = []
var in_graphics_menu: bool = false

# Settings file path
const SETTINGS_PATH = "user://graphics_settings.cfg"

func _ready() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	save_button.pressed.connect(_on_save_pressed)
	graphics_button.pressed.connect(_on_graphics_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Slider signals
	terrain_slider.value_changed.connect(_on_terrain_slider_changed)
	objects_slider.value_changed.connect(_on_objects_slider_changed)
	fog_check.toggled.connect(_on_fog_toggled)

	# Build button array for D-pad navigation
	buttons = [resume_button, save_button, graphics_button, quit_button]

	# Load saved settings
	_load_settings()

func _process(_delta: float) -> void:
	if not visible:
		return

	# Close menu with B button (jump)
	if Input.is_action_just_pressed("jump"):
		if in_graphics_menu:
			_on_back_pressed()
		else:
			hide_menu()
		return

	# D-pad navigation
	if Input.is_action_just_pressed("hotbar_unequip"):  # D-pad Down
		_move_selection(1)
	elif Input.is_action_just_pressed("hotbar_equip"):  # D-pad Up
		_move_selection(-1)

	# A button to activate selected option
	if Input.is_action_just_pressed("interact"):
		_activate_selected()

func _on_resume_pressed() -> void:
	hide_menu()
	resume_pressed.emit()

func _on_save_pressed() -> void:
	status_label.text = "Game saved!"
	status_label.modulate = Color.GREEN
	save_pressed.emit()

	# Clear status after 2 seconds
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(status_label):
		status_label.text = ""

func _on_graphics_pressed() -> void:
	main_panel.visible = false
	graphics_panel.visible = true
	in_graphics_menu = true
	buttons = [back_button]
	selected_index = 0
	_update_selection_visual()

	# Load current values from terrain world
	_load_current_values()

func _on_back_pressed() -> void:
	graphics_panel.visible = false
	main_panel.visible = true
	in_graphics_menu = false
	buttons = [resume_button, save_button, graphics_button, quit_button]
	selected_index = 0
	_update_selection_visual()

	# Save settings when leaving graphics menu
	_save_settings()

func _on_quit_pressed() -> void:
	quit_pressed.emit()

func _on_terrain_slider_changed(value: float) -> void:
	terrain_label.text = "Terrain Distance: %d" % int(value)
	_apply_terrain_distance(int(value))

func _on_objects_slider_changed(value: float) -> void:
	objects_label.text = "Object Distance: %d" % int(value)
	_apply_objects_distance(int(value))
	# Update fog distance to match object distance
	if fog_check.button_pressed:
		_apply_fog_distance(int(value))

func _on_fog_toggled(enabled: bool) -> void:
	_apply_fog_enabled(enabled)
	if enabled:
		_apply_fog_distance(int(objects_slider.value))

func _load_current_values() -> void:
	var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
	if terrain_worlds.size() > 0:
		var terrain_world = terrain_worlds[0]
		terrain_slider.value = terrain_world.view_distance
		terrain_label.text = "Terrain Distance: %d" % terrain_world.view_distance

		if terrain_world.chunk_manager:
			objects_slider.value = terrain_world.chunk_manager.load_radius
			objects_label.text = "Object Distance: %d" % terrain_world.chunk_manager.load_radius

func _apply_terrain_distance(value: int) -> void:
	# Apply to all terrain worlds (client and server if hosting)
	var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
	for terrain_world in terrain_worlds:
		terrain_world.view_distance = value
	print("[PauseMenu] Terrain distance set to: %d" % value)

func _apply_objects_distance(value: int) -> void:
	# Apply to all terrain worlds (client and server if hosting)
	var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
	for terrain_world in terrain_worlds:
		if terrain_world.chunk_manager:
			terrain_world.chunk_manager.load_radius = value
	print("[PauseMenu] Object distance set to: %d" % value)

	# Send to server so it uses our preferred render distance
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		NetworkManager.rpc_set_object_distance.rpc_id(1, value)

func _apply_fog_enabled(enabled: bool) -> void:
	var fog_manager = _get_fog_wall_manager()
	if fog_manager:
		fog_manager.set_fog_enabled(enabled)
		print("[PauseMenu] Fog walls enabled: %s" % enabled)

func _apply_fog_distance(object_distance: int) -> void:
	var fog_manager = _get_fog_wall_manager()
	if fog_manager:
		fog_manager.set_render_distance(object_distance)
		print("[PauseMenu] Fog walls at object distance: %d chunks" % object_distance)

func _get_fog_wall_manager():
	var client_node := get_node_or_null("/root/Main/Client")
	if client_node and client_node.fog_wall_manager:
		return client_node.fog_wall_manager
	return null

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("graphics", "terrain_distance", int(terrain_slider.value))
	config.set_value("graphics", "objects_distance", int(objects_slider.value))
	config.set_value("graphics", "fog_enabled", fog_check.button_pressed)
	var err = config.save(SETTINGS_PATH)
	if err == OK:
		print("[PauseMenu] Graphics settings saved")
	else:
		push_warning("[PauseMenu] Failed to save graphics settings: %s" % err)

func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err != OK:
		print("[PauseMenu] No saved graphics settings, using defaults")
		# Apply default fog on first run
		call_deferred("_apply_loaded_settings", 12, 4, true)
		return

	var terrain_dist = config.get_value("graphics", "terrain_distance", 12)
	var objects_dist = config.get_value("graphics", "objects_distance", 4)
	var fog_enabled = config.get_value("graphics", "fog_enabled", true)

	terrain_slider.value = terrain_dist
	objects_slider.value = objects_dist
	fog_check.button_pressed = fog_enabled

	# Apply settings on load (after terrain world is ready)
	call_deferred("_apply_loaded_settings", terrain_dist, objects_dist, fog_enabled)

func _apply_loaded_settings(terrain_dist: int, objects_dist: int, fog_enabled: bool = true) -> void:
	# Wait a bit for terrain world to initialize
	await get_tree().create_timer(1.0).timeout
	_apply_terrain_distance(terrain_dist)
	_apply_objects_distance(objects_dist)
	_apply_fog_enabled(fog_enabled)
	if fog_enabled:
		_apply_fog_distance(objects_dist)
	print("[PauseMenu] Applied saved graphics settings: terrain=%d, objects=%d, fog=%s" % [terrain_dist, objects_dist, fog_enabled])

func show_menu() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	selected_index = 0
	in_graphics_menu = false
	main_panel.visible = true
	graphics_panel.visible = false
	buttons = [resume_button, save_button, graphics_button, quit_button]
	_update_selection_visual()

func hide_menu() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Move selection up/down (controller D-pad)
func _move_selection(direction: int) -> void:
	if buttons.is_empty():
		return

	selected_index += direction

	# Wrap around
	if selected_index < 0:
		selected_index = buttons.size() - 1
	elif selected_index >= buttons.size():
		selected_index = 0

	_update_selection_visual()

## Update visual highlight for selected button
func _update_selection_visual() -> void:
	for i in buttons.size():
		if i == selected_index:
			buttons[i].modulate = Color(1.5, 1.5, 1.0)  # Highlight selected
			buttons[i].grab_focus()
		else:
			buttons[i].modulate = Color.WHITE  # Normal

## Activate the currently selected button (controller A button)
func _activate_selected() -> void:
	if selected_index >= 0 and selected_index < buttons.size():
		buttons[selected_index].pressed.emit()

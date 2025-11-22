extends Control

## WorldMap - Full-screen map overlay (press M to toggle)
## Features: pan, zoom, pins, pings, player markers

const WorldMapGenerator = preload("res://client/ui/world_map_generator.gd")
const BiomeGenerator = preload("res://shared/biome_generator.gd")

signal pin_placed(world_pos: Vector2, pin_name: String)
signal ping_sent(world_pos: Vector2)

# Map state
var map_generator = null  # WorldMapGenerator
var current_zoom_level: float = 1.0  # 1.0 = zoomed in, higher = zoomed out
var current_center: Vector2 = Vector2.ZERO  # World position at center of map
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_start_center: Vector2 = Vector2.ZERO
var is_toggling: bool = false  # Prevent rapid toggling
var current_map_texture: ImageTexture = null  # Currently visible map area (generated on demand)
var world_texture_size: int = 128  # Size of map texture (reduced for performance)
var world_map_radius: float = 5000.0  # Max view distance

# Map display settings
const MIN_ZOOM := 0.5       # Max zoom in (500 units visible)
const MAX_ZOOM := 50.0      # Max zoom out (50000 units visible = entire world)
const BASE_WORLD_SIZE := 1000.0  # World units visible at zoom level 1.0
const MAX_TEXTURE_SIZE := 512  # Maximum texture resolution for performance

# References
var local_player: Node3D = null
var remote_players: Dictionary = {}
var biome_generator: BiomeGenerator = null

# Map pins (persistent per character)
var map_pins: Array = []  # Array of {pos: Vector2, name: String}

# Active pings (ephemeral, 15 seconds)
var active_pings: Array = []  # Array of {pos: Vector2, time_left: float, from_peer: int}

# UI nodes
@onready var map_texture_rect: TextureRect = $Panel/MapContainer/MapTextureRect
@onready var zoom_label: Label = $Panel/TopBar/ZoomLabel
@onready var position_label: Label = $Panel/TopBar/PositionLabel
@onready var close_button: Button = $Panel/TopBar/CloseButton

func _ready() -> void:
	print("[WorldMap] _ready() called - initializing...")
	visible = false
	print("[WorldMap] Set initial visible to false")

	close_button.pressed.connect(_on_close_pressed)
	print("[WorldMap] Connected close button")

	# Setup map texture rect for mouse events
	map_texture_rect.gui_input.connect(_on_map_input)
	print("[WorldMap] Connected map_texture_rect.gui_input to _on_map_input")

	# Make sure this control captures input when visible
	set_process_input(true)
	set_process_unhandled_input(true)
	print("[WorldMap] Called set_process_input(true) and set_process_unhandled_input(true)")

	print("[WorldMap] Full-screen map initialized - READY")

func _input(event: InputEvent) -> void:
	if not visible or is_toggling:
		return

	# Handle ESC or M to close map with higher priority
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_M:
				visible = false
				is_toggling = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()

func initialize(generator: BiomeGenerator, player: Node3D) -> void:
	biome_generator = generator
	local_player = player
	map_generator = WorldMapGenerator.new(generator)

	# Center map on player
	if local_player:
		var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)
		current_center = player_xz

	print("[WorldMap] Initialized with BiomeGenerator and player")

func _process(delta: float) -> void:
	if not visible or is_toggling:
		return

	# Handle ESC or M to close map
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("toggle_map"):
		visible = false
		is_toggling = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Update active pings (count down timers)
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i].time_left -= delta
		if active_pings[i].time_left <= 0:
			active_pings.remove_at(i)

	# Update UI labels
	_update_ui_labels()

	# Queue redraw for custom rendering (player markers, pins, pings)
	queue_redraw()

func _draw() -> void:
	if not visible:
		return

	# Draw player markers, pins, and pings on top of the map texture
	_draw_pins()
	_draw_pings()
	_draw_player_markers()

func toggle_map() -> void:
	if is_toggling:
		return

	is_toggling = true
	visible = !visible

	if visible:
		# Release mouse from 3D camera
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		# Re-center on player when opening
		if local_player:
			var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)
			current_center = player_xz

		# Wait for UI layout to complete before generating texture
		await get_tree().process_frame
		await get_tree().process_frame

		# Check if still visible (user might have closed it already)
		if not visible:
			is_toggling = false
			return

		# Generate map for current view area
		print("[WorldMap] Generating visible map area...")
		_generate_current_view()
		print("[WorldMap] Map generated")

		is_toggling = false
	else:
		# Restore mouse capture for 3D camera
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		is_toggling = false

func _generate_current_view() -> void:
	"""Generate map texture for the currently visible area only"""
	if not map_generator:
		return

	# Calculate visible world size based on zoom
	var visible_world_size := BASE_WORLD_SIZE * current_zoom_level

	# Generate texture for just this visible area
	current_map_texture = map_generator.generate_map_texture(current_center, visible_world_size, world_texture_size)

	# Set it directly to the TextureRect
	map_texture_rect.texture = current_map_texture

func refresh_map() -> void:
	# When panning/zooming, regenerate the visible area
	_generate_current_view()

func _on_close_pressed() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_map_input(event: InputEvent) -> void:
	# Handle mouse wheel zoom
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_in()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_out()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Start dragging
				is_dragging = true
				drag_start_pos = mb.position
				drag_start_center = current_center
			else:
				# End dragging
				is_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# Place pin
			_place_pin_at_mouse(mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			# Send ping
			_send_ping_at_mouse(mb.position)

	# Handle mouse motion for dragging
	if event is InputEventMouseMotion and is_dragging:
		var motion := event as InputEventMouseMotion
		var delta_pixels := motion.position - drag_start_pos

		# Convert pixel delta to world delta
		var world_size := BASE_WORLD_SIZE * current_zoom_level
		var map_size := map_texture_rect.size.x
		var pixels_to_world := world_size / map_size

		var world_delta := delta_pixels * pixels_to_world

		# Update center (inverted because dragging map moves world in opposite direction)
		current_center = drag_start_center - world_delta

		# Refresh map (instant now with cached texture)
		refresh_map()

func _zoom_in() -> void:
	current_zoom_level = clamp(current_zoom_level * 0.8, MIN_ZOOM, MAX_ZOOM)
	refresh_map()

func _zoom_out() -> void:
	current_zoom_level = clamp(current_zoom_level * 1.25, MIN_ZOOM, MAX_ZOOM)
	refresh_map()

func _place_pin_at_mouse(mouse_pos: Vector2) -> void:
	var world_pos := _mouse_to_world_pos(mouse_pos)
	print("[WorldMap] Placing pin at world position: %s" % world_pos)

	# Add pin (TODO: prompt for name)
	var pin_name := "Pin %d" % (map_pins.size() + 1)
	map_pins.append({"pos": world_pos, "name": pin_name})

	pin_placed.emit(world_pos, pin_name)
	queue_redraw()

func _send_ping_at_mouse(mouse_pos: Vector2) -> void:
	var world_pos := _mouse_to_world_pos(mouse_pos)
	print("[WorldMap] Sending ping at world position: %s" % world_pos)

	# Add local ping
	add_ping(world_pos, multiplayer.get_unique_id())

	# Emit signal to send to network
	ping_sent.emit(world_pos)

func _mouse_to_world_pos(mouse_pos: Vector2) -> Vector2:
	# Convert mouse position on map to world position
	var map_size := map_texture_rect.size
	var visible_world_size := BASE_WORLD_SIZE * current_zoom_level

	# Normalize mouse position (0-1) relative to the visible map area
	var norm_x := mouse_pos.x / map_size.x
	var norm_y := mouse_pos.y / map_size.y

	# Convert to world coordinates based on current view
	var world_x := current_center.x + (norm_x - 0.5) * visible_world_size
	var world_z := current_center.y + (norm_y - 0.5) * visible_world_size

	return Vector2(world_x, world_z)

func _world_to_screen_pos(world_pos: Vector2) -> Vector2:
	# Convert world position to screen position on map
	var map_size := map_texture_rect.size
	var visible_world_size := BASE_WORLD_SIZE * current_zoom_level

	# Offset from center of current view
	var offset := world_pos - current_center

	# Normalize to -0.5 to 0.5 relative to visible area
	var norm_x := offset.x / visible_world_size
	var norm_y := offset.y / visible_world_size

	# Convert to screen coordinates
	var screen_x := (norm_x + 0.5) * map_size.x
	var screen_y := (norm_y + 0.5) * map_size.y

	return Vector2(screen_x, screen_y) + map_texture_rect.global_position

func _draw_player_markers() -> void:
	if not local_player:
		return

	# Draw local player
	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)
	var screen_pos := _world_to_screen_pos(player_xz)

	# Check if on screen
	if _is_on_screen(screen_pos):
		# Draw player marker with direction indicator
		draw_circle(screen_pos, 8, Color.GREEN)
		draw_circle(screen_pos, 8, Color.WHITE, false, 2.0)

		# Draw crosshair to show exact position
		var cross_size := 15.0
		draw_line(screen_pos + Vector2(-cross_size, 0), screen_pos + Vector2(cross_size, 0), Color.WHITE, 1.0)
		draw_line(screen_pos + Vector2(0, -cross_size), screen_pos + Vector2(0, cross_size), Color.WHITE, 1.0)

	# Draw remote players
	for peer_id in remote_players:
		var player = remote_players[peer_id]
		if player and is_instance_valid(player):
			var remote_xz := Vector2(player.global_position.x, player.global_position.z)
			var remote_screen := _world_to_screen_pos(remote_xz)

			if _is_on_screen(remote_screen):
				draw_circle(remote_screen, 6, Color.BLUE)
				draw_circle(remote_screen, 6, Color.WHITE, false, 2.0)

func _draw_pins() -> void:
	for pin in map_pins:
		var screen_pos := _world_to_screen_pos(pin.pos)

		if _is_on_screen(screen_pos):
			# Draw pin marker (red flag icon)
			draw_circle(screen_pos, 5, Color.RED)
			draw_line(screen_pos, screen_pos + Vector2(0, -15), Color.RED, 2.0)

func _draw_pings() -> void:
	for ping in active_pings:
		var screen_pos := _world_to_screen_pos(ping.pos)

		if _is_on_screen(screen_pos):
			# Draw pulsing circle (opacity based on time left)
			var alpha: float = ping.time_left / 15.0
			var radius: float = lerp(20.0, 5.0, alpha)
			var color: Color = Color.YELLOW
			color.a = alpha

			draw_circle(screen_pos, radius, color, false, 3.0)

func _is_on_screen(screen_pos: Vector2) -> bool:
	var rect_pos := map_texture_rect.global_position
	var rect_size := map_texture_rect.size

	return screen_pos.x >= rect_pos.x and screen_pos.x <= rect_pos.x + rect_size.x and \
		   screen_pos.y >= rect_pos.y and screen_pos.y <= rect_pos.y + rect_size.y

func _update_ui_labels() -> void:
	# Update zoom label
	var world_size := BASE_WORLD_SIZE * current_zoom_level
	zoom_label.text = "Zoom: %.0fm (%.2fx)" % [world_size, current_zoom_level]

	# Update position label with player position if available
	if local_player:
		var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)
		position_label.text = "Player: (%.1f, %.1f) | Center: (%.1f, %.1f)" % [player_xz.x, player_xz.y, current_center.x, current_center.y]
	else:
		position_label.text = "Center: %.0f, %.0f" % [current_center.x, current_center.y]

func add_ping(world_pos: Vector2, from_peer: int) -> void:
	"""Add a ping to the map (called from network or locally)"""
	active_pings.append({
		"pos": world_pos,
		"time_left": 15.0,
		"from_peer": from_peer
	})
	print("[WorldMap] Ping added at %s from peer %d" % [world_pos, from_peer])

func set_remote_players(players: Dictionary) -> void:
	"""Update remote players dictionary"""
	remote_players = players

func load_pins(pins: Array) -> void:
	"""Load pins from save data"""
	map_pins = pins
	print("[WorldMap] Loaded %d pins from save data" % pins.size())

func get_pins() -> Array:
	"""Get current pins for saving"""
	return map_pins

extends Control

## WorldMap - Full-screen map overlay (press M to toggle)
## Features: pan, zoom, pins, pings, player markers

const WorldMapGenerator = preload("res://client/ui/world_map_generator.gd")

signal pin_placed(world_pos: Vector2, pin_name: String)
signal pin_removed(world_pos: Vector2)
signal pin_renamed(world_pos: Vector2, new_name: String)
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
var world_texture_size: int = 64  # Size of map texture (reduced for performance)
var world_map_radius: float = 5000.0  # Max view distance

# Map display settings
const MIN_ZOOM := 0.5       # Max zoom in (500 units visible)
const MAX_ZOOM := 50.0      # Max zoom out (50000 units visible = entire world)
const BASE_WORLD_SIZE := 1000.0  # World units visible at zoom level 1.0
const MAX_TEXTURE_SIZE := 128  # Maximum texture resolution for performance

# Debounce for map regeneration (prevents lag on rapid zoom/pan)
var regenerate_timer: float = 0.0
const REGENERATE_DELAY: float = 0.15  # Wait 150ms after last input before regenerating
var needs_regenerate: bool = false
var last_generated_center: Vector2 = Vector2.ZERO
var last_generated_zoom: float = 1.0

# References
var local_player: Node3D = null
var remote_players: Dictionary = {}
var biome_generator = null  # BiomeGenerator or TerrainBiomeGenerator instance

# Map pins (persistent per character)
var map_pins: Array = []  # Array of {pos: Vector2, name: String}

# Active pings (ephemeral, 15 seconds)
var active_pings: Array = []  # Array of {pos: Vector2, time_left: float, from_peer: int}

# Pin editing state
var selected_pin_index: int = -1
var is_renaming_pin: bool = false
var rename_line_edit: LineEdit = null
var rename_popup: Panel = null

# UI nodes
@onready var map_texture_rect: TextureRect = $Panel/MapContainer/MapTextureRect
@onready var overlay: Control = $Panel/MapContainer/MapTextureRect/Overlay
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

	# Create rename popup
	_create_rename_popup()

	# Connect overlay draw
	if overlay:
		overlay.draw.connect(_draw_overlay)

	print("[WorldMap] Full-screen map initialized - READY")

func _create_rename_popup() -> void:
	rename_popup = Panel.new()
	rename_popup.visible = false
	rename_popup.custom_minimum_size = Vector2(200, 80)
	rename_popup.z_index = 100

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	rename_popup.add_child(vbox)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(margin)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(inner_vbox)

	var label := Label.new()
	label.text = "Rename Pin:"
	inner_vbox.add_child(label)

	rename_line_edit = LineEdit.new()
	rename_line_edit.placeholder_text = "Enter pin name..."
	rename_line_edit.text_submitted.connect(_on_rename_submitted)
	inner_vbox.add_child(rename_line_edit)

	var button_hbox := HBoxContainer.new()
	button_hbox.add_theme_constant_override("separation", 8)
	inner_vbox.add_child(button_hbox)

	var confirm_btn := Button.new()
	confirm_btn.text = "Rename"
	confirm_btn.pressed.connect(_on_rename_confirmed)
	button_hbox.add_child(confirm_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.pressed.connect(_on_pin_delete_pressed)
	button_hbox.add_child(delete_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_rename_cancelled)
	button_hbox.add_child(cancel_btn)

	add_child(rename_popup)

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

func initialize(generator, player: Node3D) -> void:
	biome_generator = generator
	local_player = player
	map_generator = WorldMapGenerator.new(generator)

	# Center map on player
	if local_player:
		var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)
		current_center = player_xz

	print("[WorldMap] Initialized with BiomeGenerator and player")

func _process(delta: float) -> void:
	# Always update ping timers even when map is closed
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i].time_left -= delta
		if active_pings[i].time_left <= 0:
			active_pings.remove_at(i)

	if not visible or is_toggling:
		return

	# Handle ESC or M to close map
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("toggle_map"):
		visible = false
		is_toggling = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Handle debounced map regeneration
	if needs_regenerate:
		regenerate_timer -= delta
		if regenerate_timer <= 0:
			needs_regenerate = false
			_generate_current_view()

	# Update UI labels
	_update_ui_labels()

	# Queue redraw for custom rendering (player markers, pins, pings)
	if overlay:
		overlay.queue_redraw()

func _draw_overlay() -> void:
	if not visible or not overlay:
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
	# When panning/zooming, schedule a debounced regeneration
	# This prevents lag from regenerating on every frame during drag/zoom
	needs_regenerate = true
	regenerate_timer = REGENERATE_DELAY

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
			# Check if clicking on existing pin first
			var clicked_pin_index := _get_pin_at_mouse(mb.position)
			if clicked_pin_index >= 0:
				# Open rename/delete popup for this pin
				_show_pin_popup(clicked_pin_index, mb.global_position)
			else:
				# Place new pin
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

func _get_pin_at_mouse(mouse_pos: Vector2) -> int:
	"""Check if mouse is over an existing pin, return index or -1"""
	var click_radius := 15.0  # Pixels radius to detect pin click

	for i in range(map_pins.size()):
		var pin = map_pins[i]
		var screen_pos := _world_to_screen_pos(pin.pos)
		# Convert to local coords relative to map_texture_rect
		var local_click := mouse_pos + map_texture_rect.global_position
		var distance := screen_pos.distance_to(local_click)
		if distance < click_radius:
			return i

	return -1

func _show_pin_popup(pin_index: int, global_pos: Vector2) -> void:
	"""Show rename/delete popup for a pin"""
	selected_pin_index = pin_index
	is_renaming_pin = true

	# Set current name in the line edit
	if pin_index >= 0 and pin_index < map_pins.size():
		rename_line_edit.text = map_pins[pin_index].name

	# Position popup near click
	rename_popup.global_position = global_pos + Vector2(10, 10)
	rename_popup.visible = true
	rename_line_edit.grab_focus()
	rename_line_edit.select_all()

func _on_rename_submitted(new_text: String) -> void:
	_on_rename_confirmed()

func _on_rename_confirmed() -> void:
	if selected_pin_index >= 0 and selected_pin_index < map_pins.size():
		var new_name := rename_line_edit.text.strip_edges()
		if new_name.is_empty():
			new_name = "Pin %d" % (selected_pin_index + 1)

		var old_pin = map_pins[selected_pin_index]
		old_pin.name = new_name
		print("[WorldMap] Renamed pin to: %s" % new_name)
		pin_renamed.emit(old_pin.pos, new_name)

	_hide_rename_popup()
	if overlay:
		overlay.queue_redraw()

func _on_pin_delete_pressed() -> void:
	if selected_pin_index >= 0 and selected_pin_index < map_pins.size():
		var pin = map_pins[selected_pin_index]
		print("[WorldMap] Deleting pin: %s" % pin.name)
		pin_removed.emit(pin.pos)
		map_pins.remove_at(selected_pin_index)

	_hide_rename_popup()
	if overlay:
		overlay.queue_redraw()

func _on_rename_cancelled() -> void:
	_hide_rename_popup()

func _hide_rename_popup() -> void:
	rename_popup.visible = false
	is_renaming_pin = false
	selected_pin_index = -1

func _place_pin_at_mouse(mouse_pos: Vector2) -> void:
	var world_pos := _mouse_to_world_pos(mouse_pos)
	print("[WorldMap] Placing pin at world position: %s" % world_pos)

	# Add pin with default name
	var pin_name := "Pin %d" % (map_pins.size() + 1)
	map_pins.append({"pos": world_pos, "name": pin_name})

	pin_placed.emit(world_pos, pin_name)

	# Show rename popup immediately so user can name it
	_show_pin_popup(map_pins.size() - 1, get_global_mouse_position())
	if overlay:
		overlay.queue_redraw()

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
	# Convert world position to screen position on map (global coords)
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

func _world_to_overlay_pos(world_pos: Vector2) -> Vector2:
	# Convert world position to overlay local coords (for drawing)
	var map_size := overlay.size
	var visible_world_size := BASE_WORLD_SIZE * current_zoom_level

	# Offset from center of current view
	var offset := world_pos - current_center

	# Normalize to -0.5 to 0.5 relative to visible area
	var norm_x := offset.x / visible_world_size
	var norm_y := offset.y / visible_world_size

	# Convert to overlay local coordinates
	var local_x := (norm_x + 0.5) * map_size.x
	var local_y := (norm_y + 0.5) * map_size.y

	return Vector2(local_x, local_y)

func _is_pos_visible(local_pos: Vector2) -> bool:
	# Check if position is within overlay bounds
	return local_pos.x >= 0 and local_pos.x <= overlay.size.x and \
		   local_pos.y >= 0 and local_pos.y <= overlay.size.y

func _draw_player_markers() -> void:
	if not local_player or not overlay:
		return

	# Draw local player
	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)
	var local_pos := _world_to_overlay_pos(player_xz)

	# Check if on screen
	if _is_pos_visible(local_pos):
		# Draw player marker (green with white outline)
		overlay.draw_circle(local_pos, 10, Color.GREEN)
		overlay.draw_circle(local_pos, 10, Color.WHITE, false, 2.0)

		# Draw direction indicator (chevron pointing camera direction)
		var camera_controller = local_player.get_node_or_null("CameraController")
		if camera_controller and "camera_rotation" in camera_controller:
			var camera_yaw: float = camera_controller.camera_rotation.x
			var arrow_angle: float = -camera_yaw + PI / 2.0 + PI

			var v_length := 18.0
			var v_width := 12.0

			var tip := local_pos + Vector2(cos(arrow_angle), sin(arrow_angle)) * v_length
			var left := local_pos + Vector2(cos(arrow_angle + 2.8), sin(arrow_angle + 2.8)) * v_width
			var right := local_pos + Vector2(cos(arrow_angle - 2.8), sin(arrow_angle - 2.8)) * v_width

			overlay.draw_line(left, tip, Color.BLACK, 4.0)
			overlay.draw_line(right, tip, Color.BLACK, 4.0)
			overlay.draw_line(left, tip, Color.YELLOW, 2.0)
			overlay.draw_line(right, tip, Color.YELLOW, 2.0)

	# Draw remote players
	for peer_id in remote_players:
		var player = remote_players[peer_id]
		if player and is_instance_valid(player):
			var remote_xz := Vector2(player.global_position.x, player.global_position.z)
			var remote_local := _world_to_overlay_pos(remote_xz)

			if _is_pos_visible(remote_local):
				overlay.draw_circle(remote_local, 8, Color.BLUE)
				overlay.draw_circle(remote_local, 8, Color.WHITE, false, 2.0)

func _draw_pins() -> void:
	if not overlay:
		return

	for pin in map_pins:
		var local_pos := _world_to_overlay_pos(pin.pos)

		if _is_pos_visible(local_pos):
			# Draw pin marker (flag icon)
			overlay.draw_circle(local_pos, 5, Color.RED)
			overlay.draw_line(local_pos, local_pos + Vector2(0, -12), Color.RED, 2.0)
			# Small flag triangle
			var flag_points := PackedVector2Array([
				local_pos + Vector2(1, -12),
				local_pos + Vector2(10, -9),
				local_pos + Vector2(1, -6)
			])
			overlay.draw_colored_polygon(flag_points, Color.RED)

			# Draw pin name
			var font: Font = ThemeDB.fallback_font
			var font_size: int = 12
			var text_size := font.get_string_size(pin.name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos := local_pos + Vector2(-text_size.x * 0.5, -20)

			# Outline
			for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				overlay.draw_string(font, text_pos + offset, pin.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
			overlay.draw_string(font, text_pos, pin.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _draw_pings() -> void:
	if not overlay:
		return

	for ping in active_pings:
		var local_pos := _world_to_overlay_pos(ping.pos)

		if _is_pos_visible(local_pos):
			# Get ping color based on peer
			var ping_color: Color = Color.YELLOW
			if ping.from_peer != multiplayer.get_unique_id():
				var colors := [Color.CYAN, Color.MAGENTA, Color.ORANGE, Color.LIME]
				ping_color = colors[ping.from_peer % colors.size()]

			# Draw pulsing circle (opacity based on time left)
			var alpha: float = ping.time_left / 15.0
			var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.3
			var radius: float = lerp(25.0, 8.0, alpha) * pulse
			var color: Color = ping_color
			color.a = alpha

			overlay.draw_circle(local_pos, radius, color, false, 3.0)
			overlay.draw_circle(local_pos, radius * 0.4, color)

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

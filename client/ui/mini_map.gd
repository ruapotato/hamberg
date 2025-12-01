extends Control

## MiniMap - Always-visible mini-map in top right corner
## North-locked, zoomed in, shows nearby area

const WorldMapGenerator = preload("res://client/ui/world_map_generator.gd")
# BiomeGenerator type removed - accepts any generator with required methods

# Map state
var map_generator = null  # WorldMapGenerator
var local_player: Node3D = null
var remote_players: Dictionary = {}
var biome_generator = null  # BiomeGenerator or TerrainBiomeGenerator instance
var cached_map_texture: ImageTexture = null  # Large pre-generated buffer
var atlas_texture: AtlasTexture = null  # Viewport into the buffer
var buffer_center: Vector2 = Vector2.ZERO  # World position at center of buffer
var displayed_center: Vector2 = Vector2.ZERO  # Actual world position at center of displayed map (may differ due to clamping)
var buffer_world_size: float = 800.0  # World units covered by buffer (4x visible area)
var buffer_pixel_size: int = 128  # Pixel size of buffer texture (reduced for performance)

# Mini-map settings
const MINI_MAP_SIZE := 64  # Pixels shown on screen
const MINI_MAP_WORLD_SIZE := 200.0  # World units visible (fairly zoomed in)
const BUFFER_EXPAND_THRESHOLD := 50.0  # Regenerate when within 50 units of edge

# Map pins and pings
var map_pins: Array = []
var active_pings: Array = []

# Special location markers (Shnarken huts, etc.)
var special_markers: Array = []

# UI nodes
@onready var map_texture_rect: TextureRect = $Panel/MapTextureRect
@onready var refresh_timer: Timer = $RefreshTimer
@onready var overlay: Control = $Panel/MapTextureRect/Overlay
@onready var biome_label: Label = $InfoContainer/BiomeLabel
@onready var time_label: Label = $InfoContainer/TimeLabel

# Biome tracking
var current_biome: String = "Valley"

# Day/night cycle reference
var day_night_cycle: Node = null

## Format biome name from snake_case to Title Case
func _format_biome_name(biome: String) -> String:
	var words = biome.split("_")
	var formatted = ""
	for word in words:
		if formatted != "":
			formatted += " "
		formatted += word.capitalize()
	return formatted

func _ready() -> void:
	# Setup refresh timer for viewport updates (cheap, just moves the viewport)
	refresh_timer.wait_time = 0.1  # Update viewport position 10 times per second
	refresh_timer.timeout.connect(_on_refresh_timeout)
	refresh_timer.start()

	# Connect overlay drawing
	if overlay:
		overlay.draw.connect(_draw_overlay)

	print("[MiniMap] Mini-map initialized")

func initialize(generator, player: Node3D) -> void:
	biome_generator = generator
	local_player = player
	map_generator = WorldMapGenerator.new(generator)

	# DON'T generate initial mini-map here - wait for generate_initial_map() to be called
	# This allows caller to ensure proper initialization order

	print("[MiniMap] Initialized with BiomeGenerator and player")

## Call this after initialize() to generate the initial map
func generate_initial_map() -> void:
	if local_player and map_generator:
		print("[MiniMap] Generating initial map (procedural)")
		_generate_initial_minimap()

func set_world_texture(texture: ImageTexture, texture_size: int, map_radius: float) -> void:
	"""Deprecated - mini-map now generates its own view on demand"""
	pass

func _process(delta: float) -> void:
	# Update active pings (count down timers)
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i].time_left -= delta
		if active_pings[i].time_left <= 0:
			active_pings.remove_at(i)

	# Queue redraw for markers on overlay
	if overlay:
		overlay.queue_redraw()

	# Debug logging (in _process, not in _draw)
	_update_debug_logging(delta)

func _draw_overlay() -> void:
	# Draw on top of the map texture
	_draw_compass_directions()
	_draw_special_markers()
	_draw_pins()
	_draw_pings()
	_draw_player_markers()
	_draw_debug_info()

func _generate_initial_minimap() -> void:
	"""Generate buffered mini-map at player spawn location"""
	if not map_generator or not local_player:
		return

	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)
	_regenerate_buffer(player_xz)

func _regenerate_buffer(center: Vector2) -> void:
	"""Regenerate the buffer texture centered at the given world position"""
	print("[MiniMap] Generating %dx%d buffer covering %.0f units..." % [buffer_pixel_size, buffer_pixel_size, buffer_world_size])

	buffer_center = center
	displayed_center = center  # Initially centered on buffer center
	cached_map_texture = map_generator.generate_map_texture(center, buffer_world_size, buffer_pixel_size)

	# Create atlas texture to show a viewport into the buffer
	atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = cached_map_texture
	atlas_texture.region = Rect2(0, 0, MINI_MAP_SIZE, MINI_MAP_SIZE)

	map_texture_rect.texture = atlas_texture
	print("[MiniMap] Buffer generated")

func refresh_map() -> void:
	"""Update viewport position (cheap) or regenerate buffer if near edge"""
	if not atlas_texture or not local_player:
		return

	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)

	# Update biome label
	if biome_generator and biome_generator.has_method("get_biome_at_position"):
		var biome = biome_generator.get_biome_at_position(player_xz)
		if biome != current_biome:
			current_biome = biome
			if biome_label:
				biome_label.text = _format_biome_name(biome)

	# Update time label
	_update_time_display()

	# Check if player is near the edge of the buffer
	var distance_from_center := player_xz.distance_to(buffer_center)
	var buffer_radius := buffer_world_size * 0.5

	if distance_from_center > (buffer_radius - BUFFER_EXPAND_THRESHOLD):
		# Too close to edge, regenerate buffer centered on player
		print("[MiniMap] Player near buffer edge, regenerating...")
		_regenerate_buffer(player_xz)
		return

	# Player still in buffer, just update the viewport
	_update_viewport(player_xz)

func _update_viewport(player_pos: Vector2) -> void:
	"""Update the atlas viewport to center on player (no texture regeneration)"""
	# Calculate world units per pixel in the buffer
	var world_to_buffer_scale := float(buffer_pixel_size) / buffer_world_size
	var buffer_to_world_scale := buffer_world_size / float(buffer_pixel_size)

	# Convert player position relative to buffer center into buffer pixel coordinates
	var relative_pos := player_pos - buffer_center
	var buffer_pixel_x := (buffer_pixel_size * 0.5) + (relative_pos.x * world_to_buffer_scale)
	var buffer_pixel_y := (buffer_pixel_size * 0.5) + (relative_pos.y * world_to_buffer_scale)

	# Calculate how many pixels in the buffer correspond to the visible world size
	var visible_buffer_pixels := MINI_MAP_WORLD_SIZE * world_to_buffer_scale

	# Calculate viewport region (centered on player)
	var region_x := buffer_pixel_x - (visible_buffer_pixels * 0.5)
	var region_y := buffer_pixel_y - (visible_buffer_pixels * 0.5)

	# Clamp to buffer bounds
	region_x = clamp(region_x, 0, buffer_pixel_size - visible_buffer_pixels)
	region_y = clamp(region_y, 0, buffer_pixel_size - visible_buffer_pixels)

	# Calculate the actual displayed center (may differ from player pos due to clamping)
	var displayed_pixel_x := region_x + (visible_buffer_pixels * 0.5)
	var displayed_pixel_y := region_y + (visible_buffer_pixels * 0.5)
	var displayed_offset_x := (displayed_pixel_x - (buffer_pixel_size * 0.5)) * buffer_to_world_scale
	var displayed_offset_y := (displayed_pixel_y - (buffer_pixel_size * 0.5)) * buffer_to_world_scale
	displayed_center = buffer_center + Vector2(displayed_offset_x, displayed_offset_y)

	# Update the atlas region (just moves the viewport, no pixel generation!)
	atlas_texture.region = Rect2(region_x, region_y, visible_buffer_pixels, visible_buffer_pixels)

func _on_refresh_timeout() -> void:
	refresh_map()

func _world_to_screen_pos(world_pos: Vector2) -> Vector2:
	if not overlay:
		return Vector2.ZERO

	# Use the actual displayed center (accounts for viewport clamping)
	# This ensures markers align with the terrain even near buffer edges
	var offset := world_pos - displayed_center

	# Normalize to -0.5 to 0.5 based on visible world size
	var norm_x := offset.x / MINI_MAP_WORLD_SIZE
	var norm_y := offset.y / MINI_MAP_WORLD_SIZE

	# Convert to overlay local coordinates (use actual overlay size, not constant)
	var overlay_size := overlay.size
	var screen_x := (norm_x + 0.5) * overlay_size.x
	var screen_y := (norm_y + 0.5) * overlay_size.y

	return Vector2(screen_x, screen_y) + overlay.global_position

func _draw_compass_directions() -> void:
	"""Draw N, E, S, W labels inside the mini-map edge"""
	# Overlay has same size as MapTextureRect, so center is local
	var center := overlay.size * 0.5
	var radius := (overlay.size.x * 0.5) - 12.0  # Inside the map edge

	# Define compass positions (N, E, S, W)
	# North is +Z in world space, which is "up" on the map
	var directions := [
		{"label": "N", "angle": -PI / 2.0},      # Top (North)
		{"label": "E", "angle": 0.0},             # Right (East)
		{"label": "S", "angle": PI / 2.0},        # Bottom (South)
		{"label": "W", "angle": PI}               # Left (West)
	]

	for dir in directions:
		var pos := center + Vector2(cos(dir.angle), sin(dir.angle)) * radius

		# Draw text with outline for visibility
		var font := ThemeDB.fallback_font
		var font_size := 12
		var text: String = dir.label

		# Calculate text size for centering
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := pos - text_size * 0.5

		# Draw outline (black) - call on overlay
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			overlay.draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

		# Draw main text (white) - call on overlay
		overlay.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _draw_player_markers() -> void:
	if not local_player:
		return

	# Draw local player (always at center) - overlay local coordinates
	var center := overlay.size * 0.5

	# Draw direction arrow (V shape) showing camera orientation
	var camera_controller = local_player.get_node_or_null("CameraController")
	if camera_controller and "camera_rotation" in camera_controller:
		var camera_yaw: float = camera_controller.camera_rotation.x

		# Convert camera yaw to arrow direction
		# Camera yaw is in radians, 0 = looking along +Z axis
		# On mini-map: North should point UP (angle = -PI/2)
		# Negate, rotate 90 degrees, then flip 180 degrees to align correctly
		var arrow_angle := -camera_yaw + PI / 2.0 + PI  # Flip and rotate to align with map

		# Calculate V-shape points (chevron pointing in camera direction)
		var v_length := 12.0
		var v_width := 8.0

		# Tip of V (points in camera direction)
		var tip := center + Vector2(cos(arrow_angle), sin(arrow_angle)) * v_length

		# Left and right arms of V
		var left := center + Vector2(cos(arrow_angle + 2.8), sin(arrow_angle + 2.8)) * v_width
		var right := center + Vector2(cos(arrow_angle - 2.8), sin(arrow_angle - 2.8)) * v_width

		# Draw V shape as thick lines - call on overlay
		overlay.draw_line(left, tip, Color.BLACK, 5.0)
		overlay.draw_line(right, tip, Color.BLACK, 5.0)
		overlay.draw_line(left, tip, Color.YELLOW, 3.0)
		overlay.draw_line(right, tip, Color.YELLOW, 3.0)

		# Draw center dot - call on overlay
		overlay.draw_circle(center, 3, Color.YELLOW)
		overlay.draw_circle(center, 3, Color.BLACK, false, 1.0)
	else:
		# Fallback: draw simple circle if no camera - call on overlay
		overlay.draw_circle(center, 8, Color.YELLOW)
		overlay.draw_circle(center, 8, Color.BLACK, false, 2.0)

	# Draw remote players
	for peer_id in remote_players:
		var player = remote_players[peer_id]
		if player and is_instance_valid(player):
			var remote_xz := Vector2(player.global_position.x, player.global_position.z)
			var remote_screen := _world_to_screen_pos(remote_xz)

			if _is_on_screen(remote_screen):
				var local_pos := remote_screen - overlay.global_position
				overlay.draw_circle(local_pos, 4, Color.BLUE)
				overlay.draw_circle(local_pos, 4, Color.WHITE, false, 1.5)

func _draw_pins() -> void:
	var center := overlay.size * 0.5
	var edge_radius := (overlay.size.x * 0.5) - 8.0  # Inside edge

	for pin in map_pins:
		var screen_pos := _world_to_screen_pos(pin.pos)

		if _is_on_screen(screen_pos):
			# Draw pin marker (flag icon)
			var local_pos := screen_pos - overlay.global_position
			overlay.draw_circle(local_pos, 4, Color.RED)
			overlay.draw_line(local_pos, local_pos + Vector2(0, -10), Color.RED, 2.0)
			# Small flag triangle
			var flag_points := PackedVector2Array([
				local_pos + Vector2(1, -10),
				local_pos + Vector2(8, -7),
				local_pos + Vector2(1, -4)
			])
			overlay.draw_colored_polygon(flag_points, Color.RED)
		else:
			# Draw edge indicator pointing to off-screen pin
			var local_pos := screen_pos - overlay.global_position
			var direction := (local_pos - center).normalized()
			var edge_pos := center + direction * edge_radius

			# Draw arrow pointing outward
			overlay.draw_circle(edge_pos, 4, Color.RED)
			var arrow_tip := edge_pos + direction * 6
			overlay.draw_line(edge_pos, arrow_tip, Color.RED, 2.0)

func _draw_pings() -> void:
	var center := overlay.size * 0.5
	var edge_radius := (overlay.size.x * 0.5) - 8.0  # Inside edge

	for ping in active_pings:
		var screen_pos := _world_to_screen_pos(ping.pos)
		var alpha: float = ping.time_left / 15.0

		# Get ping color based on peer
		var ping_color: Color = Color.YELLOW
		if ping.from_peer != multiplayer.get_unique_id():
			var colors := [Color.CYAN, Color.MAGENTA, Color.ORANGE, Color.LIME]
			ping_color = colors[ping.from_peer % colors.size()]

		if _is_on_screen(screen_pos):
			# Draw pulsing circle on map
			var local_pos := screen_pos - overlay.global_position
			var radius: float = lerp(12.0, 4.0, alpha)
			var color: Color = ping_color
			color.a = alpha * 0.8

			overlay.draw_circle(local_pos, radius, color, false, 2.0)
			overlay.draw_circle(local_pos, radius * 0.5, color)
		else:
			# Draw edge indicator pointing to off-screen ping
			var local_pos := screen_pos - overlay.global_position
			var direction := (local_pos - center).normalized()
			var edge_pos := center + direction * edge_radius

			# Pulsing arrow indicator
			var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.3
			var color: Color = ping_color
			color.a = alpha

			# Draw pulsing circle at edge
			overlay.draw_circle(edge_pos, 5 * pulse, color)

			# Draw arrow pointing outward
			var arrow_tip := edge_pos + direction * (8 * pulse)
			var arrow_left := edge_pos + direction.rotated(2.5) * 4
			var arrow_right := edge_pos + direction.rotated(-2.5) * 4
			overlay.draw_line(edge_pos, arrow_tip, color, 2.0)
			overlay.draw_line(arrow_tip, arrow_left, color, 2.0)
			overlay.draw_line(arrow_tip, arrow_right, color, 2.0)

func _draw_special_markers() -> void:
	var center := overlay.size * 0.5
	var edge_radius := (overlay.size.x * 0.5) - 6.0

	for marker in special_markers:
		var screen_pos := _world_to_screen_pos(marker.pos)
		var marker_color: Color = marker.get("color", Color.GOLD)
		var marker_type: String = marker.get("type", "default")

		if _is_on_screen(screen_pos):
			var local_pos := screen_pos - overlay.global_position

			# Draw small icon based on type
			if marker_type == "shnarken":
				# Draw small boot icon
				overlay.draw_rect(Rect2(local_pos + Vector2(-3, -4), Vector2(6, 8)), marker_color)
				overlay.draw_rect(Rect2(local_pos + Vector2(1, 0), Vector2(4, 4)), marker_color)
				overlay.draw_rect(Rect2(local_pos + Vector2(-3, -4), Vector2(6, 8)), Color.WHITE, false, 1.0)
			else:
				# Default small diamond
				var diamond := PackedVector2Array([
					local_pos + Vector2(0, -5),
					local_pos + Vector2(4, 0),
					local_pos + Vector2(0, 5),
					local_pos + Vector2(-4, 0)
				])
				overlay.draw_colored_polygon(diamond, marker_color)
		else:
			# Draw edge indicator pointing to off-screen marker
			var local_pos := screen_pos - overlay.global_position
			var direction := (local_pos - center).normalized()
			var edge_pos := center + direction * edge_radius

			# Small arrow at edge
			overlay.draw_circle(edge_pos, 3, marker_color)

## Add a special marker to the mini-map
func add_special_marker(world_pos: Vector2, name: String, type: String = "default", color: Color = Color.GOLD) -> void:
	special_markers.append({
		"pos": world_pos,
		"name": name,
		"type": type,
		"color": color
	})

func _is_on_screen(screen_pos: Vector2) -> bool:
	if not overlay:
		return false
	var rect_pos := overlay.global_position
	var rect_size := overlay.size

	return screen_pos.x >= rect_pos.x and screen_pos.x <= rect_pos.x + rect_size.x and \
		   screen_pos.y >= rect_pos.y and screen_pos.y <= rect_pos.y + rect_size.y

func add_ping(world_pos: Vector2, from_peer: int) -> void:
	"""Add a ping to the mini-map"""
	active_pings.append({
		"pos": world_pos,
		"time_left": 15.0,
		"from_peer": from_peer
	})

func set_remote_players(players: Dictionary) -> void:
	"""Update remote players dictionary"""
	remote_players = players

func set_pins(pins: Array) -> void:
	"""Update pins array (handles both array and Vector2 formats)"""
	map_pins = []
	for pin in pins:
		var pos_data = pin.get("pos", [0, 0])
		var pos: Vector2
		# Handle both array format [x, y] and Vector2 format
		if pos_data is Array:
			pos = Vector2(pos_data[0], pos_data[1])
		elif pos_data is Vector2:
			pos = pos_data
		else:
			pos = Vector2.ZERO
		map_pins.append({"pos": pos, "name": pin.get("name", "Pin")})

func _update_time_display() -> void:
	"""Update the time label from DayNightCycle"""
	if not time_label:
		return

	# Find DayNightCycle if we don't have it yet
	if not day_night_cycle:
		_find_day_night_cycle()

	if day_night_cycle and day_night_cycle.has_method("get_time_string_12h"):
		time_label.text = day_night_cycle.get_time_string_12h()

func _find_day_night_cycle() -> void:
	"""Find the DayNightCycle node in the scene tree"""
	# Look for TerrainWorld which contains DayNightCycle
	var terrain_world = get_tree().get_first_node_in_group("terrain_world")
	if terrain_world:
		day_night_cycle = terrain_world.get_node_or_null("DayNightCycle")
		return

	# Fallback: search from root
	var root = get_tree().root
	day_night_cycle = _find_node_by_class(root, "DayNightCycle")

func _find_node_by_class(node: Node, class_name_to_find: String) -> Node:
	"""Recursively search for a node by class name"""
	if node.get_class() == class_name_to_find or node.name == class_name_to_find:
		return node
	for child in node.get_children():
		var result = _find_node_by_class(child, class_name_to_find)
		if result:
			return result
	return null

# Debug timer for logging
var debug_log_timer: float = 0.0
const DEBUG_LOG_INTERVAL: float = 2.0  # Log every 2 seconds

func _draw_debug_info() -> void:
	"""Draw debug UV coordinates on screen"""
	if not local_player or not map_generator:
		return

	if not is_instance_valid(local_player):
		return

	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)

	# Check if map_generator has the debug method
	if not map_generator.has_method("debug_get_uv_for_world_pos"):
		return

	var debug_info = map_generator.debug_get_uv_for_world_pos(player_xz)
	if debug_info.is_empty():
		return

	# Get font safely
	var font = ThemeDB.fallback_font
	if not font:
		return

	var font_size := 10
	var y_offset := overlay.size.y + 5

	# World position
	var world_text := "World: %.0f, %.0f" % [player_xz.x, player_xz.y]
	overlay.draw_string(font, Vector2(0, y_offset), world_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# UV coordinates (what minimap uses)
	var uv: Vector2 = debug_info.get("uv", Vector2.ZERO)
	var uv_text := "Minimap UV: %.4f, %.4f" % [uv.x, uv.y]
	overlay.draw_string(font, Vector2(0, y_offset + 12), uv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.CYAN)

	# Shader UV (same formula, just showing it)
	var coverage: float = debug_info.get("coverage", 100000.0)
	var shader_uv_x := (player_xz.x + coverage * 0.5) / coverage
	var shader_uv_y := (player_xz.y + coverage * 0.5) / coverage
	var shader_text := "Shader UV: %.4f, %.4f" % [shader_uv_x, shader_uv_y]
	overlay.draw_string(font, Vector2(0, y_offset + 24), shader_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.YELLOW)

	# Pixel coordinates
	var pixel: Vector2i = debug_info.get("pixel", Vector2i.ZERO)
	var tex_size: Vector2i = debug_info.get("tex_size", Vector2i.ZERO)
	var pixel_text := "Pixel: %d, %d / %d" % [pixel.x, pixel.y, tex_size.x]
	overlay.draw_string(font, Vector2(0, y_offset + 36), pixel_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GREEN)

	# Coverage
	var cov_text := "Coverage: %.0f" % coverage
	overlay.draw_string(font, Vector2(0, y_offset + 48), cov_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.ORANGE)

func _update_debug_logging(delta: float) -> void:
	"""Periodic debug logging - called from _process"""
	if not local_player or not map_generator:
		return

	if not is_instance_valid(local_player):
		return

	debug_log_timer += delta
	if debug_log_timer < DEBUG_LOG_INTERVAL:
		return

	debug_log_timer = 0.0

	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)

	if not map_generator.has_method("debug_get_uv_for_world_pos"):
		return

	var debug_info = map_generator.debug_get_uv_for_world_pos(player_xz)
	if debug_info.is_empty():
		return

	var uv: Vector2 = debug_info.get("uv", Vector2.ZERO)
	var pixel: Vector2i = debug_info.get("pixel", Vector2i.ZERO)
	var tex_size: Vector2i = debug_info.get("tex_size", Vector2i.ZERO)
	var coverage: float = debug_info.get("coverage", 100000.0)
	var shader_uv_x := (player_xz.x + coverage * 0.5) / coverage
	var shader_uv_y := (player_xz.y + coverage * 0.5) / coverage

	print("[MiniMap DEBUG] Player world pos: %s" % player_xz)
	print("[MiniMap DEBUG] Minimap UV: %s, Pixel: %s, Tex size: %s" % [uv, pixel, tex_size])
	print("[MiniMap DEBUG] Coverage: %.0f, Shader UV would be: (%.4f, %.4f)" % [coverage, shader_uv_x, shader_uv_y])

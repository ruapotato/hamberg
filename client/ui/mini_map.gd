extends Control

## MiniMap - Always-visible mini-map in top right corner
## North-locked, zoomed in, shows nearby area

const WorldMapGenerator = preload("res://client/ui/world_map_generator.gd")
const BiomeGenerator = preload("res://shared/biome_generator.gd")

# Map state
var map_generator = null  # WorldMapGenerator
var local_player: Node3D = null
var remote_players: Dictionary = {}
var biome_generator: BiomeGenerator = null
var cached_map_texture: ImageTexture = null  # Large pre-generated buffer
var atlas_texture: AtlasTexture = null  # Viewport into the buffer
var buffer_center: Vector2 = Vector2.ZERO  # World position at center of buffer
var buffer_world_size: float = 800.0  # World units covered by buffer (4x visible area)
var buffer_pixel_size: int = 256  # Pixel size of buffer texture

# Mini-map settings
const MINI_MAP_SIZE := 64  # Pixels shown on screen
const MINI_MAP_WORLD_SIZE := 200.0  # World units visible (fairly zoomed in)
const BUFFER_EXPAND_THRESHOLD := 50.0  # Regenerate when within 50 units of edge

# Map pins and pings
var map_pins: Array = []
var active_pings: Array = []

# UI nodes
@onready var map_texture_rect: TextureRect = $Panel/MapTextureRect
@onready var refresh_timer: Timer = $RefreshTimer

func _ready() -> void:
	# Setup refresh timer for viewport updates (cheap, just moves the viewport)
	refresh_timer.wait_time = 0.1  # Update viewport position 10 times per second
	refresh_timer.timeout.connect(_on_refresh_timeout)
	refresh_timer.start()

	print("[MiniMap] Mini-map initialized")

func initialize(generator: BiomeGenerator, player: Node3D) -> void:
	biome_generator = generator
	local_player = player
	map_generator = WorldMapGenerator.new(generator)

	# Generate initial mini-map once at spawn
	_generate_initial_minimap()

	print("[MiniMap] Initialized with BiomeGenerator and player")

func set_world_texture(texture: ImageTexture, texture_size: int, map_radius: float) -> void:
	"""Deprecated - mini-map now generates its own view on demand"""
	pass

func _process(delta: float) -> void:
	# Update active pings (count down timers)
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i].time_left -= delta
		if active_pings[i].time_left <= 0:
			active_pings.remove_at(i)

	# Queue redraw for markers
	queue_redraw()

func _draw() -> void:
	# Draw on top of the map texture
	_draw_compass_directions()
	_draw_pins()
	_draw_pings()
	_draw_player_markers()

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

	# Update the atlas region (just moves the viewport, no pixel generation!)
	atlas_texture.region = Rect2(region_x, region_y, visible_buffer_pixels, visible_buffer_pixels)

func _on_refresh_timeout() -> void:
	refresh_map()

func _world_to_screen_pos(world_pos: Vector2) -> Vector2:
	if not local_player:
		return Vector2.ZERO

	# Center is always player position
	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)

	# Offset from center
	var offset := world_pos - player_xz

	# Normalize to -0.5 to 0.5
	var norm_x := offset.x / MINI_MAP_WORLD_SIZE
	var norm_y := offset.y / MINI_MAP_WORLD_SIZE

	# Convert to screen coordinates
	var screen_x := (norm_x + 0.5) * MINI_MAP_SIZE
	var screen_y := (norm_y + 0.5) * MINI_MAP_SIZE

	return Vector2(screen_x, screen_y) + map_texture_rect.global_position

func _draw_compass_directions() -> void:
	"""Draw N, E, S, W labels around the mini-map edge"""
	var center := map_texture_rect.global_position + (map_texture_rect.size * 0.5)
	var radius := (MINI_MAP_SIZE * 0.5) + 8.0  # Just outside the map edge

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

		# Draw outline (black)
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

		# Draw main text (white)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _draw_player_markers() -> void:
	if not local_player:
		return

	# Draw local player (always at center)
	var center := map_texture_rect.global_position + (map_texture_rect.size * 0.5)

	# Draw direction arrow showing camera orientation
	var camera_controller = local_player.get_node_or_null("CameraController")
	if camera_controller and "camera_rotation" in camera_controller:
		var camera_yaw: float = camera_controller.camera_rotation.x

		# Convert camera yaw to arrow direction
		# Camera yaw is in radians, 0 = North (+Z), rotates clockwise
		# We need to rotate 90 degrees because Godot's +Z is "forward" but we want North to be "up" on map
		var arrow_angle := camera_yaw - PI / 2.0  # Rotate to align North with up

		# Calculate arrow points (triangle pointing in camera direction)
		var arrow_length := 10.0
		var arrow_width := 6.0

		# Tip of arrow (points in camera direction)
		var tip := center + Vector2(cos(arrow_angle), sin(arrow_angle)) * arrow_length

		# Left and right base points
		var left := center + Vector2(cos(arrow_angle + 2.5), sin(arrow_angle + 2.5)) * arrow_width
		var right := center + Vector2(cos(arrow_angle - 2.5), sin(arrow_angle - 2.5)) * arrow_width

		# Draw filled triangle
		draw_colored_polygon(PackedVector2Array([tip, left, right]), Color.GREEN)

		# Draw outline
		draw_polyline(PackedVector2Array([tip, left, right, tip]), Color.WHITE, 1.5)
	else:
		# Fallback: draw simple circle if no camera
		draw_circle(center, 6, Color.GREEN)
		draw_circle(center, 6, Color.WHITE, false, 2.0)

	# Draw remote players
	for peer_id in remote_players:
		var player = remote_players[peer_id]
		if player and is_instance_valid(player):
			var remote_xz := Vector2(player.global_position.x, player.global_position.z)
			var remote_screen := _world_to_screen_pos(remote_xz)

			if _is_on_screen(remote_screen):
				draw_circle(remote_screen, 4, Color.BLUE)
				draw_circle(remote_screen, 4, Color.WHITE, false, 1.5)

func _draw_pins() -> void:
	for pin in map_pins:
		var screen_pos := _world_to_screen_pos(pin.pos)

		if _is_on_screen(screen_pos):
			# Draw small pin marker
			draw_circle(screen_pos, 3, Color.RED)

func _draw_pings() -> void:
	for ping in active_pings:
		var screen_pos := _world_to_screen_pos(ping.pos)

		if _is_on_screen(screen_pos):
			# Draw pulsing circle
			var alpha: float = ping.time_left / 15.0
			var radius: float = lerp(15.0, 3.0, alpha)
			var color: Color = Color.YELLOW
			color.a = alpha * 0.8

			draw_circle(screen_pos, radius, color, false, 2.0)

func _is_on_screen(screen_pos: Vector2) -> bool:
	var rect_pos := map_texture_rect.global_position
	var rect_size := map_texture_rect.size

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
	"""Update pins array"""
	map_pins = pins

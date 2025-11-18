extends Control

## MiniMap - Always-visible mini-map in top right corner
## North-locked, zoomed in, shows nearby area

const WorldMapGenerator = preload("res://client/ui/world_map_generator.gd")

# Map state
var map_generator = null  # WorldMapGenerator
var local_player: Node3D = null
var remote_players: Dictionary = {}
var biome_generator: BiomeGenerator = null

# Mini-map settings
const MINI_MAP_SIZE := 200  # Pixels
const MINI_MAP_WORLD_SIZE := 200.0  # World units visible (fairly zoomed in)

# Map pins and pings
var map_pins: Array = []
var active_pings: Array = []

# UI nodes
@onready var map_texture_rect: TextureRect = $Panel/MapTextureRect
@onready var refresh_timer: Timer = $RefreshTimer

func _ready() -> void:
	# Setup refresh timer
	refresh_timer.wait_time = 1.0  # Refresh every second
	refresh_timer.timeout.connect(_on_refresh_timeout)
	refresh_timer.start()

	print("[MiniMap] Mini-map initialized")

func initialize(generator: BiomeGenerator, player: Node3D) -> void:
	biome_generator = generator
	local_player = player
	map_generator = WorldMapGenerator.new(generator)

	print("[MiniMap] Initialized with BiomeGenerator and player")

	# Generate initial map
	refresh_map()

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
	_draw_pins()
	_draw_pings()
	_draw_player_markers()

func refresh_map() -> void:
	if not map_generator or not local_player:
		return

	# Center on player
	var player_xz := Vector2(local_player.global_position.x, local_player.global_position.z)

	# Generate map texture
	var texture: ImageTexture = map_generator.generate_map_texture(player_xz, MINI_MAP_WORLD_SIZE, MINI_MAP_SIZE)
	map_texture_rect.texture = texture

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

func _draw_player_markers() -> void:
	if not local_player:
		return

	# Draw local player (always at center)
	var center := map_texture_rect.global_position + (map_texture_rect.size * 0.5)
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

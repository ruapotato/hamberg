extends Control

## PingScreenIndicator - Screen-space indicator showing direction to ping
## Shows arrow and "Ping" text at screen edge when ping is off-screen or far away

var ping_world_pos: Vector3 = Vector3.ZERO
var time_left: float = 15.0
var from_peer: int = 0
var ping_color: Color = Color.YELLOW

# References
var camera: Camera3D = null
var local_player: Node3D = null

# UI settings
const EDGE_MARGIN := 60.0
const MIN_DISTANCE_FOR_INDICATOR := 100.0  # Show indicator when ping is this far away

func _ready() -> void:
	# Set to full screen
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func initialize(world_pos: Vector2, peer_id: int, cam: Camera3D, player: Node3D) -> void:
	ping_world_pos = Vector3(world_pos.x, 0.0, world_pos.y)
	from_peer = peer_id
	camera = cam
	local_player = player

	# Set color based on peer
	if peer_id == multiplayer.get_unique_id():
		ping_color = Color.YELLOW
	else:
		var colors := [Color.CYAN, Color.MAGENTA, Color.ORANGE, Color.LIME]
		ping_color = colors[peer_id % colors.size()]

func _process(delta: float) -> void:
	time_left -= delta

	if time_left <= 0:
		queue_free()
		return

	queue_redraw()

func _draw() -> void:
	if not camera or not local_player or not is_instance_valid(camera) or not is_instance_valid(local_player):
		return

	var player_pos := local_player.global_position
	var distance := Vector2(player_pos.x, player_pos.z).distance_to(Vector2(ping_world_pos.x, ping_world_pos.z))

	# Only show screen indicator if ping is far away
	if distance < MIN_DISTANCE_FOR_INDICATOR:
		return

	# Check if ping is on screen
	var screen_pos := camera.unproject_position(ping_world_pos + Vector3(0, 25, 0))  # Aim at beam top
	var viewport_rect := get_viewport_rect()
	var on_screen := viewport_rect.has_point(screen_pos)

	# Also check if ping is behind camera
	var to_ping := (ping_world_pos - camera.global_position).normalized()
	var cam_forward := -camera.global_transform.basis.z
	var is_behind := to_ping.dot(cam_forward) < 0

	# If ping is on-screen and not behind camera, draw distance text at position
	if on_screen and not is_behind:
		_draw_distance_label(screen_pos, distance)
	else:
		# Draw edge indicator
		_draw_edge_indicator(is_behind, distance)

func _draw_distance_label(screen_pos: Vector2, distance: float) -> void:
	var alpha: float = clamp(time_left / 3.0, 0.0, 1.0)
	var color: Color = ping_color
	color.a = alpha

	var font: Font = ThemeDB.fallback_font
	var font_size := 16
	var text := "Ping %.0fm" % distance

	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := screen_pos - Vector2(text_size.x * 0.5, -30)

	# Draw outline
	var outline_color := Color.BLACK
	outline_color.a = alpha
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color)

	# Draw text
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_edge_indicator(is_behind: bool, distance: float) -> void:
	var viewport_rect: Rect2 = get_viewport_rect()
	var center: Vector2 = viewport_rect.size * 0.5

	# Calculate direction to ping in screen space
	var player_pos: Vector3 = local_player.global_position
	var to_ping: Vector2 = Vector2(ping_world_pos.x - player_pos.x, ping_world_pos.z - player_pos.z).normalized()

	# Get camera yaw to transform world direction to screen direction
	var cam_yaw: float = camera.global_rotation.y
	var screen_dir: Vector2 = to_ping.rotated(-cam_yaw)

	# If behind camera, flip direction
	if is_behind:
		screen_dir = -screen_dir

	# Convert to screen coordinates (Y is inverted)
	var screen_direction: Vector2 = Vector2(screen_dir.x, screen_dir.y)

	# Find edge position
	var edge_pos: Vector2 = _get_edge_position(center, screen_direction, viewport_rect.size)

	# Calculate alpha based on time
	var alpha: float = clamp(time_left / 3.0, 0.0, 1.0)
	var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.2

	var color: Color = ping_color
	color.a = alpha

	# Draw pulsing circle
	draw_circle(edge_pos, 12 * pulse, color)

	# Draw arrow pointing toward ping
	var arrow_length := 20.0 * pulse
	var arrow_dir := screen_direction.normalized()
	var arrow_tip := edge_pos - arrow_dir * (15 + arrow_length)

	# Arrow head
	var head_size := 10.0
	var head_left := arrow_tip + arrow_dir.rotated(2.5) * head_size
	var head_right := arrow_tip + arrow_dir.rotated(-2.5) * head_size

	draw_line(edge_pos - arrow_dir * 15, arrow_tip, color, 3.0)
	draw_line(arrow_tip, head_left, color, 3.0)
	draw_line(arrow_tip, head_right, color, 3.0)

	# Draw "Ping" text and distance
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var text: String = "Ping %.0fm" % distance

	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_offset := arrow_dir * 50
	var text_pos := edge_pos - text_offset - Vector2(text_size.x * 0.5, -text_size.y * 0.5)

	# Clamp text position to stay on screen
	text_pos.x = clamp(text_pos.x, 10, viewport_rect.size.x - text_size.x - 10)
	text_pos.y = clamp(text_pos.y, 10, viewport_rect.size.y - 10)

	# Draw outline
	var outline_color := Color.BLACK
	outline_color.a = alpha
	for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color)

	# Draw text
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _get_edge_position(center: Vector2, direction: Vector2, size: Vector2) -> Vector2:
	# Find intersection with screen edge
	var half_size: Vector2 = size * 0.5 - Vector2(EDGE_MARGIN, EDGE_MARGIN)

	# Calculate intersection with each edge
	var t_values: Array[float] = []

	if direction.x != 0:
		var t_horizontal: float = half_size.x / abs(direction.x)
		t_values.append(t_horizontal)

	if direction.y != 0:
		var t_vertical: float = half_size.y / abs(direction.y)
		t_values.append(t_vertical)

	# Use minimum t that keeps us on screen
	var t: float = 1.0
	if not t_values.is_empty():
		t = t_values.min()

	return center + direction * t

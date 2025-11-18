extends Node3D

## PingIndicator - Shows direction to a pinged location in 3D space
## Floats above the ping location and pulses for visibility

var ping_world_pos: Vector2 = Vector2.ZERO
var time_left: float = 15.0
var from_peer: int = 0

# Visual components
var mesh_instance: MeshInstance3D
var sprite: Sprite3D

func _ready() -> void:
	# Create visual indicator
	_setup_visual()

func _setup_visual() -> void:
	# Create a billboard sprite that always faces camera
	sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true  # Always visible through walls
	sprite.render_priority = 10  # Render on top
	add_child(sprite)

	# Create a simple texture programmatically (yellow circle)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Draw yellow circle
	for y in 64:
		for x in 64:
			var dx := x - 32
			var dy := y - 32
			var dist := sqrt(dx * dx + dy * dy)

			if dist < 28 and dist > 22:  # Ring shape
				img.set_pixel(x, y, Color.YELLOW)

	var texture := ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.pixel_size = 0.05

	# Offset upward so it floats above the ground
	sprite.position.y = 3.0

	print("[PingIndicator] Visual indicator created")

func initialize(world_pos: Vector2, peer_id: int) -> void:
	ping_world_pos = world_pos
	from_peer = peer_id

	# Set 3D position (assume ground level, will be adjusted by terrain height)
	global_position = Vector3(world_pos.x, 20.0, world_pos.y)

	print("[PingIndicator] Initialized at %s from peer %d" % [world_pos, peer_id])

func _process(delta: float) -> void:
	time_left -= delta

	if time_left <= 0:
		queue_free()
		return

	# Pulse effect
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.2
	if sprite:
		sprite.scale = Vector3.ONE * pulse

	# Fade out in last 3 seconds
	if time_left < 3.0:
		var alpha := time_left / 3.0
		if sprite:
			sprite.modulate.a = alpha

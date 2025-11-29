extends Node3D

## PingIndicator - Shows direction to a pinged location in 3D space
## Creates a Valheim-style light beam that's visible from anywhere

var ping_world_pos: Vector2 = Vector2.ZERO
var time_left: float = 15.0
var from_peer: int = 0

# Visual components
var beam_mesh: MeshInstance3D
var top_sprite: Sprite3D
var base_sprite: Sprite3D

# Colors based on peer
var ping_color: Color = Color.YELLOW

func _ready() -> void:
	_setup_visual()

func _setup_visual() -> void:
	# Create a tall light beam (cylinder)
	beam_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.3
	cylinder.bottom_radius = 0.5
	cylinder.height = 50.0  # Tall beam visible from far away
	beam_mesh.mesh = cylinder

	# Create glowing material for beam
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = ping_color
	beam_mat.emission_enabled = true
	beam_mat.emission = ping_color
	beam_mat.emission_energy_multiplier = 2.0
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color.a = 0.5
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mesh.material_override = beam_mat

	# Position beam so it goes from ground up
	beam_mesh.position.y = 25.0  # Half height
	add_child(beam_mesh)

	# Create top marker (billboard sprite)
	top_sprite = Sprite3D.new()
	top_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	top_sprite.shaded = false
	top_sprite.no_depth_test = true
	top_sprite.render_priority = 10
	top_sprite.position.y = 52.0  # Above the beam
	add_child(top_sprite)

	# Create marker texture (diamond shape)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Draw diamond shape
	for y in 64:
		for x in 64:
			var dx: int = abs(x - 32)
			var dy: int = abs(y - 32)
			if dx + dy < 28 and dx + dy > 20:  # Diamond outline
				img.set_pixel(x, y, ping_color)
			elif dx + dy < 20:  # Filled center
				var c: Color = ping_color
				c.a = 0.5
				img.set_pixel(x, y, c)

	var texture := ImageTexture.create_from_image(img)
	top_sprite.texture = texture
	top_sprite.pixel_size = 0.1

	# Create base ring at ground level
	base_sprite = Sprite3D.new()
	base_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # Only rotates on Y axis
	base_sprite.shaded = false
	base_sprite.render_priority = 5
	base_sprite.position.y = 0.5
	base_sprite.rotation_degrees.x = 90  # Lay flat
	add_child(base_sprite)

	# Create ring texture for base
	var base_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	base_img.fill(Color.TRANSPARENT)

	for y in 128:
		for x in 128:
			var dx: int = x - 64
			var dy: int = y - 64
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 60 and dist > 50:  # Ring
				base_img.set_pixel(x, y, ping_color)
			elif dist < 50 and dist > 40:  # Inner ring
				var c: Color = ping_color
				c.a = 0.3
				base_img.set_pixel(x, y, c)

	var base_texture := ImageTexture.create_from_image(base_img)
	base_sprite.texture = base_texture
	base_sprite.pixel_size = 0.1

func initialize(world_pos: Vector2, peer_id: int) -> void:
	ping_world_pos = world_pos
	from_peer = peer_id

	# Different colors for different peers
	if peer_id == multiplayer.get_unique_id():
		ping_color = Color.YELLOW  # Your own pings
	else:
		# Assign colors based on peer ID
		var colors := [Color.CYAN, Color.MAGENTA, Color.ORANGE, Color.LIME]
		ping_color = colors[peer_id % colors.size()]

	# Set 3D position
	global_position = Vector3(world_pos.x, 0.0, world_pos.y)

	# Update colors
	_update_colors()

func _update_colors() -> void:
	if beam_mesh and beam_mesh.material_override:
		var mat: StandardMaterial3D = beam_mesh.material_override
		mat.albedo_color = Color(ping_color.r, ping_color.g, ping_color.b, 0.5)
		mat.emission = ping_color

	if top_sprite:
		top_sprite.modulate = ping_color

	if base_sprite:
		base_sprite.modulate = ping_color

func _process(delta: float) -> void:
	time_left -= delta

	if time_left <= 0:
		queue_free()
		return

	# Pulse effect on beam
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.005) * 0.1
	if beam_mesh:
		beam_mesh.scale.x = pulse
		beam_mesh.scale.z = pulse

	# Rotate top marker slowly
	if top_sprite:
		top_sprite.rotation.y += delta * 2.0

	# Expand/contract base ring
	var ring_pulse := 1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.2
	if base_sprite:
		base_sprite.scale = Vector3.ONE * ring_pulse

	# Fade out in last 3 seconds
	if time_left < 3.0:
		var alpha := time_left / 3.0
		if beam_mesh and beam_mesh.material_override:
			var mat: StandardMaterial3D = beam_mesh.material_override
			mat.albedo_color.a = 0.5 * alpha
		if top_sprite:
			top_sprite.modulate.a = alpha
		if base_sprite:
			base_sprite.modulate.a = alpha

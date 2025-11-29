extends Node3D

## MapMarkerIndicator - Persistent map marker visible in 3D world
## Unlike pings, these stay until removed

var marker_world_pos: Vector2 = Vector2.ZERO
var marker_name: String = "Marker"
var marker_color: Color = Color.RED

# Visual components
var pole_mesh: MeshInstance3D
var flag_sprite: Sprite3D
var label_3d: Label3D

func _ready() -> void:
	_setup_visual()

func _setup_visual() -> void:
	# Create pole
	pole_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.08
	cylinder.height = 8.0
	pole_mesh.mesh = cylinder

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.4, 0.25, 0.1)  # Brown wood
	pole_mesh.material_override = pole_mat
	pole_mesh.position.y = 4.0
	add_child(pole_mesh)

	# Create flag sprite
	flag_sprite = Sprite3D.new()
	flag_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flag_sprite.shaded = false
	flag_sprite.no_depth_test = true
	flag_sprite.render_priority = 10
	flag_sprite.position.y = 8.5
	add_child(flag_sprite)

	# Create flag texture (triangular flag shape)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Draw triangular flag
	for y in 64:
		for x in 64:
			# Triangle pointing right from left edge
			var progress: float = float(x) / 64.0
			var height_at_x: float = 64.0 * (1.0 - progress)
			var center: float = 32.0
			if x < 48 and abs(y - center) < height_at_x * 0.5:
				img.set_pixel(x, y, marker_color)

	var texture := ImageTexture.create_from_image(img)
	flag_sprite.texture = texture
	flag_sprite.pixel_size = 0.05

	# Create 3D label for marker name
	label_3d = Label3D.new()
	label_3d.text = marker_name
	label_3d.font_size = 32
	label_3d.outline_size = 8
	label_3d.modulate = Color.WHITE
	label_3d.outline_modulate = Color.BLACK
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.position.y = 10.0
	add_child(label_3d)

func initialize(world_pos: Vector2, name: String, color: Color = Color.RED) -> void:
	marker_world_pos = world_pos
	marker_name = name
	marker_color = color

	# Set 3D position
	global_position = Vector3(world_pos.x, 0.0, world_pos.y)

	# Update visuals
	if label_3d:
		label_3d.text = name

	if flag_sprite:
		flag_sprite.modulate = color

func set_marker_name(new_name: String) -> void:
	marker_name = new_name
	if label_3d:
		label_3d.text = new_name

func _process(_delta: float) -> void:
	# Gentle wave animation for flag
	if flag_sprite:
		var wave := sin(Time.get_ticks_msec() * 0.003) * 0.1
		flag_sprite.rotation.z = wave

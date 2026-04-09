extends Area3D

const FloatingText = preload("res://client/ui/floating_text.gd")

## Resource Item - Dropped item that can be picked up
## Spawned when environmental objects are destroyed

@export var item_name: String = "wood"
@export var amount: int = 1
@export var lifetime: float = 300.0  # 5 minutes before despawn

var spawn_time: float = 0.0
var bob_offset: float = 0.0  # Random bob phase
var network_id: String = ""  # Unique ID for network sync
var pickup_requested: bool = false  # Prevents duplicate pickup requests
var overlap_check_done: bool = false  # Whether we've checked for overlapping bodies

# Visual
var sprite: Sprite3D = null

func _ready() -> void:
	spawn_time = Time.get_ticks_msec() / 1000.0
	bob_offset = randf() * TAU

	# Setup collision
	collision_layer = 4  # Item layer
	collision_mask = 2   # Player layer

	# Create visual
	_create_visual()

	# Connect pickup signal
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# Skip all processing if pickup already requested
	if pickup_requested:
		return

	# Check for overlapping bodies once after spawn (body_entered doesn't fire for already-overlapping)
	if not overlap_check_done:
		var time_since_spawn = (Time.get_ticks_msec() / 1000.0) - spawn_time
		if time_since_spawn >= 0.1:
			overlap_check_done = true
			_check_overlapping_bodies()
			if pickup_requested:
				return

	# Bob up and down
	var time = Time.get_ticks_msec() / 1000.0 + bob_offset
	var bob = sin(time * 2.0) * 0.08
	if sprite:
		sprite.position.y = 0.4 + bob

	# Check lifetime
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - spawn_time > lifetime:
		print("[ResourceItem] %s despawned (lifetime expired)" % item_name)
		queue_free()

func _create_visual() -> void:
	# Billboard sprite using the item's inventory icon
	sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.008  # Small world-space size
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Try to get texture from TextureGenerator
	var tex: Texture2D = null
	var tex_gen: Node = get_node_or_null("/root/TextureGenerator")
	if tex_gen and tex_gen.has_method("get_item_icon"):
		tex = tex_gen.get_item_icon(item_name)

	# Fallback: try loading from environment textures for natural resources
	if not tex:
		var env_paths: Dictionary = {
			"wood": "res://assets/textures/environment/oak_tree_front.png",
			"stone": "res://assets/textures/environment/rock.png",
			"plant_fiber": "res://assets/textures/environment/grass.png",
			"resin": "res://assets/textures/environment/oak_tree_front.png",
			"bone": "res://assets/textures/environment/rock.png",
		}
		var path: String = env_paths.get(item_name, "")
		if path != "" and ResourceLoader.exists(path):
			tex = load(path)

	# Final fallback: colored square
	if not tex:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var color: Color = _get_item_color()
		img.fill(color)
		tex = ImageTexture.create_from_image(img)

	sprite.texture = tex
	sprite.position.y = 0.4
	add_child(sprite)

	# Collision shape for pickup
	var collision_shape := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	collision_shape.shape = shape
	add_child(collision_shape)

func _get_item_color() -> Color:
	match item_name:
		"wood", "resin": return Color(0.5, 0.3, 0.1)
		"stone", "iron", "copper": return Color(0.5, 0.5, 0.55)
		"bone", "rotten_flesh": return Color(0.8, 0.8, 0.7)
		"glowing_spore", "fungal_essence", "plant_fiber": return Color(0.0, 1.0, 0.42)
		"ember_core": return Color(1.0, 0.3, 0.0)
		"ectoplasm": return Color(0.7, 0.9, 1.0)
		"shadow_shard": return Color(0.3, 0.0, 0.4)
		"spore_heart": return Color(0.0, 0.8, 0.34)
		"crystal_shard": return Color(1.0, 0.0, 0.58)
		_: return Color(0.8, 0.8, 0.8)

func _on_body_entered(body: Node3D) -> void:
	# Prevent duplicate pickup requests
	if pickup_requested:
		return

	# Check if it's a player
	if not body.has_node("Inventory"):
		return

	# Only allow local player to pick up
	if not body.is_multiplayer_authority():
		return

	# Send pickup request to server (server-authoritative)
	if NetworkManager and NetworkManager.is_client:
		pickup_requested = true  # Mark as requested to prevent duplicates
		set_deferred("monitorable", false)  # Disable collision detection
		visible = false  # Hide immediately so it looks picked up
		print("[ResourceItem] Requesting pickup of %d x %s (network_id: %s)" % [amount, item_name, network_id])

		# Show floating loot text in front of player's view (not at item position)
		var color: Color = FloatingText.RESOURCE_COLORS.get(item_name, Color.WHITE)
		var ft = FloatingText.new()
		ft.setup("+%d %s" % [amount, item_name.capitalize()], color)
		get_tree().current_scene.add_child(ft)
		# Position in front of the camera so player can see it
		var camera := get_viewport().get_camera_3d()
		if camera:
			var cam_fwd := -camera.global_transform.basis.z
			ft.global_position = camera.global_position + cam_fwd * 3.0 + Vector3(randf_range(-0.3, 0.3), -0.5, 0)
		else:
			ft.global_position = global_position + Vector3(0, 1.5, 0)

		NetworkManager.rpc_request_pickup_item.rpc_id(1, item_name, amount, network_id)

func set_item_data(item: String, qty: int) -> void:
	item_name = item
	amount = qty

## Check for bodies already overlapping when spawned
func _check_overlapping_bodies() -> void:
	if pickup_requested:
		return

	var overlapping = get_overlapping_bodies()
	for body in overlapping:
		_on_body_entered(body)
		if pickup_requested:
			break

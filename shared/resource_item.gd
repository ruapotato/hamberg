extends Area3D

## Resource Item - Dropped item that can be picked up
## Spawned when environmental objects are destroyed

@export var item_name: String = "wood"
@export var amount: int = 1
@export var lifetime: float = 300.0  # 5 minutes before despawn

var spawn_time: float = 0.0
var bob_offset: float = 0.0  # Random bob phase

# Visual
var mesh_instance: MeshInstance3D

func _ready() -> void:
	spawn_time = Time.get_ticks_msec() / 1000.0
	bob_offset = randf() * TAU

	# Setup collision
	collision_layer = 4  # Item layer
	collision_mask = 2   # Player layer

	# Create visual mesh
	_create_mesh()

	# Connect pickup signal
	body_entered.connect(_on_body_entered)

	print("[ResourceItem] Spawned %d x %s" % [amount, item_name])

func _process(delta: float) -> void:
	# Bob up and down
	var time = Time.get_ticks_msec() / 1000.0 + bob_offset
	var bob = sin(time * 2.0) * 0.05  # Reduced bob amount
	if mesh_instance:
		mesh_instance.position.y = 0.3 + bob  # Lower base height

	# Rotate slowly
	rotation.y += delta * 1.0

	# Check lifetime
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - spawn_time > lifetime:
		print("[ResourceItem] %s despawned (lifetime expired)" % item_name)
		queue_free()

func _create_mesh() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	# Create mesh based on item type
	match item_name:
		"wood":
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.05
			mesh.bottom_radius = 0.05
			mesh.height = 0.3
			mesh_instance.mesh = mesh

			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.6, 0.4, 0.2)
			mesh_instance.material_override = mat

		"stone":
			var mesh = SphereMesh.new()
			mesh.radius = 0.15
			mesh_instance.mesh = mesh

			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.5, 0.5, 0.55)
			mesh_instance.material_override = mat

		_:
			# Default cube
			var mesh = BoxMesh.new()
			mesh.size = Vector3(0.2, 0.2, 0.2)
			mesh_instance.mesh = mesh

	mesh_instance.position.y = 0.3  # Start at lower height

	# Add collision shape
	var collision_shape = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.5  # Larger pickup radius
	collision_shape.shape = shape
	add_child(collision_shape)

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player
	if not body.has_method("pickup_item"):
		return

	# Try to give item to player
	body.pickup_item(item_name, amount)

	# Remove item from world
	queue_free()

func set_item_data(item: String, qty: int) -> void:
	item_name = item
	amount = qty

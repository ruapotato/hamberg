extends Area3D
class_name ThrownRock

## ThrownRock - Projectile thrown by Gahnomes
## Simple rock that flies in a direction and damages players on hit

@export var damage: float = 8.0
@export var speed: float = 15.0
@export var lifetime: float = 5.0  # Seconds before auto-despawn
@export var gravity_factor: float = 0.5  # How much gravity affects the rock

var direction: Vector3 = Vector3.FORWARD
var thrower: Node = null  # Reference to the enemy that threw this
var velocity: Vector3 = Vector3.ZERO
var time_alive: float = 0.0

# Visual
var rock_mesh: MeshInstance3D = null

func _ready() -> void:
	# Set up collision
	collision_layer = 0  # Doesn't block anything
	collision_mask = 1 | 2  # Detect world (buildings/terrain) AND players

	# Create visual rock mesh
	_create_rock_mesh()

	# Connect body entered signal
	body_entered.connect(_on_body_entered)

	# Initialize velocity
	velocity = direction * speed

func _create_rock_mesh() -> void:
	rock_mesh = MeshInstance3D.new()

	# Create an irregular rock shape using a squashed/stretched sphere
	var mesh = SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.2
	rock_mesh.mesh = mesh

	# Rock material - gray/brown stone color
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.3, 1)  # Brownish gray
	mat.roughness = 0.9
	rock_mesh.material_override = mat

	# Random rotation for visual variety
	rock_mesh.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	add_child(rock_mesh)

	# Create collision shape
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.15
	collision.shape = shape
	add_child(collision)

func _physics_process(delta: float) -> void:
	time_alive += delta

	# Auto-despawn after lifetime
	if time_alive > lifetime:
		queue_free()
		return

	# Apply gravity to velocity
	velocity.y -= 9.8 * gravity_factor * delta

	# Move the rock
	global_position += velocity * delta

	# Rotate the rock as it flies (tumbling effect)
	if rock_mesh:
		rock_mesh.rotation.x += delta * 10.0
		rock_mesh.rotation.z += delta * 7.0

	# Check if we hit the ground (simple ground check)
	if global_position.y < -10:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	# Don't hit the thrower
	if body == thrower:
		return

	# Don't hit other enemies
	if body.is_in_group("enemies"):
		return

	# Hit a wall/building/terrain - just destroy the rock
	if body.collision_layer & 1:  # World layer
		print("[ThrownRock] Hit wall/building")
		queue_free()
		return

	# Hit a player!
	if body.is_in_group("players"):
		print("[ThrownRock] Hit player: %s" % body.name)

		# LOCAL-FIRST DAMAGE: Only apply damage if this is MY local player
		# Check if the hit player is the local player
		var my_peer_id = multiplayer.get_unique_id()
		var local_player_name = "Player_" + str(my_peer_id)

		if body.name == local_player_name:
			# This is MY player - apply damage locally
			if body.has_method("take_damage"):
				var knockback_dir = velocity.normalized()
				knockback_dir.y = 0.2  # Slight upward knockback
				knockback_dir = knockback_dir.normalized()
				print("[ThrownRock] Dealing %.1f damage to local player" % damage)
				body.take_damage(damage, 0, knockback_dir * 5.0)  # knockback strength

		# Destroy the rock
		queue_free()

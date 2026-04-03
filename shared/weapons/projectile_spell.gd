extends SpellBase
class_name ProjectileSpell
## Projectile-based spells like Fireball, Ice Shard, Magic Missile

# Projectile scene that will be instantiated (loaded dynamically if exists)
var PROJECTILE_BASE_SCENE: PackedScene = null

func _init() -> void:
	if ResourceLoader.exists("res://shared/weapons/projectile_base.tscn"):
		PROJECTILE_BASE_SCENE = load("res://shared/weapons/projectile_base.tscn")


func _execute_spell() -> void:
	if not spell_data:
		return

	# Fire multiple missiles if specified (e.g., Magic Missile)
	var missile_count := spell_data.missile_count
	for i in range(missile_count):
		_spawn_projectile(i, missile_count)

	# TODO: Add AudioManager for impact sound
	# AudioManager.play_sound_3d(spell_data.impact_sound, get_cast_origin(), -3.0)


func _spawn_projectile(index: int = 0, total_count: int = 1) -> void:
	# Create projectile instance
	var projectile: Node3D = _create_projectile_instance()
	if not projectile:
		return

	# Add to scene
	get_tree().current_scene.add_child(projectile)

	# Position at cast point
	var cast_origin := get_cast_origin()
	projectile.global_position = cast_origin

	# Calculate direction with spread for multiple missiles
	var direction := get_cast_direction()
	if total_count > 1:
		direction = _apply_missile_spread(direction, index, total_count)

	# Set projectile properties
	_configure_projectile(projectile, direction)


func _create_projectile_instance() -> Node3D:
	# Try to load custom projectile scene, fallback to base
	var scene_path := "res://shared/weapons/projectile_%s.tscn" % spell_id
	var projectile_instance: Node3D = null

	if ResourceLoader.exists(scene_path):
		var scene := load(scene_path) as PackedScene
		projectile_instance = scene.instantiate()
	else:
		# Use base projectile scene
		if PROJECTILE_BASE_SCENE:
			projectile_instance = PROJECTILE_BASE_SCENE.instantiate()

	return projectile_instance


func _configure_projectile(projectile: Node3D, direction: Vector3) -> void:
	if not projectile or not spell_data:
		return

	# Set basic properties
	projectile.set("damage", base_damage)
	projectile.set("speed", spell_data.projectile_speed)
	projectile.set("lifetime", spell_data.projectile_lifetime)
	projectile.set("direction", direction)
	projectile.set("owner_spell", self)
	projectile.set("owner_player", owner_player)

	# Set homing if applicable
	if spell_data.homing_strength > 0.0:
		projectile.set("homing_strength", spell_data.homing_strength)

	# Set pierce count
	if spell_data.pierce_count > 0:
		projectile.set("pierce_count", spell_data.pierce_count)

	# Set explosion radius
	if spell_data.explosion_radius > 0.0:
		projectile.set("explosion_radius", spell_data.explosion_radius)

	# Set visual properties
	projectile.set("trail_color", spell_data.trail_color)
	projectile.set("glow_intensity", spell_data.glow_intensity)

	# Orient projectile
	if direction != Vector3.ZERO:
		projectile.look_at(projectile.global_position + direction, Vector3.UP)


func _apply_missile_spread(base_direction: Vector3, index: int, total: int) -> Vector3:
	# Spread missiles in a cone pattern
	var spread_angle: float = 15.0  # degrees
	var angle_step: float = spread_angle / max(total - 1, 1)
	var start_angle: float = -spread_angle / 2.0

	var angle: float = start_angle + (angle_step * index)
	var angle_rad: float = deg_to_rad(angle)

	# Get camera up vector for proper rotation
	var camera: Camera3D = null
	if owner_player:
		camera = owner_player.get_node("CameraMount/Camera3D")

	var up_vector := Vector3.UP
	if camera:
		up_vector = camera.global_transform.basis.y

	# Rotate direction around up vector
	var rotated := base_direction.rotated(up_vector, angle_rad)
	return rotated.normalized()


# Alternative method: spawn projectile at target location (for spells like Meteor)
func spawn_projectile_at_position(target_position: Vector3, from_above: bool = false) -> void:
	var projectile: Node3D = _create_projectile_instance()
	if not projectile:
		return

	get_tree().current_scene.add_child(projectile)

	if from_above:
		# Spawn projectile above target (for meteor strikes)
		projectile.global_position = target_position + Vector3(0, 20, 0)
		var direction := Vector3.DOWN
		_configure_projectile(projectile, direction)
	else:
		projectile.global_position = target_position
		var direction := get_cast_direction()
		_configure_projectile(projectile, direction)


# Helper to create a simple projectile manually (if scene doesn't exist)
func create_basic_projectile() -> RigidBody3D:
	var projectile := RigidBody3D.new()
	projectile.name = "Projectile"

	# Add collision shape
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	collision.shape = shape
	projectile.add_child(collision)

	# Add mesh
	var mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.2
	sphere_mesh.height = 0.4
	mesh_instance.mesh = sphere_mesh
	projectile.add_child(mesh_instance)

	# Add light
	var light := OmniLight3D.new()
	light.omni_range = 5.0
	light.light_energy = spell_data.glow_intensity if spell_data else 2.0
	light.light_color = spell_data.trail_color if spell_data else Color.WHITE
	projectile.add_child(light)

	# Setup physics
	projectile.gravity_scale = 0.0
	projectile.lock_rotation = true
	projectile.collision_layer = 0b10000  # Projectile layer
	projectile.collision_mask = 0b1101  # World, enemy, interactable

	return projectile

extends RigidBody3D
class_name SpellProjectile
## Base projectile for spell projectiles (fireball, ice shard, etc)

@export var damage: int = 50
@export var speed: float = 40.0
@export var lifetime: float = 5.0
@export var direction: Vector3 = Vector3.FORWARD

# Homing
@export var homing_strength: float = 0.0
var homing_target: Node3D = null

# Piercing
@export var pierce_count: int = 0
var enemies_hit: Array[Node] = []

# Explosion
@export var explosion_radius: float = 0.0

# Visual
@export var trail_color: Color = Color.WHITE
@export var glow_intensity: float = 2.0

# References
var owner_spell: SpellBase = null
var owner_player: Node = null

# State
var has_exploded: bool = false
var time_alive: float = 0.0

# Components
var mesh_instance: MeshInstance3D = null
var light_source: OmniLight3D = null
var trail_particles: GPUParticles3D = null
var collision_shape: CollisionShape3D = null


func _ready() -> void:
	add_to_group("player_spells")
	add_to_group("player_projectiles")

	_setup_projectile()
	_setup_physics()

	# Set initial velocity
	linear_velocity = direction.normalized() * speed

	# Auto-destroy after lifetime
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_expired)


func _setup_projectile() -> void:
	# Ensure we have components
	if not has_node("MeshInstance3D"):
		_create_default_mesh()

	if not has_node("OmniLight3D"):
		_create_default_light()

	if not has_node("CollisionShape3D"):
		_create_default_collision()

	mesh_instance = get_node_or_null("MeshInstance3D")
	light_source = get_node_or_null("OmniLight3D")
	collision_shape = get_node_or_null("CollisionShape3D")

	# Apply visual properties
	if light_source:
		light_source.light_color = trail_color
		light_source.light_energy = glow_intensity

	if mesh_instance and mesh_instance.mesh:
		var material := StandardMaterial3D.new()
		material.albedo_color = trail_color
		material.emission_enabled = true
		material.emission = trail_color
		material.emission_energy_multiplier = glow_intensity
		mesh_instance.material_override = material


func _create_default_mesh() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	mesh_instance.mesh = sphere
	add_child(mesh_instance)


func _create_default_light() -> void:
	light_source = OmniLight3D.new()
	light_source.name = "OmniLight3D"
	light_source.omni_range = 5.0
	light_source.light_energy = glow_intensity
	light_source.light_color = trail_color
	add_child(light_source)


func _create_default_collision() -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	collision_shape.shape = shape
	add_child(collision_shape)


func _setup_physics() -> void:
	gravity_scale = 0.0
	lock_rotation = true
	collision_layer = 0b10000  # Projectile layer
	collision_mask = 0b1101  # World, enemy, interactable
	contact_monitor = true
	max_contacts_reported = 5

	# Connect collision signal
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	time_alive += delta

	# Homing behavior
	if homing_strength > 0.0 and homing_target:
		_apply_homing(delta)

	# Orient to movement direction
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity.normalized(), Vector3.UP)


func _apply_homing(delta: float) -> void:
	if not is_instance_valid(homing_target):
		homing_target = null
		return

	# Calculate direction to target
	var to_target := (homing_target.global_position - global_position).normalized()

	# Blend current direction with target direction
	var new_direction := linear_velocity.normalized().lerp(to_target, homing_strength * delta)
	linear_velocity = new_direction * speed


func find_homing_target() -> void:
	if not owner_player:
		return

	# Find nearest enemy
	var camera: Camera3D = owner_player.get_node_or_null("CameraMount/Camera3D")
	if not camera:
		return

	var forward := -camera.global_transform.basis.z
	var best_target: Node3D = null
	var best_score := -1.0

	# Get enemies in range
	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 30.0

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 0b100  # Enemy layer

	var results := space_state.intersect_shape(query)

	for result in results:
		var enemy: Node = result.collider
		if not enemy or not enemy.has_method("take_damage"):
			continue

		# Calculate score based on distance and angle
		var to_enemy: Vector3 = (enemy.global_position - global_position).normalized()
		var distance: float = global_position.distance_to(enemy.global_position)
		var angle: float = forward.dot(to_enemy)

		var score: float = angle / (distance * 0.1 + 1.0)

		if score > best_score:
			best_score = score
			best_target = enemy

	homing_target = best_target


func _on_body_entered(body: Node) -> void:
	if has_exploded:
		return

	# Ignore owner player
	if body == owner_player:
		return

	# Check if it's an enemy
	var is_enemy := false
	var enemy_node: Node = null

	if body.has_method("take_damage"):
		is_enemy = true
		enemy_node = body
	elif body.get_parent() and body.get_parent().has_method("take_damage"):
		is_enemy = true
		enemy_node = body.get_parent()

	if is_enemy and enemy_node:
		# Check if we already hit this enemy
		if enemy_node in enemies_hit:
			return

		enemies_hit.append(enemy_node)

		# Deal damage - pass hit position for headshot detection
		if owner_spell:
			owner_spell.apply_damage_to_enemy(enemy_node, damage, global_position)
		else:
			enemy_node.take_damage(damage, owner_player, global_position)

		# Spawn hit effect
		_spawn_hit_effect()

		# Check if we should pierce
		if pierce_count > 0 and enemies_hit.size() <= pierce_count:
			# Continue through enemy
			return
		else:
			# Explode or destroy
			if explosion_radius > 0.0:
				_explode()
			else:
				_destroy()
			return

	# Check if we hit a destructible tree
	if body.is_in_group("destructible_trees"):
		if owner_spell:
			owner_spell.damage_destructible(body, damage, global_position)
		_spawn_hit_effect()
		if explosion_radius > 0.0:
			_explode()
		else:
			_destroy()
		return

	# Hit world or non-enemy
	if explosion_radius > 0.0:
		_explode()
	else:
		_destroy()


func _explode() -> void:
	if has_exploded:
		return

	has_exploded = true

	# Find enemies in explosion radius
	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = explosion_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 0b100  # Enemy layer

	var results := space_state.intersect_shape(query)

	# Damage all enemies in radius
	for result in results:
		var enemy: Node = result.collider
		if enemy and enemy.has_method("take_damage"):
			# For explosions, hit center mass (not headshot)
			var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.9, 0)
			if owner_spell:
				owner_spell.apply_damage_to_enemy(enemy, damage, hit_pos)
			else:
				enemy.take_damage(damage, owner_player, hit_pos)

	# Spawn explosion effect
	_spawn_explosion_effect()

	# Destroy projectile
	_destroy()


func _spawn_hit_effect() -> void:
	# Simple hit particles
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 10
	particles.lifetime = 0.3
	particles.explosiveness = 1.0

	get_tree().current_scene.add_child(particles)
	particles.global_position = global_position

	# Auto-remove
	await get_tree().create_timer(particles.lifetime + 0.1).timeout
	if is_instance_valid(particles):
		particles.queue_free()


func _spawn_explosion_effect() -> void:
	# Create explosion visual
	var explosion := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = explosion_radius
	sphere.height = explosion_radius * 2.0
	explosion.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = trail_color
	material.emission_enabled = true
	material.emission = trail_color
	material.emission_energy_multiplier = glow_intensity * 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material_override = material

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position

	# Animate explosion
	var tween := create_tween()
	tween.tween_property(explosion, "scale", Vector3.ONE * 1.5, 0.3)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(explosion.queue_free)

	# TODO: Add AudioManager for explosion sound
	# if owner_spell and owner_spell.spell_data:
	# 	AudioManager.play_sound_3d(owner_spell.spell_data.impact_sound, global_position, 0.0)


func _on_lifetime_expired() -> void:
	if not has_exploded:
		_destroy()


func _destroy() -> void:
	queue_free()


func get_damage() -> float:
	return damage

extends SpellBase
class_name AOESpell
## Area of Effect spells like Meteor Storm, Blizzard, Frost Nova, Inferno

# AOE visual components
var aoe_area: Area3D = null
var aoe_mesh: MeshInstance3D = null
var aoe_particles: GPUParticles3D = null
var aoe_light: OmniLight3D = null

# AOE state
var is_aoe_active: bool = false
var aoe_center: Vector3 = Vector3.ZERO
var damage_tick_timer: float = 0.0
var aoe_duration_timer: float = 0.0

# Meteor storm state
var meteor_spawn_timer: float = 0.0
var meteors_spawned: int = 0


func _ready() -> void:
	super._ready()
	_setup_aoe_area()


func _process(delta: float) -> void:
	if is_aoe_active:
		_update_aoe(delta)


func _setup_aoe_area() -> void:
	# Create Area3D for detecting enemies
	aoe_area = Area3D.new()
	aoe_area.name = "AOEArea"
	aoe_area.collision_layer = 0
	aoe_area.collision_mask = 0b100  # Enemy layer
	aoe_area.monitoring = false
	add_child(aoe_area)

	# Add collision shape
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 5.0
	collision.shape = sphere
	aoe_area.add_child(collision)

	# Create visual mesh (ground circle)
	aoe_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 5.0
	cylinder.bottom_radius = 5.0
	cylinder.height = 0.1
	aoe_mesh.mesh = cylinder
	aoe_mesh.visible = false

	# Create material
	var material := StandardMaterial3D.new()
	material.albedo_color = spell_data.trail_color if spell_data else Color.WHITE
	material.emission_enabled = true
	material.emission = spell_data.trail_color if spell_data else Color.WHITE
	material.emission_energy_multiplier = spell_data.glow_intensity if spell_data else 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.4
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	aoe_mesh.material_override = material

	add_child(aoe_mesh)

	# Create AOE light
	aoe_light = OmniLight3D.new()
	aoe_light.omni_range = 10.0
	aoe_light.light_energy = spell_data.glow_intensity if spell_data else 2.0
	aoe_light.light_color = spell_data.trail_color if spell_data else Color.WHITE
	aoe_light.visible = false
	add_child(aoe_light)


func _execute_spell() -> void:
	if not spell_data:
		return

	# Determine AOE center
	var hit_result := raycast_from_camera(100.0)
	if hit_result.is_empty():
		# If no ground hit, place at feet
		aoe_center = owner_player.global_position if owner_player else global_position
	else:
		aoe_center = hit_result.position

	# Special handling for different AOE types
	match spell_id:
		"frost_nova":
			# Frost Nova centers on player
			aoe_center = owner_player.global_position if owner_player else global_position
			_start_instant_aoe()

		"meteor_storm":
			_start_meteor_storm()

		"flame_wave":
			_start_expanding_wave()

		_:
			# Default: standard AOE
			_start_standard_aoe()


func _start_standard_aoe() -> void:
	is_aoe_active = true
	aoe_duration_timer = 0.0
	damage_tick_timer = 0.0

	# Setup area
	var collision := aoe_area.get_child(0) as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = spell_data.aoe_radius

	aoe_area.global_position = aoe_center
	aoe_area.monitoring = true

	# Setup visuals
	aoe_mesh.global_position = aoe_center
	var cylinder := aoe_mesh.mesh as CylinderMesh
	if cylinder:
		cylinder.top_radius = spell_data.aoe_radius
		cylinder.bottom_radius = spell_data.aoe_radius
	aoe_mesh.visible = true

	aoe_light.global_position = aoe_center
	aoe_light.omni_range = spell_data.aoe_radius * 2.0
	aoe_light.visible = true

	# TODO: Add AudioManager for impact sound
	# AudioManager.play_sound_3d(spell_data.impact_sound, aoe_center, 0.0)


func _start_instant_aoe() -> void:
	# For instant AOEs like Frost Nova - hit once then end
	aoe_center = owner_player.global_position if owner_player else global_position

	# Setup area temporarily
	var collision := aoe_area.get_child(0) as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = spell_data.aoe_radius

	aoe_area.global_position = aoe_center
	aoe_area.monitoring = true

	# Get enemies and damage them (hit center mass for AOE)
	var enemies := _get_enemies_in_aoe()
	for enemy in enemies:
		var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.9, 0)
		apply_damage_to_enemy(enemy, base_damage, hit_pos)

	# Visual effect
	_spawn_nova_effect()

	# TODO: Add AudioManager for impact sound
	# AudioManager.play_sound_3d(spell_data.impact_sound, aoe_center, 0.0)

	# Clean up
	aoe_area.monitoring = false


func _start_meteor_storm() -> void:
	is_aoe_active = true
	aoe_duration_timer = 0.0
	meteors_spawned = 0
	meteor_spawn_timer = 0.0

	# Setup area for tracking
	var collision := aoe_area.get_child(0) as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = spell_data.aoe_radius

	aoe_area.global_position = aoe_center

	# Show AOE indicator
	aoe_mesh.global_position = aoe_center
	var cylinder := aoe_mesh.mesh as CylinderMesh
	if cylinder:
		cylinder.top_radius = spell_data.aoe_radius
		cylinder.bottom_radius = spell_data.aoe_radius
	aoe_mesh.visible = true

	# TODO: Add AudioManager for cast sound
	# AudioManager.play_sound_3d(spell_data.cast_sound, aoe_center, 0.0)


func _start_expanding_wave() -> void:
	# Flame Wave expands outward from player
	aoe_center = owner_player.global_position if owner_player else global_position

	is_aoe_active = true
	aoe_duration_timer = 0.0

	# Wave will expand over duration
	var collision := aoe_area.get_child(0) as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = 0.5  # Start small

	aoe_area.global_position = aoe_center
	aoe_area.monitoring = true

	aoe_mesh.global_position = aoe_center
	aoe_mesh.visible = true

	# TODO: Add AudioManager for impact sound
	# AudioManager.play_sound_3d(spell_data.impact_sound, aoe_center, 0.0)


func _update_aoe(delta: float) -> void:
	aoe_duration_timer += delta

	# Check if AOE should end
	if aoe_duration_timer >= spell_data.aoe_duration:
		_end_aoe()
		return

	# Update based on spell type
	if spell_id == "meteor_storm":
		_update_meteor_storm(delta)
	elif spell_id == "flame_wave":
		_update_flame_wave(delta)
	else:
		_update_standard_aoe(delta)


func _update_standard_aoe(delta: float) -> void:
	# Apply damage over time
	damage_tick_timer += delta
	if damage_tick_timer >= spell_data.tick_interval:
		damage_tick_timer = 0.0

		var enemies := _get_enemies_in_aoe()
		for enemy in enemies:
			var damage := spell_data.damage_per_tick if spell_data.damage_per_tick > 0 else base_damage
			var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.9, 0)
			apply_damage_to_enemy(enemy, damage, hit_pos)


func _update_meteor_storm(delta: float) -> void:
	meteor_spawn_timer += delta

	# Spawn meteors at intervals
	if meteor_spawn_timer >= spell_data.meteor_interval and meteors_spawned < spell_data.meteor_count:
		meteor_spawn_timer = 0.0
		_spawn_meteor()
		meteors_spawned += 1


func _update_flame_wave(delta: float) -> void:
	# Expand the wave
	var progress := aoe_duration_timer / spell_data.aoe_duration
	var current_radius := spell_data.aoe_radius * progress

	# Update collision
	var collision := aoe_area.get_child(0) as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		collision.shape.radius = current_radius

	# Update visual
	var cylinder := aoe_mesh.mesh as CylinderMesh
	if cylinder:
		cylinder.top_radius = current_radius
		cylinder.bottom_radius = current_radius

	# Apply damage (continuous)
	damage_tick_timer += delta
	if damage_tick_timer >= 0.2:  # Faster tick rate for wave
		damage_tick_timer = 0.0

		var enemies := _get_enemies_in_aoe()
		for enemy in enemies:
			var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.9, 0)
			apply_damage_to_enemy(enemy, base_damage, hit_pos)

		# Apply knockback
		if spell_data.knockback_force > 0.0:
			for enemy in enemies:
				if enemy.has_method("apply_knockback"):
					var direction: Vector3 = (enemy.global_position - aoe_center).normalized()
					enemy.apply_knockback(direction * spell_data.knockback_force * delta)


func _spawn_meteor() -> void:
	# Random position within AOE radius
	var random_offset := Vector2(
		randf_range(-spell_data.aoe_radius, spell_data.aoe_radius),
		randf_range(-spell_data.aoe_radius, spell_data.aoe_radius)
	)

	var meteor_target := aoe_center + Vector3(random_offset.x, 0, random_offset.y)

	# Create meteor projectile
	var meteor := _create_meteor_projectile()
	if not meteor:
		return

	get_tree().current_scene.add_child(meteor)

	# Spawn above target
	meteor.global_position = meteor_target + Vector3(0, 20, 0)

	# Set downward velocity
	if meteor is RigidBody3D:
		meteor.linear_velocity = Vector3(0, -30, 0)

	# Meteor explodes on impact
	meteor.set("explosion_radius", spell_data.explosion_radius)
	meteor.set("damage", base_damage)
	meteor.set("owner_spell", self)


func _create_meteor_projectile() -> Node3D:
	# Try to load meteor scene
	var scene_path := "res://shared/weapons/meteor.tscn"
	if ResourceLoader.exists(scene_path):
		var scene := load(scene_path) as PackedScene
		return scene.instantiate()

	# Create basic meteor
	var meteor := RigidBody3D.new()
	meteor.name = "Meteor"

	# Collision
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	collision.shape = shape
	meteor.add_child(collision)

	# Mesh
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mesh_instance.mesh = sphere

	# Material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.3, 0.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.0)
	material.emission_energy_multiplier = 3.0
	mesh_instance.material_override = material

	meteor.add_child(mesh_instance)

	# Light
	var light := OmniLight3D.new()
	light.omni_range = 8.0
	light.light_energy = 3.0
	light.light_color = Color(1.0, 0.4, 0.0)
	meteor.add_child(light)

	# Trail particles
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.amount = 20
	particles.lifetime = 0.5
	meteor.add_child(particles)

	meteor.gravity_scale = 3.0
	meteor.collision_layer = 0b10000
	meteor.collision_mask = 0b1101

	return meteor


func _spawn_nova_effect() -> void:
	# Create expanding ring effect
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = spell_data.aoe_radius * 0.8
	torus.outer_radius = spell_data.aoe_radius
	ring.mesh = torus

	var material := StandardMaterial3D.new()
	material.albedo_color = spell_data.trail_color if spell_data else Color.WHITE
	material.emission_enabled = true
	material.emission = spell_data.trail_color if spell_data else Color.WHITE
	material.emission_energy_multiplier = spell_data.glow_intensity if spell_data else 3.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material

	get_tree().current_scene.add_child(ring)
	ring.global_position = aoe_center

	# Animate the ring
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(ring.queue_free)


func _get_enemies_in_aoe() -> Array[Node]:
	if not aoe_area:
		return []

	var enemies: Array[Node] = []
	var bodies := aoe_area.get_overlapping_bodies()
	var areas := aoe_area.get_overlapping_areas()

	# Check bodies
	for body in bodies:
		if body and body.has_method("take_damage"):
			enemies.append(body)

	# Check areas (for enemy hitboxes)
	for area in areas:
		var parent := area.get_parent()
		if parent and parent.has_method("take_damage"):
			if parent not in enemies:
				enemies.append(parent)

	return enemies


func _end_aoe() -> void:
	is_aoe_active = false
	aoe_area.monitoring = false
	aoe_mesh.visible = false
	aoe_light.visible = false
	meteors_spawned = 0


# Healing Rain specific functionality
func _apply_healing() -> void:
	if not spell_data or spell_data.heal_per_tick <= 0:
		return

	# Find allies in AOE (including owner player)
	var allies: Array[Node] = []

	if owner_player and aoe_center.distance_to(owner_player.global_position) <= spell_data.aoe_radius:
		allies.append(owner_player)

	# TODO: Add other players/allies detection

	# Heal allies
	for ally in allies:
		if ally.has_method("heal"):
			ally.heal(spell_data.heal_per_tick)

		# Bonus mana regen
		if spell_data.mana_regen_bonus > 0:
			if ally.has_method("add_mana"):
				ally.add_mana(spell_data.mana_regen_bonus)


# Time Warp specific functionality
func _apply_time_warp_effects() -> void:
	if not spell_data:
		return

	# Slow enemies
	var enemies := _get_enemies_in_aoe()
	for enemy in enemies:
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(spell_data.slow_percent, spell_data.aoe_duration)

	# Speed up player
	if spell_data.player_speed_bonus > 0.0 and owner_player:
		if owner_player.has_method("apply_speed_buff"):
			owner_player.apply_speed_buff(spell_data.player_speed_bonus, spell_data.aoe_duration)

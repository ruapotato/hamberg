extends SpellBase
class_name BeamSpell
## Continuous beam spells like Chain Lightning, Soul Drain

# Beam visual components
var beam_mesh: MeshInstance3D = null
var beam_particles: GPUParticles3D = null
var beam_light: OmniLight3D = null

# Beam state
var is_beam_active: bool = false
var beam_target: Node = null
var beam_hit_position: Vector3 = Vector3.ZERO
var damage_tick_timer: float = 0.0

# Chain lightning state
var chained_targets: Array[Node] = []


func _ready() -> void:
	super._ready()
	_setup_beam_visuals()


func _process(delta: float) -> void:
	if is_beam_active:
		_update_beam(delta)


func _setup_beam_visuals() -> void:
	# Create beam mesh
	beam_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.1
	cylinder.bottom_radius = 0.1
	cylinder.height = 1.0
	beam_mesh.mesh = cylinder
	beam_mesh.visible = false

	# Create beam material
	var material := StandardMaterial3D.new()
	material.albedo_color = spell_data.trail_color if spell_data else Color.WHITE
	material.emission_enabled = true
	material.emission = spell_data.trail_color if spell_data else Color.WHITE
	material.emission_energy_multiplier = spell_data.glow_intensity if spell_data else 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.7
	beam_mesh.material_override = material

	add_child(beam_mesh)

	# Create beam light
	beam_light = OmniLight3D.new()
	beam_light.omni_range = 5.0
	beam_light.light_energy = spell_data.glow_intensity if spell_data else 2.0
	beam_light.light_color = spell_data.trail_color if spell_data else Color.WHITE
	beam_light.visible = false
	add_child(beam_light)


func _execute_spell() -> void:
	if not spell_data:
		return

	# Start the beam
	_start_beam()

	# Create a timer for beam duration
	var duration_timer := get_tree().create_timer(spell_data.beam_duration)
	duration_timer.timeout.connect(_stop_beam)


func _start_beam() -> void:
	is_beam_active = true
	beam_mesh.visible = true
	beam_light.visible = true
	chained_targets.clear()
	damage_tick_timer = 0.0

	# TODO: Add AudioManager for beam sound
	# if spell_data:
	# 	AudioManager.play_sound_3d(spell_data.impact_sound, global_position, 0.0)


func _stop_beam() -> void:
	is_beam_active = false
	beam_mesh.visible = false
	beam_light.visible = false
	beam_target = null
	chained_targets.clear()


func _update_beam(delta: float) -> void:
	# Raycast to find target
	var hit_result := raycast_from_camera(spell_data.beam_range)

	if hit_result.is_empty():
		# No hit, just point forward
		var cast_origin := get_cast_origin()
		var direction := get_cast_direction()
		beam_hit_position = cast_origin + direction * spell_data.beam_range
		beam_target = null
	else:
		beam_hit_position = hit_result.position
		var collider = hit_result.collider

		# Find enemy node
		if collider and collider.has_method("take_damage"):
			beam_target = collider
		elif collider and collider.get_parent() and collider.get_parent().has_method("take_damage"):
			beam_target = collider.get_parent()
		elif collider and collider.is_in_group("destructible_trees"):
			# Hit a tree - damage it
			beam_target = null
			damage_tick_timer += delta
			if damage_tick_timer >= spell_data.tick_interval:
				damage_tick_timer = 0.0
				damage_destructible(collider, spell_data.damage_per_tick if spell_data else base_damage, beam_hit_position)
		else:
			beam_target = null

	# Update beam visual
	_update_beam_visual()

	# Apply damage over time
	if beam_target:
		damage_tick_timer += delta
		if damage_tick_timer >= spell_data.tick_interval:
			damage_tick_timer = 0.0
			_apply_beam_damage()

			# Chain lightning effect
			if spell_data.chain_count > 0:
				_chain_to_nearby_enemies()


func _update_beam_visual() -> void:
	var cast_origin := get_cast_origin()
	var beam_direction := (beam_hit_position - cast_origin).normalized()
	var beam_length := cast_origin.distance_to(beam_hit_position)

	# Position beam at midpoint
	var midpoint := cast_origin + beam_direction * (beam_length / 2.0)
	beam_mesh.global_position = midpoint

	# Scale beam to length
	var scale_factor := beam_length
	beam_mesh.scale = Vector3(
		spell_data.beam_width if spell_data else 0.1,
		scale_factor,
		spell_data.beam_width if spell_data else 0.1
	)

	# Rotate beam to point at target
	if beam_direction != Vector3.ZERO:
		beam_mesh.look_at(beam_hit_position, Vector3.UP)
		beam_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	# Update light position
	beam_light.global_position = beam_hit_position


func _apply_beam_damage() -> void:
	if not beam_target:
		return

	var damage := spell_data.damage_per_tick if spell_data else base_damage
	apply_damage_to_enemy(beam_target, damage, beam_hit_position)

	# Create hit effect
	_spawn_beam_hit_effect(beam_hit_position)


func _chain_to_nearby_enemies() -> void:
	if not spell_data or spell_data.chain_count <= 0:
		return

	if not beam_target:
		return

	# Don't chain from the same target multiple times in quick succession
	if beam_target in chained_targets:
		return

	chained_targets.append(beam_target)

	# Find nearby enemies
	var nearby_enemies := get_enemies_in_radius(beam_target.global_position, spell_data.chain_range)

	var chained := 0
	for enemy in nearby_enemies:
		if enemy == beam_target:
			continue

		if enemy in chained_targets:
			continue

		if chained >= spell_data.chain_count:
			break

		# Chain to this enemy
		_chain_lightning_to(beam_target.global_position, enemy)
		chained += 1


func _chain_lightning_to(from_position: Vector3, target_enemy: Node) -> void:
	if not target_enemy:
		return

	# Calculate damage with falloff
	var chain_damage := spell_data.damage_per_tick
	if spell_data.chain_damage_falloff < 1.0:
		chain_damage = int(chain_damage * spell_data.chain_damage_falloff)

	# Apply damage - hit enemy center
	apply_damage_to_enemy(target_enemy, chain_damage, target_enemy.global_position + Vector3(0, 1.0, 0))

	# Create chain visual
	_spawn_chain_visual(from_position, target_enemy.global_position)

	# TODO: Add AudioManager for chain sound
	# AudioManager.play_sound_3d("lightning_chain", target_enemy.global_position, -5.0)


func _spawn_chain_visual(from: Vector3, to: Vector3) -> void:
	# Create a temporary beam between the two points
	var chain_beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = 1.0
	chain_beam.mesh = cylinder

	# Material
	var material := StandardMaterial3D.new()
	material.albedo_color = spell_data.trail_color if spell_data else Color(0.7, 0.7, 1.0)
	material.emission_enabled = true
	material.emission = spell_data.trail_color if spell_data else Color(0.7, 0.7, 1.0)
	material.emission_energy_multiplier = 3.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.8
	chain_beam.material_override = material

	# Add to scene
	get_tree().current_scene.add_child(chain_beam)

	# Position and scale
	var direction := (to - from).normalized()
	var length := from.distance_to(to)
	var midpoint := from + direction * (length / 2.0)

	chain_beam.global_position = midpoint
	chain_beam.scale = Vector3(0.05, length, 0.05)

	if direction != Vector3.ZERO:
		chain_beam.look_at(to, Vector3.UP)
		chain_beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	# Remove after short delay
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(chain_beam):
		chain_beam.queue_free()


func _spawn_beam_hit_effect(position: Vector3) -> void:
	# Create simple particle effect at hit point
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 8
	particles.lifetime = 0.3
	particles.explosiveness = 1.0

	# Add to scene
	get_tree().current_scene.add_child(particles)
	particles.global_position = position

	# Remove after lifetime
	await get_tree().create_timer(particles.lifetime + 0.1).timeout
	if is_instance_valid(particles):
		particles.queue_free()


# Soul Drain specific functionality
func _apply_soul_drain_healing() -> void:
	if not spell_data or not beam_target:
		return

	if spell_data.lifesteal_percent > 0.0 and owner_player:
		var heal_amount := int(spell_data.damage_per_tick * spell_data.lifesteal_percent)
		if owner_player.has_method("heal"):
			owner_player.heal(heal_amount)

	if spell_data.mana_steal_percent > 0.0:
		var mana_amount := int(spell_data.damage_per_tick * spell_data.mana_steal_percent)
		add_mana(mana_amount)

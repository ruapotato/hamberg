extends Projectile

## Thorn Shot - Arcing nature projectile that spawns a brief poison patch on impact

@export var gravity_strength: float = 12.0

func _physics_process(delta: float) -> void:
	if has_hit:
		return
	velocity.y -= gravity_strength * delta
	position += velocity * delta

	if velocity.length() > 0.1:
		var look_target := position + velocity.normalized()
		if position.distance_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)

func _hit() -> void:
	has_hit = true
	velocity = Vector3.ZERO
	SoundManager.play_sound_varied("magic_hit", global_position, 0.0, 0.15)

	# Spawn brief poison patch
	var fire_area_scene: PackedScene = load("res://shared/effects/fire_area.tscn")
	if fire_area_scene:
		var patch: Node3D = fire_area_scene.instantiate()
		patch.radius = 2.0
		patch.damage = damage * 0.3
		patch.duration = 3.0
		get_tree().root.add_child(patch)
		patch.global_position = global_position

		# Tint green
		var particles: GPUParticles3D = patch.get_node_or_null("GPUParticles3D")
		if particles and particles.process_material:
			particles.process_material = particles.process_material.duplicate()
			(particles.process_material as ParticleProcessMaterial).color = Color(0.0, 1.0, 0.42, 0.8)
		var light: OmniLight3D = patch.get_node_or_null("GroundGlow")
		if light:
			light.light_color = Color(0.0, 1.0, 0.42)

	await get_tree().create_timer(0.1).timeout
	queue_free()

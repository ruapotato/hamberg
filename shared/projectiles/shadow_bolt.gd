extends Projectile

## Shadow Bolt - Slow, heavy dark projectile with high damage
## Larger visual, ominous glow

func _physics_process(delta: float) -> void:
	if has_hit:
		return
	position += velocity * delta

func _hit() -> void:
	has_hit = true
	velocity = Vector3.ZERO
	SoundManager.play_sound_varied("magic_hit", global_position, -3.0, 0.2)

	# Heal shooter for 20% of damage on hit
	var shooter: Object = instance_from_id(owner_id)
	if shooter and "health" in shooter and "player_food" in shooter:
		var max_hp: float = shooter.player_food.get_max_health() if shooter.player_food else 50.0
		shooter.health = min(shooter.health + damage * 0.2, max_hp)

	await get_tree().create_timer(0.1).timeout
	queue_free()

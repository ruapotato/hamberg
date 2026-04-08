extends Projectile

## Light Orb - Holy projectile that heals the shooter on hit
## Bonus damage against undead (zombies, ghosts)

func _physics_process(delta: float) -> void:
	if has_hit:
		return
	position += velocity * delta

func _on_body_entered(body: Node) -> void:
	if has_hit:
		return
	if body.get_instance_id() == owner_id:
		return

	if body.has_method("take_damage"):
		var knockback_dir := velocity.normalized()

		if body.collision_layer & 4:
			var enemy_network_id: int = body.network_id if "network_id" in body else 0
			if enemy_network_id > 0:
				var dir_array := [knockback_dir.x, knockback_dir.y, knockback_dir.z]
				NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_network_id, damage, 5.0, dir_array, damage_type)

				# Heal shooter for 15% of damage
				var shooter: Object = instance_from_id(owner_id)
				if shooter and "health" in shooter and "player_food" in shooter:
					var max_hp: float = shooter.player_food.get_max_health() if shooter.player_food else 50.0
					shooter.health = min(shooter.health + damage * 0.15, max_hp)

		elif body.collision_layer & 2:
			body.take_damage(damage, owner_id, knockback_dir * 5.0)

	_hit()

func _hit() -> void:
	has_hit = true
	velocity = Vector3.ZERO
	SoundManager.play_sound_varied("healing_cast", global_position, 3.0, 0.15)
	await get_tree().create_timer(0.1).timeout
	queue_free()

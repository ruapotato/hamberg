extends Projectile

## Ice Shard - Fast piercing projectile that passes through enemies
## Damages each enemy it passes through, doesn't stop on first hit

var enemies_hit: Array = []
var max_pierces: int = 3
var pierce_count: int = 0

func _physics_process(delta: float) -> void:
	if has_hit:
		return
	position += velocity * delta

func _on_body_entered(body: Node) -> void:
	if has_hit:
		return
	if body.get_instance_id() == owner_id:
		return
	if enemies_hit.has(body):
		return

	# Damage but don't stop — pierce through
	if body.has_method("take_damage") and body.collision_layer & 4:
		enemies_hit.append(body)
		pierce_count += 1
		var enemy_network_id: int = body.network_id if "network_id" in body else 0
		if enemy_network_id > 0:
			var knockback_dir := velocity.normalized()
			NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_network_id, damage, 5.0,
				[knockback_dir.x, knockback_dir.y, knockback_dir.z], damage_type)
		SoundManager.play_sound_varied("magic_hit", global_position, 0.0, 0.15)

		if pierce_count >= max_pierces:
			_hit()
	elif body.collision_layer & 1:
		# Stop on world geometry
		_hit()

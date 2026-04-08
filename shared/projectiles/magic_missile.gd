extends Projectile

## Magic Missile - Straight-flying arcane projectile used by all non-fire wands
## No gravity, just flies in a line and damages on hit

func _physics_process(delta: float) -> void:
	if has_hit:
		return
	position += velocity * delta

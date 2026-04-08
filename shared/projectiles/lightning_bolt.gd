extends Projectile

## Lightning Bolt - Extremely fast, thin electric projectile
## Travels at high speed in a straight line

func _physics_process(delta: float) -> void:
	if has_hit:
		return
	position += velocity * delta

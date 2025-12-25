extends Node3D

## CriticalHitEffect - Dramatic particle burst for critical hits
## Bigger, more particles, with golden sparks to indicate crit
## Auto-destroys after particles finish

func _ready() -> void:
	# Start all particle emitters
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = true

	# Destroy after longest particle lifetime + buffer
	await get_tree().create_timer(1.2).timeout
	queue_free()

## Set the hit direction for directional particle emission
func set_hit_direction(direction: Vector3) -> void:
	# Rotate particles to spray in hit direction
	if direction.length() > 0.1:
		look_at(global_position + direction, Vector3.UP)

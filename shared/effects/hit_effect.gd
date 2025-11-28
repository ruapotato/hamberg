extends Node3D

## HitEffect - Burst particle effect when player is hit
## Auto-destroys after particles finish

func _ready() -> void:
	var particles = $GPUParticles3D
	particles.emitting = true
	# Destroy after particles finish
	await get_tree().create_timer(particles.lifetime + 0.2).timeout
	queue_free()

extends Projectile

## Arrow - Physical projectile affected by gravity, sticks where it lands

@export var gravity_strength: float = 0.02  # Gravity strength
@export var speed_multiplier: float = 1.0
@export var stick_duration: float = 10.0  # How long arrow stays stuck before despawning

var initial_direction: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if has_hit:
		return

	# Apply gravity to velocity (arrows arc downward)
	velocity.y -= gravity_strength * delta

	# Move projectile
	position += velocity * delta

	# Rotate to face direction of travel (follow the arc)
	if velocity.length() > 0.1:
		var look_target = position + velocity.normalized()
		if position.distance_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)

func setup(start_pos: Vector3, direction: Vector3, speed: float, dmg: float, shooter_id: int, dmg_type: int = -1) -> void:
	"""Initialize the arrow - shoots where player is aiming, gravity arcs it down"""
	position = start_pos

	# Shoot exactly in the direction the player is aiming
	velocity = direction.normalized() * speed * speed_multiplier
	initial_direction = direction.normalized()
	damage = dmg
	damage_type = dmg_type
	owner_id = shooter_id

	# Initial rotation
	if velocity.length() > 0.01:
		var target = position + velocity.normalized()
		if position.distance_to(target) > 0.01:
			look_at(target, Vector3.UP)

func _hit() -> void:
	"""Called when arrow hits something - stick in place then despawn"""
	has_hit = true
	velocity = Vector3.ZERO

	# Disable collision so it doesn't keep hitting things
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	# Arrow sticks where it lands, then despawns
	await get_tree().create_timer(stick_duration).timeout
	queue_free()

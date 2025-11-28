extends Area3D
class_name Projectile

## Projectile - Base class for all projectiles (arrows, fireballs, etc.)
## Moves in a direction and damages enemies/objects on hit

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var owner_id: int = -1  # ID of the player who fired this
var has_hit: bool = false

@onready var lifetime_timer: Timer = $Lifetime

func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if lifetime_timer:
		lifetime_timer.timeout.connect(_on_lifetime_timeout)

func _physics_process(delta: float) -> void:
	if has_hit:
		return

	# Move projectile
	position += velocity * delta

func setup(start_pos: Vector3, direction: Vector3, speed: float, dmg: float, shooter_id: int) -> void:
	"""Initialize the projectile with starting parameters"""
	position = start_pos
	velocity = direction.normalized() * speed
	damage = dmg
	owner_id = shooter_id

	# Rotate to face direction of travel
	if velocity.length() > 0.01:
		var target = position + velocity.normalized()
		# Only look_at if the target is different from current position
		if position.distance_to(target) > 0.01:
			look_at(target, Vector3.UP)

func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	# Don't hit the shooter
	if body.get_instance_id() == owner_id:
		return

	print("[Projectile] Hit body: %s" % body.name)

	# Check if it's a damageable entity (player or enemy)
	if body.has_method("take_damage"):
		var knockback_dir = velocity.normalized()

		# Damage enemies (layer 4) - use network damage system
		if body.collision_layer & 4:
			var enemy_network_id = body.network_id if "network_id" in body else 0
			if enemy_network_id > 0:
				print("[Projectile] Hit enemy %s (net_id=%d) for %.1f damage" % [body.name, enemy_network_id, damage])
				var dir_array = [knockback_dir.x, knockback_dir.y, knockback_dir.z]
				NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_network_id, damage, 5.0, dir_array)
			else:
				print("[Projectile] Hit enemy %s but it has no network_id!" % body.name)

		# Damage players (layer 2)
		elif body.collision_layer & 2:
			# For player damage, we need to pass attacker_id for parry system
			var attacker_instance_id = owner_id
			body.take_damage(damage, attacker_instance_id, knockback_dir * 5.0)
			print("[Projectile] Damaged player %s for %.1f" % [body.name, damage])

	# Hit something - destroy projectile
	_hit()

func _on_area_entered(area: Node) -> void:
	if has_hit:
		return

	print("[Projectile] Hit area: %s" % area.name)
	# Could handle hitting other projectiles, etc.
	_hit()

func _hit() -> void:
	"""Called when projectile hits something"""
	has_hit = true
	velocity = Vector3.ZERO

	# TODO: Play impact effect/sound

	# Destroy after a brief moment
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _on_lifetime_timeout() -> void:
	"""Destroy projectile when lifetime expires"""
	print("[Projectile] Lifetime expired")
	queue_free()

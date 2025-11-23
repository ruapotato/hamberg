extends Node3D

## FireArea - Area of effect fire damage zone
## Deals damage over time to enemies in radius

@export var radius: float = 5.0
@export var damage: float = 12.0
@export var tick_rate: float = 0.5  # Damage every 0.5 seconds
@export var duration: float = 3.0  # How long the fire lasts

var tick_timer: float = 0.0
var enemies_in_area: Array = []

func _ready() -> void:
	# Setup collision shape
	var collision_shape = $AreaOfEffect/CollisionShape3D
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

	# Setup particles to match radius
	var particles = $GPUParticles3D
	particles.visibility_aabb = AABB(Vector3(-radius, 0, -radius), Vector3(radius * 2, 3, radius * 2))

	# Setup timer
	$Timer.wait_time = duration
	$Timer.start()

	print("[FireArea] Created fire area (radius: %.1fm, damage: %.1f, duration: %.1fs)" % [radius, damage, duration])

func _process(delta: float) -> void:
	# Tick damage
	tick_timer += delta
	if tick_timer >= tick_rate:
		tick_timer = 0.0
		_deal_damage_to_enemies()

func _on_area_body_entered(body: Node3D) -> void:
	# Check if it's an enemy
	if body.has_method("take_damage") and body.collision_layer & 4:  # Enemy layer
		if not enemies_in_area.has(body):
			enemies_in_area.append(body)
			print("[FireArea] Enemy entered fire: %s" % body.name)

func _on_area_body_exited(body: Node3D) -> void:
	if enemies_in_area.has(body):
		enemies_in_area.erase(body)
		print("[FireArea] Enemy left fire: %s" % body.name)

func _deal_damage_to_enemies() -> void:
	# Deal damage to all enemies in area
	for enemy in enemies_in_area:
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			var direction = (enemy.global_position - global_position).normalized()
			enemy.take_damage(damage, 0.5, direction)

func _on_timer_timeout() -> void:
	# Fire duration expired, clean up
	print("[FireArea] Fire area expired")
	queue_free()

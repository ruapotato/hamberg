extends Node3D

## SporeCloud - Area of effect poison damage zone from Sporelings
## Deals damage over time to PLAYERS in radius

@export var radius: float = 3.0
@export var damage: float = 8.0
@export var tick_rate: float = 0.8  # Damage every 0.8 seconds
@export var duration: float = 4.0  # How long the cloud lasts

# Network sync - only the host deals damage
var is_host: bool = false
var spawner_network_id: int = 0  # Network ID of the spawning enemy for damage attribution

var tick_timer: float = 0.0
var players_in_area: Array = []

@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var ground_glow: OmniLight3D = $GroundGlow

func _ready() -> void:
	# Setup collision shape based on radius
	var collision_shape = $AreaOfEffect/CollisionShape3D
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

	# Setup particles to match radius
	if particles and particles.process_material:
		particles.process_material = particles.process_material.duplicate()
		var mat = particles.process_material as ParticleProcessMaterial
		mat.emission_sphere_radius = radius

		particles.amount = max(40, int(50 * radius))
		particles.lifetime = clampf(duration * 0.4, 0.6, 1.5)
		var size_scale = clampf(radius / 3.0, 0.5, 1.2)
		mat.scale_min = 0.2 * size_scale
		mat.scale_max = 0.6 * size_scale

		particles.visibility_aabb = AABB(Vector3(-radius - 1, 0, -radius - 1), Vector3((radius + 1) * 2, 4, (radius + 1) * 2))

	# Setup light to match radius
	if ground_glow:
		ground_glow.omni_range = radius * 1.2
		var light_scale = clampf(radius / 3.0, 0.5, 1.0)
		ground_glow.light_energy = 2.0 * light_scale

	# Setup timer
	$Timer.wait_time = duration
	$Timer.start()

	print("[SporeCloud] Created spore cloud (radius: %.1fm, damage: %.1f, duration: %.1fs)" % [radius, damage, duration])

func _process(delta: float) -> void:
	# Tick damage
	tick_timer += delta
	if tick_timer >= tick_rate:
		tick_timer = 0.0
		_deal_damage_to_players()

func _on_area_body_entered(body: Node3D) -> void:
	# Check if it's a player (layer 2)
	if body.has_method("take_damage") and body.collision_layer & 2:
		if not players_in_area.has(body):
			players_in_area.append(body)
			print("[SporeCloud] Player entered spore cloud: %s" % body.name)

func _on_area_body_exited(body: Node3D) -> void:
	if players_in_area.has(body):
		players_in_area.erase(body)
		print("[SporeCloud] Player left spore cloud: %s" % body.name)

func _deal_damage_to_players() -> void:
	# Only the host deals damage to avoid duplicate damage
	if not is_host:
		return

	# Deal damage to all players in area
	for player in players_in_area:
		if is_instance_valid(player) and player.has_method("take_damage"):
			var direction = (player.global_position - global_position).normalized()

			# Check if this is the local player (we deal damage through network RPC)
			if player.is_local_player:
				# For local player, apply damage directly (we're the host)
				player.take_damage(damage, spawner_network_id, direction * 1.0)
				print("[SporeCloud] Dealt %.1f damage to local player" % damage)
			else:
				# For remote players, send damage through network
				var knockback_array = [direction.x, direction.y, direction.z]
				NetworkManager.rpc_enemy_damage_player.rpc_id(1, spawner_network_id, damage, knockback_array)
				print("[SporeCloud] Sent %.1f damage to remote player via network" % damage)

func _on_timer_timeout() -> void:
	# Cloud expired, clean up
	print("[SporeCloud] Spore cloud expired")

	# Stop particles emitting, but let remaining particles fade
	if particles:
		particles.emitting = false

	# Wait for particles to fade, then free
	await get_tree().create_timer(1.5).timeout
	queue_free()

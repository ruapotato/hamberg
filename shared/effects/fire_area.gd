extends Node3D

## FireArea - Area of effect fire damage zone
## Deals damage over time to enemies in radius

@export var radius: float = 5.0
@export var damage: float = 12.0
@export var tick_rate: float = 0.5  # Damage every 0.5 seconds
@export var duration: float = 3.0  # How long the fire lasts

var tick_timer: float = 0.0
var enemies_in_area: Array = []

@onready var audio_player: AudioStreamPlayer3D = $AudioPlayer
@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var ground_glow: OmniLight3D = $GroundGlow

func _ready() -> void:
	# Setup collision shape based on radius
	var collision_shape = $AreaOfEffect/CollisionShape3D
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

	# Setup particles to match radius
	# IMPORTANT: Duplicate the material so each fire area has its own copy
	# Without this, all fire areas share the same material and only one shows particles
	if particles and particles.process_material:
		particles.process_material = particles.process_material.duplicate()
		var mat = particles.process_material as ParticleProcessMaterial
		mat.emission_sphere_radius = radius
		# Scale particle amount based on area (minimum 10 particles)
		particles.amount = max(10, int(30 * radius))
		particles.visibility_aabb = AABB(Vector3(-radius - 1, 0, -radius - 1), Vector3((radius + 1) * 2, 4, (radius + 1) * 2))
		# Scale particle size based on radius - smaller fires have smaller particles
		var size_scale = clampf(radius / 5.0, 0.3, 1.0)  # 5.0 is the "normal" radius
		mat.scale_min = 0.3 * size_scale
		mat.scale_max = 1.0 * size_scale
		# Set particle lifetime to match duration (but cap it so they don't hang around too long)
		particles.lifetime = clampf(duration, 0.3, 1.0)

	# Setup light to match radius - smaller fires are dimmer
	if ground_glow:
		ground_glow.omni_range = radius * 1.5
		var light_scale = clampf(radius / 5.0, 0.3, 1.0)
		ground_glow.light_energy = 3.0 * light_scale

	# Setup timer
	$Timer.wait_time = duration
	$Timer.start()

	# Play fire burn sound
	_play_fire_sound()

	print("[FireArea] Created fire area (radius: %.1fm, damage: %.1f, duration: %.1fs)" % [radius, damage, duration])

func _play_fire_sound() -> void:
	"""Play looping fire burn sound"""
	if audio_player:
		var sound_path = "res://audio/generated/fire_burn_loop.wav"
		if ResourceLoader.exists(sound_path):
			var stream = load(sound_path)
			if stream:
				audio_player.stream = stream
				audio_player.play()
		else:
			# Fallback to fire_crackle if burn loop doesn't exist
			sound_path = "res://audio/generated/fire_crackle.wav"
			if ResourceLoader.exists(sound_path):
				var stream = load(sound_path)
				if stream:
					audio_player.stream = stream
					audio_player.play()

func _process(delta: float) -> void:
	# Tick damage
	tick_timer += delta
	if tick_timer >= tick_rate:
		tick_timer = 0.0
		_deal_damage_to_enemies()

	# Restart sound if it finished (loop it)
	if audio_player and not audio_player.playing:
		audio_player.play()

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
	# Deal damage to all enemies in area - use network damage system
	for enemy in enemies_in_area:
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			var direction = (enemy.global_position - global_position).normalized()
			var enemy_network_id = enemy.network_id if "network_id" in enemy else 0
			if enemy_network_id > 0:
				var dir_array = [direction.x, direction.y, direction.z]
				NetworkManager.rpc_damage_enemy.rpc_id(1, enemy_network_id, damage, 0.5, dir_array)
			else:
				print("[FireArea] Enemy %s has no network_id!" % enemy.name)

func _on_timer_timeout() -> void:
	# Fire duration expired, clean up
	print("[FireArea] Fire area expired")

	# Stop particles emitting, but let remaining particles fade
	if particles:
		particles.emitting = false

	# Fade out sound
	if audio_player:
		audio_player.stop()

	# Wait a moment for particles to fade, then free
	await get_tree().create_timer(1.0).timeout
	queue_free()

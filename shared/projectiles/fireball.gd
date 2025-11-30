extends Projectile

## Fireball - Arcing projectile that applies gravity and creates fire area on impact

@export var gravity_strength: float = 0.02  # Gravity strength (lower = floatier, more range)
@export var speed_multiplier: float = 1.0  # Full speed for long range
@export var fire_area_radius: float = 5.0
@export var fire_area_damage: float = 12.0
@export var fire_area_duration: float = 3.0

var initial_direction: Vector3 = Vector3.ZERO
var audio_player: AudioStreamPlayer3D

func _ready() -> void:
	super._ready()  # Connect collision signals from parent
	_setup_flight_sound()

func _setup_flight_sound() -> void:
	"""Setup and start playing the fireball flight sound"""
	audio_player = AudioStreamPlayer3D.new()
	audio_player.max_distance = 30.0
	audio_player.unit_size = 8.0
	add_child(audio_player)

	var sound_path = "res://audio/generated/fireball_flight.wav"
	if ResourceLoader.exists(sound_path):
		var stream = load(sound_path)
		if stream:
			audio_player.stream = stream
			audio_player.play()
			# Loop when sound finishes (fireball can fly for up to 8 seconds)
			audio_player.finished.connect(_on_flight_sound_finished)

func _on_flight_sound_finished() -> void:
	"""Restart the flight sound to loop it"""
	if audio_player and not has_hit:
		audio_player.play()

func _physics_process(delta: float) -> void:
	if has_hit:
		return

	# Apply gravity to velocity
	velocity.y -= gravity_strength * delta

	# Move projectile
	position += velocity * delta

	# Rotate to face direction of travel (follow the arc)
	if velocity.length() > 0.1:
		var look_target = position + velocity.normalized()
		if position.distance_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)

func setup(start_pos: Vector3, direction: Vector3, speed: float, dmg: float, shooter_id: int, dmg_type: int = -1) -> void:
	"""Initialize the fireball - shoots exactly where player is aiming, gravity pulls it down"""
	position = start_pos

	# Shoot exactly in the direction the player is aiming
	# Gravity will naturally arc it down - aim up for distance, level/down for close range
	# Apply speed multiplier for slower, more dramatic fireball
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
	"""Called when fireball hits something - spawn fire area"""
	has_hit = true
	velocity = Vector3.ZERO

	# Stop flight sound
	if audio_player:
		audio_player.stop()

	# Spawn fire area at impact location
	_spawn_fire_area()

	# Destroy after a brief moment
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _spawn_fire_area() -> void:
	"""Spawn the fire area effect at impact position"""
	var fire_area_scene = load("res://shared/effects/fire_area.tscn")
	if fire_area_scene:
		var fire_area = fire_area_scene.instantiate()
		# Set properties BEFORE adding to tree so _ready() uses correct values
		fire_area.radius = fire_area_radius
		fire_area.damage = fire_area_damage
		fire_area.duration = fire_area_duration
		get_tree().root.add_child(fire_area)
		fire_area.global_position = global_position
		print("[Fireball] Spawned fire area at %s" % global_position)

extends Area3D
class_name MageOrbProjectile

## MageOrbProjectile - Slow homing purple orb that can be blocked by attacks
## Fired by mage zombies, tracks player slowly, destroyable

signal orb_destroyed(orb: MageOrbProjectile)

# Orb stats
@export var damage: float = 20.0
@export var homing_speed: float = 4.0  # How fast it moves toward player
@export var turn_speed: float = 2.0  # How fast it can turn
@export var lifetime: float = 8.0  # Seconds before timeout
@export var health: float = 10.0  # HP - can be destroyed by player

# Internal state
var target: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var current_health: float
var caster: Node3D = null
var time_alive: float = 0.0
var is_timing_out: bool = false  # Prevent multiple timeout tweens

# Visual components
var sprite: Sprite3D
var glow_light: OmniLight3D
var trail_particles: GPUParticles3D

# Animation
var pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("enemy_projectiles")

	# Setup collision
	collision_layer = 4  # Enemy layer
	collision_mask = 2 | 8  # Player layer and projectile/spell layer

	current_health = health

	# Create visuals
	_create_visuals()

	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Find target
	_find_target()


func _create_visuals() -> void:
	# Main orb sprite
	sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.pixel_size = 0.015
	sprite.texture = _generate_orb_texture()
	add_child(sprite)

	# Glow light
	glow_light = OmniLight3D.new()
	glow_light.light_color = Color(0.7, 0.2, 1.0)  # Purple
	glow_light.light_energy = 1.5
	glow_light.omni_range = 3.0
	glow_light.omni_attenuation = 1.5
	add_child(glow_light)


func _generate_orb_texture() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 2

	# Draw orb with gradient
	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var dist := pos.distance_to(center)

			if dist < radius:
				# Create gradient from center to edge
				var t := dist / radius
				var alpha := 1.0 - (t * t)

				# Core is bright white-purple, edges are dark purple
				var core_color := Color(0.9, 0.7, 1.0)
				var edge_color := Color(0.5, 0.1, 0.8)
				var color := core_color.lerp(edge_color, t)
				color.a = alpha

				img.set_pixel(x, y, color)
			elif dist < radius + 2:
				# Outer glow
				var glow_t := (dist - radius) / 2.0
				var glow_color := Color(0.7, 0.2, 1.0, 0.5 * (1.0 - glow_t))
				img.set_pixel(x, y, glow_color)

	return ImageTexture.create_from_image(img)


func _find_target() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		players = get_tree().get_nodes_in_group("local_player")

	if players.size() > 0:
		# Find closest player
		var closest_dist := INF
		for p in players:
			var dist := global_position.distance_to(p.global_position)
			if dist < closest_dist:
				closest_dist = dist
				target = p


func _physics_process(delta: float) -> void:
	time_alive += delta

	# Process hit flash (no tweens)
	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0 and sprite:
			sprite.modulate = Color(1.0, 1.0, 1.0)

	# Check timeout
	if time_alive >= lifetime:
		_timeout()
		return

	# Homing behavior
	if target and is_instance_valid(target):
		var target_pos := target.global_position + Vector3.UP  # Aim at chest height
		var desired_dir := (target_pos - global_position).normalized()

		# Gradually turn toward target
		if velocity.length() > 0:
			var current_dir := velocity.normalized()
			var new_dir := current_dir.lerp(desired_dir, turn_speed * delta)
			velocity = new_dir * homing_speed
		else:
			velocity = desired_dir * homing_speed
	else:
		# Find new target if current is invalid
		_find_target()
		if target:
			var dir := (target.global_position - global_position).normalized()
			velocity = dir * homing_speed

	# Move
	global_position += velocity * delta

	# Animate
	_update_animation(delta)


func _update_animation(delta: float) -> void:
	pulse_time += delta * 5.0

	if sprite:
		# Pulsing scale
		var scale_pulse := 1.0 + sin(pulse_time) * 0.15
		sprite.scale = Vector3.ONE * scale_pulse

		# Rotate slightly
		sprite.rotation.z += delta * 2.0

	if glow_light:
		# Pulsing light
		glow_light.light_energy = 1.5 + sin(pulse_time * 1.5) * 0.5

	# Flash more intensely as timeout approaches
	if lifetime - time_alive < 2.0:
		var warning_flash := sin(time_alive * 10.0) * 0.5 + 0.5
		if sprite:
			sprite.modulate = Color(1.0, warning_flash, warning_flash)


func _on_body_entered(body: Node3D) -> void:
	if body == caster:
		return

	if body.is_in_group("player") or body.is_in_group("local_player"):
		# Hit player
		if body.has_method("take_damage"):
			body.take_damage(damage, caster)
		_destroy(true)


func _on_area_entered(area: Area3D) -> void:
	# Check if hit by player spell/projectile
	if area.is_in_group("player_spells") or area.is_in_group("player_projectiles"):
		# Take damage from spell
		var spell_damage := 10.0
		if area.has_method("get_damage"):
			spell_damage = area.get_damage()
		elif "damage" in area:
			spell_damage = area.damage

		take_damage(spell_damage)


var _hit_flash_timer: float = 0.0

func take_damage(amount: float, _attacker: Node3D = null) -> void:
	current_health -= amount

	# Flash white (no tweens)
	if sprite:
		sprite.modulate = Color.WHITE
		_hit_flash_timer = 0.05

	if current_health <= 0:
		_destroy(false)


func _timeout() -> void:
	# Only timeout once
	if is_timing_out:
		return
	is_timing_out = true

	# Just delete immediately (no fade animation)
	queue_free()


func _destroy(_hit_target: bool) -> void:
	# Emit signal
	orb_destroyed.emit(self)

	# No fancy effects - just remove immediately
	queue_free()


## Initialize the orb with settings
func initialize(start_velocity: Vector3, caster_node: Node3D, orb_damage: float = 20.0) -> void:
	velocity = start_velocity.normalized() * homing_speed
	caster = caster_node
	damage = orb_damage

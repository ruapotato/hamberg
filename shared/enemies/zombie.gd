extends "res://shared/enemies/enemy.gd"

## Zombie - Undead enemy that spawns in all biomes
## Uses ZombieTextureGenerator for procedural pixel art sprites
## Different zombie types have different stats and appearances:
##   walker, runner, brute, mage_zombie, exploder

# Zombie type - set BEFORE adding to tree (used in _ready)
var zombie_type: String = "walker"

# Type-specific stats: {hp, speed, charge_speed, damage, attack_range}
const ZOMBIE_STATS = {
	"walker": { "hp": 50.0, "speed": 3.0, "charge_speed": 5.0, "damage": 10.0, "attack_range": 1.0 },
	"runner": { "hp": 30.0, "speed": 6.0, "charge_speed": 8.0, "damage": 8.0, "attack_range": 0.9 },
	"brute": { "hp": 150.0, "speed": 1.5, "charge_speed": 3.0, "damage": 25.0, "attack_range": 1.5 },
	"mage_zombie": { "hp": 40.0, "speed": 2.5, "charge_speed": 4.0, "damage": 15.0, "attack_range": 1.2 },
	"exploder": { "hp": 35.0, "speed": 4.0, "charge_speed": 6.0, "damage": 30.0, "attack_range": 1.8 },
}

func _ready() -> void:
	_apply_zombie_type()
	super._ready()

	# Zombies are slightly more aggressive than gahnomes
	aggression = randf_range(0.6, 0.95)
	patience = randf_range(0.3, 0.6)

	health = max_health

## Configure stats and name based on zombie_type
func _apply_zombie_type() -> void:
	var stats = ZOMBIE_STATS.get(zombie_type, ZOMBIE_STATS["walker"])

	enemy_name = "Zombie"
	max_health = stats["hp"]
	move_speed = stats["speed"]
	charge_speed = stats["charge_speed"]
	strafe_speed = stats["speed"] * 0.5
	attack_range = stats["attack_range"]
	weapon_id = "fists"
	loot_table = { "bone": 2, "rotten_flesh": 1 }

	# Brutes are tankier with slower attacks
	if zombie_type == "brute":
		attack_cooldown_time = 2.0
		windup_time = 0.8
		detection_range = 16.0
		preferred_distance = 4.0
	elif zombie_type == "runner":
		attack_cooldown_time = 0.8
		windup_time = 0.3
		detection_range = 24.0
		preferred_distance = 3.0
	elif zombie_type == "exploder":
		attack_cooldown_time = 1.0
		windup_time = 0.6
		detection_range = 20.0
		preferred_distance = 2.0
	elif zombie_type == "mage_zombie":
		attack_cooldown_time = 1.5
		windup_time = 0.6
		detection_range = 22.0
		preferred_distance = 8.0
		throw_range = 14.0
		throw_min_range = 5.0
		rock_damage = stats["damage"]
	else:
		# Walker - balanced defaults
		attack_cooldown_time = 1.2
		windup_time = 0.5
		detection_range = 18.0
		preferred_distance = 5.0

	# Zombie resistances - undead creature
	damage_resistances = {
		WeaponData.DamageType.SLASH: 0.9,    # Slightly resistant (dead flesh)
		WeaponData.DamageType.BLUNT: 1.1,    # Slightly weak (brittle bones)
		WeaponData.DamageType.PIERCE: 0.8,   # Resistant (holes don't matter to undead)
		WeaponData.DamageType.FIRE: 1.4,     # Weak to fire (dry and burnable)
		WeaponData.DamageType.ICE: 0.9,      # Slightly resistant (already cold)
		WeaponData.DamageType.POISON: 0.5,   # Very resistant (already dead)
	}

## Set zombie type externally (e.g., from spawner before adding to tree)
func set_zombie_type(type: String) -> void:
	zombie_type = type

## Override body setup to use ZombieTextureGenerator sprites
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	# Directional Billboard Sprite3D (Paper Mario style)
	var sprite = DirectionalSpriteScript.new()
	sprite.name = "Sprite"
	sprite.pixel_size = 0.02
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Get zombie texture from the autoload generator
	var zombie_tex = ZombieTextureGenerator.get_zombie_texture(zombie_type)
	sprite.texture = zombie_tex
	sprite.set_textures_4dir(zombie_tex, zombie_tex, zombie_tex, zombie_tex)

	# Zombie textures are 64x96, pixel_size 0.02 -> 1.92 units tall, center at half
	var sprite_height = 96.0 * 0.02  # 1.92
	sprite.position = Vector3(0, sprite_height * 0.5, 0)

	# Scale brutes up and runners slightly smaller
	if zombie_type == "brute":
		body_container.scale = Vector3(1.3, 1.3, 1.3)
	elif zombie_type == "runner":
		body_container.scale = Vector3(0.9, 0.9, 0.9)

	body_container.add_child(sprite)

	head_base_height = 0.0  # No 3D head to bob

## Override telegraph to use sprite tint
func _set_windup_telegraph(enabled: bool) -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	if enabled:
		# Red-ish warning tint for zombies
		_set_body_tint(Color(1.0, 0.4, 0.4, 1.0))
	else:
		_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

## Override attack swing animation (sprite squash-and-stretch)
func _play_attack_swing() -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	# Preserve base scale (brutes are 1.3x, runners 0.9x)
	var base_scale = body_container.scale
	var squash = Vector3(base_scale.x * 1.2, base_scale.y * 0.85, base_scale.z * 1.2)

	# Quick lunge forward effect via scale squash
	windup_tween = create_tween()
	windup_tween.tween_property(body_container, "scale", squash, 0.1)
	windup_tween.tween_property(body_container, "scale", base_scale, 0.3)

	_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

extends Resource
class_name SpellData
## Data structure for spell configuration

# Basic info
@export var spell_id: String = ""
@export var display_name: String = ""
@export var description: String = ""

# Spell classification
@export var damage_type: int = 0  # SpellRegistry.DamageType
@export var spell_type: int = 0   # SpellRegistry.SpellType
@export var spell_tier: int = 1

# Core stats
@export var base_damage: int = 30
@export var mana_cost: int = 10
@export var cast_time: float = 0.5
@export var cooldown: float = 1.0

# Projectile properties
@export var projectile_speed: float = 40.0
@export var projectile_lifetime: float = 5.0
@export var homing_strength: float = 0.0
@export var pierce_count: int = 0
@export var missile_count: int = 1

# Beam properties
@export var beam_range: float = 20.0
@export var beam_duration: float = 1.0
@export var beam_width: float = 0.5

# AOE properties
@export var aoe_radius: float = 5.0
@export var aoe_duration: float = 3.0
@export var explosion_radius: float = 0.0

# Damage over time
@export var damage_per_tick: int = 0
@export var tick_interval: float = 0.5
@export var dot_damage_per_sec: int = 0
@export var dot_duration: float = 0.0

# Element-specific effects
@export var burn_damage_per_sec: int = 0
@export var burn_duration: float = 0.0
@export var slow_percent: float = 0.0
@export var slow_duration: float = 0.0
@export var freeze_chance: float = 0.0
@export var freeze_duration: float = 0.0
@export var stun_chance: float = 0.0
@export var stun_duration: float = 0.0
@export var root_duration: float = 0.0

# Chain lightning
@export var chain_count: int = 0
@export var chain_range: float = 5.0
@export var chain_damage_falloff: float = 1.0

# Meteor storm
@export var meteor_count: int = 0
@export var meteor_interval: float = 0.5

# Healing/Support
@export var heal_per_tick: int = 0
@export var heal_allies: int = 0
@export var mana_regen_bonus: int = 0
@export var player_speed_bonus: float = 0.0

# Lifesteal/Manasteal
@export var lifesteal_percent: float = 0.0
@export var mana_steal_percent: float = 0.0

# Special bonuses
@export var bonus_vs_undead: float = 1.0
@export var knockback_force: float = 0.0

# Visual/Audio
@export var cast_sound: String = "spell_cast"
@export var impact_sound: String = "spell_impact"
@export var particle_effect: String = ""
@export var trail_color: Color = Color.WHITE
@export var glow_intensity: float = 1.0


static func from_dict(data: Dictionary):
	var script = preload("res://shared/weapons/spell_data.gd")
	var spell = script.new()

	# Basic info
	spell.spell_id = data.get("spell_id", "")
	spell.display_name = data.get("display_name", "")
	spell.description = data.get("description", "")

	# Classification
	spell.damage_type = data.get("damage_type", 0)
	spell.spell_type = data.get("spell_type", 0)
	spell.spell_tier = data.get("spell_tier", 1)

	# Core stats
	spell.base_damage = data.get("base_damage", 30)
	spell.mana_cost = data.get("mana_cost", 10)
	spell.cast_time = data.get("cast_time", 0.5)
	spell.cooldown = data.get("cooldown", 1.0)

	# Projectile
	spell.projectile_speed = data.get("projectile_speed", 40.0)
	spell.projectile_lifetime = data.get("projectile_lifetime", 5.0)
	spell.homing_strength = data.get("homing_strength", 0.0)
	spell.pierce_count = data.get("pierce_count", 0)
	spell.missile_count = data.get("missile_count", 1)

	# Beam
	spell.beam_range = data.get("beam_range", 20.0)
	spell.beam_duration = data.get("beam_duration", 1.0)
	spell.beam_width = data.get("beam_width", 0.5)

	# AOE
	spell.aoe_radius = data.get("aoe_radius", 5.0)
	spell.aoe_duration = data.get("aoe_duration", 3.0)
	spell.explosion_radius = data.get("explosion_radius", 0.0)

	# DOT
	spell.damage_per_tick = data.get("damage_per_tick", 0)
	spell.tick_interval = data.get("tick_interval", 0.5)
	spell.dot_damage_per_sec = data.get("dot_damage_per_sec", 0)
	spell.dot_duration = data.get("dot_duration", 0.0)

	# Element effects
	spell.burn_damage_per_sec = data.get("burn_damage_per_sec", 0)
	spell.burn_duration = data.get("burn_duration", 0.0)
	spell.slow_percent = data.get("slow_percent", 0.0)
	spell.slow_duration = data.get("slow_duration", 0.0)
	spell.freeze_chance = data.get("freeze_chance", 0.0)
	spell.freeze_duration = data.get("freeze_duration", 0.0)
	spell.stun_chance = data.get("stun_chance", 0.0)
	spell.stun_duration = data.get("stun_duration", 0.0)
	spell.root_duration = data.get("root_duration", 0.0)

	# Chain lightning
	spell.chain_count = data.get("chain_count", 0)
	spell.chain_range = data.get("chain_range", 5.0)
	spell.chain_damage_falloff = data.get("chain_damage_falloff", 1.0)

	# Meteor
	spell.meteor_count = data.get("meteor_count", 0)
	spell.meteor_interval = data.get("meteor_interval", 0.5)

	# Healing
	spell.heal_per_tick = data.get("heal_per_tick", 0)
	spell.heal_allies = data.get("heal_allies", 0)
	spell.mana_regen_bonus = data.get("mana_regen_bonus", 0)
	spell.player_speed_bonus = data.get("player_speed_bonus", 0.0)

	# Steal
	spell.lifesteal_percent = data.get("lifesteal_percent", 0.0)
	spell.mana_steal_percent = data.get("mana_steal_percent", 0.0)

	# Special
	spell.bonus_vs_undead = data.get("bonus_vs_undead", 1.0)
	spell.knockback_force = data.get("knockback_force", 0.0)

	# Visual/Audio
	spell.cast_sound = data.get("cast_sound", "spell_cast")
	spell.impact_sound = data.get("impact_sound", "spell_impact")
	spell.particle_effect = data.get("particle_effect", "")
	spell.trail_color = data.get("trail_color", Color.WHITE)
	spell.glow_intensity = data.get("glow_intensity", 1.0)

	return spell

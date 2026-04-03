extends Node
## SpellRegistry - Static spell data registry for all magic spells
## Autoload singleton - do not use class_name to avoid shadowing

const SpellData = preload("res://shared/weapons/spell_data.gd")

# Damage type enum
enum DamageType {
	FIRE,
	ICE,
	LIGHTNING,
	ARCANE,
	NATURE,
	DARK,
	HOLY
}

# Spell type enum
enum SpellType {
	PROJECTILE,
	BEAM,
	AOE,
	BUFF,
	SUMMON
}

# All spell definitions
static var SPELLS: Dictionary = {
	# FIRE SPELLS
	"fireball": {
		"spell_id": "fireball",
		"display_name": "Fireball",
		"damage_type": DamageType.FIRE,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 50,
		"mana_cost": 15,
		"cast_time": 0.3,
		"cooldown": 0.5,
		"projectile_speed": 40.0,
		"projectile_lifetime": 5.0,
		"explosion_radius": 2.0,
		"burn_damage_per_sec": 10,
		"burn_duration": 3.0,
		"spell_tier": 1,
		"description": "Launch a flaming projectile that explodes on impact",
		"cast_sound": "fire_cast",
		"impact_sound": "fire_impact",
		"particle_effect": "fireball_particle",
		"trail_color": Color(1.0, 0.4, 0.0),
		"glow_intensity": 2.0
	},

	"flame_wave": {
		"spell_id": "flame_wave",
		"display_name": "Flame Wave",
		"damage_type": DamageType.FIRE,
		"spell_type": SpellType.AOE,
		"base_damage": 35,
		"mana_cost": 25,
		"cast_time": 0.5,
		"cooldown": 3.0,
		"aoe_radius": 8.0,
		"aoe_duration": 2.0,
		"burn_damage_per_sec": 15,
		"burn_duration": 4.0,
		"knockback_force": 10.0,
		"spell_tier": 2,
		"description": "Unleash a wave of fire that spreads outward",
		"cast_sound": "flame_wave_cast",
		"impact_sound": "fire_whoosh",
		"particle_effect": "flame_wave_particle",
		"trail_color": Color(1.0, 0.3, 0.0)
	},

	"meteor_storm": {
		"spell_id": "meteor_storm",
		"display_name": "Meteor Storm",
		"damage_type": DamageType.FIRE,
		"spell_type": SpellType.AOE,
		"base_damage": 120,
		"mana_cost": 60,
		"cast_time": 2.0,
		"cooldown": 10.0,
		"aoe_radius": 15.0,
		"aoe_duration": 5.0,
		"meteor_count": 12,
		"meteor_interval": 0.4,
		"explosion_radius": 3.0,
		"burn_damage_per_sec": 25,
		"burn_duration": 5.0,
		"spell_tier": 4,
		"description": "Rain fiery meteors from the sky",
		"cast_sound": "meteor_cast",
		"impact_sound": "meteor_impact",
		"particle_effect": "meteor_particle",
		"trail_color": Color(1.0, 0.5, 0.0),
		"glow_intensity": 3.0
	},

	"inferno": {
		"spell_id": "inferno",
		"display_name": "Inferno",
		"damage_type": DamageType.FIRE,
		"spell_type": SpellType.AOE,
		"base_damage": 80,
		"mana_cost": 45,
		"cast_time": 1.5,
		"cooldown": 8.0,
		"aoe_radius": 10.0,
		"aoe_duration": 6.0,
		"burn_damage_per_sec": 30,
		"burn_duration": 6.0,
		"damage_per_tick": 20,
		"tick_interval": 0.5,
		"spell_tier": 3,
		"description": "Create a raging inferno that burns all within",
		"cast_sound": "inferno_cast",
		"impact_sound": "inferno_loop",
		"particle_effect": "inferno_particle",
		"trail_color": Color(1.0, 0.2, 0.0),
		"glow_intensity": 2.5
	},

	# ICE SPELLS
	"ice_shard": {
		"spell_id": "ice_shard",
		"display_name": "Ice Shard",
		"damage_type": DamageType.ICE,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 45,
		"mana_cost": 12,
		"cast_time": 0.2,
		"cooldown": 0.4,
		"projectile_speed": 50.0,
		"projectile_lifetime": 5.0,
		"slow_percent": 0.3,
		"slow_duration": 2.0,
		"pierce_count": 2,
		"spell_tier": 1,
		"description": "Fire a sharp ice projectile that pierces enemies",
		"cast_sound": "ice_cast",
		"impact_sound": "ice_impact",
		"particle_effect": "ice_shard_particle",
		"trail_color": Color(0.5, 0.8, 1.0),
		"glow_intensity": 1.5
	},

	"frost_nova": {
		"spell_id": "frost_nova",
		"display_name": "Frost Nova",
		"damage_type": DamageType.ICE,
		"spell_type": SpellType.AOE,
		"base_damage": 40,
		"mana_cost": 20,
		"cast_time": 0.3,
		"cooldown": 2.5,
		"aoe_radius": 6.0,
		"slow_percent": 0.6,
		"slow_duration": 4.0,
		"freeze_chance": 0.3,
		"freeze_duration": 2.0,
		"spell_tier": 2,
		"description": "Freeze enemies around you in place",
		"cast_sound": "frost_nova_cast",
		"impact_sound": "ice_shatter",
		"particle_effect": "frost_nova_particle",
		"trail_color": Color(0.6, 0.9, 1.0)
	},

	"blizzard": {
		"spell_id": "blizzard",
		"display_name": "Blizzard",
		"damage_type": DamageType.ICE,
		"spell_type": SpellType.AOE,
		"base_damage": 25,
		"mana_cost": 50,
		"cast_time": 1.5,
		"cooldown": 8.0,
		"aoe_radius": 12.0,
		"aoe_duration": 8.0,
		"damage_per_tick": 15,
		"tick_interval": 0.5,
		"slow_percent": 0.7,
		"slow_duration": 8.0,
		"spell_tier": 4,
		"description": "Summon a devastating blizzard",
		"cast_sound": "blizzard_cast",
		"impact_sound": "blizzard_loop",
		"particle_effect": "blizzard_particle",
		"trail_color": Color(0.7, 0.9, 1.0),
		"glow_intensity": 1.8
	},

	"glacial_spike": {
		"spell_id": "glacial_spike",
		"display_name": "Glacial Spike",
		"damage_type": DamageType.ICE,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 100,
		"mana_cost": 40,
		"cast_time": 1.2,
		"cooldown": 4.0,
		"projectile_speed": 35.0,
		"projectile_lifetime": 6.0,
		"explosion_radius": 4.0,
		"slow_percent": 0.8,
		"slow_duration": 5.0,
		"freeze_chance": 0.8,
		"freeze_duration": 3.0,
		"spell_tier": 3,
		"description": "Launch a massive ice spike that shatters on impact",
		"cast_sound": "glacial_spike_cast",
		"impact_sound": "ice_shatter_heavy",
		"particle_effect": "glacial_spike_particle",
		"trail_color": Color(0.4, 0.7, 1.0),
		"glow_intensity": 2.2
	},

	# LIGHTNING SPELLS
	"chain_lightning": {
		"spell_id": "chain_lightning",
		"display_name": "Chain Lightning",
		"damage_type": DamageType.LIGHTNING,
		"spell_type": SpellType.BEAM,
		"base_damage": 60,
		"mana_cost": 30,
		"cast_time": 0.4,
		"cooldown": 2.0,
		"beam_range": 25.0,
		"chain_count": 4,
		"chain_range": 8.0,
		"chain_damage_falloff": 0.7,
		"stun_chance": 0.4,
		"stun_duration": 1.0,
		"spell_tier": 2,
		"description": "Lightning that chains between enemies",
		"cast_sound": "lightning_cast",
		"impact_sound": "lightning_zap",
		"particle_effect": "chain_lightning_particle",
		"trail_color": Color(0.7, 0.7, 1.0),
		"glow_intensity": 2.5
	},

	"thunder_strike": {
		"spell_id": "thunder_strike",
		"display_name": "Thunder Strike",
		"damage_type": DamageType.LIGHTNING,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 90,
		"mana_cost": 35,
		"cast_time": 0.8,
		"cooldown": 3.0,
		"projectile_speed": 60.0,
		"projectile_lifetime": 4.0,
		"explosion_radius": 5.0,
		"stun_chance": 0.7,
		"stun_duration": 2.0,
		"spell_tier": 3,
		"description": "Call down a bolt of thunder",
		"cast_sound": "thunder_cast",
		"impact_sound": "thunder_boom",
		"particle_effect": "thunder_particle",
		"trail_color": Color(0.8, 0.8, 1.0),
		"glow_intensity": 3.0
	},

	"static_field": {
		"spell_id": "static_field",
		"display_name": "Static Field",
		"damage_type": DamageType.LIGHTNING,
		"spell_type": SpellType.AOE,
		"base_damage": 20,
		"mana_cost": 40,
		"cast_time": 1.0,
		"cooldown": 6.0,
		"aoe_radius": 10.0,
		"aoe_duration": 10.0,
		"damage_per_tick": 12,
		"tick_interval": 0.3,
		"stun_chance": 0.15,
		"stun_duration": 0.5,
		"spell_tier": 3,
		"description": "Create an electrified field that shocks enemies",
		"cast_sound": "static_cast",
		"impact_sound": "static_loop",
		"particle_effect": "static_field_particle",
		"trail_color": Color(0.6, 0.6, 1.0),
		"glow_intensity": 1.5
	},

	# ARCANE SPELLS
	"magic_missile": {
		"spell_id": "magic_missile",
		"display_name": "Magic Missile",
		"damage_type": DamageType.ARCANE,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 30,
		"mana_cost": 10,
		"cast_time": 0.2,
		"cooldown": 0.3,
		"projectile_speed": 45.0,
		"projectile_lifetime": 5.0,
		"homing_strength": 0.5,
		"missile_count": 3,
		"spell_tier": 1,
		"description": "Fire homing arcane missiles",
		"cast_sound": "arcane_cast",
		"impact_sound": "arcane_impact",
		"particle_effect": "magic_missile_particle",
		"trail_color": Color(0.8, 0.4, 1.0),
		"glow_intensity": 1.5
	},

	"arcane_blast": {
		"spell_id": "arcane_blast",
		"display_name": "Arcane Blast",
		"damage_type": DamageType.ARCANE,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 85,
		"mana_cost": 35,
		"cast_time": 1.0,
		"cooldown": 2.5,
		"projectile_speed": 30.0,
		"projectile_lifetime": 6.0,
		"explosion_radius": 4.5,
		"knockback_force": 15.0,
		"spell_tier": 3,
		"description": "Powerful arcane explosion",
		"cast_sound": "arcane_blast_cast",
		"impact_sound": "arcane_explosion",
		"particle_effect": "arcane_blast_particle",
		"trail_color": Color(0.7, 0.3, 1.0),
		"glow_intensity": 2.5
	},

	"time_warp": {
		"spell_id": "time_warp",
		"display_name": "Time Warp",
		"damage_type": DamageType.ARCANE,
		"spell_type": SpellType.AOE,
		"base_damage": 0,
		"mana_cost": 55,
		"cast_time": 1.5,
		"cooldown": 15.0,
		"aoe_radius": 12.0,
		"aoe_duration": 8.0,
		"slow_percent": 0.85,
		"slow_duration": 8.0,
		"player_speed_bonus": 0.5,
		"spell_tier": 4,
		"description": "Warp time, slowing enemies and speeding allies",
		"cast_sound": "time_warp_cast",
		"impact_sound": "time_warp_loop",
		"particle_effect": "time_warp_particle",
		"trail_color": Color(0.6, 0.2, 1.0),
		"glow_intensity": 2.0
	},

	# NATURE SPELLS
	"vine_grasp": {
		"spell_id": "vine_grasp",
		"display_name": "Vine Grasp",
		"damage_type": DamageType.NATURE,
		"spell_type": SpellType.AOE,
		"base_damage": 25,
		"mana_cost": 20,
		"cast_time": 0.5,
		"cooldown": 4.0,
		"aoe_radius": 7.0,
		"root_duration": 3.0,
		"damage_per_tick": 10,
		"tick_interval": 1.0,
		"spell_tier": 2,
		"description": "Entangle enemies with magical vines",
		"cast_sound": "nature_cast",
		"impact_sound": "vines_rustle",
		"particle_effect": "vine_particle",
		"trail_color": Color(0.3, 0.8, 0.3)
	},

	"healing_rain": {
		"spell_id": "healing_rain",
		"display_name": "Healing Rain",
		"damage_type": DamageType.NATURE,
		"spell_type": SpellType.AOE,
		"base_damage": -30,  # Negative damage = healing
		"mana_cost": 40,
		"cast_time": 1.0,
		"cooldown": 10.0,
		"aoe_radius": 10.0,
		"aoe_duration": 8.0,
		"heal_per_tick": 15,
		"tick_interval": 1.0,
		"mana_regen_bonus": 5,
		"spell_tier": 3,
		"description": "Summon healing rain for allies",
		"cast_sound": "healing_cast",
		"impact_sound": "rain_loop",
		"particle_effect": "healing_rain_particle",
		"trail_color": Color(0.4, 1.0, 0.4),
		"glow_intensity": 1.2
	},

	# DARK SPELLS
	"soul_drain": {
		"spell_id": "soul_drain",
		"display_name": "Soul Drain",
		"damage_type": DamageType.DARK,
		"spell_type": SpellType.BEAM,
		"base_damage": 35,
		"mana_cost": 15,
		"cast_time": 0.3,
		"cooldown": 1.0,
		"beam_range": 20.0,
		"beam_duration": 2.0,
		"damage_per_tick": 20,
		"tick_interval": 0.2,
		"lifesteal_percent": 0.5,
		"mana_steal_percent": 0.3,
		"spell_tier": 2,
		"description": "Drain life and mana from your foes",
		"cast_sound": "dark_cast",
		"impact_sound": "soul_drain_loop",
		"particle_effect": "soul_drain_particle",
		"trail_color": Color(0.5, 0.0, 0.5),
		"glow_intensity": 1.8
	},

	"shadow_bolt": {
		"spell_id": "shadow_bolt",
		"display_name": "Shadow Bolt",
		"damage_type": DamageType.DARK,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 70,
		"mana_cost": 25,
		"cast_time": 0.8,
		"cooldown": 1.5,
		"projectile_speed": 40.0,
		"projectile_lifetime": 5.0,
		"dot_damage_per_sec": 20,
		"dot_duration": 5.0,
		"spell_tier": 2,
		"description": "Hurl a bolt of shadow energy",
		"cast_sound": "shadow_cast",
		"impact_sound": "shadow_impact",
		"particle_effect": "shadow_bolt_particle",
		"trail_color": Color(0.3, 0.0, 0.3),
		"glow_intensity": 1.5
	},

	# HOLY SPELLS
	"divine_light": {
		"spell_id": "divine_light",
		"display_name": "Divine Light",
		"damage_type": DamageType.HOLY,
		"spell_type": SpellType.AOE,
		"base_damage": 65,
		"mana_cost": 30,
		"cast_time": 0.7,
		"cooldown": 3.0,
		"aoe_radius": 8.0,
		"bonus_vs_undead": 2.0,
		"heal_allies": 40,
		"spell_tier": 2,
		"description": "Holy light that damages undead and heals allies",
		"cast_sound": "holy_cast",
		"impact_sound": "divine_light_impact",
		"particle_effect": "divine_light_particle",
		"trail_color": Color(1.0, 1.0, 0.7),
		"glow_intensity": 2.5
	},

	"smite": {
		"spell_id": "smite",
		"display_name": "Smite",
		"damage_type": DamageType.HOLY,
		"spell_type": SpellType.PROJECTILE,
		"base_damage": 110,
		"mana_cost": 45,
		"cast_time": 1.2,
		"cooldown": 4.0,
		"projectile_speed": 80.0,
		"projectile_lifetime": 3.0,
		"bonus_vs_undead": 2.5,
		"explosion_radius": 3.0,
		"stun_duration": 2.0,
		"spell_tier": 3,
		"description": "Devastating holy strike against evil",
		"cast_sound": "smite_cast",
		"impact_sound": "smite_impact",
		"particle_effect": "smite_particle",
		"trail_color": Color(1.0, 0.95, 0.6),
		"glow_intensity": 3.5
	}
}


static func get_spell_data(spell_id: String) -> Dictionary:
	if spell_id in SPELLS:
		return SPELLS[spell_id]
	return {}


static func get_spells_by_damage_type(damage_type: DamageType) -> Array[String]:
	var result: Array[String] = []
	for spell_id in SPELLS:
		var data: Dictionary = SPELLS[spell_id]
		if data.get("damage_type") == damage_type:
			result.append(spell_id)
	return result


static func get_spells_by_type(spell_type: SpellType) -> Array[String]:
	var result: Array[String] = []
	for spell_id in SPELLS:
		var data: Dictionary = SPELLS[spell_id]
		if data.get("spell_type") == spell_type:
			result.append(spell_id)
	return result


static func get_spells_by_tier(tier: int) -> Array[String]:
	var result: Array[String] = []
	for spell_id in SPELLS:
		var data: Dictionary = SPELLS[spell_id]
		if data.get("spell_tier", 1) == tier:
			result.append(spell_id)
	return result


static func get_all_spell_ids() -> Array[String]:
	var result: Array[String] = []
	for spell_id in SPELLS:
		result.append(spell_id)
	return result


static func get_damage_type_color(damage_type: DamageType) -> Color:
	match damage_type:
		DamageType.FIRE:
			return Color(1.0, 0.4, 0.0)
		DamageType.ICE:
			return Color(0.5, 0.8, 1.0)
		DamageType.LIGHTNING:
			return Color(0.7, 0.7, 1.0)
		DamageType.ARCANE:
			return Color(0.8, 0.4, 1.0)
		DamageType.NATURE:
			return Color(0.3, 0.8, 0.3)
		DamageType.DARK:
			return Color(0.5, 0.0, 0.5)
		DamageType.HOLY:
			return Color(1.0, 1.0, 0.7)
	return Color.WHITE


static func get_damage_type_name(damage_type: DamageType) -> String:
	match damage_type:
		DamageType.FIRE:
			return "Fire"
		DamageType.ICE:
			return "Ice"
		DamageType.LIGHTNING:
			return "Lightning"
		DamageType.ARCANE:
			return "Arcane"
		DamageType.NATURE:
			return "Nature"
		DamageType.DARK:
			return "Dark"
		DamageType.HOLY:
			return "Holy"
	return "Unknown"

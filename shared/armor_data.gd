extends Resource
class_name ArmorData

## ArmorData - Resource for armor items
## Defines armor stats, set bonuses, and visual appearance

# Which slot this armor piece goes in
enum ArmorSlot {
	HEAD,
	CHEST,
	LEGS,
	CAPE,
	ACCESSORY,  # Special items like Cyclops Eye
}

# Set bonus types
enum SetBonus {
	NONE,
	PIG_DOUBLE_JUMP,      # Full pig set: can double jump
	DEER_STAMINA_SAVER,   # Full deer set: 50% less stamina for sprinting
	CYCLOPS_LIGHT,        # Cyclops Eye: provides light around player
}

const ItemData = preload("res://shared/item_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")

@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
var item_type = ItemData.ItemType.ARMOR  # Always ARMOR type
@export var max_stack_size: int = 1  # Armor doesn't stack
@export var weight: float = 2.0

# Armor-specific properties
@export var armor_slot: ArmorSlot = ArmorSlot.CHEST
@export var durability: int = 100

# Per-damage-type armor values (flat damage reduction)
# Each damage type has its own armor value
@export var armor_values: Dictionary = {
	WeaponData.DamageType.SLASH: 1.0,
	WeaponData.DamageType.BLUNT: 1.0,
	WeaponData.DamageType.PIERCE: 1.0,
	WeaponData.DamageType.FIRE: 1.0,
	WeaponData.DamageType.ICE: 1.0,
	WeaponData.DamageType.POISON: 1.0,
}

## Get armor value for a specific damage type
func get_armor_for_type(damage_type: int) -> float:
	if armor_values.has(damage_type):
		return armor_values[damage_type]
	return 1.0  # Default

## Get total armor (sum of all types, for display purposes)
func get_total_armor() -> float:
	var total := 0.0
	for value in armor_values.values():
		total += value
	return total / armor_values.size()  # Average armor across types

# Set bonus system
@export var armor_set_id: String = ""  # e.g., "pig", "deer" - pieces with same ID form a set
@export var set_bonus: SetBonus = SetBonus.NONE  # Bonus when full set is worn

# Movement speed modifier (negative = slower, e.g., -0.05 = 5% slower)
# Used for heavy tank armor that trades speed for defense
@export var speed_modifier: float = 0.0

# Visual customization - colors to apply to player body parts when worn
@export var primary_color: Color = Color(0.5, 0.5, 0.5, 1.0)  # Main armor color
@export var secondary_color: Color = Color(0.3, 0.3, 0.3, 1.0)  # Accent color

## Get a plain dictionary representation for networking
func to_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"display_name": display_name,
		"description": description,
		"max_stack_size": max_stack_size,
		"weight": weight,
		"armor_slot": armor_slot,
		"armor_values": armor_values,
		"durability": durability,
		"armor_set_id": armor_set_id,
		"set_bonus": set_bonus,
	}

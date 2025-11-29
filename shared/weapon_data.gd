extends Resource
class_name WeaponData

## WeaponData - Resource for weapon items (swords, axes, bows, wands)
## Contains all ItemData properties plus weapon-specific properties

# ItemData properties (copied to avoid circular dependency)
@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var max_stack_size: int = 1
@export var weight: float = 1.0

enum ItemType {
	RESOURCE,
	WEAPON,
	SHIELD,
	ARMOR,
	CONSUMABLE,
	TOOL,
	BUILDABLE,
}
var item_type: ItemType = ItemType.WEAPON

enum DamageType {
	SLASH,    # Swords, axes - good vs unarmored
	BLUNT,    # Clubs, hammers - good vs armored
	PIERCE,   # Spears, arrows - good vs armor
	FIRE,     # Fire wands - magic damage
	ICE,      # Ice wands - magic damage
	POISON,   # Poison weapons
}

enum WeaponType {
	MELEE_ONE_HAND,   # Sword, axe, club
	MELEE_TWO_HAND,   # Greatsword, battleaxe
	RANGED,           # Bow, crossbow
	MAGIC,            # Wands, staves
}

@export var weapon_type: WeaponType = WeaponType.MELEE_ONE_HAND
@export var damage: float = 10.0
@export var damage_type: DamageType = DamageType.SLASH
@export var attack_speed: float = 1.0  # Attacks per second
@export var knockback: float = 5.0
@export var durability: int = 100
@export var stamina_cost: float = 10.0
@export var parry_window: float = 0.15  # Time window (seconds) to successfully parry after starting block

# Tool type for environmental object requirements (axe, pickaxe, blunt, etc.)
# Empty string means no special tool type (e.g., fists, generic weapons)
@export var tool_type: String = ""

# For ranged weapons
@export var projectile_scene: PackedScene = null
@export var projectile_speed: float = 30.0

# Visual representation (spawned in player hand when equipped)
@export var weapon_scene: PackedScene = null

func _init() -> void:
	item_type = ItemType.WEAPON
	max_stack_size = 1  # Weapons don't stack

## Get a plain dictionary representation for networking
func to_dict() -> Dictionary:
	var base = {
		"item_id": item_id,
		"display_name": display_name,
		"description": description,
		"item_type": item_type,
		"max_stack_size": max_stack_size,
		"weight": weight,
	}
	base["weapon_type"] = weapon_type
	base["damage"] = damage
	base["damage_type"] = damage_type
	base["attack_speed"] = attack_speed
	base["knockback"] = knockback
	base["durability"] = durability
	base["stamina_cost"] = stamina_cost
	base["parry_window"] = parry_window
	base["tool_type"] = tool_type
	base["projectile_speed"] = projectile_speed
	return base

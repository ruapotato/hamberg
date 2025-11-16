extends Resource
class_name ShieldData

## ShieldData - Resource for shield items
## Contains all ItemData properties plus shield-specific properties

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
var item_type: ItemType = ItemType.SHIELD

enum ShieldType {
	BUCKLER,       # Small shield - low block, high parry bonus
	ROUND,         # Medium shield - medium block, medium parry
	TOWER,         # Large shield - high block, no parry bonus
}

@export var shield_type: ShieldType = ShieldType.ROUND
@export var block_armor: float = 10.0  # Amount of damage blocked
@export var parry_bonus: float = 2.0   # Damage multiplier on successful parry
@export var parry_window: float = 0.3  # Time window for perfect parry (seconds)
@export var durability: int = 100
@export var stamina_drain_per_hit: float = 5.0  # Stamina used when blocking

# Visual representation (spawned in player hand when equipped)
@export var shield_scene: PackedScene = null

func _init() -> void:
	item_type = ItemType.SHIELD
	max_stack_size = 1  # Shields don't stack

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
	base["shield_type"] = shield_type
	base["block_armor"] = block_armor
	base["parry_bonus"] = parry_bonus
	base["parry_window"] = parry_window
	base["durability"] = durability
	base["stamina_drain_per_hit"] = stamina_drain_per_hit
	return base

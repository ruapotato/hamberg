extends Resource
class_name ItemData

## ItemData - Base resource for all items in the game
## Defines common properties like name, description, icon, stack size, etc.

enum ItemType {
	RESOURCE,      # Wood, stone, resin, etc.
	WEAPON,        # Swords, axes, bows, etc.
	SHIELD,        # Tower shield, round shield, buckler
	ARMOR,         # Helmet, chest, legs
	CONSUMABLE,    # Food, potions
	TOOL,          # Hammer, hoe, cultivator
	BUILDABLE,     # Workbench, furniture
	ACCESSORY,     # Special items like Cyclops Eye (equippable with effects)
	BOSS_SUMMON,   # Items that summon bosses when used/purchased
}

@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var item_type: ItemType = ItemType.RESOURCE
@export var max_stack_size: int = 50
@export var weight: float = 1.0

## Get a plain dictionary representation for networking
func to_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"display_name": display_name,
		"description": description,
		"item_type": item_type,
		"max_stack_size": max_stack_size,
		"weight": weight,
	}

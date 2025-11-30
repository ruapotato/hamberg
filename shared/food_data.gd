extends "res://shared/item_data.gd"
class_name FoodData

## FoodData - Data class for consumable food items
## Defines stat bonuses when eaten (Valheim-style food system)

# Stat bonuses when eaten
@export var health_bonus: float = 0.0      # Added to max health
@export var stamina_bonus: float = 0.0     # Added to max stamina
@export var bp_bonus: float = 0.0          # Added to max brain power
@export var duration: float = 600.0        # How long the food buff lasts (seconds)

# Healing over time (optional)
@export var heal_per_second: float = 0.0   # HP regen while buff active

func _init() -> void:
	item_type = ItemType.CONSUMABLE

## Get a plain dictionary representation for networking
func to_dict() -> Dictionary:
	var base = super.to_dict()
	base["health_bonus"] = health_bonus
	base["stamina_bonus"] = stamina_bonus
	base["bp_bonus"] = bp_bonus
	base["duration"] = duration
	base["heal_per_second"] = heal_per_second
	return base

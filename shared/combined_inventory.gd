extends RefCounted

## CombinedInventory - Wrapper that combines player inventory with nearby chests for crafting
## This enables "magic chest" behavior where nearby storage contributes to crafting
## Implements the same interface as Inventory (has_item, get_item_count, remove_item, add_item)

var player_inventory: Node = null
var nearby_chests: Array = []  # Array of chest nodes

const CHEST_SEARCH_RADIUS: float = 15.0  # How far from player/workbench to search for chests

func _init(p_inventory: Node = null, p_chests: Array = []) -> void:
	player_inventory = p_inventory
	nearby_chests = p_chests

## Check if combined inventory has at least the specified amount of an item
func has_item(item_name: String, amount: int = 1) -> bool:
	return get_item_count(item_name) >= amount

## Get total count of an item across player inventory and all nearby chests
func get_item_count(item_name: String) -> int:
	var total := 0

	# Count from player inventory
	if player_inventory and player_inventory.has_method("get_item_count"):
		total += player_inventory.get_item_count(item_name)

	# Count from all nearby chests
	for chest in nearby_chests:
		if chest and is_instance_valid(chest) and chest.has_method("get_item_count"):
			total += chest.get_item_count(item_name)

	return total

## Remove items from combined inventory (chests first, then player inventory)
## Returns true if successful, false if not enough items
func remove_item(item_name: String, amount: int) -> bool:
	if not has_item(item_name, amount):
		return false

	var remaining = amount

	# Remove from chests first (preserve player inventory when possible)
	for chest in nearby_chests:
		if remaining <= 0:
			break
		if chest and is_instance_valid(chest) and chest.has_method("remove_item"):
			var chest_count = chest.get_item_count(item_name)
			if chest_count > 0:
				var to_remove = min(chest_count, remaining)
				var removed = chest.remove_item(item_name, to_remove)
				remaining -= removed

	# Remove remainder from player inventory
	if remaining > 0 and player_inventory and player_inventory.has_method("remove_item"):
		if not player_inventory.remove_item(item_name, remaining):
			# This shouldn't happen if has_item returned true
			push_error("[CombinedInventory] Failed to remove remaining %d x %s from player" % [remaining, item_name])
			return false

	return true

## Add items to player inventory (crafted items always go to player)
## Returns amount that couldn't fit (overflow)
func add_item(item_name: String, amount: int) -> int:
	if player_inventory and player_inventory.has_method("add_item"):
		return player_inventory.add_item(item_name, amount)
	return amount  # All overflow if no player inventory

## Get the player inventory reference
func get_player_inventory() -> Node:
	return player_inventory

## Get the list of nearby chests
func get_nearby_chests() -> Array:
	return nearby_chests

## Get inventory data for display (combines all sources)
func get_inventory_data() -> Array:
	# Just return player inventory data - this is for compatibility
	if player_inventory and player_inventory.has_method("get_inventory_data"):
		return player_inventory.get_inventory_data()
	return []

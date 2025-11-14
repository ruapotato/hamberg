extends Node

## Inventory - Server-authoritative player inventory system
## Handles item storage, stacking, and management

const MAX_SLOTS: int = 30  # 5 rows x 6 columns
const MAX_STACK_SIZE: Dictionary = {
	"wood": 50,
	"stone": 50,
	"iron": 50,
	"copper": 50,
	"resin": 50,
}

# Inventory data: Array of {item: String, amount: int}
var slots: Array[Dictionary] = []
var owner_id: int = -1

func _init(player_id: int = -1) -> void:
	owner_id = player_id
	# Initialize empty slots
	slots.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		slots[i] = {}

## Add item to inventory (returns amount that couldn't fit)
func add_item(item_name: String, amount: int) -> int:
	var remaining := amount

	# First, try to stack with existing items
	for i in MAX_SLOTS:
		if slots[i].is_empty():
			continue

		if slots[i].get("item") == item_name:
			var current_amount: int = slots[i].get("amount", 0)
			var max_stack: int = MAX_STACK_SIZE.get(item_name, 99)
			var can_add := mini(remaining, max_stack - current_amount)

			if can_add > 0:
				slots[i]["amount"] = current_amount + can_add
				remaining -= can_add

			if remaining == 0:
				return 0

	# Then, fill empty slots
	for i in MAX_SLOTS:
		if slots[i].is_empty():
			var max_stack: int = MAX_STACK_SIZE.get(item_name, 99)
			var can_add := mini(remaining, max_stack)

			slots[i] = {
				"item": item_name,
				"amount": can_add
			}
			remaining -= can_add

			if remaining == 0:
				return 0

	# Return whatever couldn't fit
	return remaining

## Remove item from inventory (returns true if successful)
func remove_item(item_name: String, amount: int) -> bool:
	if not has_item(item_name, amount):
		return false

	var to_remove := amount

	# Remove from slots
	for i in MAX_SLOTS:
		if slots[i].is_empty():
			continue

		if slots[i].get("item") == item_name:
			var current_amount: int = slots[i].get("amount", 0)
			var remove_amount := mini(to_remove, current_amount)

			slots[i]["amount"] = current_amount - remove_amount
			to_remove -= remove_amount

			# Clear slot if empty
			if slots[i]["amount"] <= 0:
				slots[i] = {}

			if to_remove == 0:
				return true

	return false

## Check if inventory has enough of an item
func has_item(item_name: String, amount: int) -> bool:
	var total := 0

	for slot in slots:
		if slot.get("item") == item_name:
			total += slot.get("amount", 0)

	return total >= amount

## Get total amount of an item
func get_item_count(item_name: String) -> int:
	var total := 0

	for slot in slots:
		if slot.get("item") == item_name:
			total += slot.get("amount", 0)

	return total

## Get inventory as array (for syncing to client)
func get_inventory_data() -> Array:
	return slots.duplicate(true)

## Set inventory from data (when syncing from server)
func set_inventory_data(data: Array) -> void:
	slots = data.duplicate(true)
	slots.resize(MAX_SLOTS)

## Clear all items
func clear() -> void:
	for i in MAX_SLOTS:
		slots[i] = {}

## Swap two inventory slots
func swap_slots(slot_a: int, slot_b: int) -> void:
	if slot_a < 0 or slot_a >= MAX_SLOTS or slot_b < 0 or slot_b >= MAX_SLOTS:
		push_error("[Inventory] Invalid slot indices for swap: %d, %d" % [slot_a, slot_b])
		return

	var temp = slots[slot_a].duplicate(true)
	slots[slot_a] = slots[slot_b].duplicate(true)
	slots[slot_b] = temp

	print("[Inventory] Swapped slots %d and %d" % [slot_a, slot_b])

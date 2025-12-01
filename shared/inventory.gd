extends Node

## Inventory - Server-authoritative player inventory system
## Handles item storage, stacking, and management

const MAX_SLOTS: int = 30  # 5 rows x 6 columns

## Get max stack size for an item (uses ItemDatabase if available, fallback to 99)
func _get_max_stack_size(item_name: String) -> int:
	if ItemDatabase:
		return ItemDatabase.get_max_stack_size(item_name)
	# Fallback for legacy items or if ItemDatabase isn't loaded yet
	return 99

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
			var max_stack: int = _get_max_stack_size(item_name)
			var can_add := mini(remaining, max_stack - current_amount)

			if can_add > 0:
				slots[i]["amount"] = current_amount + can_add
				remaining -= can_add

			if remaining == 0:
				return 0

	# Then, fill empty slots
	for i in MAX_SLOTS:
		if slots[i].is_empty():
			var max_stack: int = _get_max_stack_size(item_name)
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
	# Build new typed array manually to avoid type mismatch
	var new_slots: Array[Dictionary] = []
	new_slots.resize(MAX_SLOTS)

	# Copy each element
	for i in range(MAX_SLOTS):
		if i < data.size() and data[i] is Dictionary:
			new_slots[i] = data[i].duplicate(true)
		else:
			new_slots[i] = {}

	# Replace slots
	slots = new_slots

## Clear all items
func clear() -> void:
	for i in MAX_SLOTS:
		slots[i] = {}

## Swap two inventory slots (or merge if same item type)
func swap_slots(slot_a: int, slot_b: int) -> void:
	if slot_a < 0 or slot_a >= MAX_SLOTS or slot_b < 0 or slot_b >= MAX_SLOTS:
		push_error("[Inventory] Invalid slot indices for swap: %d, %d" % [slot_a, slot_b])
		return

	var data_a = slots[slot_a]
	var data_b = slots[slot_b]

	# Check if both slots have the same item - merge stacks
	var item_a = data_a.get("item", "")
	var item_b = data_b.get("item", "")

	if not item_a.is_empty() and item_a == item_b:
		# Same item type - merge stacks
		var amount_a: int = data_a.get("amount", 0)
		var amount_b: int = data_b.get("amount", 0)
		var max_stack: int = _get_max_stack_size(item_a)

		var total = amount_a + amount_b
		if total <= max_stack:
			# Everything fits in slot_b
			slots[slot_b] = {"item": item_a, "amount": total}
			slots[slot_a] = {}
			print("[Inventory] Merged slots %d and %d: %d x %s" % [slot_a, slot_b, total, item_a])
		else:
			# Fill slot_b to max, leave remainder in slot_a
			slots[slot_b] = {"item": item_a, "amount": max_stack}
			slots[slot_a] = {"item": item_a, "amount": total - max_stack}
			print("[Inventory] Partial merge slots %d and %d: %d in target, %d remaining" % [slot_a, slot_b, max_stack, total - max_stack])
		return

	# Different items or one empty - do a regular swap
	var temp = slots[slot_a].duplicate(true)
	slots[slot_a] = slots[slot_b].duplicate(true)
	slots[slot_b] = temp

	print("[Inventory] Swapped slots %d and %d" % [slot_a, slot_b])

## Set a specific slot to an item and amount (for chest transfers)
func set_slot(slot_index: int, item_name: String, amount: int) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		push_error("[Inventory] Invalid slot index: %d" % slot_index)
		return

	if item_name.is_empty() or amount <= 0:
		slots[slot_index] = {}
	else:
		slots[slot_index] = {"item": item_name, "amount": amount}

## Remove a specific amount from a specific slot (for shop selling)
func remove_item_at_slot(slot_index: int, amount: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		push_error("[Inventory] Invalid slot index: %d" % slot_index)
		return false

	if slots[slot_index].is_empty():
		return false

	var current_amount: int = slots[slot_index].get("amount", 0)
	if current_amount < amount:
		return false

	var new_amount = current_amount - amount
	if new_amount <= 0:
		slots[slot_index] = {}
	else:
		slots[slot_index]["amount"] = new_amount

	return true

## Get data for a specific slot
func get_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return {}
	return slots[slot_index]

## Check if inventory has space for an item
func has_space_for(item_name: String, amount: int) -> bool:
	var remaining := amount
	var max_stack: int = _get_max_stack_size(item_name)

	# Check existing stacks
	for slot in slots:
		if slot.get("item") == item_name:
			var current_amount: int = slot.get("amount", 0)
			var can_add := max_stack - current_amount
			remaining -= can_add
			if remaining <= 0:
				return true

	# Check empty slots
	for slot in slots:
		if slot.is_empty():
			remaining -= max_stack
			if remaining <= 0:
				return true

	return remaining <= 0

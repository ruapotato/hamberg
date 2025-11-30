class_name ServerChestStorage
extends RefCounted

## ServerChestStorage - Handles chest inventory storage and transfers

var server: Node

func _init(s: Node) -> void:
	server = s

# =============================================================================
# CHEST INVENTORY ACCESS
# =============================================================================

## Get chest inventory array
func get_chest_inventory(chest_network_id: int) -> Array:
	if chest_network_id not in server.placed_buildables:
		return []

	var buildable_data = server.placed_buildables[chest_network_id]
	return buildable_data.get("inventory", [])

## Set a chest slot
func set_chest_slot(chest_network_id: int, slot_index: int, item_id: String, quantity: int) -> void:
	if chest_network_id not in server.placed_buildables:
		return

	var buildable_data = server.placed_buildables[chest_network_id]
	var inventory = buildable_data.get("inventory", [])

	# Expand inventory if needed
	while inventory.size() <= slot_index:
		inventory.append({"item_id": "", "quantity": 0})

	inventory[slot_index] = {"item_id": item_id, "quantity": quantity}
	buildable_data["inventory"] = inventory

## Add item to chest (finds first available slot)
func add_item_to_chest(chest_network_id: int, item_id: String, quantity: int) -> int:
	if chest_network_id not in server.placed_buildables:
		return quantity

	var buildable_data = server.placed_buildables[chest_network_id]
	var inventory = buildable_data.get("inventory", [])

	# Initialize inventory if needed (20 slots for chest)
	while inventory.size() < 20:
		inventory.append({"item_id": "", "quantity": 0})

	var remaining = quantity

	# First try to stack with existing items
	for i in range(inventory.size()):
		if remaining <= 0:
			break
		var slot = inventory[i]
		if slot.item_id == item_id:
			var max_stack = 99
			var can_add = min(remaining, max_stack - slot.quantity)
			if can_add > 0:
				slot.quantity += can_add
				remaining -= can_add

	# Then find empty slots
	for i in range(inventory.size()):
		if remaining <= 0:
			break
		var slot = inventory[i]
		if slot.item_id == "" or slot.quantity <= 0:
			var add_amount = min(remaining, 99)
			inventory[i] = {"item_id": item_id, "quantity": add_amount}
			remaining -= add_amount

	buildable_data["inventory"] = inventory
	return remaining

# =============================================================================
# CHEST OPEN/CLOSE
# =============================================================================

## Handle player opening a chest
func handle_open_chest(peer_id: int, chest_network_id: int) -> void:
	if chest_network_id not in server.placed_buildables:
		print("[Server] Chest %d not found" % chest_network_id)
		return

	server.player_open_chests[peer_id] = chest_network_id
	print("[Server] Player %d opened chest %d" % [peer_id, chest_network_id])

	# Send chest inventory to player
	var inventory = get_chest_inventory(chest_network_id)
	NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, inventory)

## Handle player closing a chest
func handle_close_chest(peer_id: int, chest_network_id: int) -> void:
	if peer_id in server.player_open_chests:
		server.player_open_chests.erase(peer_id)
	print("[Server] Player %d closed chest %d" % [peer_id, chest_network_id])

# =============================================================================
# CHEST TRANSFERS
# =============================================================================

## Transfer item from chest to player inventory
func handle_chest_to_player(peer_id: int, chest_network_id: int, chest_slot: int, quantity: int) -> void:
	if peer_id not in server.spawned_players:
		return
	if chest_network_id not in server.placed_buildables:
		return

	var player = server.spawned_players[peer_id]
	var inventory = get_chest_inventory(chest_network_id)

	if chest_slot < 0 or chest_slot >= inventory.size():
		return

	var slot_data = inventory[chest_slot]
	if slot_data.item_id == "" or slot_data.quantity <= 0:
		return

	var take_amount = min(quantity, slot_data.quantity)
	var item_id = slot_data.item_id

	# Try to add to player inventory
	if player.inventory:
		var remaining = player.inventory.add_item(item_id, take_amount)
		var actually_taken = take_amount - remaining

		if actually_taken > 0:
			# Update chest slot
			slot_data.quantity -= actually_taken
			if slot_data.quantity <= 0:
				slot_data.item_id = ""
				slot_data.quantity = 0

			# Sync both inventories
			NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())
			NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, inventory)

			print("[Server] Transferred %d %s from chest to player" % [actually_taken, item_id])

## Transfer item from player inventory to chest
func handle_player_to_chest(peer_id: int, chest_network_id: int, player_slot: int, quantity: int) -> void:
	if peer_id not in server.spawned_players:
		return
	if chest_network_id not in server.placed_buildables:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory:
		return

	var slot_data = player.inventory.get_slot(player_slot)
	if slot_data.item_id == "" or slot_data.quantity <= 0:
		return

	var transfer_amount = min(quantity, slot_data.quantity)
	var item_id = slot_data.item_id

	# Try to add to chest
	var remaining = add_item_to_chest(chest_network_id, item_id, transfer_amount)
	var actually_transferred = transfer_amount - remaining

	if actually_transferred > 0:
		# Remove from player inventory
		player.inventory.remove_item_at(player_slot, actually_transferred)

		# Sync both inventories
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())
		var chest_inv = get_chest_inventory(chest_network_id)
		NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, chest_inv)

		print("[Server] Transferred %d %s from player to chest" % [actually_transferred, item_id])

## Swap items within chest
func handle_chest_swap(peer_id: int, chest_network_id: int, from_slot: int, to_slot: int) -> void:
	if chest_network_id not in server.placed_buildables:
		return

	var inventory = get_chest_inventory(chest_network_id)

	# Expand if needed
	var max_slot = max(from_slot, to_slot)
	while inventory.size() <= max_slot:
		inventory.append({"item_id": "", "quantity": 0})

	# Swap
	var temp = inventory[from_slot]
	inventory[from_slot] = inventory[to_slot]
	inventory[to_slot] = temp

	# Sync
	NetworkManager.rpc_sync_chest_inventory.rpc_id(peer_id, chest_network_id, inventory)

## Quick deposit - deposit matching items from player to nearby chests
func handle_quick_deposit(peer_id: int, position: Array) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory:
		return

	var player_pos = Vector3(position[0], position[1], position[2])

	# Find nearby chests
	var nearby_chests = get_nearby_chests(player_pos, 5.0)

	if nearby_chests.is_empty():
		print("[Server] No chests nearby for quick deposit")
		return

	var deposited_count = 0

	# For each item in player inventory, try to deposit to matching chest stacks
	for slot_idx in range(player.inventory.get_slot_count()):
		var slot_data = player.inventory.get_slot(slot_idx)
		if slot_data.item_id == "" or slot_data.quantity <= 0:
			continue

		var item_id = slot_data.item_id

		# Try each chest
		for chest_id in nearby_chests:
			var chest_inv = get_chest_inventory(chest_id)

			# Only deposit if chest already has this item type
			var has_item = false
			for chest_slot in chest_inv:
				if chest_slot.item_id == item_id:
					has_item = true
					break

			if has_item:
				var remaining = add_item_to_chest(chest_id, item_id, slot_data.quantity)
				var deposited = slot_data.quantity - remaining

				if deposited > 0:
					player.inventory.remove_item_at(slot_idx, deposited)
					deposited_count += deposited

	if deposited_count > 0:
		print("[Server] Quick deposited %d items" % deposited_count)
		NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())

## Get nearby chests
func get_nearby_chests(position: Vector3, radius: float) -> Array:
	var nearby = []

	for network_id in server.placed_buildables:
		var data = server.placed_buildables[network_id]
		if data.piece_name != "chest":
			continue

		var chest_pos = Vector3(data.position[0], data.position[1], data.position[2])
		if chest_pos.distance_to(position) <= radius:
			nearby.append(network_id)

	return nearby

class_name ServerInventory
extends RefCounted

## ServerInventory - Handles inventory operations, crafting, and equipment

var server: Node

func _init(s: Node) -> void:
	server = s

# =============================================================================
# PICKUP
# =============================================================================

## Handle item pickup request
func handle_pickup_request(peer_id: int, item_network_id: int) -> void:
	# Check if already picked up
	if item_network_id in server.picked_up_items:
		print("[Server] Item %d already picked up" % item_network_id)
		return

	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory:
		return

	# Mark as picked up
	server.picked_up_items[item_network_id] = true

	# Broadcast pickup to all clients
	NetworkManager.rpc_pickup_resource_item.rpc(item_network_id)
	print("[Server] Player %d picked up resource item %d" % [peer_id, item_network_id])

# =============================================================================
# CRAFTING
# =============================================================================

## Handle craft request
func handle_craft_request(peer_id: int, recipe_id: String) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory:
		return

	# Get recipe from crafting recipes
	var CraftingRecipes = preload("res://shared/crafting_recipes.gd")
	var recipe = CraftingRecipes.get_recipe(recipe_id)

	if not recipe:
		print("[Server] Unknown recipe: %s" % recipe_id)
		return

	# Check if player has ingredients
	var ingredients = recipe.get("ingredients", {})
	for item_id in ingredients:
		var needed = ingredients[item_id]
		if not player.inventory.has_item(item_id, needed):
			print("[Server] Player missing ingredient: %s x%d" % [item_id, needed])
			return

	# Consume ingredients
	for item_id in ingredients:
		var needed = ingredients[item_id]
		player.inventory.remove_item(item_id, needed)

	# Give result
	var result_id = recipe.get("result", "")
	var result_count = recipe.get("count", 1)

	if result_id:
		player.inventory.add_item(result_id, result_count)
		print("[Server] Player %d crafted %d %s" % [peer_id, result_count, result_id])

	# Sync inventory
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())

# =============================================================================
# EQUIPMENT
# =============================================================================

## Handle equip request
func handle_equip_request(peer_id: int, slot_index: int) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory or not player.equipment:
		return

	var slot_data = player.inventory.get_slot(slot_index)
	if slot_data.item_id == "":
		return

	# Get item data to determine equipment slot
	var item_data = ItemDatabase.get_item(slot_data.item_id)
	if not item_data:
		return

	var Equipment = preload("res://shared/equipment.gd")
	var equip_slot = -1

	# Determine slot based on item type
	if item_data is preload("res://shared/weapon_data.gd"):
		equip_slot = Equipment.EquipmentSlot.MAIN_HAND
	elif item_data is preload("res://shared/shield_data.gd"):
		equip_slot = Equipment.EquipmentSlot.OFF_HAND
	elif "slot" in item_data:
		equip_slot = item_data.slot

	if equip_slot < 0:
		print("[Server] Item %s cannot be equipped" % slot_data.item_id)
		return

	# Unequip current item in that slot (if any)
	var current_equipped = player.equipment.get_equipped_item(equip_slot)
	if current_equipped:
		player.inventory.add_item(current_equipped, 1)

	# Remove from inventory and equip
	player.inventory.remove_item_at(slot_index, 1)
	player.equipment.equip_item(equip_slot, slot_data.item_id)

	print("[Server] Player %d equipped %s" % [peer_id, slot_data.item_id])

	# Sync both
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())
	NetworkManager.rpc_sync_equipment.rpc_id(peer_id, player.equipment.get_as_dict())

## Handle unequip request
func handle_unequip_request(peer_id: int, equip_slot: int) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory or not player.equipment:
		return

	var item_id = player.equipment.get_equipped_item(equip_slot)
	if not item_id:
		return

	# Add to inventory
	var remaining = player.inventory.add_item(item_id, 1)
	if remaining > 0:
		print("[Server] Inventory full, can't unequip")
		return

	# Unequip
	player.equipment.unequip_slot(equip_slot)
	print("[Server] Player %d unequipped %s" % [peer_id, item_id])

	# Sync both
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())
	NetworkManager.rpc_sync_equipment.rpc_id(peer_id, player.equipment.get_as_dict())

## Handle swap slots request
func handle_swap_slots(peer_id: int, from_slot: int, to_slot: int) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory:
		return

	player.inventory.swap_slots(from_slot, to_slot)
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())

## Handle drop item request
func handle_drop_item(peer_id: int, slot_index: int, quantity: int) -> void:
	if peer_id not in server.spawned_players:
		return

	var player = server.spawned_players[peer_id]
	if not player.inventory:
		return

	var slot_data = player.inventory.get_slot(slot_index)
	if slot_data.item_id == "":
		return

	var drop_amount = min(quantity, slot_data.quantity)
	player.inventory.remove_item_at(slot_index, drop_amount)

	# TODO: Spawn dropped item in world

	print("[Server] Player %d dropped %d %s" % [peer_id, drop_amount, slot_data.item_id])
	NetworkManager.rpc_sync_inventory.rpc_id(peer_id, player.inventory.get_as_array())

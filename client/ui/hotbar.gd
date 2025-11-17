extends Control

## Hotbar - Always-visible UI showing first 9 inventory slots
## Supports number key (1-9) selection like Valheim

signal hotbar_selection_changed(slot_index: int, item_name: String)

const InventorySlot = preload("res://client/ui/inventory_slot.tscn")
const HOTBAR_SIZE: int = 9

var slots: Array[Node] = []
var selected_slot: int = 0
var player_inventory: Node = null

@onready var slots_container: HBoxContainer = $Background/SlotsContainer

func _ready() -> void:
	_create_slots()
	_update_selection()

func _process(_delta: float) -> void:
	# Handle number keys 1-9 for slot selection
	for i in range(1, 10):
		if Input.is_action_just_pressed("hotbar_" + str(i)):
			select_slot(i - 1)

func _create_slots() -> void:
	slots.clear()

	for i in HOTBAR_SIZE:
		var slot = InventorySlot.instantiate()
		slot.slot_index = i
		slot.is_hotbar_slot = true
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slots_container.add_child(slot)
		slots.append(slot)

func _on_slot_right_clicked(slot_index: int) -> void:
	if not player_inventory:
		return

	# Get the item in this slot
	var inventory_data = player_inventory.get_inventory_data()
	if slot_index >= inventory_data.size():
		return

	var slot_data = inventory_data[slot_index]
	if slot_data.is_empty():
		return

	var item_id = slot_data.get("item", "")
	if item_id.is_empty():
		return

	print("[Hotbar] Right-clicked slot %d with item: %s" % [slot_index, item_id])

	# Check if this is an equippable item
	var item_data = ItemDatabase.get_item(item_id)
	if not item_data:
		return

	# Determine which equipment slot to equip to based on item type
	var equip_slot = -1
	match item_data.item_type:
		ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL, ItemData.ItemType.RESOURCE:
			equip_slot = Equipment.EquipmentSlot.MAIN_HAND
		ItemData.ItemType.SHIELD:
			equip_slot = Equipment.EquipmentSlot.OFF_HAND
		_:
			print("[Hotbar] Item %s is not equippable" % item_id)
			return

	# Check if this item is already equipped - if so, unequip it
	var player = player_inventory.get_parent()
	if player and player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		var currently_equipped = equipment.get_equipped_item(equip_slot)

		if currently_equipped == item_id:
			# Item is already equipped - unequip it
			print("[Hotbar] Unequipping %s from equipment slot %d" % [item_id, equip_slot])
			NetworkManager.rpc_request_unequip_slot.rpc_id(1, equip_slot)
			return

	# Request to equip this item on the server (send equipment slot, not inventory slot)
	print("[Hotbar] Requesting to equip %s to equipment slot %d" % [item_id, equip_slot])
	NetworkManager.rpc_request_equip_item.rpc_id(1, equip_slot, item_id)

func _on_slot_clicked(slot_index: int) -> void:
	select_slot(slot_index)

## Select a hotbar slot and auto-equip the item
func select_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SIZE:
		return

	# If clicking the same slot, just update selection - don't re-equip
	var is_same_slot = (index == selected_slot)

	selected_slot = index
	_update_selection()

	# Get currently selected item
	var item_id = ""
	if player_inventory:
		var inventory_data = player_inventory.get_inventory_data()
		if index < inventory_data.size() and not inventory_data[index].is_empty():
			item_id = inventory_data[index].get("item", "")

	# Emit signal for build mode / equipment changes
	hotbar_selection_changed.emit(selected_slot, item_id)

	# Notify player of selection change
	if player_inventory and player_inventory.get_parent().has_method("on_hotbar_selection_changed"):
		player_inventory.get_parent().on_hotbar_selection_changed(selected_slot)

	# If selecting the same slot and item is equipped, unequip it (toggle behavior)
	if is_same_slot and not item_id.is_empty():
		var item_data = ItemDatabase.get_item(item_id)
		if item_data:
			var equip_slot = -1
			match item_data.item_type:
				ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL, ItemData.ItemType.RESOURCE:
					equip_slot = Equipment.EquipmentSlot.MAIN_HAND
				ItemData.ItemType.SHIELD:
					equip_slot = Equipment.EquipmentSlot.OFF_HAND

			if equip_slot != -1:
				# Check if this item is currently equipped
				var player = player_inventory.get_parent()
				if player and player.has_node("Equipment"):
					var equipment = player.get_node("Equipment")
					var currently_equipped = equipment.get_equipped_item(equip_slot)
					if currently_equipped == item_id:
						# Item is equipped - unequip it
						print("[Hotbar] Toggling off %s from equipment slot %d" % [item_id, equip_slot])
						NetworkManager.rpc_request_unequip_slot.rpc_id(1, equip_slot)
						return
					# If not equipped, fall through to equip logic below

	# Auto-equip the item ONLY if it's an equippable item (weapon, tool, or shield)
	if not item_id.is_empty():
		var item_data = ItemDatabase.get_item(item_id)
		if item_data:
			var equip_slot = -1
			match item_data.item_type:
				ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL, ItemData.ItemType.RESOURCE:
					equip_slot = Equipment.EquipmentSlot.MAIN_HAND
				ItemData.ItemType.SHIELD:
					equip_slot = Equipment.EquipmentSlot.OFF_HAND

			if equip_slot != -1:
				print("[Hotbar] Auto-equipping %s to equipment slot %d" % [item_id, equip_slot])
				NetworkManager.rpc_request_equip_item.rpc_id(1, equip_slot, item_id)

## Update visual selection (hotbar doesn't show selection, only equipped status)
func _update_selection() -> void:
	# Don't show selection border in hotbar - only equipped border matters
	for i in slots.size():
		slots[i].set_selected(false)

## Link to player's inventory for data sync
func set_player_inventory(inventory: Node) -> void:
	player_inventory = inventory

	# Connect to equipment changes
	var player = inventory.get_parent()
	if player and player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		if equipment and not equipment.equipment_changed.is_connected(_on_equipment_changed):
			equipment.equipment_changed.connect(_on_equipment_changed)

	refresh_display()

## Refresh hotbar display from inventory data
func refresh_display() -> void:
	if not player_inventory:
		return

	var inventory_data = player_inventory.get_inventory_data()

	# Get player's equipment to check what's equipped
	var player = player_inventory.get_parent()
	var equipment = null
	if player and player.has_node("Equipment"):
		equipment = player.get_node("Equipment")

	# Track which item IDs we've already marked as equipped (to avoid duplicates)
	var equipped_item_ids_seen: Array[String] = []

	for i in HOTBAR_SIZE:
		if i < inventory_data.size():
			slots[i].set_item_data(inventory_data[i])

			# Check if this item is equipped
			var slot_data = inventory_data[i]
			var item_id = slot_data.get("item", "")
			var is_equipped = false

			if equipment and not item_id.is_empty():
				# Check all equipment slots
				for equip_slot in Equipment.EquipmentSlot.values():
					var equipped_id = equipment.get_equipped_item(equip_slot)
					if equipped_id == item_id:
						# Only mark as equipped if this is the FIRST occurrence of this item
						if not equipped_item_ids_seen.has(item_id):
							is_equipped = true
							equipped_item_ids_seen.append(item_id)
						break

			slots[i].set_equipped(is_equipped)
		else:
			slots[i].set_item_data({})
			slots[i].set_equipped(false)

## Called when equipment changes
func _on_equipment_changed(_slot) -> void:
	# Refresh display to update equipped borders
	refresh_display()

## Get currently selected slot index
func get_selected_slot() -> int:
	return selected_slot

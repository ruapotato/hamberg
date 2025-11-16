extends Node
class_name Equipment

## Equipment - Manages equipped items (weapon, shield, armor)
## Server-authoritative with client synchronization

# Preload item classes
const ItemData = preload("res://shared/item_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")

signal equipment_changed(slot: EquipmentSlot)

enum EquipmentSlot {
	MAIN_HAND,     # Weapon or tool
	OFF_HAND,      # Shield or two-handed weapon (null)
	HEAD,          # Helmet
	CHEST,         # Chest armor
	LEGS,          # Leg armor
}

# Current equipped items: slot -> item_id
var equipped_items: Dictionary = {
	EquipmentSlot.MAIN_HAND: "",
	EquipmentSlot.OFF_HAND: "",
	EquipmentSlot.HEAD: "",
	EquipmentSlot.CHEST: "",
	EquipmentSlot.LEGS: "",
}

var owner_id: int = -1

func _init(player_id: int = -1) -> void:
	owner_id = player_id

## Equip an item to a slot
func equip_item(slot: EquipmentSlot, item_id: String) -> bool:
	# Validate item exists
	if not item_id.is_empty() and not ItemDatabase.has_item(item_id):
		push_error("[Equipment] Unknown item: %s" % item_id)
		return false

	# Check item type matches slot
	if not item_id.is_empty():
		var item_data = ItemDatabase.get_item(item_id)
		if not _is_valid_for_slot(item_data, slot):
			push_warning("[Equipment] Item %s cannot be equipped to slot %s" % [item_id, slot])
			return false

		# Valheim-style two-handed weapon restrictions:
		# 1. Two-handed weapons occupy both hands - clear off-hand when equipping
		if item_data is WeaponData and item_data.weapon_type == WeaponData.WeaponType.MELEE_TWO_HAND:
			if not equipped_items[EquipmentSlot.OFF_HAND].is_empty():
				print("[Equipment] Two-handed weapon equipped - clearing off-hand shield")
			equipped_items[EquipmentSlot.OFF_HAND] = ""  # Clear off-hand
			equipment_changed.emit(EquipmentSlot.OFF_HAND)

		# 2. Shields cannot be equipped with two-handed weapons - clear main hand if two-handed
		if item_data is ShieldData and slot == EquipmentSlot.OFF_HAND:
			var main_hand_item_id = equipped_items.get(EquipmentSlot.MAIN_HAND, "")
			if not main_hand_item_id.is_empty():
				var main_hand_item = ItemDatabase.get_item(main_hand_item_id)
				if main_hand_item is WeaponData and main_hand_item.weapon_type == WeaponData.WeaponType.MELEE_TWO_HAND:
					print("[Equipment] Shield cannot be equipped with two-handed weapon - clearing main hand")
					equipped_items[EquipmentSlot.MAIN_HAND] = ""
					equipment_changed.emit(EquipmentSlot.MAIN_HAND)

	# Equip item
	equipped_items[slot] = item_id
	equipment_changed.emit(slot)
	print("[Equipment] Equipped %s to slot %s" % [item_id if not item_id.is_empty() else "nothing", slot])
	return true

## Unequip an item from a slot
func unequip_slot(slot: EquipmentSlot) -> String:
	var item_id = equipped_items.get(slot, "")
	equipped_items[slot] = ""
	equipment_changed.emit(slot)
	print("[Equipment] Unequipped slot %s" % slot)
	return item_id

## Get equipped item in a slot
func get_equipped_item(slot: EquipmentSlot) -> String:
	return equipped_items.get(slot, "")

## Get equipped item data in a slot (returns ItemData or null)
func get_equipped_item_data(slot: EquipmentSlot):
	var item_id = get_equipped_item(slot)
	if item_id.is_empty():
		return null
	return ItemDatabase.get_item(item_id)

## Check if an item type is valid for a slot
func _is_valid_for_slot(item_data, slot: EquipmentSlot) -> bool:  # item_data is ItemData
	match slot:
		EquipmentSlot.MAIN_HAND:
			return item_data.item_type in [ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL]
		EquipmentSlot.OFF_HAND:
			return item_data.item_type == ItemData.ItemType.SHIELD
		EquipmentSlot.HEAD, EquipmentSlot.CHEST, EquipmentSlot.LEGS:
			return item_data.item_type == ItemData.ItemType.ARMOR
	return false

## Get equipment data for synchronization
func get_equipment_data() -> Dictionary:
	return equipped_items.duplicate()

## Set equipment from data (when syncing from server)
func set_equipment_data(data: Dictionary) -> void:
	for slot in EquipmentSlot.values():
		var item_id = data.get(slot, "")
		if equipped_items.get(slot, "") != item_id:
			equipped_items[slot] = item_id
			equipment_changed.emit(slot)

## Clear all equipment
func clear() -> void:
	for slot in EquipmentSlot.values():
		if not equipped_items.get(slot, "").is_empty():
			equipped_items[slot] = ""
			equipment_changed.emit(slot)

## Get the currently equipped weapon data (main hand) - returns WeaponData or null
func get_equipped_weapon():
	var item_data = get_equipped_item_data(EquipmentSlot.MAIN_HAND)
	if item_data is WeaponData:
		return item_data
	return null

## Get the currently equipped shield data (off hand) - returns ShieldData or null
func get_equipped_shield():
	var item_data = get_equipped_item_data(EquipmentSlot.OFF_HAND)
	if item_data is ShieldData:
		return item_data
	return null

## Check if a two-handed weapon is equipped
func is_two_handed_equipped() -> bool:
	var weapon = get_equipped_weapon()
	if weapon:
		return weapon.weapon_type == WeaponData.WeaponType.MELEE_TWO_HAND
	return false

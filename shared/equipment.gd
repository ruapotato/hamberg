extends Node
class_name Equipment

## Equipment - Manages equipped items (weapon, shield, armor)
## Server-authoritative with client synchronization

# Preload item classes
const ItemData = preload("res://shared/item_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")
const ArmorData = preload("res://shared/armor_data.gd")

signal equipment_changed(slot: EquipmentSlot)

enum EquipmentSlot {
	MAIN_HAND,     # Weapon or tool
	OFF_HAND,      # Shield or two-handed weapon (null)
	HEAD,          # Helmet
	CHEST,         # Chest armor
	LEGS,          # Leg armor
	CAPE,          # Cape/cloak
}

# Current equipped items: slot -> item_id
var equipped_items: Dictionary = {
	EquipmentSlot.MAIN_HAND: "",
	EquipmentSlot.OFF_HAND: "",
	EquipmentSlot.HEAD: "",
	EquipmentSlot.CHEST: "",
	EquipmentSlot.LEGS: "",
	EquipmentSlot.CAPE: "",
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
func _is_valid_for_slot(item_data, slot: EquipmentSlot) -> bool:  # item_data is ItemData or ArmorData
	match slot:
		EquipmentSlot.MAIN_HAND:
			# Allow weapons, tools, and placeable resources (like earth)
			return item_data.item_type in [ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL, ItemData.ItemType.RESOURCE]
		EquipmentSlot.OFF_HAND:
			return item_data.item_type == ItemData.ItemType.SHIELD
		EquipmentSlot.HEAD, EquipmentSlot.CHEST, EquipmentSlot.LEGS, EquipmentSlot.CAPE:
			# For armor, also check that the armor slot matches
			if item_data is ArmorData:
				var armor_slot_map = {
					EquipmentSlot.HEAD: ArmorData.ArmorSlot.HEAD,
					EquipmentSlot.CHEST: ArmorData.ArmorSlot.CHEST,
					EquipmentSlot.LEGS: ArmorData.ArmorSlot.LEGS,
					EquipmentSlot.CAPE: ArmorData.ArmorSlot.CAPE,
				}
				return item_data.armor_slot == armor_slot_map.get(slot, -1)
			return item_data.item_type == ItemData.ItemType.ARMOR
	return false

## Get equipment data for synchronization
func get_equipment_data() -> Dictionary:
	return equipped_items.duplicate()

## Set equipment from data (when syncing from server)
func set_equipment_data(data: Dictionary) -> void:
	print("[Equipment] set_equipment_data received: %s" % data)
	for slot in EquipmentSlot.values():
		# Try enum key, int key, and string key (JSON/RPC may convert to string)
		var item_id = data.get(slot, data.get(int(slot), data.get(str(slot), "")))
		print("[Equipment]   Slot %d -> item_id: '%s'" % [slot, item_id])
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

## Get total armor value from all equipped armor pieces
func get_total_armor() -> float:
	var total: float = 0.0
	for slot in [EquipmentSlot.HEAD, EquipmentSlot.CHEST, EquipmentSlot.LEGS, EquipmentSlot.CAPE]:
		var item_data = get_equipped_item_data(slot)
		if item_data is ArmorData:
			total += item_data.armor_value
	return total

## Get all equipped armor pieces as ArmorData
func get_equipped_armor() -> Array:
	var armor_pieces: Array = []
	for slot in [EquipmentSlot.HEAD, EquipmentSlot.CHEST, EquipmentSlot.LEGS, EquipmentSlot.CAPE]:
		var item_data = get_equipped_item_data(slot)
		if item_data is ArmorData:
			armor_pieces.append(item_data)
	return armor_pieces

## Check if player has a full armor set equipped (all 4 pieces with same set_id)
func has_full_armor_set(set_id: String) -> bool:
	var armor_pieces = get_equipped_armor()
	if armor_pieces.size() < 4:
		return false

	for piece in armor_pieces:
		if piece.armor_set_id != set_id:
			return false
	return true

## Get the active set bonus (if any) - returns ArmorData.SetBonus enum value
func get_active_set_bonus():
	var armor_pieces = get_equipped_armor()

	if armor_pieces.size() < 4:
		return ArmorData.SetBonus.NONE

	# Check if all pieces are from the same set
	var first_set_id = armor_pieces[0].armor_set_id

	if first_set_id.is_empty():
		return ArmorData.SetBonus.NONE

	for piece in armor_pieces:
		if piece.armor_set_id != first_set_id:
			return ArmorData.SetBonus.NONE

	# All pieces match - return the set bonus from the first piece
	return armor_pieces[0].set_bonus

## Check if player has the pig double jump set bonus active
func has_double_jump_bonus() -> bool:
	return get_active_set_bonus() == ArmorData.SetBonus.PIG_DOUBLE_JUMP

## Check if player has the deer stamina saver set bonus active
func has_stamina_saver_bonus() -> bool:
	return get_active_set_bonus() == ArmorData.SetBonus.DEER_STAMINA_SAVER

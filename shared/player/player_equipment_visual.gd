class_name PlayerEquipmentVisual
extends RefCounted

## PlayerEquipmentVisual - Handles weapon and shield visual attachment
## Spawns and despawns 3D models when equipment changes

const Equipment = preload("res://shared/equipment.gd")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# EQUIPMENT CHANGE HANDLER
# =============================================================================

## Called when equipment changes (spawn/despawn visuals)
func on_equipment_changed(slot) -> void:
	print("[Player] Equipment changed in slot: %s" % slot)

	match slot:
		Equipment.EquipmentSlot.MAIN_HAND:
			update_weapon_visual()
		Equipment.EquipmentSlot.OFF_HAND:
			update_shield_visual()
		Equipment.EquipmentSlot.HEAD, Equipment.EquipmentSlot.CHEST, Equipment.EquipmentSlot.LEGS:
			# TODO: Implement armor visuals
			pass

# =============================================================================
# WEAPON VISUAL
# =============================================================================

## Update the main hand weapon visual
func update_weapon_visual() -> void:
	# Remove existing weapon visual and wrist pivot
	if player.equipped_weapon_visual:
		player.equipped_weapon_visual.queue_free()
		player.equipped_weapon_visual = null
	if player.weapon_wrist_pivot:
		player.weapon_wrist_pivot.queue_free()
		player.weapon_wrist_pivot = null

	# Get equipped weapon
	var weapon_id = player.equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)
	if weapon_id.is_empty():
		return

	# Get weapon data
	var weapon_data = ItemDatabase.get_item(weapon_id)
	if not weapon_data:
		push_error("[Player] Unknown weapon: %s" % weapon_id)
		return

	# Special case: fists have no visual
	if weapon_id == "fists":
		return

	# Load weapon scene
	var weapon_scene = weapon_data.get("weapon_scene")
	if not weapon_scene:
		push_warning("[Player] No weapon scene for: %s" % weapon_id)
		return

	# Instantiate weapon visual
	player.equipped_weapon_visual = weapon_scene.instantiate()

	# Create wrist pivot for natural weapon rotation during swings
	player.weapon_wrist_pivot = Node3D.new()
	player.weapon_wrist_pivot.name = "WristPivot"

	# Find right hand attachment point
	var right_hand_attach = _find_hand_attach_point("RightHand")
	if right_hand_attach:
		right_hand_attach.add_child(player.weapon_wrist_pivot)
		player.weapon_wrist_pivot.add_child(player.equipped_weapon_visual)

		# Rotate weapon 90 degrees forward so it points forward
		player.equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)

		# Apply mount point offset
		if player.equipped_weapon_visual.has_node("MountPoint"):
			var mount_point = player.equipped_weapon_visual.get_node("MountPoint")
			var rotated_offset = player.equipped_weapon_visual.basis * mount_point.position
			player.equipped_weapon_visual.position = -rotated_offset

		print("[Player] Equipped weapon visual: %s (with wrist pivot)" % weapon_id)
	else:
		# Fallback: attach to body container
		if player.body_container:
			player.body_container.add_child(player.weapon_wrist_pivot)
			player.weapon_wrist_pivot.add_child(player.equipped_weapon_visual)
			player.weapon_wrist_pivot.position = Vector3(0.3, 1.2, 0)
			player.equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
			print("[Player] Equipped weapon visual (fallback): %s" % weapon_id)
		else:
			player.weapon_wrist_pivot.queue_free()
			player.weapon_wrist_pivot = null
			player.equipped_weapon_visual.queue_free()
			player.equipped_weapon_visual = null
			push_warning("[Player] No attachment point for weapon")

# =============================================================================
# SHIELD VISUAL
# =============================================================================

## Update the off hand shield visual
func update_shield_visual() -> void:
	# Remove existing shield visual
	if player.equipped_shield_visual:
		player.equipped_shield_visual.queue_free()
		player.equipped_shield_visual = null

	# Get equipped shield
	var shield_id = player.equipment.get_equipped_item(Equipment.EquipmentSlot.OFF_HAND)
	if shield_id.is_empty():
		return

	# Get shield data
	var shield_data = ItemDatabase.get_item(shield_id)
	if not shield_data:
		push_error("[Player] Unknown shield: %s" % shield_id)
		return

	# Load shield scene
	var shield_scene = shield_data.get("shield_scene")
	if not shield_scene:
		push_warning("[Player] No shield scene for: %s" % shield_id)
		return

	# Instantiate shield visual
	player.equipped_shield_visual = shield_scene.instantiate()

	# Find left hand attachment point
	var left_hand_attach = _find_hand_attach_point("LeftHand")
	if left_hand_attach:
		left_hand_attach.add_child(player.equipped_shield_visual)
		player.equipped_shield_visual.rotation_degrees = Vector3(90, 0, 0)

		# Apply mount point offset
		if player.equipped_shield_visual.has_node("MountPoint"):
			var mount_point = player.equipped_shield_visual.get_node("MountPoint")
			player.equipped_shield_visual.position = -mount_point.position

		print("[Player] Equipped shield visual: %s" % shield_id)
	else:
		# Fallback: attach to body container
		if player.body_container:
			player.body_container.add_child(player.equipped_shield_visual)
			player.equipped_shield_visual.position = Vector3(-0.3, 1.2, 0)
			player.equipped_shield_visual.rotation_degrees = Vector3(90, 0, 0)
			print("[Player] Equipped shield visual (fallback): %s" % shield_id)
		else:
			player.equipped_shield_visual.queue_free()
			player.equipped_shield_visual = null
			push_warning("[Player] No attachment point for shield")

# =============================================================================
# HELPER
# =============================================================================

## Find a hand attachment point (HandAttach node in arm)
func _find_hand_attach_point(hand_name: String) -> Node3D:
	if not player.body_container:
		return null

	var arm_name = ""
	if hand_name == "RightHand":
		arm_name = "RightArm"
	elif hand_name == "LeftHand":
		arm_name = "LeftArm"
	else:
		return null

	if not player.body_container.has_node(arm_name):
		return null

	var arm = player.body_container.get_node(arm_name)
	if not arm or not is_instance_valid(arm):
		return null

	# Find HandAttach node in the arm (it's under Elbow)
	if arm.has_node("Elbow/HandAttach"):
		return arm.get_node("Elbow/HandAttach")
	if arm.has_node("HandAttach"):
		return arm.get_node("HandAttach")

	return null

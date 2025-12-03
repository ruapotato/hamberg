class_name PlayerEquipmentVisual
extends RefCounted

## PlayerEquipmentVisual - Handles weapon, shield, and armor visual attachment
## Spawns and despawns 3D models when equipment changes
## Changes player body colors based on equipped armor

const Equipment = preload("res://shared/equipment.gd")
const ArmorData = preload("res://shared/armor_data.gd")

var player: CharacterBody3D

# Default colors for unarmored player (skin-colored)
const DEFAULT_SKIN_COLOR: Color = Color(0.9, 0.75, 0.65, 1.0)  # Natural skin tone
const DEFAULT_CLOTHES_COLOR: Color = Color(0.7, 0.65, 0.6, 1.0)  # Light tan (minimal clothing)
const DEFAULT_PANTS_COLOR: Color = Color(0.6, 0.55, 0.5, 1.0)  # Slightly darker tan

# Cape visual node reference
var cape_visual: Node3D = null

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
		Equipment.EquipmentSlot.HEAD:
			update_head_armor_visual()
		Equipment.EquipmentSlot.CHEST:
			update_chest_armor_visual()
		Equipment.EquipmentSlot.LEGS:
			update_legs_armor_visual()
		Equipment.EquipmentSlot.CAPE:
			update_cape_visual()

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

		# Connect weapon hitbox for collision-based combat
		_setup_weapon_hitbox()

		print("[Player] Equipped weapon visual: %s (with wrist pivot)" % weapon_id)
	else:
		# Fallback: attach to body container
		if player.body_container:
			player.body_container.add_child(player.weapon_wrist_pivot)
			player.weapon_wrist_pivot.add_child(player.equipped_weapon_visual)
			player.weapon_wrist_pivot.position = Vector3(0.3, 1.2, 0)
			player.equipped_weapon_visual.rotation_degrees = Vector3(90, 0, 0)
			# Connect weapon hitbox for collision-based combat
			_setup_weapon_hitbox()
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
# WEAPON HITBOX SETUP
# =============================================================================

## Setup weapon hitbox for collision-based combat (Valheim-style)
func _setup_weapon_hitbox() -> void:
	# Clear any previous hitbox reference
	player.weapon_hitbox = null

	if not player.equipped_weapon_visual:
		return

	# Find the Hitbox Area3D in the weapon scene
	if player.equipped_weapon_visual.has_node("Hitbox"):
		player.weapon_hitbox = player.equipped_weapon_visual.get_node("Hitbox")

		# Connect body_entered signal for collision detection
		if not player.weapon_hitbox.body_entered.is_connected(_on_weapon_hitbox_body_entered):
			player.weapon_hitbox.body_entered.connect(_on_weapon_hitbox_body_entered)

		# Ensure hitbox starts disabled
		player.weapon_hitbox.monitoring = false
		var collision_shape = player.weapon_hitbox.get_node_or_null("CollisionShape3D")
		if collision_shape:
			collision_shape.disabled = true

		# DEBUG: Add visual mesh for hitbox
		_add_hitbox_debug_visual(player.weapon_hitbox, collision_shape)

		print("[Player] Weapon hitbox connected: %s" % player.equipped_weapon_visual.name)
	else:
		print("[Player] Weapon has no Hitbox node: %s" % player.equipped_weapon_visual.name)

## DEBUG: Add visual representation of hitbox
func _add_hitbox_debug_visual(hitbox: Area3D, collision_shape: CollisionShape3D) -> void:
	if not collision_shape or not collision_shape.shape:
		return

	# Remove existing debug mesh if any
	var existing = hitbox.get_node_or_null("DebugMesh")
	if existing:
		existing.queue_free()

	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "DebugMesh"

	# Create mesh matching the collision shape
	var shape = collision_shape.shape
	if shape is CapsuleShape3D:
		var capsule = CapsuleMesh.new()
		capsule.radius = shape.radius
		capsule.height = shape.height
		debug_mesh.mesh = capsule
	elif shape is BoxShape3D:
		var box = BoxMesh.new()
		box.size = shape.size
		debug_mesh.mesh = box
	elif shape is SphereShape3D:
		var sphere = SphereMesh.new()
		sphere.radius = shape.radius
		debug_mesh.mesh = sphere

	# Create green translucent material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.0, 0.3)  # Green, semi-transparent
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	debug_mesh.material_override = mat

	hitbox.add_child(debug_mesh)

## Called when weapon hitbox collides with a body during attack
func _on_weapon_hitbox_body_entered(body: Node3D) -> void:
	print("[Hitbox] body_entered signal! body=%s, hitbox_active=%s, is_attacking=%s" % [body.name, player.hitbox_active, player.is_attacking])

	if not player.is_local_player or not player.hitbox_active:
		print("[Hitbox] Skipped - local=%s, active=%s" % [player.is_local_player, player.hitbox_active])
		return

	# Only process if we're attacking
	if not player.is_attacking and not player.is_special_attacking:
		print("[Hitbox] Skipped - not attacking")
		return

	# Check if it's an enemy
	if body.has_method("take_damage") and body.collision_layer & 4:
		var enemy_id = body.get_instance_id()

		# Prevent hitting same enemy twice per swing
		if enemy_id in player.hitbox_hit_enemies:
			print("[Hitbox] Skipped - already hit this enemy")
			return

		player.hitbox_hit_enemies.append(enemy_id)
		print("[Hitbox] HIT ENEMY: %s" % body.name)

		# Get damage from combat module
		if player.combat:
			player.combat.process_hitbox_hit(body)
	else:
		print("[Hitbox] Not an enemy - has_take_damage=%s, layer=%d" % [body.has_method("take_damage"), body.collision_layer])

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

# =============================================================================
# ARMOR VISUALS
# =============================================================================

## Update head armor visual (changes head/neck color)
func update_head_armor_visual() -> void:
	if not player.body_container:
		return

	var armor_data = player.equipment.get_equipped_item_data(Equipment.EquipmentSlot.HEAD)
	var color = DEFAULT_SKIN_COLOR

	if armor_data is ArmorData:
		color = armor_data.primary_color
		print("[Player] Equipped head armor: %s (color: %s)" % [armor_data.item_id, color])
	else:
		print("[Player] Unequipped head armor - reverting to skin color")

	# Apply color to head and neck
	_set_mesh_color(player.body_container, "Head", color)
	_set_mesh_color(player.body_container, "Neck", color)

## Update chest armor visual (changes torso color)
func update_chest_armor_visual() -> void:
	if not player.body_container:
		return

	var armor_data = player.equipment.get_equipped_item_data(Equipment.EquipmentSlot.CHEST)
	var color = DEFAULT_CLOTHES_COLOR

	if armor_data is ArmorData:
		color = armor_data.primary_color
		print("[Player] Equipped chest armor: %s (color: %s)" % [armor_data.item_id, color])
	else:
		print("[Player] Unequipped chest armor - reverting to default clothes color")

	# Apply color to torso
	_set_mesh_color(player.body_container, "Torso", color)
	# Also color the child mesh inside torso if present
	var torso = player.body_container.get_node_or_null("Torso")
	if torso:
		_set_mesh_color(torso, "MeshInstance3D", color)

	# Apply secondary color to arms if armor equipped
	if armor_data is ArmorData:
		_set_arm_colors(armor_data.secondary_color)
	else:
		_set_arm_colors(DEFAULT_SKIN_COLOR)

## Update legs armor visual (changes legs and hips color)
func update_legs_armor_visual() -> void:
	if not player.body_container:
		return

	var armor_data = player.equipment.get_equipped_item_data(Equipment.EquipmentSlot.LEGS)
	var color = DEFAULT_PANTS_COLOR

	if armor_data is ArmorData:
		color = armor_data.primary_color
		print("[Player] Equipped leg armor: %s (color: %s)" % [armor_data.item_id, color])
	else:
		print("[Player] Unequipped leg armor - reverting to default pants color")

	# Apply color to hips and legs
	_set_mesh_color(player.body_container, "Hips", color)
	_set_leg_colors(color)

## Update cape visual (creates/removes cape mesh)
func update_cape_visual() -> void:
	# Remove existing cape
	if cape_visual:
		cape_visual.queue_free()
		cape_visual = null

	if not player.body_container:
		return

	var armor_data = player.equipment.get_equipped_item_data(Equipment.EquipmentSlot.CAPE)
	if not armor_data is ArmorData:
		print("[Player] Unequipped cape")
		return

	print("[Player] Equipped cape: %s" % armor_data.item_id)

	# Create cape visual (simple flowing shape attached to shoulders)
	cape_visual = Node3D.new()
	cape_visual.name = "Cape"
	player.body_container.add_child(cape_visual)

	# Create cape mesh - a simple elongated shape hanging from the back
	var cape_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.25, 0.6, 0.05)  # Wide, tall, thin
	cape_mesh.mesh = box

	# Create material with armor colors
	var mat = StandardMaterial3D.new()
	mat.albedo_color = armor_data.primary_color
	cape_mesh.material_override = mat

	cape_mesh.position = Vector3(0, -0.3, -0.08)  # Behind and below attachment
	cape_visual.add_child(cape_mesh)

	# Position cape at upper back (between shoulders)
	cape_visual.position = Vector3(0, 1.35, -0.05)

## Initialize all armor visuals to default (unarmored) state
func initialize_armor_visuals() -> void:
	if not player.body_container:
		return

	print("[Player] Initializing armor visuals to default skin colors")

	# Head - skin color
	_set_mesh_color(player.body_container, "Head", DEFAULT_SKIN_COLOR)
	_set_mesh_color(player.body_container, "Neck", DEFAULT_SKIN_COLOR)

	# Torso - light tan (minimal clothing)
	_set_mesh_color(player.body_container, "Torso", DEFAULT_CLOTHES_COLOR)
	var torso = player.body_container.get_node_or_null("Torso")
	if torso:
		_set_mesh_color(torso, "MeshInstance3D", DEFAULT_CLOTHES_COLOR)

	# Arms - skin color
	_set_arm_colors(DEFAULT_SKIN_COLOR)

	# Hips and legs - slightly darker tan
	_set_mesh_color(player.body_container, "Hips", DEFAULT_PANTS_COLOR)
	_set_leg_colors(DEFAULT_PANTS_COLOR)

# =============================================================================
# COLOR HELPERS
# =============================================================================

## Set the color of a named MeshInstance3D node
func _set_mesh_color(parent: Node3D, node_name: String, color: Color) -> void:
	var mesh_node = parent.get_node_or_null(node_name)
	if mesh_node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mesh_node.material_override = mat

## Set colors for arm meshes
func _set_arm_colors(color: Color) -> void:
	for arm_name in ["LeftArm", "RightArm"]:
		var arm = player.body_container.get_node_or_null(arm_name)
		if not arm:
			continue

		# Color the upper arm mesh (first MeshInstance3D child)
		for child in arm.get_children():
			if child is MeshInstance3D:
				var mat = StandardMaterial3D.new()
				mat.albedo_color = color
				child.material_override = mat
				break

		# Color forearm (Elbow node and its mesh)
		var elbow = arm.get_node_or_null("Elbow")
		if elbow:
			for child in elbow.get_children():
				if child is MeshInstance3D:
					var mat = StandardMaterial3D.new()
					mat.albedo_color = color
					child.material_override = mat
					break

			# Color hand
			var hand = elbow.get_node_or_null("HandAttach")
			if hand:
				for child in hand.get_children():
					if child is MeshInstance3D:
						var mat = StandardMaterial3D.new()
						mat.albedo_color = color
						child.material_override = mat
						break

## Set colors for leg meshes
func _set_leg_colors(color: Color) -> void:
	for leg_name in ["LeftLeg", "RightLeg"]:
		var leg = player.body_container.get_node_or_null(leg_name)
		if not leg:
			continue

		# Color upper leg mesh
		for child in leg.get_children():
			if child is MeshInstance3D:
				var mat = StandardMaterial3D.new()
				mat.albedo_color = color
				child.material_override = mat
				break

		# Color knee/lower leg
		var knee = leg.get_node_or_null("Knee")
		if knee:
			for child in knee.get_children():
				if child is MeshInstance3D:
					var mat = StandardMaterial3D.new()
					mat.albedo_color = color
					child.material_override = mat
					break

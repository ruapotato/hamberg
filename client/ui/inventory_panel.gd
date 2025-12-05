extends Control

## InventoryPanel - Full inventory UI (toggled with Tab)
## Shows all 30 inventory slots + crafting panel

const InventorySlot = preload("res://client/ui/inventory_slot.tscn")
const ItemData = preload("res://shared/item_data.gd")
const Equipment = preload("res://shared/equipment.gd")
const ArmorData = preload("res://shared/armor_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const MAX_SLOTS: int = 30
const COLUMNS: int = 6

var slots: Array[Node] = []
var player_inventory: Node = null
var is_open: bool = false
var nearby_stations: Array = []  # Crafting stations player is near (e.g., ["workbench"])
var focused_slot: int = 0  # For controller navigation
var picked_up_slot: int = -1  # Slot being moved (-1 = none)

@onready var inventory_grid: GridContainer = $Panel/InventoryGrid
@onready var panel: Panel = $Panel
@onready var recipe_list: VBoxContainer = $Panel/CraftingPanel/RecipeList

# Stats panel nodes
var stats_panel: Panel = null
var stats_label: RichTextLabel = null

func _ready() -> void:
	_create_slots()
	_create_stats_panel()
	hide_inventory()

	# Set up grid columns
	if inventory_grid:
		inventory_grid.columns = COLUMNS

	# Populate crafting recipes
	_populate_recipes()

## Create the player stats panel (shows food buffs, armor, set bonuses)
## This panel appears on the right side of the inventory, as a separate panel
func _create_stats_panel() -> void:
	# Create stats panel as sibling to Panel, not inside it
	stats_panel = Panel.new()
	stats_panel.name = "StatsPanel"
	add_child(stats_panel)

	# Position stats panel to the right of the inventory panel
	# Inventory panel is centered at 450px offset, so place stats panel to its right
	stats_panel.anchor_left = 0.5
	stats_panel.anchor_top = 0.5
	stats_panel.anchor_right = 0.5
	stats_panel.anchor_bottom = 0.5
	stats_panel.offset_left = 470  # Just to the right of the inventory panel (which ends at 450)
	stats_panel.offset_top = -300  # Same height as inventory
	stats_panel.offset_right = 720  # 250px wide
	stats_panel.offset_bottom = 300

	# Background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.15, 0.15, 0.15, 0.95)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	stats_panel.add_child(bg)

	# Title
	var title = Label.new()
	title.name = "Title"
	title.text = "CHARACTER STATS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_bottom = 40
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	stats_panel.add_child(title)

	# Stats label (RichTextLabel for formatting)
	stats_label = RichTextLabel.new()
	stats_label.name = "StatsLabel"
	stats_label.bbcode_enabled = true
	stats_label.anchor_top = 0.08
	stats_label.anchor_right = 1.0
	stats_label.anchor_bottom = 1.0
	stats_label.offset_left = 10
	stats_label.offset_top = 5
	stats_label.offset_right = -10
	stats_label.offset_bottom = -5
	stats_label.add_theme_font_size_override("normal_font_size", 14)
	stats_panel.add_child(stats_label)

func _process(_delta: float) -> void:
	# Toggle inventory with Tab key (unless debug console is open)
	if Input.is_action_just_pressed("toggle_inventory"):
		# Don't toggle inventory if debug console is handling Tab for autocomplete
		var debug_console = get_tree().get_first_node_in_group("debug_console")
		if debug_console and debug_console.visible:
			return
		toggle_inventory()

	# Close inventory with ESC
	if is_open and Input.is_action_just_pressed("ui_cancel"):
		hide_inventory()
		return

	# Handle D-pad navigation when inventory is open
	if is_open:
		# D-pad left/right navigates horizontally
		if Input.is_action_just_pressed("hotbar_next"):
			_move_focus(1, 0)  # Right
		elif Input.is_action_just_pressed("hotbar_prev"):
			_move_focus(-1, 0)  # Left

		# D-pad up/down navigates vertically when inventory open
		if Input.is_action_just_pressed("hotbar_equip"):
			_move_focus(0, -1)  # Up
		elif Input.is_action_just_pressed("hotbar_unequip"):
			_move_focus(0, 1)  # Down

		# A button: Pick up/drop item (for moving items)
		if Input.is_action_just_pressed("interact"):
			_handle_item_pickup_drop()

func _create_slots() -> void:
	slots.clear()

	for i in MAX_SLOTS:
		var slot = InventorySlot.instantiate()
		slot.slot_index = i
		slot.is_hotbar_slot = false
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.drag_ended.connect(_on_slot_drag_ended)
		slot.drag_dropped_outside.connect(_on_slot_dropped_outside)
		inventory_grid.add_child(slot)
		slots.append(slot)

func _on_slot_clicked(slot_index: int) -> void:
	# TODO: Implement slot interaction (drag/drop, etc.)
	print("[InventoryPanel] Clicked slot %d" % slot_index)

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

	print("[InventoryPanel] Right-clicked slot %d with item: %s" % [slot_index, item_id])

	# Check if this is an equippable item
	var item_data = ItemDatabase.get_item(item_id)
	if not item_data:
		print("[InventoryPanel] Unknown item: %s" % item_id)
		return

	# Handle consumable items (food) - eat on right-click (server-authoritative)
	if item_data.item_type == ItemData.ItemType.CONSUMABLE:
		print("[InventoryPanel] Requesting to eat %s from slot %d" % [item_id, slot_index])
		NetworkManager.rpc_request_eat_food.rpc_id(1, item_id, slot_index)
		return

	# Determine which slot to equip to based on item type
	var equip_slot = -1
	match item_data.item_type:
		ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL, ItemData.ItemType.RESOURCE:
			equip_slot = Equipment.EquipmentSlot.MAIN_HAND
		ItemData.ItemType.SHIELD:
			equip_slot = Equipment.EquipmentSlot.OFF_HAND
		ItemData.ItemType.ARMOR:
			# Determine equipment slot based on armor slot type
			if item_data is ArmorData:
				match item_data.armor_slot:
					ArmorData.ArmorSlot.HEAD:
						equip_slot = Equipment.EquipmentSlot.HEAD
					ArmorData.ArmorSlot.CHEST:
						equip_slot = Equipment.EquipmentSlot.CHEST
					ArmorData.ArmorSlot.LEGS:
						equip_slot = Equipment.EquipmentSlot.LEGS
					ArmorData.ArmorSlot.CAPE:
						equip_slot = Equipment.EquipmentSlot.CAPE
					ArmorData.ArmorSlot.ACCESSORY:
						equip_slot = Equipment.EquipmentSlot.ACCESSORY
					_:
						print("[InventoryPanel] Unknown armor slot type")
						return
			else:
				print("[InventoryPanel] Armor item %s has no armor slot data" % item_id)
				return
		_:
			print("[InventoryPanel] Item %s is not equippable" % item_id)
			return

	# Check if this item is already equipped - if so, unequip it
	var player = player_inventory.get_parent()
	if player and player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		var currently_equipped = equipment.get_equipped_item(equip_slot)

		if currently_equipped == item_id:
			# Item is already equipped - unequip it
			print("[InventoryPanel] Unequipping %s from equipment slot %d" % [item_id, equip_slot])
			NetworkManager.rpc_request_unequip_slot.rpc_id(1, equip_slot)
			return

	# Request to equip this item on the server (send equipment slot, not inventory slot)
	print("[InventoryPanel] Requesting to equip %s to equipment slot %d" % [item_id, equip_slot])
	NetworkManager.rpc_request_equip_item.rpc_id(1, equip_slot, item_id)

func _on_slot_drag_ended(from_slot: int, to_slot: int) -> void:
	if not player_inventory:
		return

	print("[InventoryPanel] Dragging from slot %d to slot %d" % [from_slot, to_slot])

	# Request server to swap items in inventory
	NetworkManager.rpc_request_swap_slots.rpc_id(1, from_slot, to_slot)

func _on_slot_dropped_outside(slot_index: int) -> void:
	if not player_inventory:
		return

	# Get the item data at this slot
	var inventory_data = player_inventory.get_inventory_data()
	if slot_index >= inventory_data.size():
		return

	var slot_data = inventory_data[slot_index]
	if slot_data.is_empty():
		return

	var item_id = slot_data.get("item", "")
	var amount = slot_data.get("amount", 0)
	if item_id.is_empty() or amount <= 0:
		return

	print("[InventoryPanel] Requesting to drop %d x %s from slot %d" % [amount, item_id, slot_index])
	NetworkManager.rpc_request_drop_item.rpc_id(1, slot_index, amount)

## Toggle inventory visibility
func toggle_inventory() -> void:
	if is_open:
		hide_inventory()
	else:
		show_inventory()

## Show inventory panel
func show_inventory() -> void:
	is_open = true
	visible = true
	refresh_display()

	# Update stats display
	_update_stats_display()

	# Update recipe button states based on current inventory
	_update_recipe_buttons()

	# Initialize focus visual for controller
	_update_focus_visual()

	# Capture mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Update the player stats display panel
func _update_stats_display() -> void:
	if not stats_label or not player_inventory:
		return

	var player = player_inventory.get_parent()
	if not player:
		return

	var text = ""

	# Food buffs section
	text += "[b][color=yellow]FOOD BUFFS[/color][/b]\n"
	var player_food = player.get_node_or_null("PlayerFood")
	if player_food and player_food.has_method("get_active_foods_info"):
		var active_foods = player_food.get_active_foods_info()
		if active_foods.size() > 0:
			for food in active_foods:
				var food_name = food.get("food_id", "Unknown")
				var time_left = food.get("remaining_time", 0)
				var health_bonus = food.get("health_bonus", 0)
				var stamina_bonus = food.get("stamina_bonus", 0)
				var mins = int(time_left) / 60
				var secs = int(time_left) % 60
				var bonuses = ""
				if health_bonus > 0:
					bonuses += "+%.0fHP " % health_bonus
				if stamina_bonus > 0:
					bonuses += "+%.0fStam" % stamina_bonus
				text += "  %s (%s) - %dm %ds\n" % [food_name.capitalize().replace("_", " "), bonuses.strip_edges(), mins, secs]
		else:
			text += "  [color=gray]No food active[/color]\n"
	else:
		text += "  [color=gray]No food active[/color]\n"

	# Armor section - show defense per damage type
	text += "\n[b][color=cyan]DEFENSE[/color][/b]\n"
	var equipment = player.get_node_or_null("Equipment")
	if equipment:
		var damage_types = {
			WeaponData.DamageType.SLASH: ["Slash", "#ffffff"],
			WeaponData.DamageType.BLUNT: ["Blunt", "#aaaaaa"],
			WeaponData.DamageType.PIERCE: ["Pierce", "#ffaaff"],
			WeaponData.DamageType.FIRE: ["Fire", "#ff6600"],
			WeaponData.DamageType.ICE: ["Ice", "#66ffff"],
			WeaponData.DamageType.POISON: ["Poison", "#66ff66"],
		}
		for dmg_type in damage_types:
			var armor_val = equipment.get_total_armor(dmg_type)
			var type_info = damage_types[dmg_type]
			text += "  [color=%s]%s:[/color] %.1f\n" % [type_info[1], type_info[0], armor_val]

		# Show equipped armor pieces
		var armor_slots = {
			Equipment.EquipmentSlot.HEAD: "Head",
			Equipment.EquipmentSlot.CHEST: "Chest",
			Equipment.EquipmentSlot.LEGS: "Legs",
			Equipment.EquipmentSlot.CAPE: "Cape",
		}
		for slot in armor_slots:
			var item_id = equipment.get_equipped_item(slot)
			var slot_name = armor_slots[slot]
			if item_id.is_empty():
				text += "  %s: [color=gray]None[/color]\n" % slot_name
			else:
				var item_data = ItemDatabase.get_item(item_id)
				var display_name = item_data.display_name if item_data else item_id
				text += "  %s: %s\n" % [slot_name, display_name]

		# Show equipped accessory
		text += "\n[b][color=magenta]ACCESSORY[/color][/b]\n"
		var accessory_id = equipment.get_equipped_item(Equipment.EquipmentSlot.ACCESSORY)
		if accessory_id.is_empty():
			text += "  [color=gray]None[/color]\n"
		else:
			var accessory_data = ItemDatabase.get_item(accessory_id)
			var accessory_name = accessory_data.display_name if accessory_data else accessory_id
			text += "  %s\n" % accessory_name
			# Show accessory effect if available
			if accessory_data is ArmorData:
				match accessory_data.set_bonus:
					ArmorData.SetBonus.CYCLOPS_LIGHT:
						text += "  [color=yellow]Effect: Glowing Body[/color]\n"

		# Set bonus
		var set_bonus = equipment.get_active_set_bonus()
		text += "\n[b][color=lime]SET BONUS[/color][/b]\n"
		if set_bonus == ArmorData.SetBonus.PIG_DOUBLE_JUMP:
			text += "  [color=pink]Pig Set: DOUBLE JUMP[/color]\n"
		elif set_bonus == ArmorData.SetBonus.DEER_STAMINA_SAVER:
			text += "  [color=tan]Deer Set: 50% SPRINT STAMINA[/color]\n"
		else:
			text += "  [color=gray]None (need full matching set)[/color]\n"
	else:
		text += "  [color=gray]No equipment[/color]\n"

	stats_label.text = text

## Hide inventory panel
## Returns true if it was open (for ESC handling)
func hide_inventory() -> bool:
	var was_open = is_open
	is_open = false
	visible = false

	# Release mouse cursor (back to captured for FPS controls)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return was_open

## Link to player's inventory
func set_player_inventory(inventory: Node) -> void:
	player_inventory = inventory

	# Connect to equipment changes
	var player = inventory.get_parent()
	if player and player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		if equipment and not equipment.equipment_changed.is_connected(_on_equipment_changed):
			equipment.equipment_changed.connect(_on_equipment_changed)
			print("[InventoryPanel] Connected to equipment_changed signal")
		else:
			print("[InventoryPanel] Already connected to equipment_changed signal")

	refresh_display()

## Refresh inventory display
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

	for i in MAX_SLOTS:
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
func _on_equipment_changed(slot) -> void:
	print("[InventoryPanel] Equipment changed in slot %d, refreshing display" % slot)
	# Refresh display to update equipped borders
	refresh_display()

	# Update crafting button states
	_update_recipe_buttons()

## Check if inventory is currently open
func is_inventory_open() -> bool:
	return is_open

## Populate crafting recipe list (only basic recipes - no station required)
func _populate_recipes() -> void:
	if not recipe_list:
		return

	# Clear existing recipes
	for child in recipe_list.get_children():
		child.queue_free()

	# Add only basic recipes (no workbench required)
	var basic_recipes = CraftingRecipes.get_basic_recipes()

	for recipe in basic_recipes:
		var recipe_button = _create_recipe_button(recipe)
		recipe_list.add_child(recipe_button)

## Create a button for a recipe
func _create_recipe_button(recipe: Dictionary) -> Button:
	var button = Button.new()
	button.custom_minimum_size = Vector2(0, 50)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Create button text with requirements
	var output_item: String = recipe.get("output_item", "")
	var output_amount: int = recipe.get("output_amount", 1)
	var display_name = CraftingRecipes.get_item_display_name(output_item)

	var button_text = "%s x%d\n" % [display_name, output_amount]

	# Add crafting station requirement
	var required_station: String = recipe.get("crafting_station", "")
	if not required_station.is_empty():
		button_text += "[%s]\n" % CraftingRecipes.get_item_display_name(required_station).to_upper()

	# Add requirements
	var requirements: Dictionary = recipe.get("requirements", {})
	var req_text = ""
	var first = true
	for item_name in requirements:
		if not first:
			req_text += ", "
		req_text += "%s x%d" % [CraftingRecipes.get_item_display_name(item_name), requirements[item_name]]
		first = false

	button_text += req_text
	button.text = button_text

	# Connect button press
	button.pressed.connect(func(): _on_craft_button_pressed(recipe))

	# Store recipe reference
	button.set_meta("recipe", recipe)

	return button

## Handle craft button press
func _on_craft_button_pressed(recipe: Dictionary) -> void:
	if not player_inventory:
		return

	# Send craft request to server (server-authoritative)
	var item_name: String = recipe.get("output_item", "")
	if item_name.is_empty():
		return

	print("[InventoryPanel] Requesting to craft: %s" % item_name)
	NetworkManager.rpc_request_craft.rpc_id(1, item_name)

	# Note: Inventory will be synced back from server after crafting
	# No need to update UI here - wait for server response

## Update recipe button states based on craftability
func _update_recipe_buttons() -> void:
	if not recipe_list or not player_inventory:
		return

	# TODO: Get actual nearby stations from player
	var stations = ["workbench"]  # Temporary: treat as if always near workbench

	for button in recipe_list.get_children():
		if button is Button and button.has_meta("recipe"):
			var recipe: Dictionary = button.get_meta("recipe")
			var can_craft = CraftingRecipes.can_craft(recipe, player_inventory, stations)

			# Update button appearance based on craftability
			button.disabled = not can_craft
			button.modulate = Color.WHITE if can_craft else Color(0.5, 0.5, 0.5)

## Move focus in grid (for controller D-pad navigation)
func _move_focus(dx: int, dy: int) -> void:
	# Calculate current row and column
	var current_row = focused_slot / COLUMNS
	var current_col = focused_slot % COLUMNS

	# Calculate new position
	var new_row = current_row + dy
	var new_col = current_col + dx

	# Clamp to valid range
	var max_rows = (MAX_SLOTS + COLUMNS - 1) / COLUMNS  # Ceiling division
	new_row = clamp(new_row, 0, max_rows - 1)
	new_col = clamp(new_col, 0, COLUMNS - 1)

	# Calculate new focused slot
	var new_focus = new_row * COLUMNS + new_col

	# Clamp to valid slot range
	new_focus = clamp(new_focus, 0, MAX_SLOTS - 1)

	if new_focus != focused_slot:
		focused_slot = new_focus
		_update_focus_visual()

## Update visual highlight for focused slot
func _update_focus_visual() -> void:
	for i in slots.size():
		if slots[i].has_method("set_selected"):
			# Show selection on focused slot OR picked up slot
			var is_highlighted = (i == focused_slot) or (i == picked_up_slot)
			slots[i].set_selected(is_highlighted)

## Handle picking up and dropping items with A button
func _handle_item_pickup_drop() -> void:
	if picked_up_slot == -1:
		# No item picked up - try to pick up focused item
		if not player_inventory:
			return

		var inventory_data = player_inventory.get_inventory_data()
		if focused_slot >= inventory_data.size():
			return

		var slot_data = inventory_data[focused_slot]
		if slot_data.is_empty():
			return  # Can't pick up empty slot

		# Pick up this item
		picked_up_slot = focused_slot
		print("[InventoryPanel] Picked up item from slot %d" % picked_up_slot)
		_update_focus_visual()
	else:
		# Item already picked up - drop it at focused slot
		if picked_up_slot == focused_slot:
			# Dropping on same slot - just cancel
			print("[InventoryPanel] Cancelled move")
			picked_up_slot = -1
			_update_focus_visual()
		else:
			# Swap items
			print("[InventoryPanel] Swapping slots %d and %d" % [picked_up_slot, focused_slot])
			NetworkManager.rpc_request_swap_slots.rpc_id(1, picked_up_slot, focused_slot)
			picked_up_slot = -1
			_update_focus_visual()

## Equip the focused item (controller A button when inventory open)
func _equip_focused_item() -> void:
	if not player_inventory:
		return

	var inventory_data = player_inventory.get_inventory_data()
	if focused_slot >= inventory_data.size():
		return

	var slot_data = inventory_data[focused_slot]
	if slot_data.is_empty():
		return

	var item_id = slot_data.get("item", "")
	if item_id.is_empty():
		return

	# Check if this is an equippable item
	var item_data = ItemDatabase.get_item(item_id)
	if not item_data:
		return

	# Determine which equipment slot to equip to
	var equip_slot = -1
	match item_data.item_type:
		ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL, ItemData.ItemType.RESOURCE:
			equip_slot = Equipment.EquipmentSlot.MAIN_HAND
		ItemData.ItemType.SHIELD:
			equip_slot = Equipment.EquipmentSlot.OFF_HAND
		_:
			print("[InventoryPanel] Item %s is not equippable" % item_id)
			return

	# Check if already equipped - if so, unequip
	var player = player_inventory.get_parent()
	if player and player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		var currently_equipped = equipment.get_equipped_item(equip_slot)
		if currently_equipped == item_id:
			print("[InventoryPanel] Controller unequipping %s" % item_id)
			NetworkManager.rpc_request_unequip_slot.rpc_id(1, equip_slot)
			return

	print("[InventoryPanel] Controller equipping %s" % item_id)
	NetworkManager.rpc_request_equip_item.rpc_id(1, equip_slot, item_id)

## Unequip current equipment (controller)
func _unequip_focused_item() -> void:
	var player = player_inventory.get_parent() if player_inventory else null
	if not player or not player.has_node("Equipment"):
		return

	var equipment = player.get_node("Equipment")

	# Unequip main hand
	var main_hand = equipment.get_equipped_item(Equipment.EquipmentSlot.MAIN_HAND)
	if not main_hand.is_empty():
		print("[InventoryPanel] Controller unequipping main hand: %s" % main_hand)
		NetworkManager.rpc_request_unequip_slot.rpc_id(1, Equipment.EquipmentSlot.MAIN_HAND)

	# Unequip off hand
	var off_hand = equipment.get_equipped_item(Equipment.EquipmentSlot.OFF_HAND)
	if not off_hand.is_empty():
		print("[InventoryPanel] Controller unequipping off hand: %s" % off_hand)
		NetworkManager.rpc_request_unequip_slot.rpc_id(1, Equipment.EquipmentSlot.OFF_HAND)

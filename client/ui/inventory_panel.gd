extends Control

## InventoryPanel - Full inventory UI (toggled with Tab)
## Shows all 30 inventory slots + crafting panel

const InventorySlot = preload("res://client/ui/inventory_slot.tscn")
const MAX_SLOTS: int = 30
const COLUMNS: int = 6

var slots: Array[Node] = []
var player_inventory: Node = null
var is_open: bool = false
var nearby_stations: Array = []  # Crafting stations player is near (e.g., ["workbench"])

@onready var inventory_grid: GridContainer = $Panel/InventoryGrid
@onready var panel: Panel = $Panel
@onready var recipe_list: VBoxContainer = $Panel/CraftingPanel/RecipeList

func _ready() -> void:
	_create_slots()
	hide_inventory()

	# Set up grid columns
	if inventory_grid:
		inventory_grid.columns = COLUMNS

	# Populate crafting recipes
	_populate_recipes()

func _process(_delta: float) -> void:
	# Toggle inventory with Tab key
	if Input.is_action_just_pressed("toggle_inventory"):
		toggle_inventory()

func _create_slots() -> void:
	slots.clear()

	for i in MAX_SLOTS:
		var slot = InventorySlot.instantiate()
		slot.slot_index = i
		slot.is_hotbar_slot = false
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.drag_ended.connect(_on_slot_drag_ended)
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

	# Determine which slot to equip to based on item type
	var equip_slot = -1
	match item_data.item_type:
		ItemData.ItemType.WEAPON, ItemData.ItemType.TOOL:
			equip_slot = Equipment.EquipmentSlot.MAIN_HAND
		ItemData.ItemType.SHIELD:
			equip_slot = Equipment.EquipmentSlot.OFF_HAND
		ItemData.ItemType.ARMOR:
			# TODO: Determine HEAD/CHEST/LEGS based on armor subtype
			print("[InventoryPanel] Armor equipping not yet implemented")
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

	# Swap items in inventory
	if player_inventory.has_method("swap_slots"):
		player_inventory.swap_slots(from_slot, to_slot)
		refresh_display()

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

	# Capture mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Hide inventory panel
func hide_inventory() -> void:
	is_open = false
	visible = false

	# Release mouse cursor (back to captured for FPS controls)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Link to player's inventory
func set_player_inventory(inventory: Node) -> void:
	player_inventory = inventory

	# Connect to equipment changes
	var player = inventory.get_parent()
	if player and player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		if equipment and not equipment.equipment_changed.is_connected(_on_equipment_changed):
			equipment.equipment_changed.connect(_on_equipment_changed)

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
					if equipment.get_equipped_item(equip_slot) == item_id:
						is_equipped = true
						break

			slots[i].set_equipped(is_equipped)
		else:
			slots[i].set_item_data({})
			slots[i].set_equipped(false)

## Called when equipment changes
func _on_equipment_changed(_slot) -> void:
	# Refresh display to update equipped borders
	refresh_display()

	# Update crafting button states
	_update_recipe_buttons()

## Check if inventory is currently open
func is_inventory_open() -> bool:
	return is_open

## Populate crafting recipe list
func _populate_recipes() -> void:
	if not recipe_list:
		return

	# Clear existing recipes
	for child in recipe_list.get_children():
		child.queue_free()

	# Add all recipes
	var all_recipes = CraftingRecipes.get_all_recipes()

	for recipe in all_recipes:
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

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
		slot.drag_ended.connect(_on_slot_drag_ended)
		inventory_grid.add_child(slot)
		slots.append(slot)

func _on_slot_clicked(slot_index: int) -> void:
	# TODO: Implement slot interaction (drag/drop, etc.)
	print("[InventoryPanel] Clicked slot %d" % slot_index)

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
	refresh_display()

## Refresh inventory display
func refresh_display() -> void:
	if not player_inventory:
		return

	var inventory_data = player_inventory.get_inventory_data()

	for i in MAX_SLOTS:
		if i < inventory_data.size():
			slots[i].set_item_data(inventory_data[i])
		else:
			slots[i].set_item_data({})

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

	# TODO: Get actual nearby stations from player
	# For now, allow all crafting (no station restrictions)
	var stations = ["workbench"]  # Temporary: treat as if always near workbench

	if CraftingRecipes.craft_item(recipe, player_inventory, stations):
		print("[InventoryPanel] Successfully crafted %s" % recipe.get("output_item"))
		refresh_display()
		_update_recipe_buttons()
	else:
		var required_station: String = recipe.get("crafting_station", "")
		if not required_station.is_empty() and not stations.has(required_station):
			print("[InventoryPanel] Cannot craft - missing %s" % required_station)
		else:
			print("[InventoryPanel] Cannot craft - missing resources")

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

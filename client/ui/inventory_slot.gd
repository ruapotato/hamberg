extends Panel

## InventorySlot - UI component for a single inventory slot
## Displays item icon, amount, and selection state

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)
signal drag_started(slot_index: int)
signal drag_ended(from_slot: int, to_slot: int)
signal drag_dropped_outside(slot_index: int)

@export var slot_index: int = 0
@export var is_hotbar_slot: bool = false

var item_name: String = ""
var item_amount: int = 0
var is_selected: bool = false
var is_equipped: bool = false  # Is this item equipped?
var is_dragging: bool = false
var drag_preview: Control = null

@onready var item_icon: ColorRect = $ItemIcon
@onready var item_name_label: Label = $ItemNameLabel
@onready var amount_label: Label = $AmountLabel
@onready var selection_border: Panel = $SelectionBorder
@onready var equipped_border: Panel = $EquippedBorder

func _ready() -> void:
	# Set up click detection
	gui_input.connect(_on_gui_input)
	update_display()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("[InventorySlot] Mouse event: button=%d, pressed=%s, slot=%d, item=%s" % [event.button_index, event.pressed, slot_index, item_name])
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start potential drag
				if not item_name.is_empty():
					is_dragging = true
					drag_started.emit(slot_index)
					print("[InventorySlot] Started dragging slot %d" % slot_index)
			else:
				# Released - end drag if dragging
				if is_dragging:
					is_dragging = false
					# Find slot under mouse
					var target_slot = _get_slot_under_mouse()
					if target_slot != null and target_slot != self:
						print("[InventorySlot] Drag ended: %d -> %d" % [slot_index, target_slot.slot_index])
						drag_ended.emit(slot_index, target_slot.slot_index)
					elif target_slot == null:
						# Dropped outside any slot - drop the item
						print("[InventorySlot] Dropped outside: slot %d" % slot_index)
						drag_dropped_outside.emit(slot_index)
				else:
					# Just a click
					print("[InventorySlot] Left clicked slot %d" % slot_index)
					slot_clicked.emit(slot_index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and not item_name.is_empty():
				# Right-click to equip
				print("[InventorySlot] Right clicked slot %d with item %s" % [slot_index, item_name])
				slot_right_clicked.emit(slot_index)

## Set the item data for this slot
func set_item_data(data: Dictionary) -> void:
	if data.is_empty():
		item_name = ""
		item_amount = 0
	else:
		item_name = data.get("item", "")
		item_amount = data.get("amount", 0)

	update_display()

## Set selection state
func set_selected(selected: bool) -> void:
	is_selected = selected
	if selection_border:
		selection_border.visible = selected

## Set equipped state (shows yellow outline)
func set_equipped(equipped: bool) -> void:
	is_equipped = equipped
	if equipped_border:
		equipped_border.visible = equipped

## Update the visual display
func update_display() -> void:
	if not is_node_ready():
		return

	# Show/hide based on whether slot has an item
	var has_item := not item_name.is_empty() and item_amount > 0

	if item_icon:
		item_icon.visible = has_item
		# TODO: Load actual item icons
		# For now, just show a colored rectangle based on item type
		if has_item:
			_set_placeholder_icon(item_name)

	if item_name_label:
		item_name_label.visible = has_item
		if has_item:
			# Convert snake_case to Title Case
			var display_name = _get_display_name(item_name)
			item_name_label.text = display_name

	if amount_label:
		amount_label.visible = has_item and item_amount > 1
		amount_label.text = str(item_amount)

	if selection_border:
		selection_border.visible = is_selected

	if equipped_border:
		equipped_border.visible = is_equipped

## Get a display-friendly name for an item
func _get_display_name(item: String) -> String:
	var words = item.split("_")
	var display = ""
	for word in words:
		if display != "":
			display += " "
		display += word.capitalize()
	return display

## Placeholder icon coloring (until we have actual icons)
func _set_placeholder_icon(item: String) -> void:
	if not item_icon:
		return

	# Set color based on item type
	var icon_color := Color.WHITE
	match item:
		"wood":
			icon_color = Color(0.6, 0.4, 0.2)  # Brown
		"stone":
			icon_color = Color(0.5, 0.5, 0.5)  # Gray
		"iron":
			icon_color = Color(0.3, 0.3, 0.4)  # Dark gray-blue
		"copper":
			icon_color = Color(0.8, 0.5, 0.2)  # Copper color
		"resin":
			icon_color = Color(0.9, 0.7, 0.0)  # Golden/amber color
		"wooden_club", "hammer", "stone_axe", "stone_pickaxe":
			icon_color = Color(0.7, 0.6, 0.4)  # Tool color
		"torch":
			icon_color = Color(0.9, 0.6, 0.1)  # Torch orange
		"workbench":
			icon_color = Color(0.6, 0.4, 0.2)  # Workbench brown
		"wooden_wall", "wooden_floor", "wooden_door", "wooden_beam", "wooden_roof":
			icon_color = Color(0.5, 0.35, 0.2)  # Building material
		"raw_venison", "raw_pork", "raw_mutton":
			icon_color = Color(0.85, 0.4, 0.35)  # Raw meat red
		_:
			icon_color = Color(0.8, 0.8, 0.8)  # Default light gray

	item_icon.color = icon_color

## Get the inventory slot under the mouse cursor
func _get_slot_under_mouse() -> Node:
	var mouse_pos = get_viewport().get_mouse_position()

	# Find all inventory slots (siblings)
	var parent = get_parent()
	if not parent:
		return null

	for child in parent.get_children():
		if child == self:
			continue
		if child.has_method("get_global_rect"):
			var rect = child.get_global_rect()
			if rect.has_point(mouse_pos):
				return child

	return null

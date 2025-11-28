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
					_create_drag_preview()
					print("[InventorySlot] Started dragging slot %d" % slot_index)
			else:
				# Released - end drag if dragging
				if is_dragging:
					is_dragging = false
					_destroy_drag_preview()
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

## Create a visual drag preview that follows the mouse
func _create_drag_preview() -> void:
	if drag_preview:
		_destroy_drag_preview()

	# Create a container for the drag preview
	drag_preview = Panel.new()
	drag_preview.custom_minimum_size = Vector2(60, 70)
	drag_preview.size = Vector2(60, 70)
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse

	# Create a darker semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	drag_preview.add_theme_stylebox_override("panel", style)

	# Create the item icon
	var icon = ColorRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size = Vector2(36, 36)
	icon.position = Vector2(12, 6)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Copy color from current icon
	if item_icon:
		icon.color = item_icon.color
	drag_preview.add_child(icon)

	# Create item name label
	var name_label = Label.new()
	name_label.text = _get_display_name(item_name)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(60, 20)
	name_label.size = Vector2(60, 20)
	name_label.position = Vector2(0, 46)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.add_child(name_label)

	# Create amount label if more than 1
	if item_amount > 1:
		var amt_label = Label.new()
		amt_label.text = str(item_amount)
		amt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt_label.custom_minimum_size = Vector2(20, 15)
		amt_label.size = Vector2(20, 15)
		amt_label.position = Vector2(38, 28)
		amt_label.add_theme_font_size_override("font_size", 12)
		amt_label.add_theme_color_override("font_color", Color.YELLOW)
		amt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_preview.add_child(amt_label)

	# Add to root canvas for proper z-ordering (above everything)
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100  # Very high layer to be on top
	canvas_layer.name = "DragPreviewLayer"
	get_tree().root.add_child(canvas_layer)
	canvas_layer.add_child(drag_preview)

	# Position at mouse
	_update_drag_preview_position()

## Destroy the drag preview
func _destroy_drag_preview() -> void:
	if drag_preview:
		# Also remove the canvas layer parent
		var canvas_layer = drag_preview.get_parent()
		if canvas_layer:
			canvas_layer.queue_free()
		drag_preview = null

## Update drag preview position to follow mouse
func _update_drag_preview_position() -> void:
	if drag_preview and is_dragging:
		var mouse_pos = get_viewport().get_mouse_position()
		# Offset so cursor is at top-left corner of preview
		drag_preview.global_position = mouse_pos + Vector2(10, 10)

## Process to update drag preview position
func _process(_delta: float) -> void:
	if is_dragging and drag_preview:
		_update_drag_preview_position()

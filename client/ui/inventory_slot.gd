extends Panel

## InventorySlot - UI component for a single inventory slot
## Displays item icon, amount, and selection state

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)
signal drag_started(slot_index: int)
signal drag_ended(from_slot: int, to_slot: int)
signal drag_dropped_outside(slot_index: int)

const ItemTooltip = preload("res://client/ui/item_tooltip.gd")

@export var slot_index: int = 0
@export var is_hotbar_slot: bool = false
@export var show_tooltip: bool = true  # Can disable for certain UIs

var item_name: String = ""
var item_amount: int = 0
var is_selected: bool = false
var is_equipped: bool = false  # Is this item equipped?
var is_dragging: bool = false
var drag_preview: Control = null
var is_hovered: bool = false

# Shared tooltip instance (created once, reused)
static var _tooltip_instance: Control = null
static var _tooltip_layer: CanvasLayer = null

@onready var item_icon: TextureRect = $ItemIcon
@onready var item_icon_bg: TextureRect = $ItemIconBg
@onready var item_name_label: Label = $ItemNameLabel
@onready var amount_label: Label = $AmountLabel
@onready var selection_border: Panel = $SelectionBorder
@onready var equipped_border: Panel = $EquippedBorder

func _ready() -> void:
	# Set up click detection
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	update_display()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("[InventorySlot] Mouse event: button=%d, pressed=%s, slot=%d, item=%s" % [event.button_index, event.pressed, slot_index, item_name])
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start potential drag
				if not item_name.is_empty():
					is_dragging = true
					_hide_tooltip()  # Hide tooltip when dragging
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
		if item_icon_bg:
			item_icon_bg.visible = false  # Will be set by _set_item_icon if needed
		if has_item:
			_set_item_icon(item_name)

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

## Set item icon textures
func _set_item_icon(item: String) -> void:
	if not item_icon:
		return

	# Clear background icon by default
	if item_icon_bg:
		item_icon_bg.texture = null
		item_icon_bg.visible = false

	# Try to load icon from images/icons/{item}.png
	var icon_path = "res://images/icons/%s.png" % item
	if ResourceLoader.exists(icon_path):
		var tex = load(icon_path)
		if tex:
			item_icon.texture = tex
			return

	# Fallback: no texture (will show nothing)
	item_icon.texture = null

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
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size = Vector2(36, 36)
	icon.position = Vector2(12, 6)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Copy texture from current icon
	if item_icon and item_icon.texture:
		icon.texture = item_icon.texture
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

	# Update tooltip position while hovering
	if is_hovered and _tooltip_instance and _tooltip_instance.visible:
		_update_tooltip_position()

## Called when mouse enters the slot
func _on_mouse_entered() -> void:
	is_hovered = true
	if show_tooltip and not item_name.is_empty() and not is_dragging:
		_show_tooltip()

## Called when mouse exits the slot
func _on_mouse_exited() -> void:
	is_hovered = false
	_hide_tooltip()

## Show tooltip for current item
func _show_tooltip() -> void:
	if item_name.is_empty():
		return

	# Create shared tooltip instance if needed
	if not _tooltip_instance:
		_create_tooltip_instance()

	if _tooltip_instance:
		_tooltip_instance.show_for_item(item_name, get_viewport().get_mouse_position())

## Hide the tooltip
func _hide_tooltip() -> void:
	if _tooltip_instance:
		_tooltip_instance.visible = false

## Create the shared tooltip instance
func _create_tooltip_instance() -> void:
	# Create canvas layer for tooltip (above everything)
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 101  # Above drag preview
	_tooltip_layer.name = "TooltipLayer"
	get_tree().root.add_child(_tooltip_layer)

	# Create tooltip using the ItemTooltip script
	_tooltip_instance = PanelContainer.new()
	_tooltip_instance.set_script(ItemTooltip)
	_tooltip_layer.add_child(_tooltip_instance)
	_tooltip_instance._ready()  # Call ready manually since we're adding dynamically

## Update tooltip position to follow mouse
func _update_tooltip_position() -> void:
	if not _tooltip_instance or not _tooltip_instance.visible:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var tooltip_size = _tooltip_instance.size

	var pos = mouse_pos + Vector2(15, 15)

	# Keep on screen
	if pos.x + tooltip_size.x > viewport_size.x:
		pos.x = mouse_pos.x - tooltip_size.x - 10
	if pos.y + tooltip_size.y > viewport_size.y:
		pos.y = viewport_size.y - tooltip_size.y - 10

	_tooltip_instance.global_position = pos

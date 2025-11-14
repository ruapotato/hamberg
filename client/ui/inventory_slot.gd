extends Panel

## InventorySlot - UI component for a single inventory slot
## Displays item icon, amount, and selection state

signal slot_clicked(slot_index: int)

@export var slot_index: int = 0
@export var is_hotbar_slot: bool = false

var item_name: String = ""
var item_amount: int = 0
var is_selected: bool = false

@onready var item_icon: TextureRect = $ItemIcon
@onready var amount_label: Label = $AmountLabel
@onready var selection_border: Panel = $SelectionBorder

func _ready() -> void:
	# Set up click detection
	gui_input.connect(_on_gui_input)
	update_display()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			slot_clicked.emit(slot_index)

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

	if amount_label:
		amount_label.visible = has_item and item_amount > 1
		amount_label.text = str(item_amount)

	if selection_border:
		selection_border.visible = is_selected

## Placeholder icon coloring (until we have actual icons)
func _set_placeholder_icon(item: String) -> void:
	if not item_icon:
		return

	# Create a colored texture based on item type
	var color := Color.WHITE
	match item:
		"wood":
			color = Color(0.6, 0.4, 0.2)  # Brown
		"stone":
			color = Color(0.5, 0.5, 0.5)  # Gray
		"iron":
			color = Color(0.3, 0.3, 0.4)  # Dark gray-blue
		"copper":
			color = Color(0.8, 0.5, 0.2)  # Copper color
		_:
			color = Color(0.8, 0.8, 0.8)  # Default light gray

	item_icon.modulate = color

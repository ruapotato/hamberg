extends Control

## Hotbar - Always-visible UI showing first 9 inventory slots
## Supports number key (1-9) selection like Valheim

signal hotbar_selection_changed(slot_index: int, item_name: String)

const InventorySlot = preload("res://client/ui/inventory_slot.tscn")
const HOTBAR_SIZE: int = 9

var slots: Array[Node] = []
var selected_slot: int = 0
var player_inventory: Node = null

@onready var slots_container: HBoxContainer = $Background/SlotsContainer

func _ready() -> void:
	_create_slots()
	_update_selection()

func _process(_delta: float) -> void:
	# Handle number keys 1-9 for slot selection
	for i in range(1, 10):
		if Input.is_action_just_pressed("hotbar_" + str(i)):
			select_slot(i - 1)

func _create_slots() -> void:
	slots.clear()

	for i in HOTBAR_SIZE:
		var slot = InventorySlot.instantiate()
		slot.slot_index = i
		slot.is_hotbar_slot = true
		slot.slot_clicked.connect(_on_slot_clicked)
		slots_container.add_child(slot)
		slots.append(slot)

func _on_slot_clicked(slot_index: int) -> void:
	select_slot(slot_index)

## Select a hotbar slot
func select_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SIZE:
		return

	selected_slot = index
	_update_selection()

	# Get currently equipped item name
	var equipped_item_name = ""
	if player_inventory:
		var inventory_data = player_inventory.get_inventory_data()
		if index < inventory_data.size() and not inventory_data[index].is_empty():
			equipped_item_name = inventory_data[index].get("item", "")

	# Emit signal for build mode / equipment changes
	hotbar_selection_changed.emit(selected_slot, equipped_item_name)

	# Notify player of selection change
	if player_inventory and player_inventory.get_parent().has_method("on_hotbar_selection_changed"):
		player_inventory.get_parent().on_hotbar_selection_changed(selected_slot)

## Update visual selection
func _update_selection() -> void:
	for i in slots.size():
		slots[i].set_selected(i == selected_slot)

## Link to player's inventory for data sync
func set_player_inventory(inventory: Node) -> void:
	player_inventory = inventory
	refresh_display()

## Refresh hotbar display from inventory data
func refresh_display() -> void:
	if not player_inventory:
		return

	var inventory_data = player_inventory.get_inventory_data()

	for i in HOTBAR_SIZE:
		if i < inventory_data.size():
			slots[i].set_item_data(inventory_data[i])
		else:
			slots[i].set_item_data({})

	# Trigger update after setting data
	for slot in slots:
		slot.update_display()

## Get currently selected slot index
func get_selected_slot() -> int:
	return selected_slot

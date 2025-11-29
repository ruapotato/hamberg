extends StaticBody3D

## Chest - Storage container for items
## Interact with E key to open chest UI

@export var object_name: String = "chest"
@export var max_health: float = 100.0
@export var is_storage: bool = true
@export var storage_slots: int = 20

var current_health: float = 100.0
var is_placed: bool = false
var chunk_position: Vector2i
var object_id: int = -1
var is_preview: bool = false
var can_place: bool = true
var chest_id: String = ""  # Unique ID for server-side storage

# Chest inventory (server synced)
var inventory: Array = []  # Array of {item_name: String, quantity: int}

func _ready() -> void:
	current_health = max_health

	# Add to chest group for combined inventory crafting
	add_to_group("chest")

	if is_preview:
		_setup_preview_mode()

	# Initialize empty inventory slots
	inventory.resize(storage_slots)
	for i in storage_slots:
		inventory[i] = {"item_name": "", "quantity": 0}

	print("[Chest] Storage ready with %d slots" % storage_slots)

func take_damage(damage: float) -> bool:
	current_health -= damage

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

func _on_destroyed() -> void:
	# TODO: Drop chest contents on ground
	print("[Chest] %s destroyed!" % object_name)
	queue_free()

func _setup_preview_mode() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat = mat.duplicate()
			else:
				mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.5
			child.set_surface_override_material(0, mat)

	collision_layer = 0
	collision_mask = 0

func set_preview_valid(valid: bool, is_snapped: bool = false) -> void:
	can_place = valid

	var color_tint: Color
	if not valid:
		color_tint = Color.RED
	elif is_snapped:
		color_tint = Color(0.3, 1.0, 0.3)
	else:
		color_tint = Color(0.6, 0.8, 0.6)

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat.albedo_color = color_tint
				mat.albedo_color.a = 0.6 if is_snapped else 0.5

# Server calls this to sync inventory
func set_inventory_data(data: Array) -> void:
	inventory = data

func get_inventory_data() -> Array:
	return inventory

# Add item to chest (returns amount that couldn't fit)
func add_item(item_name: String, quantity: int) -> int:
	var remaining = quantity

	# First try to stack with existing items
	for i in storage_slots:
		if remaining <= 0:
			break
		if inventory[i].item_name == item_name:
			var max_stack = 64  # TODO: Get from ItemDatabase
			var can_add = max_stack - inventory[i].quantity
			var to_add = min(can_add, remaining)
			inventory[i].quantity += to_add
			remaining -= to_add

	# Then try empty slots
	for i in storage_slots:
		if remaining <= 0:
			break
		if inventory[i].item_name == "" or inventory[i].quantity <= 0:
			var max_stack = 64
			var to_add = min(max_stack, remaining)
			inventory[i] = {"item_name": item_name, "quantity": to_add}
			remaining -= to_add

	return remaining

# Remove item from chest (returns amount actually removed)
func remove_item(item_name: String, quantity: int) -> int:
	var removed = 0

	for i in storage_slots:
		if removed >= quantity:
			break
		if inventory[i].item_name == item_name:
			var to_remove = min(inventory[i].quantity, quantity - removed)
			inventory[i].quantity -= to_remove
			removed += to_remove

			if inventory[i].quantity <= 0:
				inventory[i] = {"item_name": "", "quantity": 0}

	return removed

# Check if chest has item
func has_item(item_name: String, quantity: int = 1) -> bool:
	var total = 0
	for i in storage_slots:
		if inventory[i].item_name == item_name:
			total += inventory[i].quantity
			if total >= quantity:
				return true
	return false

# Get total count of specific item
func get_item_count(item_name: String) -> int:
	var total = 0
	for i in storage_slots:
		if inventory[i].item_name == item_name:
			total += inventory[i].quantity
	return total

class_name BuildModePreview
extends RefCounted

## BuildModePreview - Handles ghost preview for build mode

var build_mode: Node
var ghost_preview: Node3D = null
var current_piece_name: String = ""

# Preview materials
var valid_material: StandardMaterial3D = null
var invalid_material: StandardMaterial3D = null

func _init(bm: Node) -> void:
	build_mode = bm
	setup_materials()

## Setup preview materials
func setup_materials() -> void:
	# Valid placement (green, transparent)
	valid_material = StandardMaterial3D.new()
	valid_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5)
	valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Invalid placement (red, transparent)
	invalid_material = StandardMaterial3D.new()
	invalid_material.albedo_color = Color(0.8, 0.2, 0.2, 0.5)
	invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

# =============================================================================
# PREVIEW MANAGEMENT
# =============================================================================

## Create ghost preview for a piece
func create_preview(piece_name: String) -> void:
	destroy_preview()

	var piece_scene = get_piece_scene(piece_name)
	if not piece_scene:
		return

	ghost_preview = piece_scene.instantiate()
	ghost_preview.name = "GhostPreview"
	current_piece_name = piece_name

	# Disable collisions on preview
	disable_collisions(ghost_preview)

	# Apply preview material
	apply_material(ghost_preview, valid_material)

	# Remove from buildables group (it's just a preview)
	if ghost_preview.is_in_group("buildables"):
		ghost_preview.remove_from_group("buildables")

	build_mode.add_child(ghost_preview)

## Destroy current preview
func destroy_preview() -> void:
	if ghost_preview and is_instance_valid(ghost_preview):
		ghost_preview.queue_free()
	ghost_preview = null
	current_piece_name = ""

## Update preview position and rotation
func update_preview(position: Vector3, rotation_y: float, is_valid: bool) -> void:
	if not ghost_preview:
		return

	ghost_preview.global_position = position
	ghost_preview.rotation.y = rotation_y

	# Update material based on validity
	if is_valid:
		apply_material(ghost_preview, valid_material)
	else:
		apply_material(ghost_preview, invalid_material)

## Rotate preview
func rotate_preview(amount: float = PI / 2) -> void:
	if ghost_preview:
		ghost_preview.rotation.y += amount

## Get current rotation
func get_rotation() -> float:
	if ghost_preview:
		return ghost_preview.rotation.y
	return 0.0

## Get current position
func get_position() -> Vector3:
	if ghost_preview:
		return ghost_preview.global_position
	return Vector3.ZERO

## Check if preview exists
func has_preview() -> bool:
	return ghost_preview != null and is_instance_valid(ghost_preview)

# =============================================================================
# HELPERS
# =============================================================================

## Get piece scene by name
func get_piece_scene(piece_name: String) -> PackedScene:
	var path = "res://shared/buildable/%s.tscn" % piece_name
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Disable collisions on a node and its children
func disable_collisions(node: Node) -> void:
	if node is CollisionShape3D:
		node.disabled = true
	elif node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0

	for child in node.get_children():
		disable_collisions(child)

## Apply material to a node and its children
func apply_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material

	for child in node.get_children():
		apply_material(child, material)

## Set preview visibility
func set_visible(visible: bool) -> void:
	if ghost_preview:
		ghost_preview.visible = visible

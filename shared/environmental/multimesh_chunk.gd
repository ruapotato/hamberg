extends Node3D
class_name MultimeshChunk

## Manages MultiMeshInstance3D nodes for batched rendering of environmental objects in a chunk
## Each unique mesh+material combination gets its own MultiMeshInstance3D for optimal batching

# Instance data for tracking individual objects
class InstanceData:
	var object_type: String
	var local_index: int  # Index within this object type's instance list
	var world_position: Vector3
	var rotation: Vector3
	var scale: Vector3
	var current_health: float
	var max_health: float
	var destroyed: bool = false

# MultiMesh container: one per unique mesh in an object type
class MeshContainer:
	var multimesh_instance: MultiMeshInstance3D
	var multimesh: MultiMesh
	var mesh_def_index: int  # Index in the object_def.mesh_defs array
	var local_transforms: Array[Transform3D] = []  # Per-mesh-def local transform

var chunk_position: Vector2i
var mesh_library

# Dictionary: object_type -> Array[MeshContainer]
var mesh_containers: Dictionary = {}

# Dictionary: object_type -> Array[InstanceData]
var instances: Dictionary = {}

# Dictionary: object_type -> Array[Transform3D] (base transforms before mesh offset)
var instance_transforms: Dictionary = {}

# For collision detection
var collision_area: Area3D
var collision_shapes: Array[CollisionShape3D] = []

signal instance_destroyed(chunk_pos: Vector2i, object_type: String, instance_index: int, resource_drops: Dictionary)

const MultimeshMeshesScript = preload("res://shared/environmental/multimesh_meshes.gd")

func _init():
	mesh_library = MultimeshMeshesScript.get_instance()

func _ready() -> void:
	_setup_collision_area()

func _setup_collision_area() -> void:
	collision_area = Area3D.new()
	collision_area.collision_layer = 0
	collision_area.collision_mask = 2  # Player attacks layer
	collision_area.monitoring = true
	collision_area.monitorable = false
	add_child(collision_area)

func set_chunk_position(pos: Vector2i) -> void:
	chunk_position = pos
	name = "MultimeshChunk_%d_%d" % [pos.x, pos.y]

## Add instances of an object type to this chunk
## transforms: Array of base Transform3D for each instance
## object_type: Type of object (e.g., "glowing_mushroom")
func add_instances(object_type: String, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return

	var obj_def = mesh_library.get_object_def(object_type)
	if not obj_def:
		push_error("[MultimeshChunk] Unknown object type: %s" % object_type)
		return

	# Store transforms and create instance data
	instance_transforms[object_type] = transforms
	instances[object_type] = []

	for i in transforms.size():
		var inst := InstanceData.new()
		inst.object_type = object_type
		inst.local_index = i
		inst.world_position = transforms[i].origin
		inst.rotation = transforms[i].basis.get_euler()
		inst.scale = transforms[i].basis.get_scale()
		inst.max_health = obj_def.max_health
		inst.current_health = obj_def.max_health
		instances[object_type].append(inst)

	# Create MultiMesh containers for each mesh in the object definition
	mesh_containers[object_type] = []

	for mesh_idx in obj_def.mesh_defs.size():
		var mesh_def = obj_def.mesh_defs[mesh_idx]
		var container := MeshContainer.new()
		container.mesh_def_index = mesh_idx

		# Create MultiMesh
		container.multimesh = MultiMesh.new()
		container.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		container.multimesh.mesh = mesh_def.mesh
		container.multimesh.instance_count = transforms.size()

		# Set transforms for each instance
		for i in transforms.size():
			var base_transform: Transform3D = transforms[i]
			var final_transform = base_transform * mesh_def.local_transform
			container.multimesh.set_instance_transform(i, final_transform)

		# Create MultiMeshInstance3D
		container.multimesh_instance = MultiMeshInstance3D.new()
		container.multimesh_instance.multimesh = container.multimesh
		container.multimesh_instance.material_override = mesh_def.material
		container.multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.multimesh_instance.visibility_range_end = obj_def.cull_distance
		container.multimesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(container.multimesh_instance)

		mesh_containers[object_type].append(container)

	# Add collision shapes for each instance
	_add_collision_shapes(object_type, transforms, obj_def)

func _add_collision_shapes(object_type: String, transforms: Array[Transform3D], obj_def) -> void:
	for i in transforms.size():
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = obj_def.collision_radius
		cylinder.height = obj_def.collision_height
		shape.shape = cylinder
		shape.position = transforms[i].origin + Vector3(0, obj_def.collision_height * 0.5, 0)
		shape.set_meta("object_type", object_type)
		shape.set_meta("instance_index", i)
		collision_area.add_child(shape)
		collision_shapes.append(shape)

## Get the nearest instance to a world position
func get_instance_at_position(world_pos: Vector3, max_distance: float = 2.0) -> Dictionary:
	var nearest_dist := max_distance
	var result := {"object_type": "", "index": -1, "distance": max_distance}

	for object_type in instances.keys():
		var inst_array: Array = instances[object_type]
		for i in inst_array.size():
			var inst: InstanceData = inst_array[i]
			if inst.destroyed:
				continue
			var dist := world_pos.distance_to(inst.world_position)
			if dist < nearest_dist:
				nearest_dist = dist
				result = {"object_type": object_type, "index": i, "distance": dist}

	return result

## Apply damage to an instance
func apply_damage(object_type: String, instance_index: int, damage: float) -> bool:
	if not instances.has(object_type):
		return false

	var inst_array: Array = instances[object_type]
	if instance_index < 0 or instance_index >= inst_array.size():
		return false

	var inst: InstanceData = inst_array[instance_index]
	if inst.destroyed:
		return false

	inst.current_health -= damage

	if inst.current_health <= 0:
		_destroy_instance(object_type, instance_index)
		return true

	return false

func _destroy_instance(object_type: String, instance_index: int) -> void:
	var inst_array: Array = instances[object_type]
	var inst: InstanceData = inst_array[instance_index]
	inst.destroyed = true

	# Hide by scaling to zero
	var containers: Array = mesh_containers[object_type]
	for container in containers:
		var mc: MeshContainer = container
		# Set transform to zero scale to hide
		var zero_transform := Transform3D(Basis.from_scale(Vector3.ZERO), inst.world_position)
		mc.multimesh.set_instance_transform(instance_index, zero_transform)

	# Disable collision
	for shape in collision_shapes:
		if shape.get_meta("object_type") == object_type and shape.get_meta("instance_index") == instance_index:
			shape.disabled = true
			break

	# Emit signal with resource drops
	var obj_def = mesh_library.get_object_def(object_type)
	var drops = obj_def.resource_drops.duplicate() if obj_def else {}
	instance_destroyed.emit(chunk_position, object_type, instance_index, drops)

## Mark an instance as destroyed (for loading saved state)
func mark_destroyed(object_type: String, instance_index: int) -> void:
	if not instances.has(object_type):
		return

	var inst_array: Array = instances[object_type]
	if instance_index < 0 or instance_index >= inst_array.size():
		return

	var inst: InstanceData = inst_array[instance_index]
	if inst.destroyed:
		return

	inst.destroyed = true
	inst.current_health = 0

	# Hide by scaling to zero
	var containers: Array = mesh_containers[object_type]
	for container in containers:
		var mc: MeshContainer = container
		var zero_transform := Transform3D(Basis.from_scale(Vector3.ZERO), inst.world_position)
		mc.multimesh.set_instance_transform(instance_index, zero_transform)

	# Disable collision
	for shape in collision_shapes:
		if shape.get_meta("object_type") == object_type and shape.get_meta("instance_index") == instance_index:
			shape.disabled = true
			break

## Get destroyed instance indices for saving
func get_destroyed_indices() -> Dictionary:
	var result := {}
	for object_type in instances.keys():
		var destroyed_list: Array[int] = []
		var inst_array: Array = instances[object_type]
		for i in inst_array.size():
			if inst_array[i].destroyed:
				destroyed_list.append(i)
		if not destroyed_list.is_empty():
			result[object_type] = destroyed_list
	return result

## Get instance count for an object type
func get_instance_count(object_type: String) -> int:
	if not instances.has(object_type):
		return 0
	return instances[object_type].size()

## Get total instance count across all types
func get_total_instance_count() -> int:
	var total := 0
	for object_type in instances.keys():
		total += instances[object_type].size()
	return total

## Add dense decoration instances (no collision, no tracking - pure visual)
## Used for grass and other dense vegetation that doesn't need interaction
func add_decoration_instances(object_type: String, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return

	var obj_def = mesh_library.get_object_def(object_type)
	if not obj_def:
		push_error("[MultimeshChunk] Unknown object type: %s" % object_type)
		return

	# Create MultiMesh containers for each mesh in the object definition
	if not mesh_containers.has(object_type):
		mesh_containers[object_type] = []

	for mesh_idx in obj_def.mesh_defs.size():
		var mesh_def = obj_def.mesh_defs[mesh_idx]
		var container := MeshContainer.new()
		container.mesh_def_index = mesh_idx

		# Create MultiMesh
		container.multimesh = MultiMesh.new()
		container.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		container.multimesh.mesh = mesh_def.mesh
		container.multimesh.instance_count = transforms.size()

		# Set transforms for each instance
		for i in transforms.size():
			var base_transform: Transform3D = transforms[i]
			var final_transform = base_transform * mesh_def.local_transform
			container.multimesh.set_instance_transform(i, final_transform)

		# Create MultiMeshInstance3D
		container.multimesh_instance = MultiMeshInstance3D.new()
		container.multimesh_instance.multimesh = container.multimesh
		container.multimesh_instance.material_override = mesh_def.material
		container.multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.multimesh_instance.visibility_range_end = obj_def.cull_distance
		container.multimesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(container.multimesh_instance)

		mesh_containers[object_type].append(container)

	# No collision shapes, no instance tracking for decorations

## Clean up resources
func cleanup() -> void:
	for object_type in mesh_containers.keys():
		var containers: Array = mesh_containers[object_type]
		for container in containers:
			var mc: MeshContainer = container
			if is_instance_valid(mc.multimesh_instance):
				mc.multimesh_instance.queue_free()

	mesh_containers.clear()
	instances.clear()
	instance_transforms.clear()

	for shape in collision_shapes:
		if is_instance_valid(shape):
			shape.queue_free()
	collision_shapes.clear()

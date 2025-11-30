class_name TerrainModification
extends RefCounted

## TerrainModification - Handles terrain dig, place, and flatten operations

var terrain_world: Node3D

func _init(tw: Node3D) -> void:
	terrain_world = tw

# =============================================================================
# TERRAIN MODIFICATION API
# =============================================================================

## Dig a square hole at the target position
func dig_square(world_position: Vector3, tool_name: String = "stone_pickaxe") -> int:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not terrain_world.chunks.has(key):
		push_warning("[TerrainModification] Cannot dig - chunk not loaded at %s" % world_position)
		return 0

	# Calculate operation area (3x3x3 block centered on target)
	var center_x := int(floor(world_position.x)) - 1
	var center_y := int(floor(world_position.y)) - 1
	var center_z := int(floor(world_position.z)) - 1

	var any_material_removed := false

	# Remove voxels in a 3x3x3 area for alignment with preview
	for dx in range(0, 3):
		for dy in range(0, 3):
			for dz in range(0, 3):
				var wx := center_x + dx
				var wy := center_y + dy
				var wz := center_z + dz

				# Get current density
				var current := _get_voxel_at(wx, wy, wz)
				if current > 0.1:
					any_material_removed = true

				# Set to air
				_set_voxel_at(wx, wy, wz, 0.0)

	# Mark chunk and neighbors as dirty
	_mark_area_dirty(world_position)

	terrain_world.emit_signal("terrain_modified", chunk_coords.x, chunk_coords.y, "dig_square", world_position)

	# 1 dig = 1 earth (balanced gameplay)
	return 1 if any_material_removed else 0

## Place earth in a square pattern
func place_square(world_position: Vector3, earth_amount: int) -> int:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not terrain_world.chunks.has(key):
		push_warning("[TerrainModification] Cannot place - chunk not loaded at %s" % world_position)
		return 0

	var center_x := int(floor(world_position.x)) - 1
	var center_y := int(floor(world_position.y)) - 1
	var center_z := int(floor(world_position.z)) - 1

	var any_material_placed := false

	# Add solid voxels in a 3x3x3 cube area to match dig_square
	for dx in range(0, 3):
		for dy in range(0, 3):
			for dz in range(0, 3):
				var wx := center_x + dx
				var wy := center_y + dy
				var wz := center_z + dz

				# Calculate density based on distance from center
				var dist := Vector3(dx - 1.0, dy - 1.0, dz - 1.0).length()
				var target_density := 1.0 if dist < 1.5 else 0.7

				var current: float = _get_voxel_at(wx, wy, wz)

				# Only place if we're adding material
				if target_density > current:
					any_material_placed = true
					_set_voxel_at(wx, wy, wz, target_density)

	_mark_area_dirty(world_position)

	terrain_world.emit_signal("terrain_modified", chunk_coords.x, chunk_coords.y, "place_square", world_position)

	# 1 place = 1 earth cost (balanced gameplay)
	return 1 if any_material_placed else 0

## Flatten terrain to a target height
func flatten_square(world_position: Vector3, target_height: float) -> int:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var center_x := int(floor(world_position.x))
	var center_z := int(floor(world_position.z))
	var target_y := int(floor(target_height))

	# Flatten a 4x4 area
	for dx in range(-2, 2):
		for dz in range(-2, 2):
			var wx := center_x + dx
			var wz := center_z + dz

			# Remove everything above target height
			for wy in range(target_y + 1, target_y + 10):
				_set_voxel_at(wx, wy, wz, 0.0)

			# Fill everything below target height
			for wy in range(target_y - 5, target_y + 1):
				_set_voxel_at(wx, wy, wz, 1.0)

	_mark_area_dirty(world_position)

	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)
	terrain_world.emit_signal("terrain_modified", chunk_coords.x, chunk_coords.y, "flatten_square", world_position)

	return 0

# =============================================================================
# HELPERS
# =============================================================================

## Get voxel density at world position
func _get_voxel_at(world_x: int, world_y: int, world_z: int) -> float:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(Vector3(world_x, 0, world_z))
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not terrain_world.chunks.has(key):
		return 0.0

	return terrain_world.chunks[key].get_voxel_world(world_x, world_y, world_z)

## Set voxel density at world position
func _set_voxel_at(world_x: int, world_y: int, world_z: int, density: float) -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(Vector3(world_x, 0, world_z))
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not terrain_world.chunks.has(key):
		return

	terrain_world.chunks[key].set_voxel_world(world_x, world_y, world_z, density)

## Mark area around position as needing mesh update
func _mark_area_dirty(world_position: Vector3) -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)

	# Mark the chunk and its neighbors as dirty
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := ChunkDataClass.make_key(chunk_coords.x + dx, chunk_coords.y + dz)
			if terrain_world.chunks.has(key):
				terrain_world.chunks[key].is_dirty = true
				if not terrain_world.pending_mesh_updates.has(key):
					terrain_world.pending_mesh_updates.append(key)

## Apply a terrain modification from network
func apply_network_modification(operation: String, position: Vector3, data: Dictionary) -> void:
	match operation:
		"dig_square":
			var tool_name = data.get("tool", "stone_pickaxe")
			dig_square(position, tool_name)
		"place_square":
			var earth_amount = data.get("earth_amount", 1)
			place_square(position, earth_amount)
		"flatten_square":
			var target_height = data.get("target_height", position.y)
			flatten_square(position, target_height)

extends RefCounted
class_name TerrainChunkData

## TerrainChunkData - Stores voxel data for a single terrain chunk
## Optimized: Only stores a height range around the surface, not full 256 height

const CHUNK_SIZE_XZ: int = 16  # 16x16 horizontal
const SURFACE_RANGE: int = 16  # Store 16 voxels above and below surface (32 total per column)

# Instead of full 256 height, store only around surface
# Each column stores: min_y (int), heights array (float[CHUNK_SIZE_XZ * CHUNK_SIZE_XZ])
# Plus a small voxel buffer for modifications

# Heightmap for fast surface queries
var heightmap: PackedFloat32Array  # CHUNK_SIZE_XZ * CHUNK_SIZE_XZ heights

# Sparse voxel modifications (only store non-default voxels)
# Key: packed int (x + z*16 + y*256), Value: density
var modified_voxels: Dictionary = {}

# Chunk position in chunk coordinates
var chunk_x: int = 0
var chunk_z: int = 0

# Dirty flag for mesh regeneration
var is_dirty: bool = true

# Track if chunk has been modified
var is_modified: bool = false

# Min/max Y with actual terrain (for mesh generation bounds)
var min_surface_y: int = 256
var max_surface_y: int = -256

func _init(cx: int = 0, cz: int = 0) -> void:
	chunk_x = cx
	chunk_z = cz
	heightmap = PackedFloat32Array()
	heightmap.resize(CHUNK_SIZE_XZ * CHUNK_SIZE_XZ)
	heightmap.fill(0.0)

## Get heightmap index
func _height_index(x: int, z: int) -> int:
	return x + z * CHUNK_SIZE_XZ

## Get the terrain height at a local position
func get_height(local_x: int, local_z: int) -> float:
	if local_x < 0 or local_x >= CHUNK_SIZE_XZ or local_z < 0 or local_z >= CHUNK_SIZE_XZ:
		return 0.0
	return heightmap[_height_index(local_x, local_z)]

## Set the terrain height at a local position
func set_height(local_x: int, local_z: int, height: float) -> void:
	if local_x < 0 or local_x >= CHUNK_SIZE_XZ or local_z < 0 or local_z >= CHUNK_SIZE_XZ:
		return
	heightmap[_height_index(local_x, local_z)] = height

	# Track surface bounds
	var h_int := int(floor(height))
	if h_int - 2 < min_surface_y:
		min_surface_y = h_int - 2
	if h_int + 2 > max_surface_y:
		max_surface_y = h_int + 2

## Pack voxel coordinates into a single int for dictionary key
func _pack_coords(x: int, y: int, z: int) -> int:
	return x + z * CHUNK_SIZE_XZ + (y + 128) * CHUNK_SIZE_XZ * CHUNK_SIZE_XZ

## Get voxel density at local chunk coordinates
## Uses heightmap for unmodified terrain, sparse dict for modifications
func get_voxel(x: int, y_local: int, z: int) -> float:
	if x < 0 or x >= CHUNK_SIZE_XZ or z < 0 or z >= CHUNK_SIZE_XZ:
		return 0.0

	# Convert y_local (0-255 array index) to world Y (-128 to +127)
	var world_y: int = y_local - 128

	# Check for modification first
	var key := _pack_coords(x, world_y, z)
	if modified_voxels.has(key):
		return modified_voxels[key]

	# Calculate from heightmap
	var terrain_height: float = heightmap[_height_index(x, z)]
	var distance_from_surface: float = float(world_y) - terrain_height

	if distance_from_surface < -2.0:
		return 1.0  # Deep underground
	elif distance_from_surface > 2.0:
		return 0.0  # Air
	else:
		# Smooth transition
		return 1.0 - (distance_from_surface + 2.0) / 4.0

## Get voxel using world coordinates
func get_voxel_world(world_x: int, world_y: int, world_z: int) -> float:
	var local_x: int = world_x - (chunk_x * CHUNK_SIZE_XZ)
	var local_z: int = world_z - (chunk_z * CHUNK_SIZE_XZ)
	var y_local: int = world_y + 128  # Convert world Y to array index
	return get_voxel(local_x, y_local, local_z)

## Set voxel density (creates a modification)
func set_voxel(x: int, y_local: int, z: int, density: float) -> void:
	if x < 0 or x >= CHUNK_SIZE_XZ or z < 0 or z >= CHUNK_SIZE_XZ:
		return

	var world_y: int = y_local - 128
	var key := _pack_coords(x, world_y, z)

	# Only store if different from heightmap-derived value
	var terrain_height: float = heightmap[_height_index(x, z)]
	var distance_from_surface: float = float(world_y) - terrain_height
	var default_density: float
	if distance_from_surface < -2.0:
		default_density = 1.0
	elif distance_from_surface > 2.0:
		default_density = 0.0
	else:
		default_density = 1.0 - (distance_from_surface + 2.0) / 4.0

	if abs(density - default_density) > 0.01:
		modified_voxels[key] = clamp(density, 0.0, 1.0)
		is_dirty = true
		is_modified = true

		# Update surface bounds
		if world_y - 2 < min_surface_y:
			min_surface_y = world_y - 2
		if world_y + 2 > max_surface_y:
			max_surface_y = world_y + 2
	elif modified_voxels.has(key):
		modified_voxels.erase(key)
		is_dirty = true

## Set voxel using world coordinates
func set_voxel_world(world_x: int, world_y: int, world_z: int, density: float) -> void:
	var local_x: int = world_x - (chunk_x * CHUNK_SIZE_XZ)
	var local_z: int = world_z - (chunk_z * CHUNK_SIZE_XZ)
	var y_local: int = world_y + 128
	set_voxel(local_x, y_local, local_z, density)

## Fill heightmap from biome generator (much faster than filling all voxels)
func fill_from_heights(heights: PackedFloat32Array) -> void:
	heightmap = heights

	# Calculate surface bounds
	min_surface_y = 256
	max_surface_y = -256
	for i in heightmap.size():
		var h: int = int(floor(heightmap[i]))
		if h - 2 < min_surface_y:
			min_surface_y = h - 2
		if h + 2 > max_surface_y:
			max_surface_y = h + 2

	is_dirty = true
	# Don't mark as modified - this is just procedural generation, not player modification
	# is_modified will only be true if voxels are changed via set_voxel()

## Get world position of chunk origin
func get_world_origin() -> Vector3:
	return Vector3(chunk_x * CHUNK_SIZE_XZ, 0, chunk_z * CHUNK_SIZE_XZ)

## Get the Y range that needs mesh generation
func get_surface_y_range() -> Vector2i:
	return Vector2i(max(min_surface_y - 4, -128), min(max_surface_y + 4, 127))

## Serialize chunk data for saving
func serialize() -> Dictionary:
	# Convert modified_voxels dict to array for JSON
	var mods_array := []
	for key in modified_voxels:
		mods_array.append([key, modified_voxels[key]])

	return {
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"heightmap": var_to_bytes(heightmap).hex_encode(),
		"modified_voxels": mods_array,
		"is_modified": is_modified
	}

## Deserialize chunk data
static func deserialize(data: Dictionary):
	var ChunkDataScript = load("res://shared/custom_terrain/chunk_data.gd")
	var chunk = ChunkDataScript.new(data.get("chunk_x", 0), data.get("chunk_z", 0))

	var heightmap_hex = data.get("heightmap", "")
	if heightmap_hex != "":
		var heightmap_bytes = heightmap_hex.hex_decode()
		chunk.heightmap = bytes_to_var(heightmap_bytes)

		# Recalculate bounds
		chunk.min_surface_y = 256
		chunk.max_surface_y = -256
		for i in chunk.heightmap.size():
			var h: int = int(floor(chunk.heightmap[i]))
			if h - 2 < chunk.min_surface_y:
				chunk.min_surface_y = h - 2
			if h + 2 > chunk.max_surface_y:
				chunk.max_surface_y = h + 2

	# Load modified voxels
	var mods_array = data.get("modified_voxels", [])
	for mod in mods_array:
		if mod is Array and mod.size() == 2:
			chunk.modified_voxels[mod[0]] = mod[1]

	chunk.is_modified = data.get("is_modified", false)
	chunk.is_dirty = true

	return chunk

## Get chunk key for dictionary lookups
func get_key() -> String:
	return "%d,%d" % [chunk_x, chunk_z]

## Static helper to make chunk key
static func make_key(cx: int, cz: int) -> String:
	return "%d,%d" % [cx, cz]

## Static helper to get chunk coords from world position
static func world_to_chunk_coords(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / CHUNK_SIZE_XZ)),
		int(floor(world_pos.z / CHUNK_SIZE_XZ))
	)

## Convert local Y array index to world Y coordinate
static func local_to_world_y(y_local: int) -> int:
	return y_local - 128

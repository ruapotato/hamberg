extends Node

## TerrainModifier - Handles terrain modification using VoxelTool
## Pickaxe-based square block placement and removal

# Reference to the voxel terrain
var terrain: VoxelLodTerrain = null
var voxel_tool: VoxelTool = null

# Depth-based mining difficulty settings
const BASE_MINING_SPEED: float = 1.0  # Base operations per second
const DEPTH_SLOWDOWN_FACTOR: float = 0.05  # How much slower per meter below sea level
const MIN_MINING_SPEED: float = 0.01  # Minimum speed (never completely stops)
const SEA_LEVEL: float = 0.0

# Tool effectiveness multipliers (for future tool tiers)
var tool_effectiveness: Dictionary = {
	"stone_pickaxe": 1.0,  # Base effectiveness
	"iron_pickaxe": 2.0,   # 2x faster (future)
	"steel_pickaxe": 3.0,  # 3x faster (future)
}

# Shape parameters
const SQUARE_SIZE: float = 2.0    # Size for square operations (2x2 meters, aligned to grid)
const SQUARE_DEPTH: float = 2.0   # Depth for square operations (2 meters)

# Material collection
const EARTH_PER_VOXEL: float = 0.25  # How much earth to give per voxel removed

func _ready() -> void:
	print("[TerrainModifier] Terrain modifier ready")

## Initialize with the voxel terrain
func initialize(voxel_terrain: VoxelLodTerrain) -> void:
	terrain = voxel_terrain
	if terrain:
		# Get a voxel tool for the terrain
		voxel_tool = terrain.get_voxel_tool()
		if voxel_tool:
			voxel_tool.mode = VoxelTool.MODE_REMOVE  # Default to removing
			voxel_tool.channel = VoxelBuffer.CHANNEL_SDF  # Use SDF channel for smooth terrain
			voxel_tool.sdf_strength = 1.0  # Full strength modifications
			voxel_tool.sdf_scale = 1.0  # Standard SDF scale
			print("[TerrainModifier] Initialized with terrain: %s, VoxelTool: %s" % [terrain.name, voxel_tool])
			print("[TerrainModifier] VoxelTool channel: %d, mode: %d, sdf_strength: %.2f, sdf_scale: %.2f" %
				  [voxel_tool.channel, voxel_tool.mode, voxel_tool.sdf_strength, voxel_tool.sdf_scale])
		else:
			push_error("[TerrainModifier] Failed to get voxel_tool from terrain!")
	else:
		push_error("[TerrainModifier] Failed to initialize - terrain is null")

## Calculate mining speed at a given depth
func get_mining_speed_at_depth(depth_y: float, tool_name: String = "stone_pickaxe") -> float:
	# Calculate depth below sea level
	var depth_below_sea: float = max(0.0, SEA_LEVEL - depth_y)

	# Apply depth slowdown
	var slowdown: float = 1.0 - (depth_below_sea * DEPTH_SLOWDOWN_FACTOR)
	slowdown = max(MIN_MINING_SPEED, slowdown)

	# Apply tool effectiveness
	var tool_mult: float = tool_effectiveness.get(tool_name, 1.0)

	return BASE_MINING_SPEED * slowdown * tool_mult

## Dig a square hole at the target position
## Returns the amount of earth collected
func dig_square(world_position: Vector3, tool_name: String = "stone_pickaxe") -> int:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot dig - voxel_tool not initialized")
		return 0

	# Calculate mining difficulty based on depth
	var mining_speed := get_mining_speed_at_depth(world_position.y, tool_name)

	# Set mode to remove - match placement settings
	voxel_tool.mode = VoxelTool.MODE_REMOVE
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	voxel_tool.sdf_strength = 5.0
	voxel_tool.sdf_scale = 0.5

	# Dig a box centered on the target position (works for floor, ceiling, and walls)
	# Position is already grid-snapped from player.gd, just convert to int for voxel coordinates
	var center_x := int(world_position.x)
	var center_y := int(world_position.y)
	var center_z := int(world_position.z)

	var half_size := int(SQUARE_SIZE / 2)
	var half_depth := int(SQUARE_DEPTH / 2)

	# Expand box by 1 to ensure SDF completely removes the block
	var begin := Vector3i(
		center_x - half_size - 1,
		center_y - half_depth - 1,
		center_z - half_size - 1
	)
	var end := Vector3i(
		center_x + half_size + 1,
		center_y + half_depth + 1,
		center_z + half_size + 1
	)

	voxel_tool.do_box(begin, end)

	# Reset SDF settings to default after box operation
	voxel_tool.sdf_strength = 1.0
	voxel_tool.sdf_scale = 1.0

	# Calculate earth collected (box volume)
	var volume := SQUARE_SIZE * SQUARE_SIZE * SQUARE_DEPTH
	var earth_collected := int(volume * EARTH_PER_VOXEL * mining_speed)

	return earth_collected

## Place earth in a square pattern
## Returns amount of earth actually placed
func place_square(world_position: Vector3, earth_amount: int) -> int:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot place - voxel_tool not initialized")
		return 0

	# Set mode to add with stronger settings for sharper cube edges
	voxel_tool.mode = VoxelTool.MODE_ADD
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	voxel_tool.sdf_strength = 5.0  # Higher strength for sharper cube edges
	voxel_tool.sdf_scale = 0.5  # Tighter scale for crisper placement

	# Place a box centered on the target position (consistent with dig behavior)
	# Position is already grid-snapped from player.gd, just convert to int for voxel coordinates
	var center_x := int(world_position.x)
	var center_y := int(world_position.y)
	var center_z := int(world_position.z)

	var half_size := int(SQUARE_SIZE / 2)
	var half_depth := int(SQUARE_DEPTH / 2)

	var begin := Vector3i(
		center_x - half_size,
		center_y - half_depth,  # Center the box vertically on click point
		center_z - half_size
	)
	var end := Vector3i(
		center_x + half_size,
		center_y + half_depth,  # Place equally up and down from center
		center_z + half_size
	)

	voxel_tool.do_box(begin, end)

	# Reset SDF settings to default after box operation
	voxel_tool.sdf_strength = 1.0
	voxel_tool.sdf_scale = 1.0

	# Calculate earth used (box volume)
	var volume := SQUARE_SIZE * SQUARE_SIZE * SQUARE_DEPTH
	var earth_used := int(min(volume * EARTH_PER_VOXEL, earth_amount))

	return earth_used

## Flatten a 4x4 area to the target height by generating individual dig/place operations
## Returns an array of operations to perform: [{operation: "dig_square"/"place_square", position: Vector3}]
func get_flatten_operations(world_position: Vector3, target_height: float) -> Array:
	var operations := []

	# Snap target height to grid (2-meter intervals)
	var grid_size: float = 2.0
	var snapped_height: float = floor(target_height / grid_size) * grid_size + grid_size / 2.0

	# Center position on the clicked location and snap to grid
	var center_x := floor(world_position.x / grid_size) * grid_size + grid_size / 2.0
	var center_z := floor(world_position.z / grid_size) * grid_size + grid_size / 2.0

	# 4x4 area = 16 grid cells (each 2m x 2m)
	# Flatten in a 4x4 pattern around the click point
	for x_offset in range(-3, 5, 2):  # -3, -1, 1, 3 (4 positions)
		for z_offset in range(-3, 5, 2):  # -3, -1, 1, 3 (4 positions)
			var grid_x := center_x + x_offset
			var grid_z := center_z + z_offset
			var grid_pos := Vector3(grid_x, snapped_height, grid_z)

			# For each grid cell, we need to:
			# 1. Remove any terrain above the target height (dig)
			# 2. Fill to the target height (place)
			# We'll add both operations - the server will apply them in order

			# First, dig to remove any hills above (this clears the space)
			operations.append({
				"operation": "dig_square",
				"position": Vector3(grid_x, snapped_height + 4.0, grid_z),  # Dig 4m above target
				"tool": "stone_hoe"
			})

			# Then place to create the platform at the target height
			operations.append({
				"operation": "place_square",
				"position": grid_pos,
				"earth_amount": 999999  # Unlimited for flattening
			})

	return operations

## Legacy flatten function - kept for compatibility but now just does a single box operation
func flatten_square(world_position: Vector3, target_height: float) -> int:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot flatten - voxel_tool not initialized")
		return 0

	# Snap target height to grid (2-meter intervals)
	var grid_size: float = 2.0
	var snapped_height: float = floor(target_height / grid_size) * grid_size + grid_size / 2.0

	# Center position on the clicked location
	var center_x := int(world_position.x)
	var center_z := int(world_position.z)
	var platform_y := int(snapped_height)

	# 4x4 area (8 meters x 8 meters)
	var half_area := 4  # 4 meters on each side = 8m total

	# First, remove everything ABOVE the platform
	voxel_tool.mode = VoxelTool.MODE_REMOVE
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	voxel_tool.sdf_strength = 5.0
	voxel_tool.sdf_scale = 0.5

	var remove_begin := Vector3i(
		center_x - half_area - 1,
		platform_y + 1,
		center_z - half_area - 1
	)
	var remove_end := Vector3i(
		center_x + half_area + 1,
		platform_y + 20,
		center_z + half_area + 1
	)

	voxel_tool.do_box(remove_begin, remove_end)

	# Then, add the platform itself
	voxel_tool.mode = VoxelTool.MODE_ADD
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	voxel_tool.sdf_strength = 5.0
	voxel_tool.sdf_scale = 0.5

	var add_begin := Vector3i(
		center_x - half_area,
		platform_y - 1,
		center_z - half_area
	)
	var add_end := Vector3i(
		center_x + half_area,
		platform_y + 1,
		center_z + half_area
	)

	voxel_tool.do_box(add_begin, add_end)

	# Reset SDF settings to default
	voxel_tool.sdf_strength = 1.0
	voxel_tool.sdf_scale = 1.0

	return 0

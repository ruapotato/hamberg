extends Node

## TerrainModifier - Handles terrain modification using VoxelTool
## Supports digging, leveling, and placing terrain with depth-based difficulty

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

# Mining progress tracking (for continuous mining)
var current_mining_progress: Dictionary = {}  # position -> {progress: float, total_required: float}

# Shape parameters
const CIRCLE_RADIUS: float = 1.0  # Radius for circle operations (reduced from 2.0)
const SQUARE_SIZE: float = 2.0    # Size for square operations (2x2, aligned to voxel grid) - reduced to prevent player clipping
const SQUARE_DEPTH: float = 2.0   # How deep to dig for square operations (centered on click) - reduced to prevent player clipping
const DEPTH_PER_DIG: float = 1.5  # How deep to dig per operation (for other uses)

# Material collection
const EARTH_PER_VOXEL: float = 0.25  # How much earth to give per voxel removed (reduced from 1.0)

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

## Dig a circular hole at the target position
## Returns the amount of earth collected
func dig_circle(world_position: Vector3, tool_name: String = "stone_pickaxe") -> int:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot dig - voxel_tool not initialized")
		return 0

	print("[TerrainModifier] Digging circle at %s with tool %s" % [world_position, tool_name])

	# Calculate mining difficulty based on depth
	var mining_speed := get_mining_speed_at_depth(world_position.y, tool_name)
	print("[TerrainModifier] Mining speed at depth %.2f: %.3f" % [world_position.y, mining_speed])

	# Check if area is editable
	var check_box := AABB(world_position - Vector3(CIRCLE_RADIUS, CIRCLE_RADIUS, CIRCLE_RADIUS),
						   Vector3(CIRCLE_RADIUS * 2, CIRCLE_RADIUS * 2, CIRCLE_RADIUS * 2))
	if not voxel_tool.is_area_editable(check_box):
		push_warning("[TerrainModifier] Area not editable at %s" % world_position)
		return 0

	# Set mode to remove
	voxel_tool.mode = VoxelTool.MODE_REMOVE
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	voxel_tool.sdf_strength = 1.0  # Full strength

	# Dig a sphere at the target position (centered on the click point)
	print("[TerrainModifier] Calling do_sphere at %s with radius %.2f" % [world_position, CIRCLE_RADIUS])
	voxel_tool.do_sphere(world_position, CIRCLE_RADIUS)

	# Stream disabled - using in-memory history replay system
	# No disk persistence needed

	# Calculate earth collected (approximate based on volume)
	var volume := 4.0 / 3.0 * PI * pow(CIRCLE_RADIUS, 3)
	var earth_collected := int(volume * EARTH_PER_VOXEL * mining_speed)

	print("[TerrainModifier] Dug circle, collected %d earth (speed: %.2f, volume: %.2f)" % [earth_collected, mining_speed, volume])
	return earth_collected

## Dig a square hole at the target position
## Returns the amount of earth collected
func dig_square(world_position: Vector3, tool_name: String = "stone_pickaxe") -> int:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot dig - voxel_tool not initialized")
		return 0

	print("[TerrainModifier] Digging square at %s" % world_position)

	# Calculate mining difficulty based on depth
	var mining_speed := get_mining_speed_at_depth(world_position.y, tool_name)

	# Set mode to remove with stronger settings for sharper cube edges
	voxel_tool.mode = VoxelTool.MODE_REMOVE
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	voxel_tool.sdf_strength = 5.0  # Higher strength for sharper cube edges
	voxel_tool.sdf_scale = 0.5  # Tighter scale for crisper cuts

	# Dig a box centered on the target position (works for floor, ceiling, and walls)
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
		center_y + half_depth,  # Dig equally up and down from center
		center_z + half_size
	)

	print("[TerrainModifier] Calling do_box from %s to %s" % [begin, end])
	voxel_tool.do_box(begin, end)

	# Reset SDF settings to default after box operation
	voxel_tool.sdf_strength = 1.0
	voxel_tool.sdf_scale = 1.0

	# Stream disabled - using in-memory history replay system
	# No disk persistence needed

	# Calculate earth collected (box volume)
	var volume := SQUARE_SIZE * SQUARE_SIZE * SQUARE_DEPTH
	var earth_collected := int(volume * EARTH_PER_VOXEL * mining_speed)

	print("[TerrainModifier] Dug square, collected %d earth (speed: %.2f)" % [earth_collected, mining_speed])
	return earth_collected

## Level terrain to a target height in a circle
## Smooths and flattens terrain using blur algorithm
func level_circle(world_position: Vector3, target_height: float) -> void:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot level - voxel_tool not initialized")
		return

	print("[TerrainModifier] Leveling/smoothing circle at %s" % world_position)

	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

	# Use smooth_sphere for proper terrain flattening
	# blur_radius controls how aggressive the smoothing is (higher = flatter but slower)
	var smooth_radius := 4.0  # Larger area for better flattening
	var blur_radius := 3  # Good balance between smoothness and performance
	voxel_tool.smooth_sphere(world_position, smooth_radius, blur_radius)

	print("[TerrainModifier] Smoothed terrain with radius %.2f, blur %d" % [smooth_radius, blur_radius])

	# Stream disabled - using in-memory history replay system
	# No disk persistence needed

## Place earth in a circular pattern
## Returns amount of earth actually placed (in case inventory runs out)
func place_circle(world_position: Vector3, earth_amount: int) -> int:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot place - voxel_tool not initialized")
		return 0

	print("[TerrainModifier] Placing circle at %s" % world_position)

	# Set mode to add
	voxel_tool.mode = VoxelTool.MODE_ADD
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	voxel_tool.sdf_strength = 1.0  # Full strength

	# Place a sphere at the target position
	print("[TerrainModifier] Calling do_sphere (ADD mode) at %s with radius %.2f" % [world_position, CIRCLE_RADIUS])
	voxel_tool.do_sphere(world_position, CIRCLE_RADIUS)

	# Stream disabled - using in-memory history replay system
	# No disk persistence needed

	# Calculate earth used (approximate based on volume)
	var volume := 4.0 / 3.0 * PI * pow(CIRCLE_RADIUS, 3)
	var earth_used := int(min(volume * EARTH_PER_VOXEL, earth_amount))

	print("[TerrainModifier] Placed circle, used %d earth" % earth_used)
	return earth_used

## Place earth in a square pattern
## Returns amount of earth actually placed
func place_square(world_position: Vector3, earth_amount: int) -> int:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot place - voxel_tool not initialized")
		return 0

	print("[TerrainModifier] Placing square at %s" % world_position)

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

	print("[TerrainModifier] Calling do_box (ADD mode) from %s to %s" % [begin, end])
	voxel_tool.do_box(begin, end)

	# Reset SDF settings to default after box operation
	voxel_tool.sdf_strength = 1.0
	voxel_tool.sdf_scale = 1.0

	# Stream disabled - using in-memory history replay system
	# No disk persistence needed

	# Calculate earth used (box volume)
	var volume := SQUARE_SIZE * SQUARE_SIZE * SQUARE_DEPTH
	var earth_used := int(min(volume * EARTH_PER_VOXEL, earth_amount))

	print("[TerrainModifier] Placed square, used %d earth" % earth_used)
	return earth_used

## Grow terrain in a spherical area (adds terrain with gradient falloff)
func grow_sphere(world_position: Vector3, radius: float, strength: float) -> void:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot grow - voxel_tool not initialized")
		return

	print("[TerrainModifier] Growing terrain at %s with radius %.1f, strength %.1f" % [world_position, radius, strength])

	# Set mode to add
	voxel_tool.mode = VoxelTool.MODE_ADD
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

	# Use grow_sphere for gradual terrain growth
	voxel_tool.grow_sphere(world_position, radius, strength)

	print("[TerrainModifier] Terrain grown successfully")

## Erode terrain in a spherical area (removes terrain with gradient falloff)
func erode_sphere(world_position: Vector3, radius: float, strength: float) -> void:
	if not voxel_tool:
		push_error("[TerrainModifier] Cannot erode - voxel_tool not initialized")
		return

	print("[TerrainModifier] Eroding terrain at %s with radius %.1f, strength %.1f" % [world_position, radius, strength])

	# Set mode to remove
	voxel_tool.mode = VoxelTool.MODE_REMOVE
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

	# Use grow_sphere with remove mode for gradual erosion
	voxel_tool.grow_sphere(world_position, radius, strength)

	print("[TerrainModifier] Terrain eroded successfully")

## Helper: Get approximate terrain height at a position
func _get_terrain_height_at(world_position: Vector3) -> float:
	# Use voxel tool to sample the terrain directly
	if not voxel_tool:
		return world_position.y

	# Sample voxels at the position to find surface
	# For now, just return the input Y position as we're operating at the click point
	return world_position.y

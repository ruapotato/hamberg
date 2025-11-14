extends Node
class_name VoxelInstanceLibrarySetup

## Sets up VoxelInstanceLibrary for environmental objects (trees, rocks, grass)
## Configured for biome-specific spawning

static func create_library() -> VoxelInstanceLibrary:
	var library := VoxelInstanceLibrary.new()

	# Add trees (for Valley and Forest biomes)
	_add_tree_item(library)

	# Add rocks (for all biomes)
	_add_rock_item(library)

	# Add grass (for Valley and Forest biomes)
	_add_grass_item(library)

	print("[VoxelInstanceLibrary] Created library with %d items" % library.get_item_count())
	return library

static func _add_tree_item(library: VoxelInstanceLibrary) -> void:
	var item := VoxelInstanceLibraryItem.new()

	# Load tree scene
	var tree_scene := load("res://shared/props/tree.tscn")
	if not tree_scene:
		push_error("[VoxelInstanceLibrary] Failed to load tree scene!")
		return

	item.set_item_name("tree")
	item.setup_from_template(tree_scene)
	item.persistent = false  # Don't persist instances (regenerate on load)

	# Create noise-based generator for tree placement
	var generator := VoxelInstanceGeneratorNoise.new()

	# Density noise - controls where trees spawn
	var density_noise := FastNoiseLite.new()
	density_noise.seed = 12345
	density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	density_noise.frequency = 0.05  # Larger patches of trees
	generator.noise = density_noise

	# Spawn on surface only
	generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	generator.face_mode = VoxelInstanceGenerator.FACE_MODE_FLOOR

	# Density settings
	generator.density = 0.1  # 10% of valid spots get trees
	generator.min_scale = 0.8
	generator.max_scale = 1.3
	generator.vertical_alignment = 1.0  # Align upright

	# Height constraints - only spawn in certain height ranges
	generator.min_height = -5.0
	generator.max_height = 30.0

	# Slope constraint - don't spawn on steep slopes
	generator.min_slope_degrees = 0.0
	generator.max_slope_degrees = 35.0

	item.generator = generator

	library.add_item(item)
	print("[VoxelInstanceLibrary] Added tree item")

static func _add_rock_item(library: VoxelInstanceLibrary) -> void:
	var item := VoxelInstanceLibraryItem.new()

	# Load rock scene
	var rock_scene := load("res://shared/props/rock.tscn")
	if not rock_scene:
		push_error("[VoxelInstanceLibrary] Failed to load rock scene!")
		return

	item.set_item_name("rock")
	item.setup_from_template(rock_scene)
	item.persistent = false

	# Create noise-based generator for rock placement
	var generator := VoxelInstanceGeneratorNoise.new()

	# Different noise for rocks
	var density_noise := FastNoiseLite.new()
	density_noise.seed = 54321
	density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	density_noise.frequency = 0.08  # More scattered
	generator.noise = density_noise

	# Spawn on surface
	generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	generator.face_mode = VoxelInstanceGenerator.FACE_MODE_FLOOR

	# Lower density than trees
	generator.density = 0.05  # 5% density
	generator.min_scale = 0.7
	generator.max_scale = 1.5
	generator.vertical_alignment = 0.8  # Slightly random tilt

	# Rocks can spawn in more places
	generator.min_height = -10.0
	generator.max_height = 60.0

	# Can spawn on steeper slopes
	generator.min_slope_degrees = 0.0
	generator.max_slope_degrees = 60.0

	item.generator = generator

	library.add_item(item)
	print("[VoxelInstanceLibrary] Added rock item")

static func _add_grass_item(library: VoxelInstanceLibrary) -> void:
	var item := VoxelInstanceLibraryItem.new()

	# Load grass scene
	var grass_scene := load("res://shared/props/grass.tscn")
	if not grass_scene:
		push_error("[VoxelInstanceLibrary] Failed to load grass scene!")
		return

	item.set_item_name("grass")
	item.setup_from_template(grass_scene)
	item.persistent = false

	# Create noise-based generator for grass placement
	var generator := VoxelInstanceGeneratorNoise.new()

	# Dense grass patches
	var density_noise := FastNoiseLite.new()
	density_noise.seed = 99999
	density_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	density_noise.frequency = 0.2  # Smaller patches
	generator.noise = density_noise

	# Spawn on surface
	generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	generator.face_mode = VoxelInstanceGenerator.FACE_MODE_FLOOR

	# High density for grass
	generator.density = 0.3  # 30% coverage
	generator.min_scale = 0.8
	generator.max_scale = 1.2
	generator.vertical_alignment = 1.0  # Upright
	generator.random_vertical_flip = false

	# Only in lower, flatter areas
	generator.min_height = -5.0
	generator.max_height = 25.0

	# Flat surfaces only
	generator.min_slope_degrees = 0.0
	generator.max_slope_degrees = 25.0

	item.generator = generator

	library.add_item(item)
	print("[VoxelInstanceLibrary] Added grass item")

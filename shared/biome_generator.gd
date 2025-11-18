extends VoxelGeneratorScript
class_name BiomeGenerator

## BiomeGenerator - Valheim-style biome system with organic noise-based distribution
## Uses multiple noise layers to create irregular biome shapes
## Distance influences biome difficulty, but doesn't create perfect circles

const CHANNEL := VoxelBuffer.CHANNEL_SDF

# Noise for terrain generation
var noise: FastNoiseLite
var detail_noise: FastNoiseLite

# NEW: Biome selection noises for organic shapes
var biome_noise: FastNoiseLite      # Primary biome selector
var biome_warp_x: FastNoiseLite     # Domain warping for X
var biome_warp_z: FastNoiseLite     # Domain warping for Z
var biome_scale_noise: FastNoiseLite # Controls biome size variation

# Biome difficulty zones (distances from origin - used as weights, not hard boundaries)
const SAFE_ZONE_RADIUS := 800.0      # Starting area - valley/forest likely
const MID_ZONE_RADIUS := 2000.0      # Mid-game biomes
const DANGER_ZONE_RADIUS := 4000.0   # Dangerous biomes
# Beyond DANGER_ZONE_RADIUS: Hell biome becomes more common

# Terrain parameters per biome
var biome_heights := {
	"valley": {"base": 5.0, "amplitude": 10.0, "roughness": 0.3},
	"forest": {"base": 8.0, "amplitude": 15.0, "roughness": 0.4},
	"swamp": {"base": -2.0, "amplitude": 5.0, "roughness": 0.2},
	"mountain": {"base": 40.0, "amplitude": 30.0, "roughness": 0.6},
	"desert": {"base": 3.0, "amplitude": 8.0, "roughness": 0.25},
	"wizardland": {"base": 15.0, "amplitude": 20.0, "roughness": 0.5},
	"hell": {"base": -10.0, "amplitude": 35.0, "roughness": 0.8}
}

func _init(world_seed: int = 42) -> void:
	# Main terrain noise
	noise = FastNoiseLite.new()
	noise.seed = world_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.003
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5

	# Detail noise for roughness
	detail_noise = FastNoiseLite.new()
	detail_noise.seed = world_seed + 1
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.02
	detail_noise.fractal_octaves = 3

	# NEW: Biome selection noise - creates organic biome shapes
	biome_noise = FastNoiseLite.new()
	biome_noise.seed = world_seed + 100
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	biome_noise.frequency = 0.0008  # Large-scale biome regions
	biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	biome_noise.fractal_octaves = 3
	biome_noise.fractal_lacunarity = 2.0
	biome_noise.fractal_gain = 0.5

	# NEW: Domain warping for more organic shapes (Valheim-style distortion)
	biome_warp_x = FastNoiseLite.new()
	biome_warp_x.seed = world_seed + 200
	biome_warp_x.noise_type = FastNoiseLite.TYPE_PERLIN
	biome_warp_x.frequency = 0.0005
	biome_warp_x.fractal_octaves = 2

	biome_warp_z = FastNoiseLite.new()
	biome_warp_z.seed = world_seed + 201
	biome_warp_z.noise_type = FastNoiseLite.TYPE_PERLIN
	biome_warp_z.frequency = 0.0005
	biome_warp_z.fractal_octaves = 2

	# NEW: Controls scale/size variation of biome patches
	biome_scale_noise = FastNoiseLite.new()
	biome_scale_noise.seed = world_seed + 300
	biome_scale_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_scale_noise.frequency = 0.001
	biome_scale_noise.fractal_octaves = 2

	print("[BiomeGenerator] Initialized with seed: %d (Valheim-style noise biomes)" % world_seed)

func _get_used_channels_mask() -> int:
	return 1 << CHANNEL

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Early exit for high LODs
	if lod > 4:
		return

	var buffer_size := out_buffer.get_size()
	var lod_scale := 1 << lod

	# Generate voxels
	for z in buffer_size.z:
		for x in buffer_size.x:
			# World position (XZ)
			var world_x := origin_in_voxels.x + (x << lod)
			var world_z := origin_in_voxels.z + (z << lod)

			# NEW: Get blended height across biome boundaries
			var height := _get_blended_height_at_position(Vector2(world_x, world_z))

			# Generate Y column
			for y in buffer_size.y:
				var world_y := origin_in_voxels.y + (y << lod)

				# SDF: negative = solid, positive = air
				var sdf := float(world_y) - height

				# Clamp SDF for performance
				sdf = clamp(sdf, -50.0, 50.0)

				out_buffer.set_voxel_f(sdf, x, y, z, CHANNEL)

func _get_biome_at_position(xz_pos: Vector2) -> String:
	"""Determine biome using Valheim-style noise-based distribution
	Creates organic, irregular biome shapes instead of perfect circles
	Distance still influences difficulty, but doesn't create hard boundaries"""

	# Calculate distance from origin for difficulty weighting
	var distance := xz_pos.length()

	# Apply domain warping for organic distortion (Valheim-style)
	var warp_strength := 800.0  # How much to distort coordinates
	var warp_x := biome_warp_x.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength
	var warp_z := biome_warp_z.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength

	var warped_pos := xz_pos + Vector2(warp_x, warp_z)

	# Sample biome noise at warped position (-1 to 1)
	var biome_value := biome_noise.get_noise_2d(warped_pos.x, warped_pos.y)

	# Sample scale noise to vary biome patch sizes
	var scale_value := biome_scale_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	# Combine biome noise with scale for more variation
	# This makes some biome patches larger or smaller
	var combined_value := biome_value + (scale_value * 0.3)

	# Normalize to 0-1 range for easier thresholding
	var normalized := (combined_value + 1.0) * 0.5

	# Determine difficulty tier based on distance
	var difficulty_tier := 0
	if distance < SAFE_ZONE_RADIUS:
		difficulty_tier = 0  # Safe biomes only (valley, forest)
	elif distance < MID_ZONE_RADIUS:
		difficulty_tier = 1  # Mid-game biomes (forest, swamp, desert)
	elif distance < DANGER_ZONE_RADIUS:
		difficulty_tier = 2  # Dangerous biomes (mountain, wizardland, hell)
	else:
		difficulty_tier = 3  # Mostly hell with some other dangerous biomes

	# Select biome based on noise value and difficulty tier
	# This creates irregular shapes while respecting distance-based progression
	match difficulty_tier:
		0:  # Safe zone - valley and forest
			if normalized < 0.5:
				return "valley"
			else:
				return "forest"

		1:  # Mid zone - more variety
			if normalized < 0.25:
				return "valley"  # Some safe areas still exist
			elif normalized < 0.5:
				return "forest"
			elif normalized < 0.75:
				return "swamp"
			else:
				return "desert"

		2:  # Danger zone - challenging biomes
			if normalized < 0.15:
				return "forest"  # Occasional safe pockets
			elif normalized < 0.3:
				return "swamp"
			elif normalized < 0.5:
				return "desert"
			elif normalized < 0.7:
				return "mountain"
			elif normalized < 0.85:
				return "wizardland"
			else:
				return "hell"  # Hell starts appearing

		_:  # Far zone - mostly hell with dangerous biomes
			if normalized < 0.2:
				return "mountain"
			elif normalized < 0.3:
				return "wizardland"
			else:
				return "hell"  # Dominant in far regions

	return "valley"  # Fallback

func _get_blended_height_at_position(xz_pos: Vector2) -> float:
	"""Get terrain height with smooth blending between biomes
	This prevents harsh cliffs at biome boundaries"""

	# Get the primary biome and its base noise values
	var distance := xz_pos.length()

	# Apply domain warping (same as biome selection)
	var warp_strength := 800.0
	var warp_x := biome_warp_x.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength
	var warp_z := biome_warp_z.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength
	var warped_pos := xz_pos + Vector2(warp_x, warp_z)

	# Sample biome noise
	var biome_value := biome_noise.get_noise_2d(warped_pos.x, warped_pos.y)
	var scale_value := biome_scale_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var combined_value := biome_value + (scale_value * 0.3)
	var normalized := (combined_value + 1.0) * 0.5

	# Get difficulty tier
	var difficulty_tier := 0
	if distance < SAFE_ZONE_RADIUS:
		difficulty_tier = 0
	elif distance < MID_ZONE_RADIUS:
		difficulty_tier = 1
	elif distance < DANGER_ZONE_RADIUS:
		difficulty_tier = 2
	else:
		difficulty_tier = 3

	# Sample terrain noise once (used for all biome heights)
	var noise_value := noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var detail_value := detail_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	# Helper function to calculate height for a biome
	var calculate_height = func(biome_name: String) -> float:
		var params: Dictionary = biome_heights[biome_name]
		var base: float = params["base"]
		var amplitude: float = params["amplitude"]
		var roughness: float = params["roughness"]
		return base + (noise_value * amplitude) + (detail_value * amplitude * roughness)

	# Blend between biomes based on normalized value and difficulty tier
	# Use smooth transitions instead of hard cutoffs
	var final_height := 0.0

	match difficulty_tier:
		0:  # Safe zone - valley and forest
			# Blend between valley (0.0-0.5) and forest (0.5-1.0)
			var t: float = clamp(normalized * 2.0, 0.0, 1.0)
			var valley_height: float = calculate_height.call("valley")
			var forest_height: float = calculate_height.call("forest")
			final_height = lerp(valley_height, forest_height, t)

		1:  # Mid zone - 4 biomes
			if normalized < 0.5:
				# Blend valley (0.0-0.25) to forest (0.25-0.5)
				var t: float = clamp(normalized * 4.0, 0.0, 1.0)
				var h1: float = calculate_height.call("valley")
				var h2: float = calculate_height.call("forest")
				final_height = lerp(h1, h2, t)
			else:
				# Blend swamp (0.5-0.75) to desert (0.75-1.0)
				var t: float = clamp((normalized - 0.5) * 4.0, 0.0, 1.0)
				var h1: float = calculate_height.call("swamp")
				var h2: float = calculate_height.call("desert")
				final_height = lerp(h1, h2, t)

		2:  # Danger zone - all biomes
			# Multi-stage blending across 6 biomes
			if normalized < 0.3:
				# forest (0.0-0.15) to swamp (0.15-0.3)
				var t: float = clamp(normalized / 0.3, 0.0, 1.0)
				var h1: float = calculate_height.call("forest")
				var h2: float = calculate_height.call("swamp")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.5:
				# swamp (0.3) to desert (0.5)
				var t: float = clamp((normalized - 0.3) / 0.2, 0.0, 1.0)
				var h1: float = calculate_height.call("swamp")
				var h2: float = calculate_height.call("desert")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.7:
				# desert (0.5) to mountain (0.7)
				var t: float = clamp((normalized - 0.5) / 0.2, 0.0, 1.0)
				var h1: float = calculate_height.call("desert")
				var h2: float = calculate_height.call("mountain")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.85:
				# mountain (0.7) to wizardland (0.85)
				var t: float = clamp((normalized - 0.7) / 0.15, 0.0, 1.0)
				var h1: float = calculate_height.call("mountain")
				var h2: float = calculate_height.call("wizardland")
				final_height = lerp(h1, h2, t)
			else:
				# wizardland (0.85) to hell (1.0)
				var t: float = clamp((normalized - 0.85) / 0.15, 0.0, 1.0)
				var h1: float = calculate_height.call("wizardland")
				var h2: float = calculate_height.call("hell")
				final_height = lerp(h1, h2, t)

		_:  # Far zone - mountain, wizardland, hell
			if normalized < 0.2:
				# Full mountain
				var h: float = calculate_height.call("mountain")
				final_height = h
			elif normalized < 0.3:
				# mountain (0.2) to wizardland (0.3)
				var t: float = clamp((normalized - 0.2) / 0.1, 0.0, 1.0)
				var h1: float = calculate_height.call("mountain")
				var h2: float = calculate_height.call("wizardland")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.5:
				# wizardland (0.3) to hell (0.5)
				var t: float = clamp((normalized - 0.3) / 0.2, 0.0, 1.0)
				var h1: float = calculate_height.call("wizardland")
				var h2: float = calculate_height.call("hell")
				final_height = lerp(h1, h2, t)
			else:
				# Full hell
				var h: float = calculate_height.call("hell")
				final_height = h

	return final_height

## Public API for external queries (used by map generator and other systems)
func get_biome_at_position(xz_pos: Vector2) -> String:
	"""Public wrapper for biome queries - uses new noise-based system"""
	return _get_biome_at_position(xz_pos)

func get_height_at_position(xz_pos: Vector2) -> float:
	"""Get terrain height at a specific XZ position with biome blending"""
	return _get_blended_height_at_position(xz_pos)

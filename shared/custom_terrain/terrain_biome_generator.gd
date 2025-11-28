extends RefCounted
class_name TerrainBiomeGenerator

## TerrainBiomeGenerator - Valheim-style biome system for custom terrain
## Uses FastNoiseLite (Godot's built-in noise) for biome calculation
## The shader uses Simplex noise to approximate FastNoiseLite behavior

# Noise for terrain generation
var noise: FastNoiseLite
var detail_noise: FastNoiseLite

# Biome selection noises for organic shapes
var biome_noise: FastNoiseLite      # Primary biome selector
var biome_warp_x: FastNoiseLite     # Domain warping for X
var biome_warp_z: FastNoiseLite     # Domain warping for Z
var biome_scale_noise: FastNoiseLite # Controls biome size variation

# Biome difficulty zones (distances from origin) - MUST match shader constants
const SAFE_ZONE_RADIUS := 5000.0
const MID_ZONE_RADIUS := 10000.0
const DANGER_ZONE_RADIUS := 15000.0
const EXTREME_ZONE_RADIUS := 20000.0

# Terrain parameters per biome
var biome_heights := {
	"valley": {"base": 5.0, "amplitude": 10.0, "roughness": 0.3},
	"dark_forest": {"base": 8.0, "amplitude": 15.0, "roughness": 0.4},
	"swamp": {"base": -2.0, "amplitude": 5.0, "roughness": 0.2},
	"mountain": {"base": 40.0, "amplitude": 30.0, "roughness": 0.6},
	"desert": {"base": 3.0, "amplitude": 8.0, "roughness": 0.25},
	"wizardland": {"base": 15.0, "amplitude": 20.0, "roughness": 0.5},
	"hell": {"base": -10.0, "amplitude": 35.0, "roughness": 0.8}
}

var world_seed: int

func _init(seed_value: int = 42) -> void:
	world_seed = seed_value

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

	# Biome selection noise - creates organic biome shapes
	biome_noise = FastNoiseLite.new()
	biome_noise.seed = world_seed + 100
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	biome_noise.frequency = 0.0008  # Large-scale biome regions
	biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	biome_noise.fractal_octaves = 3
	biome_noise.fractal_lacunarity = 2.0
	biome_noise.fractal_gain = 0.5

	# Domain warping for more organic shapes (Valheim-style distortion)
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

	# Controls scale/size variation of biome patches
	biome_scale_noise = FastNoiseLite.new()
	biome_scale_noise.seed = world_seed + 300
	biome_scale_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_scale_noise.frequency = 0.001
	biome_scale_noise.fractal_octaves = 2

	print("[TerrainBiomeGenerator] Initialized with seed: %d (FastNoiseLite)" % world_seed)

# ============================================================================
# BIOME SELECTION - Uses FastNoiseLite like BiomeGenerator
# ============================================================================

## Get biome index (0-6) - uses FastNoiseLite for perfect match with BiomeGenerator
func _get_biome_index(xz_pos: Vector2) -> int:
	var distance := xz_pos.length()

	# Domain warping for organic distortion (Valheim-style)
	var warp_strength := 800.0
	var warp_x := biome_warp_x.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength
	var warp_z := biome_warp_z.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength

	var warped_pos := xz_pos + Vector2(warp_x, warp_z)

	# Sample biome noise at warped position
	var biome_value := biome_noise.get_noise_2d(warped_pos.x, warped_pos.y)

	# Sample scale noise to vary biome patch sizes
	var scale_value := biome_scale_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	# Combine biome noise with scale for more variation
	var combined_value := biome_value + (scale_value * 0.3)

	# Normalize to 0-1 range
	var normalized := (combined_value + 1.0) * 0.5

	# Determine difficulty tier based on distance
	var difficulty_tier := 0
	if distance < SAFE_ZONE_RADIUS:
		difficulty_tier = 0
	elif distance < MID_ZONE_RADIUS:
		difficulty_tier = 1
	elif distance < DANGER_ZONE_RADIUS:
		difficulty_tier = 2
	elif distance < EXTREME_ZONE_RADIUS:
		difficulty_tier = 3
	else:
		difficulty_tier = 4

	# Select biome based on noise value and difficulty tier
	# Returns: 0=valley, 1=forest, 2=swamp, 3=mountain, 4=desert, 5=wizardland, 6=hell
	match difficulty_tier:
		0:  # Safe zone - valley and forest only
			if normalized < 0.5:
				return 0  # valley
			else:
				return 1  # forest

		1:  # Mid zone - more variety with swamp and desert
			if normalized < 0.25:
				return 0  # valley
			elif normalized < 0.5:
				return 1  # forest
			elif normalized < 0.75:
				return 2  # swamp
			else:
				return 4  # desert

		2:  # Danger zone - mountains and wizardland appear
			if normalized < 0.15:
				return 1  # forest
			elif normalized < 0.3:
				return 2  # swamp
			elif normalized < 0.5:
				return 4  # desert
			elif normalized < 0.7:
				return 3  # mountain
			elif normalized < 0.9:
				return 5  # wizardland
			else:
				return 6  # hell

		3:  # Extreme zone - heavy hell presence
			if normalized < 0.15:
				return 4  # desert
			elif normalized < 0.3:
				return 3  # mountain
			elif normalized < 0.45:
				return 5  # wizardland
			else:
				return 6  # hell

		_:  # Beyond extreme - mostly pure hell
			if normalized < 0.15:
				return 3  # mountain
			elif normalized < 0.25:
				return 5  # wizardland
			else:
				return 6  # hell

	return 0  # Fallback to valley

## Convert biome index to name
func _biome_index_to_name(idx: int) -> String:
	match idx:
		0: return "valley"
		1: return "dark_forest"
		2: return "swamp"
		3: return "mountain"
		4: return "desert"
		5: return "wizardland"
		6: return "hell"
		_: return "valley"

## Get biome at position - public API
func get_biome_at_position(xz_pos: Vector2) -> String:
	var idx := _get_biome_index(xz_pos)
	return _biome_index_to_name(idx)

## Get biome blend weights for smooth transitions
## Returns array of [biome_index, weight] pairs that sum to 1.0
func _get_biome_blend_weights(xz_pos: Vector2) -> Array:
	var distance := xz_pos.length()

	# Domain warping for organic distortion (Valheim-style)
	var warp_strength := 800.0
	var warp_x := biome_warp_x.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength
	var warp_z := biome_warp_z.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength

	var warped_pos := xz_pos + Vector2(warp_x, warp_z)

	# Sample biome noise at warped position
	var biome_value := biome_noise.get_noise_2d(warped_pos.x, warped_pos.y)

	# Sample scale noise to vary biome patch sizes
	var scale_value := biome_scale_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	# Combine biome noise with scale for more variation
	var combined_value := biome_value + (scale_value * 0.3)

	# Normalize to 0-1 range
	var normalized := (combined_value + 1.0) * 0.5

	# Determine difficulty tier based on distance
	var difficulty_tier := 0
	if distance < SAFE_ZONE_RADIUS:
		difficulty_tier = 0
	elif distance < MID_ZONE_RADIUS:
		difficulty_tier = 1
	elif distance < DANGER_ZONE_RADIUS:
		difficulty_tier = 2
	elif distance < EXTREME_ZONE_RADIUS:
		difficulty_tier = 3
	else:
		difficulty_tier = 4

	# Get thresholds and biomes for this tier
	var thresholds: Array = []
	var biomes: Array = []

	match difficulty_tier:
		0:  # Safe zone - valley and forest only
			thresholds = [0.5]
			biomes = [0, 1]
		1:  # Mid zone
			thresholds = [0.25, 0.5, 0.75]
			biomes = [0, 1, 2, 4]
		2:  # Danger zone
			thresholds = [0.15, 0.3, 0.5, 0.7, 0.9]
			biomes = [1, 2, 4, 3, 5, 6]
		3:  # Extreme zone
			thresholds = [0.15, 0.3, 0.45]
			biomes = [4, 3, 5, 6]
		_:  # Beyond extreme
			thresholds = [0.15, 0.25]
			biomes = [3, 5, 6]

	# Blend width controls smoothness (0.05 = 5% of normalized range)
	var blend_width := 0.08

	# Find which biomes to blend and their weights
	var weights: Array = []
	for i in biomes.size():
		weights.append(0.0)

	# Calculate blend weights based on proximity to thresholds
	var prev_threshold := 0.0
	for i in thresholds.size():
		var threshold: float = thresholds[i]
		var lower_blend := threshold - blend_width
		var upper_blend := threshold + blend_width

		if normalized < lower_blend:
			# Fully in lower biome region
			weights[i] = 1.0
			break
		elif normalized < upper_blend:
			# In blend zone
			var t := (normalized - lower_blend) / (2.0 * blend_width)
			t = t * t * (3.0 - 2.0 * t)  # Smoothstep
			weights[i] = 1.0 - t
			weights[i + 1] = t
			break
		prev_threshold = threshold

	# If past all thresholds, fully in last biome
	if weights[biomes.size() - 1] == 0.0:
		var all_zero := true
		for w in weights:
			if w > 0.0:
				all_zero = false
				break
		if all_zero:
			weights[biomes.size() - 1] = 1.0

	# Build result array with non-zero weights
	var result: Array = []
	for i in biomes.size():
		if weights[i] > 0.001:
			result.append([biomes[i], weights[i]])

	# Debug: Validate result structure
	if result.size() > 0:
		for entry in result:
			if not (entry is Array) or entry.size() < 2:
				push_error("[BiomeGenerator] Invalid blend_weights entry at %s: %s" % [xz_pos, entry])
				return [[0, 1.0]]  # Return safe default
	else:
		# If no weights were generated, return safe default (valley, 100%)
		return [[0, 1.0]]

	return result

## Calculate height for a specific biome
func _get_biome_height(xz_pos: Vector2, biome_idx: int) -> float:
	var biome_name := _biome_index_to_name(biome_idx)
	var params: Dictionary = biome_heights.get(biome_name, biome_heights["valley"])
	var base: float = params["base"]
	var amplitude: float = params["amplitude"]
	var roughness: float = params["roughness"]

	var noise_value := noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var detail_value := detail_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	return base + (noise_value * amplitude) + (detail_value * amplitude * roughness)

## Get terrain height with smooth blending between biomes
func get_height_at_position(xz_pos: Vector2) -> float:
	var blend_weights := _get_biome_blend_weights(xz_pos)

	# Blend heights from all contributing biomes
	var final_height := 0.0
	for entry in blend_weights:
		var biome_idx: int = entry[0]
		var weight: float = entry[1]
		var height := _get_biome_height(xz_pos, biome_idx)
		final_height += height * weight

	return final_height

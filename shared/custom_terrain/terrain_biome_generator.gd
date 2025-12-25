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

# === EPIC TERRAIN FEATURES ===
var ridge_noise: FastNoiseLite      # Creates mountain ridges and valleys
var cliff_noise: FastNoiseLite      # Creates cliff faces and plateaus
var ravine_noise: FastNoiseLite     # Carves ravines/dry riverbeds
var clearing_noise: FastNoiseLite   # Creates clearings in forests
var rocky_noise: FastNoiseLite      # Rocky outcrops and boulder fields
var erosion_noise: FastNoiseLite    # Erosion patterns for natural look

# === 3D CAVE SYSTEM - LIGHTWEIGHT ===
var cave_noise: FastNoiseLite       # Simple 3D cave noise (single octave for speed)
var cave_size_noise: FastNoiseLite  # Varies tunnel radius
var cave_y_noise: FastNoiseLite     # Gentle vertical variation (limited steepness)

# Biome difficulty zones (distances from origin) - MUST match shader constants
# Compact world: 1/4 scale for faster exploration
const SPAWN_FLAT_RADIUS := 20.0  # Flat terrain near spawn for shoe hut placement
const SPAWN_FLAT_BLEND := 10.0  # Blend distance from flat to normal terrain
const SPAWN_VALLEY_RADIUS := 25.0  # Always valley near spawn point (safe starting area)
const SAFE_ZONE_RADIUS := 1250.0
const MID_ZONE_RADIUS := 2500.0
const DANGER_ZONE_RADIUS := 3750.0
const EXTREME_ZONE_RADIUS := 5000.0

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
	biome_noise.frequency = 0.0032  # 4x frequency for 1/4 scale world
	biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	biome_noise.fractal_octaves = 3
	biome_noise.fractal_lacunarity = 2.0
	biome_noise.fractal_gain = 0.5

	# Domain warping for more organic shapes (Valheim-style distortion)
	biome_warp_x = FastNoiseLite.new()
	biome_warp_x.seed = world_seed + 200
	biome_warp_x.noise_type = FastNoiseLite.TYPE_PERLIN
	biome_warp_x.frequency = 0.002  # 4x frequency
	biome_warp_x.fractal_octaves = 2

	biome_warp_z = FastNoiseLite.new()
	biome_warp_z.seed = world_seed + 201
	biome_warp_z.noise_type = FastNoiseLite.TYPE_PERLIN
	biome_warp_z.frequency = 0.002  # 4x frequency
	biome_warp_z.fractal_octaves = 2

	# Controls scale/size variation of biome patches
	biome_scale_noise = FastNoiseLite.new()
	biome_scale_noise.seed = world_seed + 300
	biome_scale_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_scale_noise.frequency = 0.004  # 4x frequency
	biome_scale_noise.fractal_octaves = 2

	# === EPIC TERRAIN FEATURE NOISES ===

	# Large-scale terrain variation (hills and valleys)
	ridge_noise = FastNoiseLite.new()
	ridge_noise.seed = world_seed + 400
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.frequency = 0.002  # Large scale variation
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM  # Smooth, not ridged
	ridge_noise.fractal_octaves = 3
	ridge_noise.fractal_lacunarity = 2.0
	ridge_noise.fractal_gain = 0.5

	# Cliff noise - creates plateaus and cliff faces
	cliff_noise = FastNoiseLite.new()
	cliff_noise.seed = world_seed + 500
	cliff_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	cliff_noise.frequency = 0.006
	cliff_noise.fractal_octaves = 2

	# Ravine noise - subtle depressions
	ravine_noise = FastNoiseLite.new()
	ravine_noise.seed = world_seed + 600
	ravine_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ravine_noise.frequency = 0.002
	ravine_noise.fractal_type = FastNoiseLite.FRACTAL_FBM  # Smooth
	ravine_noise.fractal_octaves = 2

	# Clearing noise - creates open clearings in forests
	clearing_noise = FastNoiseLite.new()
	clearing_noise.seed = world_seed + 700
	clearing_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	clearing_noise.frequency = 0.015
	clearing_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE

	# Rocky noise - creates rocky outcrops and boulder fields
	rocky_noise = FastNoiseLite.new()
	rocky_noise.seed = world_seed + 800
	rocky_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	rocky_noise.frequency = 0.02
	rocky_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE

	# Erosion noise - adds natural weathering patterns
	erosion_noise = FastNoiseLite.new()
	erosion_noise.seed = world_seed + 900
	erosion_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	erosion_noise.frequency = 0.025
	erosion_noise.fractal_octaves = 4
	erosion_noise.fractal_gain = 0.7

	# === 3D CAVE SYSTEM ===
	# Grid-based tunnels with noise for variation

	# Cave size variation - makes some tunnels wider, some narrower
	cave_size_noise = FastNoiseLite.new()
	cave_size_noise.seed = world_seed + 1000
	cave_size_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cave_size_noise.frequency = 0.02  # Gradual size changes along tunnels

	# Cave Y variation - gentle vertical undulation (limited steepness)
	cave_y_noise = FastNoiseLite.new()
	cave_y_noise.seed = world_seed + 1001
	cave_y_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_y_noise.frequency = 0.008  # Very low frequency = gentle slopes, not steep

	print("[TerrainBiomeGenerator] Initialized with seed: %d (FastNoiseLite + Caves)" % world_seed)

# ============================================================================
# BIOME SELECTION - Uses FastNoiseLite like BiomeGenerator
# ============================================================================

## Get biome index (0-6) - uses FastNoiseLite for perfect match with BiomeGenerator
func _get_biome_index(xz_pos: Vector2) -> int:
	var distance := xz_pos.length()

	# Force valley biome near spawn point (safe starting area)
	if distance < SPAWN_VALLEY_RADIUS:
		return 0  # valley

	# Domain warping for organic distortion (Valheim-style)
	var warp_strength := 200.0  # 1/4 scale for compact world
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

	# Force valley biome near spawn point (safe starting area)
	if distance < SPAWN_VALLEY_RADIUS:
		return [[0, 1.0]]  # 100% valley

	# Domain warping for organic distortion (Valheim-style)
	var warp_strength := 200.0  # 1/4 scale for compact world
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

## Calculate height for a specific biome with EPIC terrain features
func _get_biome_height(xz_pos: Vector2, biome_idx: int) -> float:
	var biome_name := _biome_index_to_name(biome_idx)
	var params: Dictionary = biome_heights.get(biome_name, biome_heights["valley"])
	var base: float = params["base"]
	var amplitude: float = params["amplitude"]
	var roughness: float = params["roughness"]

	# Base terrain noise
	var noise_value := noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var detail_value := detail_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	var height := base + (noise_value * amplitude) + (detail_value * amplitude * roughness)

	# Apply smooth terrain variation per biome
	match biome_name:
		"valley":
			# Gentle extra hills
			var extra := ridge_noise.get_noise_2d(xz_pos.x, xz_pos.y)
			height += extra * 5.0
		"dark_forest":
			# More hilly
			var extra := ridge_noise.get_noise_2d(xz_pos.x, xz_pos.y)
			height += extra * 8.0
			# Slight bumpiness
			var bumps := erosion_noise.get_noise_2d(xz_pos.x, xz_pos.y)
			height += bumps * 2.0
		"mountain":
			# Much more dramatic height variation
			var extra := ridge_noise.get_noise_2d(xz_pos.x, xz_pos.y)
			height += extra * 20.0
			# Additional peaks
			var peaks := cliff_noise.get_noise_2d(xz_pos.x * 0.5, xz_pos.y * 0.5)
			height += peaks * 15.0
		"swamp":
			# Flatten towards water level
			height = lerpf(-1.0, height, 0.6)
			# Subtle mounds
			var mounds := clearing_noise.get_noise_2d(xz_pos.x * 2.0, xz_pos.y * 2.0)
			height += mounds * 2.0
		"desert":
			# Rolling dunes
			var dunes := ridge_noise.get_noise_2d(xz_pos.x * 1.5, xz_pos.y * 0.5)
			height += dunes * 6.0
		"wizardland":
			# Dramatic but smooth
			var extra := ridge_noise.get_noise_2d(xz_pos.x, xz_pos.y)
			height += extra * 15.0
			var swirl := erosion_noise.get_noise_2d(xz_pos.x + xz_pos.y * 0.1, xz_pos.y)
			height += swirl * 5.0
		"hell":
			# Chaotic terrain
			var chaos := ridge_noise.get_noise_2d(xz_pos.x * 1.5, xz_pos.y * 1.5)
			height += chaos * 18.0
			var pits := ravine_noise.get_noise_2d(xz_pos.x, xz_pos.y)
			height += pits * 8.0

	return height

# =============================================================================
# EPIC TERRAIN FEATURE FUNCTIONS
# =============================================================================

## Valley: Gentle rolling hills with subtle variation
func _apply_valley_features(xz_pos: Vector2, height: float, amplitude: float) -> float:
	# Gentle undulation for more interesting hills
	var ridge := ridge_noise.get_noise_2d(xz_pos.x * 0.3, xz_pos.y * 0.3)
	height += ridge * amplitude * 0.15  # Very subtle

	# Occasional flatter areas (clearings)
	var clearing := clearing_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	if clearing > 0.7:
		var flatten_amount := (clearing - 0.7) / 0.3
		height = lerpf(height, 5.0, flatten_amount * 0.3)

	# Very subtle depressions (dry stream beds)
	var ravine := ravine_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	if ravine > 0.9:
		var depth := (ravine - 0.9) / 0.1
		height -= depth * 2.0

	return height

## Dark Forest: Uneven ground with subtle hills and clearings
func _apply_forest_features(xz_pos: Vector2, height: float, amplitude: float) -> float:
	# Gentle hills
	var ridge := ridge_noise.get_noise_2d(xz_pos.x * 0.5, xz_pos.y * 0.5)
	height += ridge * amplitude * 0.2

	# Slight rocky bumps
	var rocky := rocky_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	if rocky > 0.75:
		var rock_height := (rocky - 0.75) / 0.25
		height += rock_height * 3.0

	# Forest clearings
	var clearing := clearing_noise.get_noise_2d(xz_pos.x * 1.5, xz_pos.y * 1.5)
	if clearing > 0.7:
		var flatten := (clearing - 0.7) / 0.3
		height = lerpf(height, 6.0, flatten * 0.3)

	# Subtle ground variation
	var erosion := erosion_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	height += erosion * 1.0

	return height

## Mountains: Dramatic peaks with smooth ridgelines
func _apply_mountain_features(xz_pos: Vector2, height: float, amplitude: float) -> float:
	# Ridge lines for mountain ranges (smooth, not sharp)
	var ridge := ridge_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	height += ridge * amplitude * 0.5

	# Valleys between peaks
	var valley: float = 1.0 - abs(ridge_noise.get_noise_2d(xz_pos.x * 0.3, xz_pos.y * 0.3))
	if valley > 0.75:
		var valley_depth: float = (valley - 0.75) / 0.25
		height -= valley_depth * 10.0

	# Rocky detail
	var rocky := rocky_noise.get_noise_2d(xz_pos.x * 2.0, xz_pos.y * 2.0)
	height += rocky * 2.0

	return height

## Swamp: Mostly flat with slight undulations
func _apply_swamp_features(xz_pos: Vector2, height: float, amplitude: float) -> float:
	# Swamps are mostly flat - reduce existing variation
	height = lerpf(-2.0, height, 0.5)

	# Slight mounds (tree islands)
	var mound := clearing_noise.get_noise_2d(xz_pos.x * 2.0, xz_pos.y * 2.0)
	if mound > 0.6:
		var mound_height := (mound - 0.6) / 0.4
		height += mound_height * 2.0

	# Subtle depressions
	var pool := rocky_noise.get_noise_2d(xz_pos.x * 0.8, xz_pos.y * 0.8)
	if pool < 0.25:
		var pool_depth := (0.25 - pool) / 0.25
		height -= pool_depth * 1.5

	return height

## Desert: Gentle dunes and subtle variation
func _apply_desert_features(xz_pos: Vector2, height: float, amplitude: float) -> float:
	# Sand dunes - gentle wave-like shapes
	var dune := ridge_noise.get_noise_2d(xz_pos.x * 1.0, xz_pos.y * 0.4)
	height += dune * amplitude * 0.3

	# Occasional higher areas
	var plateau := cliff_noise.get_noise_2d(xz_pos.x * 0.3, xz_pos.y * 0.3)
	if plateau > 0.6:
		var mesa_height := (plateau - 0.6) / 0.4
		height += mesa_height * 5.0

	# Subtle depressions
	var canyon := ravine_noise.get_noise_2d(xz_pos.x * 0.4, xz_pos.y * 0.4)
	if canyon > 0.9:
		var canyon_depth := (canyon - 0.9) / 0.1
		height -= canyon_depth * 4.0

	# Wind erosion patterns
	var erosion := erosion_noise.get_noise_2d(xz_pos.x * 3.0, xz_pos.y * 3.0)
	height += erosion * 0.8

	return height

## Wizardland: Mystical terrain with unusual formations
func _apply_wizardland_features(xz_pos: Vector2, height: float, amplitude: float) -> float:
	# Occasional tall formations
	var spire := rocky_noise.get_noise_2d(xz_pos.x * 1.2, xz_pos.y * 1.2)
	if spire > 0.7:
		var spire_height := (spire - 0.7) / 0.3
		height += spire_height * 12.0

	# Raised plateaus
	var plateau := cliff_noise.get_noise_2d(xz_pos.x * 0.5, xz_pos.y * 0.5)
	if plateau > 0.5:
		var lift := (plateau - 0.5) / 0.5
		height += lift * 8.0

	# Mystical valleys
	var valley: float = ridge_noise.get_noise_2d(xz_pos.x * 0.6, xz_pos.y * 0.6)
	if valley < -0.5:
		height += valley * 6.0

	# Swirling patterns
	var swirl_x := xz_pos.x + sin(xz_pos.y * 0.01) * 15.0
	var swirl_z := xz_pos.y + cos(xz_pos.x * 0.01) * 15.0
	var erosion := erosion_noise.get_noise_2d(swirl_x, swirl_z)
	height += erosion * 2.0

	return height

## Hell: Rough, volcanic terrain
func _apply_hell_features(xz_pos: Vector2, height: float, amplitude: float) -> float:
	# Jagged ridges
	var ridge := ridge_noise.get_noise_2d(xz_pos.x * 1.2, xz_pos.y * 1.2)
	height += ridge * amplitude * 0.6

	# Volcanic craters
	var crater := clearing_noise.get_noise_2d(xz_pos.x * 0.8, xz_pos.y * 0.8)
	if crater > 0.75:
		var crater_depth := (crater - 0.75) / 0.25
		height -= crater_depth * 10.0

	# Lava channels
	var lava := ravine_noise.get_noise_2d(xz_pos.x * 0.6, xz_pos.y * 0.6)
	if lava > 0.88:
		var channel_depth := (lava - 0.88) / 0.12
		height -= channel_depth * 6.0

	# Rocky detail
	var spike := rocky_noise.get_noise_2d(xz_pos.x * 2.0, xz_pos.y * 2.0)
	height += spike * 3.0

	# Chaotic variation
	var erosion := erosion_noise.get_noise_2d(xz_pos.x * 2.0, xz_pos.y * 2.0)
	height += erosion * 2.0

	return height

## Smoothstep helper function
func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# =============================================================================
# SUB-BIOME FEATURE QUERIES (for object spawning)
# =============================================================================

## Get sub-biome features at a position
## Returns: { "clearing": 0.0-1.0, "dense": 0.0-1.0, "rocky": 0.0-1.0, "ravine": 0.0-1.0 }
func get_sub_biome_features(xz_pos: Vector2) -> Dictionary:
	var clearing_val: float = clearing_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var rocky_val: float = rocky_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var ravine_val: float = ravine_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var ridge_val: float = abs(ridge_noise.get_noise_2d(xz_pos.x * 0.7, xz_pos.y * 0.7))

	return {
		"clearing": maxf(0.0, (clearing_val - 0.5) * 2.0),  # 0 = not clearing, 1 = full clearing
		"dense": maxf(0.0, (0.3 - clearing_val) * 3.0),     # Inverse of clearing = dense
		"rocky": maxf(0.0, (rocky_val - 0.5) * 2.0),        # 0 = not rocky, 1 = very rocky
		"ravine": maxf(0.0, (ravine_val - 0.8) * 5.0),      # 0 = not ravine, 1 = deep ravine
		"ridge": ridge_val                                   # 0 = valley, 1 = ridge top
	}

## Check if position is in a clearing (no trees should spawn here)
func is_clearing(xz_pos: Vector2) -> bool:
	var clearing_val := clearing_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	return clearing_val > 0.6

## Check if position is in a dense area (more trees/objects)
func is_dense_area(xz_pos: Vector2) -> bool:
	var clearing_val := clearing_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	return clearing_val < 0.3

## Check if position is rocky (rocks spawn, fewer trees)
func is_rocky(xz_pos: Vector2) -> bool:
	var rocky_val := rocky_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	return rocky_val > 0.6

## Check if position is in a ravine/riverbed
func is_ravine(xz_pos: Vector2) -> bool:
	var ravine_val := ravine_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	return ravine_val > 0.85

## Get tree density multiplier for a position (0.0 = no trees, 2.0 = extra dense)
func get_tree_density_multiplier(xz_pos: Vector2) -> float:
	var features := get_sub_biome_features(xz_pos)

	# No trees in clearings or ravines
	if features["clearing"] > 0.5 or features["ravine"] > 0.3:
		return 0.0

	# Fewer trees in rocky areas
	if features["rocky"] > 0.5:
		return 0.3

	# More trees in dense areas
	if features["dense"] > 0.5:
		return 1.5 + features["dense"] * 0.5  # Up to 2.0x

	return 1.0  # Normal density

## Get terrain height with smooth blending between biomes
func get_height_at_position(xz_pos: Vector2) -> float:
	var distance := xz_pos.length()

	# Flat spawn area for shoe hut
	const SPAWN_HEIGHT := 5.0  # Valley base height
	if distance < SPAWN_FLAT_RADIUS:
		return SPAWN_HEIGHT

	var blend_weights := _get_biome_blend_weights(xz_pos)

	# Blend heights from all contributing biomes
	var final_height := 0.0
	for entry in blend_weights:
		var biome_idx: int = entry[0]
		var weight: float = entry[1]
		var height := _get_biome_height(xz_pos, biome_idx)
		final_height += height * weight

	# Smooth blend from flat spawn area to normal terrain
	if distance < SPAWN_FLAT_RADIUS + SPAWN_FLAT_BLEND:
		var blend_factor := (distance - SPAWN_FLAT_RADIUS) / SPAWN_FLAT_BLEND
		# Smoothstep for nicer transition
		blend_factor = blend_factor * blend_factor * (3.0 - 2.0 * blend_factor)
		return lerpf(SPAWN_HEIGHT, final_height, blend_factor)

	return final_height

# =============================================================================
# 3D CAVE SYSTEM
# =============================================================================

## FAST cave carving - multi-level grid tunnels with vertical shafts
## Uses noise for size and gentle vertical undulation within each level
## Returns 0.0 = no cave, positive = carve this much from density
func get_fast_cave_carving(world_pos: Vector3, surface_height: float) -> float:
	# Grid spacing for tunnels
	const GRID_SPACING: float = 50.0
	const BASE_TUNNEL_RADIUS: float = 5.0
	const RADIUS_VARIATION: float = 3.0  # Radius varies from 2 to 8
	const Y_VARIATION: float = 4.0  # Max vertical undulation (gentle slopes)

	# Multi-level cave depths (units below surface)
	const CAVE_LEVELS: Array = [15.0, 40.0, 70.0, 100.0]
	const LEVEL_SPACING: float = 25.0  # Vertical distance between levels

	# Shaft parameters (vertical connections between levels)
	const SHAFT_GRID_SPACING: float = 100.0  # Shafts at intersections every 100 units
	const SHAFT_RADIUS: float = 4.0

	# Early Y check - must be below surface to be in caves
	if world_pos.y > surface_height - 8.0:
		return 0.0

	# Maximum possible cave depth
	var max_cave_depth: float = CAVE_LEVELS[CAVE_LEVELS.size() - 1] + Y_VARIATION + BASE_TUNNEL_RADIUS + RADIUS_VARIATION
	if world_pos.y < surface_height - max_cave_depth - 10.0:
		return 0.0

	var best_carve: float = 0.0

	# Check vertical shafts first (they connect levels)
	var shaft_x: float = round(world_pos.x / SHAFT_GRID_SPACING) * SHAFT_GRID_SPACING
	var shaft_z: float = round(world_pos.z / SHAFT_GRID_SPACING) * SHAFT_GRID_SPACING
	var shaft_horiz_dist: float = sqrt(
		(world_pos.x - shaft_x) * (world_pos.x - shaft_x) +
		(world_pos.z - shaft_z) * (world_pos.z - shaft_z)
	)

	# Vary shaft radius slightly
	var shaft_size_noise: float = cave_size_noise.get_noise_2d(shaft_x * 0.1, shaft_z * 0.1)
	var actual_shaft_radius: float = SHAFT_RADIUS + shaft_size_noise * 2.0

	if shaft_horiz_dist < actual_shaft_radius:
		# Check if we're within the vertical range of shafts (between first and last level)
		var shaft_top: float = surface_height - CAVE_LEVELS[0] + Y_VARIATION + 5.0
		var shaft_bottom: float = surface_height - CAVE_LEVELS[CAVE_LEVELS.size() - 1] - Y_VARIATION - 5.0
		if world_pos.y <= shaft_top and world_pos.y >= shaft_bottom:
			var shaft_carve: float = 1.0 - (shaft_horiz_dist / actual_shaft_radius)
			best_carve = maxf(best_carve, shaft_carve)

	# Check each horizontal tunnel level
	for level_depth in CAVE_LEVELS:
		var level_carve: float = _get_tunnel_level_carving(
			world_pos, surface_height, level_depth,
			GRID_SPACING, BASE_TUNNEL_RADIUS, RADIUS_VARIATION, Y_VARIATION
		)
		best_carve = maxf(best_carve, level_carve)

	return best_carve

## Get carving for a single tunnel level
func _get_tunnel_level_carving(
	world_pos: Vector3, surface_height: float, level_depth: float,
	grid_spacing: float, base_radius: float, radius_var: float, y_var: float
) -> float:
	# Quick Y check for this level
	var level_y: float = surface_height - level_depth
	var max_radius: float = base_radius + radius_var
	if absf(world_pos.y - level_y) > max_radius + y_var + 2.0:
		return 0.0

	# Find which tunnel segments we're near
	var z_in_grid: float = fmod(absf(world_pos.z), grid_spacing)
	var dist_to_x_tunnel: float = minf(z_in_grid, grid_spacing - z_in_grid)

	var x_in_grid: float = fmod(absf(world_pos.x), grid_spacing)
	var dist_to_z_tunnel: float = minf(x_in_grid, grid_spacing - x_in_grid)

	# Determine which tunnel we're closest to (X-aligned or Z-aligned)
	var in_x_tunnel: bool = dist_to_x_tunnel < dist_to_z_tunnel

	# Get tunnel center position for noise sampling
	var tunnel_sample_pos: Vector2
	var horiz_dist: float
	if in_x_tunnel:
		var tunnel_z: float = round(world_pos.z / grid_spacing) * grid_spacing
		tunnel_sample_pos = Vector2(world_pos.x, tunnel_z + level_depth * 7.0)  # Offset by depth for variation
		horiz_dist = dist_to_x_tunnel
	else:
		var tunnel_x: float = round(world_pos.x / grid_spacing) * grid_spacing
		tunnel_sample_pos = Vector2(tunnel_x + level_depth * 7.0, world_pos.z)
		horiz_dist = dist_to_z_tunnel

	# Vary tunnel radius along its length
	var size_noise: float = cave_size_noise.get_noise_2d(tunnel_sample_pos.x, tunnel_sample_pos.y)
	var tunnel_radius: float = base_radius + size_noise * radius_var

	# Early exit if too far horizontally
	if horiz_dist > tunnel_radius + 1.0:
		return 0.0

	# Gentle vertical undulation within this level
	var y_offset: float = cave_y_noise.get_noise_2d(tunnel_sample_pos.x, tunnel_sample_pos.y) * y_var
	var tunnel_y: float = level_y + y_offset

	# Vertical distance to tunnel center
	var y_dist: float = absf(world_pos.y - tunnel_y)

	# Early exit if too far vertically
	if y_dist > tunnel_radius + 1.0:
		return 0.0

	# Cylindrical distance
	var cylinder_dist: float = sqrt(horiz_dist * horiz_dist + y_dist * y_dist)

	if cylinder_dist > tunnel_radius:
		return 0.0

	# Smooth carving with falloff at edges
	return 1.0 - (cylinder_dist / tunnel_radius)

## Check if a position should have crystal formations (for rendering)
## Returns crystal intensity 0.0 to 1.0
## NOTE: Simplified - crystals disabled for now, can add back later
func get_crystal_intensity(_world_pos: Vector3) -> float:
	return 0.0

## Check if position is in the deep caves biome
func is_in_cave_zone(xz_pos: Vector2) -> bool:
	return xz_pos.length() >= MID_ZONE_RADIUS

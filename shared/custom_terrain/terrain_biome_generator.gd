extends RefCounted
class_name TerrainBiomeGenerator

## TerrainBiomeGenerator - Valheim-style biome system for custom terrain
## Adapted from BiomeGenerator (removed VoxelGeneratorScript dependency)
## Uses multiple noise layers to create irregular biome shapes

# Noise for terrain generation
var noise: FastNoiseLite
var detail_noise: FastNoiseLite

# Biome selection noises for organic shapes
var biome_noise: FastNoiseLite
var biome_warp_x: FastNoiseLite
var biome_warp_z: FastNoiseLite
var biome_scale_noise: FastNoiseLite

# Biome difficulty zones (distances from origin)
const SAFE_ZONE_RADIUS := 5000.0
const MID_ZONE_RADIUS := 10000.0
const DANGER_ZONE_RADIUS := 15000.0
const EXTREME_ZONE_RADIUS := 20000.0

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
	biome_noise.frequency = 0.0008
	biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	biome_noise.fractal_octaves = 3
	biome_noise.fractal_lacunarity = 2.0
	biome_noise.fractal_gain = 0.5

	# Domain warping for more organic shapes (Valheim-style)
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

	print("[TerrainBiomeGenerator] Initialized with seed: %d" % world_seed)

## Get biome at position using Valheim-style noise distribution
func get_biome_at_position(xz_pos: Vector2) -> String:
	var distance := xz_pos.length()

	# Apply domain warping for organic distortion
	var warp_strength := 800.0
	var warp_x := biome_warp_x.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength
	var warp_z := biome_warp_z.get_noise_2d(xz_pos.x, xz_pos.y) * warp_strength

	var warped_pos := xz_pos + Vector2(warp_x, warp_z)

	# Sample biome noise at warped position
	var biome_value := biome_noise.get_noise_2d(warped_pos.x, warped_pos.y)
	var scale_value := biome_scale_noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var combined_value := biome_value + (scale_value * 0.3)
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
	match difficulty_tier:
		0:  # Safe zone - valley and forest only
			if normalized < 0.5:
				return "valley"
			else:
				return "forest"

		1:  # Mid zone - more variety
			if normalized < 0.25:
				return "valley"
			elif normalized < 0.5:
				return "forest"
			elif normalized < 0.75:
				return "swamp"
			else:
				return "desert"

		2:  # Danger zone - mountains and wizardland
			if normalized < 0.15:
				return "forest"
			elif normalized < 0.3:
				return "swamp"
			elif normalized < 0.5:
				return "desert"
			elif normalized < 0.7:
				return "mountain"
			elif normalized < 0.9:
				return "wizardland"
			else:
				return "hell"

		3:  # Extreme zone - heavy hell presence
			if normalized < 0.15:
				return "desert"
			elif normalized < 0.3:
				return "mountain"
			elif normalized < 0.45:
				return "wizardland"
			else:
				return "hell"

		_:  # Beyond extreme - mostly pure hell
			if normalized < 0.15:
				return "mountain"
			elif normalized < 0.25:
				return "wizardland"
			else:
				return "hell"

	return "valley"

## Get terrain height with smooth blending between biomes
func get_height_at_position(xz_pos: Vector2) -> float:
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
	elif distance < EXTREME_ZONE_RADIUS:
		difficulty_tier = 3
	else:
		difficulty_tier = 4

	# Sample terrain noise
	var noise_value := noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var detail_value := detail_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	# Helper to calculate height for a biome
	var calculate_height = func(biome_name: String) -> float:
		var params: Dictionary = biome_heights[biome_name]
		var base: float = params["base"]
		var amplitude: float = params["amplitude"]
		var roughness: float = params["roughness"]
		return base + (noise_value * amplitude) + (detail_value * amplitude * roughness)

	# Blend between biomes based on difficulty tier
	var final_height := 0.0

	match difficulty_tier:
		0:  # Safe zone - valley and forest
			var t: float = clamp(normalized * 2.0, 0.0, 1.0)
			var valley_height: float = calculate_height.call("valley")
			var forest_height: float = calculate_height.call("forest")
			final_height = lerp(valley_height, forest_height, t)

		1:  # Mid zone - 4 biomes
			if normalized < 0.5:
				var t: float = clamp(normalized * 4.0, 0.0, 1.0)
				var h1: float = calculate_height.call("valley")
				var h2: float = calculate_height.call("forest")
				final_height = lerp(h1, h2, t)
			else:
				var t: float = clamp((normalized - 0.5) * 4.0, 0.0, 1.0)
				var h1: float = calculate_height.call("swamp")
				var h2: float = calculate_height.call("desert")
				final_height = lerp(h1, h2, t)

		2:  # Danger zone
			if normalized < 0.3:
				var t: float = clamp(normalized / 0.3, 0.0, 1.0)
				var h1: float = calculate_height.call("forest")
				var h2: float = calculate_height.call("swamp")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.5:
				var t: float = clamp((normalized - 0.3) / 0.2, 0.0, 1.0)
				var h1: float = calculate_height.call("swamp")
				var h2: float = calculate_height.call("desert")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.7:
				var t: float = clamp((normalized - 0.5) / 0.2, 0.0, 1.0)
				var h1: float = calculate_height.call("desert")
				var h2: float = calculate_height.call("mountain")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.9:
				var t: float = clamp((normalized - 0.7) / 0.2, 0.0, 1.0)
				var h1: float = calculate_height.call("mountain")
				var h2: float = calculate_height.call("wizardland")
				final_height = lerp(h1, h2, t)
			else:
				var t: float = clamp((normalized - 0.9) / 0.1, 0.0, 1.0)
				var h1: float = calculate_height.call("wizardland")
				var h2: float = calculate_height.call("hell")
				final_height = lerp(h1, h2, t)

		3:  # Extreme zone
			if normalized < 0.15:
				final_height = calculate_height.call("desert")
			elif normalized < 0.3:
				var t: float = clamp((normalized - 0.15) / 0.15, 0.0, 1.0)
				var h1: float = calculate_height.call("desert")
				var h2: float = calculate_height.call("mountain")
				final_height = lerp(h1, h2, t)
			elif normalized < 0.45:
				var t: float = clamp((normalized - 0.3) / 0.15, 0.0, 1.0)
				var h1: float = calculate_height.call("mountain")
				var h2: float = calculate_height.call("wizardland")
				final_height = lerp(h1, h2, t)
			else:
				var t: float = clamp((normalized - 0.45) / 0.55, 0.0, 1.0)
				var h1: float = calculate_height.call("wizardland")
				var h2: float = calculate_height.call("hell")
				final_height = lerp(h1, h2, t)

		_:  # Beyond extreme
			if normalized < 0.15:
				final_height = calculate_height.call("mountain")
			elif normalized < 0.25:
				var t: float = clamp((normalized - 0.15) / 0.1, 0.0, 1.0)
				var h1: float = calculate_height.call("mountain")
				var h2: float = calculate_height.call("wizardland")
				final_height = lerp(h1, h2, t)
			else:
				var t: float = clamp((normalized - 0.25) / 0.75, 0.0, 1.0)
				var h1: float = calculate_height.call("wizardland")
				var h2: float = calculate_height.call("hell")
				final_height = lerp(h1, h2, t)

	return final_height

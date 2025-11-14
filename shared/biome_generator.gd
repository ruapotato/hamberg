extends VoxelGeneratorScript
class_name BiomeGenerator

## BiomeGenerator - Valheim-style biome system
## Distance from origin determines biome difficulty
## Height modifies biome type (mountains high, oceans low)

const CHANNEL := VoxelBuffer.CHANNEL_SDF

# Noise for terrain generation
var noise: FastNoiseLite
var detail_noise: FastNoiseLite

# Biome configuration (distances from origin in blocks)
const MEADOWS_RADIUS := 500.0      # Starting area
const FOREST_RADIUS := 1000.0      # Black forest equivalent
const SWAMP_RADIUS := 1500.0       # Dangerous swamps
const MOUNTAIN_RADIUS := 2000.0    # Mountain biome start
const PLAINS_RADIUS := 2500.0      # Plains
const MISTLANDS_RADIUS := 3000.0   # End-game biome

# Height thresholds
const OCEAN_LEVEL := -15.0
const BEACH_LEVEL := -5.0
const LOWLAND_LEVEL := 0.0
const HIGHLAND_LEVEL := 30.0
const MOUNTAIN_LEVEL := 50.0

# Terrain parameters per biome
var biome_heights := {
	"meadows": {"base": 5.0, "amplitude": 10.0, "roughness": 0.3},
	"forest": {"base": 8.0, "amplitude": 15.0, "roughness": 0.4},
	"swamp": {"base": -2.0, "amplitude": 5.0, "roughness": 0.2},
	"mountain": {"base": 40.0, "amplitude": 30.0, "roughness": 0.6},
	"plains": {"base": 3.0, "amplitude": 8.0, "roughness": 0.25},
	"mistlands": {"base": 15.0, "amplitude": 20.0, "roughness": 0.5}
}

func _init() -> void:
	# Main terrain noise
	noise = FastNoiseLite.new()
	noise.seed = 42
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.003
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5

	# Detail noise for roughness
	detail_noise = FastNoiseLite.new()
	detail_noise.seed = 43
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.02
	detail_noise.fractal_octaves = 3

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

			# Determine biome based on distance from origin
			var distance_from_origin := sqrt(world_x * world_x + world_z * world_z)
			var biome := _get_biome_at_distance(distance_from_origin)
			var biome_params: Dictionary = biome_heights[biome]

			# Get base height from noise
			var noise_value := noise.get_noise_2d(world_x, world_z)
			var detail_value := detail_noise.get_noise_2d(world_x, world_z)

			# Calculate terrain height based on biome
			var base_height: float = biome_params["base"]
			var amplitude: float = biome_params["amplitude"]
			var roughness: float = biome_params["roughness"]

			var height := base_height + (noise_value * amplitude) + (detail_value * amplitude * roughness)

			# Generate Y column
			for y in buffer_size.y:
				var world_y := origin_in_voxels.y + (y << lod)

				# SDF: negative = solid, positive = air
				var sdf := float(world_y) - height

				# Clamp SDF for performance
				sdf = clamp(sdf, -50.0, 50.0)

				out_buffer.set_voxel_f(sdf, x, y, z, CHANNEL)

func _get_biome_at_distance(distance: float) -> String:
	"""Determine biome based on distance from origin (Valheim-style)"""
	if distance < MEADOWS_RADIUS:
		return "meadows"
	elif distance < FOREST_RADIUS:
		return "forest"
	elif distance < SWAMP_RADIUS:
		return "swamp"
	elif distance < MOUNTAIN_RADIUS:
		return "mountain"
	elif distance < PLAINS_RADIUS:
		return "plains"
	else:
		return "mistlands"

## Public API for external queries
func get_biome_at_position(xz_pos: Vector2) -> String:
	var distance := xz_pos.length()
	return _get_biome_at_distance(distance)

func get_height_at_position(xz_pos: Vector2) -> float:
	var distance := xz_pos.length()
	var biome := _get_biome_at_distance(distance)
	var biome_params: Dictionary = biome_heights[biome]

	var noise_value := noise.get_noise_2d(xz_pos.x, xz_pos.y)
	var detail_value := detail_noise.get_noise_2d(xz_pos.x, xz_pos.y)

	var base_height: float = biome_params["base"]
	var amplitude: float = biome_params["amplitude"]
	var roughness: float = biome_params["roughness"]

	return base_height + (noise_value * amplitude) + (detail_value * amplitude * roughness)

class_name WorldMapGenerator
extends RefCounted

## WorldMapGenerator - Generates map data from BiomeGenerator
## This samples the world's terrain at any scale to create map representations

const BiomeGenerator = preload("res://shared/biome_generator.gd")

# Biome colors for map rendering (matches terrain shader grass colors exactly)
const BIOME_BASE_COLORS := {
	"valley": Color(0.2, 0.5, 1.0),      # BRIGHT BLUE (serene valley)
	"forest": Color(0.1, 0.9, 0.1),      # BRIGHT GREEN (lush forest)
	"swamp": Color(0.5, 0.6, 0.2),       # YELLOW-GREEN (murky swamp)
	"mountain": Color(0.8, 0.8, 0.8),    # WHITE (snow/ice)
	"desert": Color(1.0, 0.9, 0.3),      # BRIGHT YELLOW (sandy desert)
	"wizardland": Color(0.9, 0.2, 1.0),  # BRIGHT MAGENTA (magical)
	"hell": Color(0.9, 0.1, 0.0)         # BRIGHT RED (hellfire)
}

var biome_generator: BiomeGenerator = null
var cached_map_data: Dictionary = {}  # Cache for different scales/regions

func _init(generator: BiomeGenerator) -> void:
	biome_generator = generator
	print("[WorldMapGenerator] Initialized with BiomeGenerator")

## Generate map texture for a given world region
## center: Center position in world coordinates (Vector2 XZ)
## size: Size of the map area in world units
## resolution: Size of the output image in pixels
func generate_map_texture(center: Vector2, world_size: float, resolution: int) -> ImageTexture:
	# Create image
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGB8)

	# Calculate world units per pixel
	var units_per_pixel := world_size / float(resolution)

	# Calculate starting corner
	var start_x := center.x - (world_size * 0.5)
	var start_z := center.y - (world_size * 0.5)

	# Sample terrain data and render to image
	for py in resolution:
		for px in resolution:
			# World position for this pixel
			var world_x := start_x + (px * units_per_pixel)
			var world_z := start_z + (py * units_per_pixel)
			var world_pos := Vector2(world_x, world_z)

			# Get terrain data
			var biome := biome_generator.get_biome_at_position(world_pos)
			var height := biome_generator.get_height_at_position(world_pos)

			# Get base color for biome
			var base_color: Color = BIOME_BASE_COLORS.get(biome, Color.GRAY)

			# Apply height-based shading (hybrid style)
			# Normalize height to roughly 0-1 range (typical terrain is -20 to 80)
			var height_normalized: float = clamp((height + 20.0) / 100.0, 0.0, 1.0)

			# Darken/lighten based on height
			var height_modifier: float = lerp(0.6, 1.4, height_normalized)
			var final_color: Color = base_color * height_modifier

			# Set pixel
			image.set_pixel(px, py, final_color)

	# Create texture from image
	return ImageTexture.create_from_image(image)

## Generate a higher detail map for a specific region
## Useful for zoomed-in views
func generate_detailed_map(center: Vector2, world_size: float, resolution: int = 512) -> ImageTexture:
	return generate_map_texture(center, world_size, resolution)

## Get the biome and height at a specific world position (for tooltips, etc.)
func get_terrain_info_at(world_pos: Vector2) -> Dictionary:
	if not biome_generator:
		return {}

	return {
		"biome": biome_generator.get_biome_at_position(world_pos),
		"height": biome_generator.get_height_at_position(world_pos)
	}

## Pre-generate map data for faster rendering
## This can run in the background
func pregenerate_world_map(max_radius: float, resolution: int = 1024) -> ImageTexture:
	print("[WorldMapGenerator] Pre-generating full world map (radius: %.0f, resolution: %d)" % [max_radius, resolution])

	# Generate centered at origin
	var texture := generate_map_texture(Vector2.ZERO, max_radius * 2.0, resolution)

	print("[WorldMapGenerator] Full world map pre-generated")
	return texture

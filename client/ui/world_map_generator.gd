class_name WorldMapGenerator
extends RefCounted

## WorldMapGenerator - Generates map data using procedural biome calculation
## Uses the same noise algorithm as TerrainBiomeGenerator for perfect alignment
## Works everywhere in the infinite world - no texture boundaries

# Biome colors for map rendering (MUST match terrain_material.gdshader EXACTLY)
const BIOME_BASE_COLORS := {
	"valley": Color(0.25, 0.55, 0.95),    # BRIGHT BLUE (serene meadows)
	"forest": Color(0.15, 0.85, 0.2),     # BRIGHT GREEN (lush forest)
	"swamp": Color(0.6, 0.75, 0.3),       # YELLOW-GREEN (murky swamp)
	"mountain": Color(0.95, 0.97, 1.0),   # WHITE (snow/ice)
	"desert": Color(0.95, 0.85, 0.35),    # BRIGHT YELLOW (sandy desert)
	"wizardland": Color(0.9, 0.3, 1.0),   # BRIGHT MAGENTA (magical)
	"hell": Color(0.9, 0.2, 0.1)          # BRIGHT RED (hellfire)
}

var biome_generator = null  # BiomeGenerator or TerrainBiomeGenerator instance
var cached_map_data: Dictionary = {}  # Cache for different scales/regions

func _init(generator) -> void:
	biome_generator = generator
	print("[WorldMapGenerator] Initialized with BiomeGenerator (procedural mode)")

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

			# Get biome color using procedural calculation (matches shader exactly)
			var biome: String = biome_generator.get_biome_at_position(world_pos)
			var height: float = biome_generator.get_height_at_position(world_pos)
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

class_name TerrainBiomeTexture
extends RefCounted

## TerrainBiomeTexture - Handles dynamic biome texture generation for shader

var terrain_world: Node3D

# Dynamic biome texture system (follows player for shader alignment)
var biome_texture: ImageTexture = null
var biome_texture_center: Vector2 = Vector2.ZERO
var biome_texture_last_update_pos: Vector2 = Vector2.ZERO
const BIOME_TEXTURE_SIZE: int = 256  # Resolution of the texture
const BIOME_TEXTURE_WORLD_SIZE: float = 512.0  # World units covered by texture
const BIOME_TEXTURE_UPDATE_THRESHOLD: float = 64.0  # Regenerate when player moves this far

func _init(tw: Node3D) -> void:
	terrain_world = tw

# =============================================================================
# BIOME TEXTURE GENERATION
# =============================================================================

## Generate biome texture centered at a world position
## Stores blend information: R=primary biome, G=secondary biome, B=blend weight
func generate_biome_texture(center: Vector2) -> void:
	if not terrain_world.biome_generator:
		return

	# Create image to store biome blend info (RGB format)
	var image := Image.create(BIOME_TEXTURE_SIZE, BIOME_TEXTURE_SIZE, false, Image.FORMAT_RGB8)

	# Calculate world units per pixel
	var units_per_pixel := BIOME_TEXTURE_WORLD_SIZE / float(BIOME_TEXTURE_SIZE)

	# Calculate starting corner
	var start_x := center.x - (BIOME_TEXTURE_WORLD_SIZE * 0.5)
	var start_z := center.y - (BIOME_TEXTURE_WORLD_SIZE * 0.5)

	# Sample biome at each pixel
	for py in BIOME_TEXTURE_SIZE:
		for px in BIOME_TEXTURE_SIZE:
			var world_x := start_x + (px * units_per_pixel)
			var world_z := start_z + (py * units_per_pixel)
			var world_pos := Vector2(world_x, world_z)

			# Get blend weights for smooth transitions
			var blend_weights: Array = terrain_world.biome_generator._get_biome_blend_weights(world_pos)

			# Extract primary and secondary biome with blend weight
			var primary_idx: int = 0
			var secondary_idx: int = 0
			var blend_weight: float = 0.0

			if blend_weights.size() >= 1 and blend_weights[0] is Array and blend_weights[0].size() >= 2:
				primary_idx = blend_weights[0][0]
			if blend_weights.size() >= 2 and blend_weights[1] is Array and blend_weights[1].size() >= 2:
				secondary_idx = blend_weights[1][0]
				blend_weight = blend_weights[1][1]  # Weight of secondary biome

			# Store in RGB: R=primary (0-6 -> 0-0.857), G=secondary, B=blend weight
			var r := float(primary_idx) / 7.0
			var g := float(secondary_idx) / 7.0
			var b := blend_weight
			image.set_pixel(px, py, Color(r, g, b, 1.0))

	# Create or update texture
	if biome_texture == null:
		biome_texture = ImageTexture.create_from_image(image)
	else:
		biome_texture.update(image)

	biome_texture_center = center
	biome_texture_last_update_pos = center

	# Update shader parameters
	if terrain_world.terrain_material is ShaderMaterial:
		var shader_mat: ShaderMaterial = terrain_world.terrain_material as ShaderMaterial
		shader_mat.set_shader_parameter("biome_texture", biome_texture)
		shader_mat.set_shader_parameter("biome_texture_center", biome_texture_center)

## Update biome texture if player has moved far enough
func update_for_player(player_pos: Vector3) -> void:
	if terrain_world.is_server:
		return  # Only client needs biome texture for rendering

	var player_xz := Vector2(player_pos.x, player_pos.z)
	var distance_moved := player_xz.distance_to(biome_texture_last_update_pos)

	# Regenerate texture if player moved far enough
	if biome_texture == null or distance_moved > BIOME_TEXTURE_UPDATE_THRESHOLD:
		generate_biome_texture(player_xz)

## Convert biome name to index (must match shader)
func biome_name_to_index(biome_name: String) -> int:
	match biome_name:
		"valley": return 0
		"forest": return 1
		"swamp": return 2
		"mountain": return 3
		"desert": return 4
		"wizardland": return 5
		"hell": return 6
		_: return 0

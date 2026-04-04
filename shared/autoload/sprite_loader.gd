extends Node

## SpriteLoader - Loads character sprites from disk and caches them
##
## Supports 36-angle sprites at res://assets/sprites/characters/{name}/angle_000.png through angle_350.png
## Also supports legacy 4-direction sprites for backward compatibility.

const SPRITE_BASE_PATH = "res://assets/sprites/characters/"

# 360-degree sprite system
var sprite_cache: Dictionary = {}
var angle_count: int = 36
var angle_step: float = 10.0  # degrees per frame

# Legacy 4-direction cache (deprecated)
const DIRECTIONS = ["front", "back", "left", "right"]
var _cache: Dictionary = {}

## Check if a character has 36-angle sprites available on disk
func has_character(character_name: String) -> bool:
	var path = SPRITE_BASE_PATH + character_name + "/angle_000.png"
	return ResourceLoader.exists(path)

## Check if a character has legacy 4-direction sprites
func has_character_4dir(character_name: String) -> bool:
	var path = SPRITE_BASE_PATH + character_name + "/front.png"
	return ResourceLoader.exists(path)

## Load all 36 angle PNGs for a character, with caching.
## Returns array of 36 Texture2D, index 0 = 0 degrees, index 1 = 10 degrees, etc.
## Returns an empty array if no sprites exist.
func load_character_angles(character_name: String) -> Array:
	if sprite_cache.has(character_name):
		return sprite_cache[character_name]

	if not has_character(character_name):
		return []

	var textures: Array = []
	for i in range(angle_count):
		var angle_deg = i * int(angle_step)
		var path = "res://assets/sprites/characters/%s/angle_%03d.png" % [character_name, angle_deg]
		var tex = load(path)
		textures.append(tex)

	if textures.size() == 36 and textures[0] != null:
		sprite_cache[character_name] = textures

	return textures

## Get the closest texture for a given angle in degrees.
func get_texture_for_angle(character_name: String, angle_degrees: float) -> Texture2D:
	var textures = load_character_angles(character_name)
	if textures.is_empty():
		return null
	# Normalize angle to 0-360
	var normalized = fmod(angle_degrees, 360.0)
	if normalized < 0:
		normalized += 360.0
	var index = int(round(normalized / angle_step)) % angle_count
	return textures[index]

## DEPRECATED: Load legacy 4-direction sprites for a character.
## Use load_character_angles() instead for 36-angle support.
func load_character_sprites(character_name: String) -> Dictionary:
	if _cache.has(character_name):
		return _cache[character_name]

	if not has_character_4dir(character_name):
		return {}

	var sprites: Dictionary = {}
	for dir in DIRECTIONS:
		var path = SPRITE_BASE_PATH + character_name + "/" + dir + ".png"
		if ResourceLoader.exists(path):
			sprites[dir] = load(path) as Texture2D
		else:
			sprites[dir] = null

	_cache[character_name] = sprites
	return sprites

extends Node

## SpriteLoader - Loads aalib character sprites from disk and caches them
##
## Sprites are expected at res://assets/sprites/characters/{name}/{front,back,left,right}.png
## Returns dictionaries with Texture2D values for each direction.

const DIRECTIONS = ["front", "back", "left", "right"]
const SPRITE_BASE_PATH = "res://assets/sprites/characters/"

# Cache: character_name -> {"front": Texture2D, "back": ..., "left": ..., "right": ...}
var _cache: Dictionary = {}

## Check if a character has any sprites available on disk
func has_character(character_name: String) -> bool:
	var path = SPRITE_BASE_PATH + character_name + "/front.png"
	return ResourceLoader.exists(path)

## Load all 4 directional sprites for a character, with caching.
## Returns {"front": Texture2D or null, "back": ..., "left": ..., "right": ...}
## Returns an empty dictionary if no sprites exist at all.
func load_character_sprites(character_name: String) -> Dictionary:
	if _cache.has(character_name):
		return _cache[character_name]

	if not has_character(character_name):
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

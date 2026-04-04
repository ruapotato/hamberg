extends "res://shared/animals/passive_animal.gd"

## Deer - Graceful forest creature
## Found in meadow and dark_forest biomes
## Drops raw venison when killed

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with deer-specific values
	enemy_name = "Deer"
	max_health = 25.0
	move_speed = 4.0  # Deer are fast
	strafe_speed = 3.0
	loot_table = {"raw_venison": 2, "deer_leather": 2}

	# Deer are skittish - flee when players get close
	is_skittish = true
	flee_detection_range = 12.0  # Deer are very alert

	print("[Deer] Deer ready (network_id=%d)" % network_id)

## Build deer body - 2D billboard sprite (Paper Mario style)
func _setup_body() -> void:
	# Check if BodyContainer already exists in the scene (from TSCN)
	var existing_container = get_node_or_null("BodyContainer")
	if existing_container and existing_container.get_child_count() > 0:
		body_container = existing_container
		head_base_height = 0.85 * 0.9
		print("[Deer] Using custom mesh from TSCN")
		return

	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	var sprite = DirectionalSpriteScript.new()
	sprite.name = "BodySprite"
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Try aalib sprites first, fall back to procedural
	var aalib = SpriteLoader.load_character_sprites("deer")
	if aalib.size() > 0 and aalib.get("front") != null:
		sprite.pixel_size = 0.0025  # 672px * 0.0025 = ~1.68 units tall
		sprite.texture = aalib.get("left", aalib["front"])
		sprite.set_textures_4dir(
			aalib["front"],
			aalib["back"],
			aalib.get("left", aalib["front"]),
			aalib.get("right", aalib["front"])
		)
	else:
		sprite.pixel_size = 0.025
		var tex_side = TextureGenerator.generate_deer_texture("side")
		var tex_front = TextureGenerator.generate_deer_texture("front")
		var tex_back = TextureGenerator.generate_deer_texture("back")
		sprite.texture = tex_side
		sprite.set_textures_4dir(tex_front, tex_back, tex_side, tex_side)

	# Position sprite so bottom is at ground level
	var sprite_height = sprite.texture.get_height() if sprite.texture else 32
	sprite.position.y = sprite_height * sprite.pixel_size * 0.5
	body_container.add_child(sprite)

	head_base_height = 0.85 * 0.9

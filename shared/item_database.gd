extends Node

## ItemDatabase - Central registry of all items in the game
## Autoload singleton that stores item definitions

# Preload item classes
const ItemData = preload("res://shared/item_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")
const FoodData = preload("res://shared/food_data.gd")
const ArmorData = preload("res://shared/armor_data.gd")

var items: Dictionary = {}  # item_id -> ItemData

func _ready() -> void:
	_initialize_items()
	print("[ItemDatabase] Initialized with %d items" % items.size())

func _initialize_items() -> void:
	# Resources
	_register_resource("wood", "Wood", "Basic building material from trees.", 50, 1.0)
	_register_resource("stone", "Stone", "Heavy building material from rocks.", 50, 2.0)
	_register_resource("earth", "Earth", "Dirt and soil dug from the ground. Can be placed to build up terrain.", 50, 2.0)
	_register_resource("resin", "Resin", "Sticky substance from trees. Used for torches and fire.", 50, 0.5)
	_register_resource("iron", "Iron", "Strong metal ore.", 50, 3.0)
	_register_resource("copper", "Copper", "Reddish metal ore.", 50, 2.5)

	# Raw meat (from passive animals)
	_register_resource("raw_venison", "Raw Venison", "Raw deer meat. Cook it to eat safely.", 20, 1.5)
	_register_resource("raw_pork", "Raw Pork", "Raw pig meat. Cook it to eat safely.", 20, 2.0)
	_register_resource("raw_mutton", "Raw Mutton", "Raw sheep meat. Cook it to eat safely.", 20, 1.8)

	# Cooking byproducts
	_register_resource("charcoal", "Charcoal", "Burned remains of food. Can be used as fuel.", 50, 0.3)

	# Enemy drops
	_register_resource("bone", "Bone", "A sturdy bone dropped by zombies. Useful for crafting.", 50, 1.0)
	_register_resource("rotten_flesh", "Rotten Flesh", "Decaying flesh from zombies. Unpleasant but useful.", 50, 0.5)

	# Biome 2 drops
	_register_resource("glowing_spore", "Glowing Spore", "A luminescent spore from the dark forest. Has healing properties.", 50, 0.2)
	_register_resource("fungal_essence", "Fungal Essence", "Concentrated fungal extract. Invigorating when prepared.", 50, 0.3)

	# Leather (from animals - for crafting armor)
	_register_resource("pig_leather", "Pig Leather", "Soft pink leather from flying pigs. Light and bouncy.", 30, 1.0)
	_register_resource("deer_leather", "Deer Leather", "Supple tan leather from deer. Surprisingly light.", 30, 0.8)

	# Crafted resources
	_register_resource("plant_fiber", "Plant Fiber", "Fibrous plant material gathered from bushes. Used for rope and bandages.", 50, 0.2)
	_register_resource("rope", "Rope", "A length of rope made from plant fiber. Useful for building and crafting.", 50, 0.5)
	_register_resource("arrows", "Arrows", "Wooden arrows tipped with stone. Ammunition for bows.", 50, 0.1)

	# Valley biome foods (edible raw with small buffs, cook for better)
	_register_food("pinkberry", "Pinkberry", "A small bright pink berry found in valley bushes. Eat raw for a small HP boost.", 20, 0.1, 10.0, 5.0, 0.0, 300.0, 0.5)
	_register_food("rootbeer", "Rootbeer", "A hearty brown root from the valley. Eat raw or brew into a drink.", 20, 0.3, 15.0, 10.0, 0.0, 300.0, 0.5)
	_register_resource("rootbeer_seed", "Rootbeer Seed", "A plantable seed that grows into rootbeer plants.", 50, 0.05)

	# Dark Forest biome foods
	_register_food("dark_mushroom", "Shadow Mushroom", "A dark mushroom from the forest depths. Slightly poisonous but boosts brain power.", 20, 0.2, -5.0, 0.0, 15.0, 180.0, 0.0)
	_register_resource("nightshade_berry", "Nightshade Berry", "A poisonous berry. Dangerous raw but useful in potions.", 20, 0.1)
	_register_food("truffle", "Truffle", "A rare and valuable mushroom found underground. Prized delicacy.", 20, 0.3, 10.0, 10.0, 10.0, 300.0, 0.5)
	_register_resource("fungal_seed", "Fungal Spore Seed", "A plantable spore that grows into mushrooms.", 50, 0.05)

	# Swamp biome foods
	_register_food("swamp_root", "Bog Root", "A tough root pulled from the swamp. Eat raw for stamina.", 20, 0.4, 5.0, 20.0, 0.0, 300.0, 0.3)
	_register_resource("marsh_herb", "Marsh Herb", "A healing herb that thrives in wetlands. Useful in potions.", 20, 0.2)
	_register_resource("lotus_seed", "Lotus Seed", "A plantable seed from the swamp lotus.", 50, 0.05)

	# Mountain biome foods
	_register_food("frost_berry", "Frost Berry", "An icy blue berry from the mountains. Grants cold resistance.", 20, 0.1, 10.0, 5.0, 5.0, 300.0, 0.5)
	_register_resource("alpine_herb", "Alpine Herb", "A potent healing herb from high altitudes.", 20, 0.2)
	_register_resource("ice_crystal_seed", "Ice Crystal Seed", "A plantable crystalline seed from the mountains.", 50, 0.1)

	# Desert biome foods
	_register_food("prickly_fruit", "Prickly Fruit", "A juicy fruit from desert cacti. Restores stamina.", 20, 0.3, 5.0, 20.0, 0.0, 300.0, 0.3)
	_register_resource("desert_sage", "Desert Sage", "A fragrant desert herb. Boosts brain power.", 20, 0.2)
	_register_resource("sun_seed", "Sun Seed", "A heat-resistant plantable seed from the desert.", 50, 0.05)

	# Wizardland biome foods
	_register_food("mana_fruit", "Mana Fruit", "A glowing fruit saturated with magical energy. Large brain power boost.", 20, 0.3, 5.0, 5.0, 25.0, 300.0, 0.3)
	_register_resource("arcane_herb", "Arcane Herb", "A mystical herb used in spell crafting.", 20, 0.2)
	_register_resource("crystal_seed", "Crystal Seed", "A crystalline plantable seed infused with magic.", 50, 0.1)

	# Hell biome foods
	_register_food("ember_pepper", "Ember Pepper", "A fiery pepper from the underworld. Grants fire resistance and damage boost.", 20, 0.2, 10.0, 10.0, 5.0, 300.0, 0.5)
	_register_resource("brimstone_root", "Brimstone Root", "A sulfurous root from hellish terrain. Crafting ingredient.", 20, 0.3)
	_register_resource("ash_seed", "Ash Seed", "A heat-hardened plantable seed from the inferno.", 50, 0.05)

	# Cooked food (consumable)
	_register_food("cooked_venison", "Cooked Venison", "Hearty deer meat. Increases max health and regenerates HP over time.", 20, 1.5, 40.0, 20.0, 10.0, 900.0, 2.0)
	_register_food("cooked_pork", "Cooked Pork", "Savory pig meat. Increases max stamina and regenerates HP over time.", 20, 2.0, 20.0, 40.0, 10.0, 900.0, 1.5)
	_register_food("cooked_mutton", "Cooked Mutton", "Tender sheep meat. Balanced nutrition and regenerates HP over time.", 20, 1.8, 30.0, 30.0, 20.0, 900.0, 1.8)

	# Cooked biome foods
	_register_food("cooked_rootbeer", "Rootbeer Brew", "A warm rootbeer brew. Boosts health and stamina.", 20, 0.3, 25.0, 15.0, 5.0, 600.0, 1.5)
	_register_food("cooked_truffle", "Cooked Truffle", "A seared truffle. Excellent balanced nutrition.", 20, 0.3, 35.0, 25.0, 25.0, 900.0, 2.0)
	_register_food("cooked_frost_berry", "Cooked Frost Berry", "Frost berries warmed into a jam. Cold resistance and health.", 20, 0.1, 20.0, 10.0, 15.0, 600.0, 1.5)
	_register_food("cooked_prickly_fruit", "Cooked Prickly Fruit", "Roasted cactus fruit. Great stamina food.", 20, 0.3, 15.0, 35.0, 5.0, 600.0, 1.0)
	_register_food("cooked_mana_fruit", "Cooked Mana Fruit", "Simmered mana fruit. Massive brain power boost.", 20, 0.3, 15.0, 10.0, 45.0, 900.0, 1.5)
	_register_food("cooked_ember_pepper", "Cooked Ember Pepper", "A roasted ember pepper. Fire resistance and damage boost.", 20, 0.2, 20.0, 15.0, 10.0, 600.0, 1.5)

	# Potions (consumable)
	_register_food("healing_potion", "Healing Potion", "A restorative potion brewed from glowing spores. Quickly restores health.", 10, 0.5, 50.0, 0.0, 0.0, 30.0, 12.0)
	_register_food("stamina_potion", "Stamina Potion", "An energizing potion brewed from fungal essence. Quickly restores stamina.", 10, 0.5, 0.0, 50.0, 0.0, 30.0, 0.0)
	_register_food("bandage", "Bandage", "A simple bandage made from plant fiber. Heals 5 HP/sec for 10 seconds. Does not use a food slot.", 20, 0.2, 0.0, 0.0, 0.0, 10.0, 5.0)

	# Biome potions
	_register_food("antidote_potion", "Antidote Potion", "Cures poison and restores health. Brewed from marsh herbs.", 10, 0.5, 30.0, 0.0, 0.0, 30.0, 8.0)
	_register_food("mana_potion", "Mana Potion", "A powerful potion that restores brain power. Brewed from arcane herbs.", 10, 0.5, 0.0, 0.0, 60.0, 30.0, 0.0)
	_register_food("fire_resistance_potion", "Fire Resistance Potion", "Grants temporary fire resistance. Brewed from ember peppers.", 10, 0.5, 15.0, 15.0, 0.0, 120.0, 1.0)
	_register_food("frost_resistance_potion", "Frost Resistance Potion", "Grants temporary cold resistance. Brewed from frost berries.", 10, 0.5, 15.0, 15.0, 0.0, 120.0, 1.0)
	_register_food("speed_potion", "Speed Potion", "Greatly boosts stamina recovery. Brewed from desert sage.", 10, 0.5, 0.0, 60.0, 0.0, 60.0, 0.0)

	# Basic tools (no workbench required)
	_register_tool("hammer", "Hammer", "Used for building structures.", 1)
	_register_tool("torch", "Torch", "Provides light in dark places.", 20)

	# Advanced tools (workbench required)
	_register_tool("stone_pickaxe", "Stone Pickaxe", "Used for terrain modification. Left click: dig square, Middle click: place earth square (consumes earth from inventory).", 1)
	_register_tool("stone_hoe", "Stone Hoe", "Used for flattening terrain. Left/Right click: flatten 4x4 area (8m x 8m) to a perfect grid level at your standing height.", 1)

	# Tier 0: Unarmed
	_register_weapon_fists()

	# Basic weapons (no workbench required)
	_register_weapon_club()

	# Tier 1 Weapons - Wood & Stone
	_register_weapon_stone_sword()
	_register_weapon_stone_axe()
	_register_weapon_stone_knife()
	_register_weapon_fire_wand()
	_register_weapon_bow()

	# Tier 2 Weapons - Iron (workbench required)
	_register_weapon_iron_sword()
	_register_weapon_iron_axe()
	_register_weapon_iron_pickaxe()

	# Shields
	_register_shield_tower()
	_register_shield_round()
	_register_shield_buckler()

	# Armor sets
	_register_pig_armor_set()
	_register_deer_armor_set()
	_register_bone_armor_set()  # Mid-tier from zombie drops
	_register_tank_armor_set()  # Buy-only from Shnarken

	# Tier 1-2 Elemental Wands (workbench required)
	_register_lightning_wand()
	_register_arcane_wand()
	_register_nature_wand()
	_register_dark_wand()
	_register_holy_wand()

	# Buy-only weapons
	_register_ice_wand()  # Buy-only from Shnarken

	# Boss items
	_register_glowing_medallion()  # Triggers Cyclops boss fight
	_register_cyclops_eye()  # Drops from Cyclops, provides light

## Helper: Register a basic resource item
func _register_resource(id: String, name: String, desc: String, stack: int, w: float) -> void:
	var item = ItemData.new()
	item.item_id = id
	item.display_name = name
	item.description = desc
	item.item_type = ItemData.ItemType.RESOURCE
	item.max_stack_size = stack
	item.weight = w
	items[id] = item

## Helper: Register a tool item
func _register_tool(id: String, name: String, desc: String, stack: int) -> void:
	var item = ItemData.new()
	item.item_id = id
	item.display_name = name
	item.description = desc
	item.item_type = ItemData.ItemType.TOOL
	item.max_stack_size = stack
	item.weight = 2.0
	items[id] = item

## Helper: Register a food item (consumable with stat bonuses)
func _register_food(id: String, name: String, desc: String, stack: int, w: float, health: float, stamina: float, bp: float, duration: float, regen: float = 1.0) -> void:
	var food = FoodData.new()
	food.item_id = id
	food.display_name = name
	food.description = desc
	food.max_stack_size = stack
	food.weight = w
	food.health_bonus = health
	food.stamina_bonus = stamina
	food.bp_bonus = bp
	food.duration = duration
	food.heal_per_second = regen
	items[id] = food

## Tier 0: Unarmed
func _register_weapon_fists() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "fists"
	weapon.display_name = "Fists"
	weapon.description = "Your bare hands. Low damage, no cost."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	weapon.damage = 5.0
	weapon.damage_type = WeaponData.DamageType.BLUNT
	weapon.attack_speed = 2.0  # Fast punches
	weapon.knockback = 5.0  # Moderate knockback
	weapon.durability = 999999  # Infinite durability
	weapon.stamina_cost = 3.0  # Very low stamina cost
	weapon.parry_window = 0.15  # Short parry window for fists (skilled timing required)
	weapon.tool_type = "blunt"  # Can break small things, but not chop trees
	weapon.weight = 0.0
	weapon.weapon_scene = load("res://shared/weapons/fists.tscn")  # Invisible but has hitbox
	items["fists"] = weapon

	# Sporeling tendrils - Dark Forest enemies hit HARD (biome 2)
	# Players need biome 1 armor before venturing into the dark forest
	var sporeling = WeaponData.new()
	sporeling.item_id = "sporeling_fists"
	sporeling.display_name = "Sporeling Tendrils"
	sporeling.description = "Powerful fungal tendrils."
	sporeling.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	sporeling.damage = 52.0  # Biome 2 - will wreck unarmored players (50% increase)
	sporeling.damage_type = WeaponData.DamageType.BLUNT
	sporeling.attack_speed = 1.2
	sporeling.knockback = 8.0
	sporeling.durability = 999999
	sporeling.stamina_cost = 0.0
	sporeling.weight = 0.0
	items["sporeling_fists"] = sporeling

	# Zombie walker fists - Valley enemies, moderate damage
	var zombie_walker = WeaponData.new()
	zombie_walker.item_id = "zombie_walker_fists"
	zombie_walker.display_name = "Zombie Claws"
	zombie_walker.description = "Rotting undead claws."
	zombie_walker.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	zombie_walker.damage = 10.0
	zombie_walker.damage_type = WeaponData.DamageType.SLASH
	zombie_walker.attack_speed = 1.5
	zombie_walker.knockback = 5.0
	zombie_walker.durability = 999999
	zombie_walker.stamina_cost = 0.0
	zombie_walker.weight = 0.0
	items["zombie_walker_fists"] = zombie_walker

	# Zombie runner fists - fast but weaker
	var zombie_runner = WeaponData.new()
	zombie_runner.item_id = "zombie_runner_fists"
	zombie_runner.display_name = "Zombie Claws"
	zombie_runner.description = "Quick undead swipes."
	zombie_runner.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	zombie_runner.damage = 8.0
	zombie_runner.damage_type = WeaponData.DamageType.SLASH
	zombie_runner.attack_speed = 2.0
	zombie_runner.knockback = 4.0
	zombie_runner.durability = 999999
	zombie_runner.stamina_cost = 0.0
	zombie_runner.weight = 0.0
	items["zombie_runner_fists"] = zombie_runner

	# Zombie brute fists - Dark Forest, hits very hard
	var zombie_brute = WeaponData.new()
	zombie_brute.item_id = "zombie_brute_fists"
	zombie_brute.display_name = "Brute Slam"
	zombie_brute.description = "Massive undead fists."
	zombie_brute.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	zombie_brute.damage = 35.0
	zombie_brute.damage_type = WeaponData.DamageType.BLUNT
	zombie_brute.attack_speed = 1.0
	zombie_brute.knockback = 10.0
	zombie_brute.durability = 999999
	zombie_brute.stamina_cost = 0.0
	zombie_brute.weight = 0.0
	items["zombie_brute_fists"] = zombie_brute

	# Zombie mage fists - Dark Forest, magic-infused melee
	var zombie_mage = WeaponData.new()
	zombie_mage.item_id = "zombie_mage_zombie_fists"
	zombie_mage.display_name = "Necrotic Touch"
	zombie_mage.description = "Death-infused strikes."
	zombie_mage.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	zombie_mage.damage = 25.0
	zombie_mage.damage_type = WeaponData.DamageType.BLUNT
	zombie_mage.attack_speed = 1.2
	zombie_mage.knockback = 6.0
	zombie_mage.durability = 999999
	zombie_mage.stamina_cost = 0.0
	zombie_mage.weight = 0.0
	items["zombie_mage_zombie_fists"] = zombie_mage

	# Zombie exploder fists - kamikaze type
	var zombie_exploder = WeaponData.new()
	zombie_exploder.item_id = "zombie_exploder_fists"
	zombie_exploder.display_name = "Explosive Slam"
	zombie_exploder.description = "Volatile undead slam."
	zombie_exploder.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	zombie_exploder.damage = 30.0
	zombie_exploder.damage_type = WeaponData.DamageType.FIRE
	zombie_exploder.attack_speed = 1.0
	zombie_exploder.knockback = 12.0
	zombie_exploder.durability = 999999
	zombie_exploder.stamina_cost = 0.0
	zombie_exploder.weight = 0.0
	items["zombie_exploder_fists"] = zombie_exploder

## Basic club weapon (no workbench required)
func _register_weapon_club() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "club"
	weapon.display_name = "Wooden Club"
	weapon.description = "A simple wooden club. Basic blunt damage."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	weapon.damage = 10.0  # Slightly better than fists
	weapon.damage_type = WeaponData.DamageType.BLUNT
	weapon.attack_speed = 1.3  # Medium speed
	weapon.knockback = 8.0  # Good knockback
	weapon.durability = 80
	weapon.stamina_cost = 6.0
	weapon.tool_type = "blunt"  # Good for breaking things, can split logs
	weapon.weight = 2.5
	# Uses fists animation/no scene for now - simple club
	items["club"] = weapon

## Tier 1 Weapons
func _register_weapon_stone_sword() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "stone_sword"
	weapon.display_name = "Stone Sword"
	weapon.description = "A simple sword made of stone and wood. Balanced damage and speed."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	weapon.damage = 15.0
	weapon.damage_type = WeaponData.DamageType.SLASH
	weapon.attack_speed = 1.5  # 1.5 attacks per second (medium speed)
	weapon.knockback = 5.0
	weapon.durability = 100
	weapon.stamina_cost = 8.0
	weapon.weight = 3.0
	weapon.weapon_scene = load("res://shared/weapons/stone_sword.tscn")
	items["stone_sword"] = weapon

func _register_weapon_stone_axe() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "stone_axe"
	weapon.display_name = "Stone Axe (Head Smasher)"
	weapon.description = "A heavy two-handed axe. Slow but devastating. Required for chopping trees."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_TWO_HAND
	weapon.damage = 20.0  # Primary tree chopper - 2-3 hits for small tree
	weapon.damage_type = WeaponData.DamageType.SLASH
	weapon.attack_speed = 0.8  # Slower than sword
	weapon.knockback = 15.0  # High knockback
	weapon.durability = 120
	weapon.stamina_cost = 12.0  # Reasonable stamina for tree chopping
	weapon.tool_type = "axe"  # Can chop trees!
	weapon.weight = 6.0
	weapon.weapon_scene = load("res://shared/weapons/stone_axe.tscn")
	items["stone_axe"] = weapon

func _register_weapon_stone_knife() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "stone_knife"
	weapon.display_name = "Stone Knife"
	weapon.description = "A quick and light blade. Fast attacks, low damage."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	weapon.damage = 8.0  # Fast but lower damage
	weapon.damage_type = WeaponData.DamageType.PIERCE
	weapon.attack_speed = 2.5  # Very fast
	weapon.knockback = 2.0
	weapon.durability = 80
	weapon.stamina_cost = 4.0  # Very cheap per swing
	weapon.weight = 1.0
	weapon.weapon_scene = load("res://shared/weapons/stone_knife.tscn")
	items["stone_knife"] = weapon

func _register_weapon_fire_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "fire_wand"
	weapon.display_name = "Fire Wand"
	weapon.description = "A magical wand that shoots fireballs. Uses Brain Power (BP) instead of stamina."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 15.0
	weapon.damage_type = WeaponData.DamageType.FIRE
	weapon.attack_speed = 1.0
	weapon.knockback = 3.0
	weapon.durability = 60
	weapon.stamina_cost = 10.0  # For magic weapons, this is actually brain power cost
	weapon.spell_name = "fireball"  # Maps to SpellRegistry
	weapon.projectile_speed = 30.0
	weapon.weight = 1.5
	weapon.weapon_scene = load("res://shared/weapons/fire_wand.tscn")
	weapon.projectile_scene = load("res://shared/projectiles/fireball.tscn")
	items["fire_wand"] = weapon

func _register_weapon_bow() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "bow"
	weapon.display_name = "Hunting Bow"
	weapon.description = "A simple wooden bow. Physical ranged damage."
	weapon.weapon_type = WeaponData.WeaponType.RANGED
	weapon.damage = 12.0
	weapon.damage_type = WeaponData.DamageType.PIERCE
	weapon.attack_speed = 0.8
	weapon.knockback = 5.0
	weapon.durability = 100
	weapon.stamina_cost = 6.0
	weapon.projectile_speed = 40.0
	weapon.weight = 2.0
	weapon.weapon_scene = load("res://shared/weapons/bow.tscn")
	weapon.projectile_scene = load("res://shared/projectiles/arrow.tscn")
	items["bow"] = weapon

## Tier 2 Weapons - Iron
func _register_weapon_iron_sword() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "iron_sword"
	weapon.display_name = "Iron Sword"
	weapon.description = "A sturdy iron sword. Better damage than stone."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	weapon.damage = 25.0
	weapon.damage_type = WeaponData.DamageType.SLASH
	weapon.attack_speed = 1.5
	weapon.knockback = 6.0
	weapon.durability = 150
	weapon.stamina_cost = 10.0
	weapon.weight = 3.5
	weapon.weapon_scene = load("res://shared/weapons/iron_sword.tscn")
	items["iron_sword"] = weapon

func _register_weapon_iron_axe() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "iron_axe"
	weapon.display_name = "Iron Axe"
	weapon.description = "A heavy iron axe. Chops trees faster and hits harder."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_TWO_HAND
	weapon.damage = 30.0
	weapon.damage_type = WeaponData.DamageType.SLASH
	weapon.attack_speed = 0.9
	weapon.knockback = 16.0
	weapon.durability = 180
	weapon.stamina_cost = 14.0
	weapon.tool_type = "axe"
	weapon.weight = 6.5
	weapon.weapon_scene = load("res://shared/weapons/iron_axe.tscn")
	items["iron_axe"] = weapon

func _register_weapon_iron_pickaxe() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "iron_pickaxe"
	weapon.display_name = "Iron Pickaxe"
	weapon.description = "A sturdy iron pickaxe. Mines faster than stone."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	weapon.damage = 15.0
	weapon.damage_type = WeaponData.DamageType.PIERCE
	weapon.attack_speed = 1.0
	weapon.knockback = 3.0
	weapon.durability = 180
	weapon.stamina_cost = 7.0
	weapon.tool_type = "pickaxe"
	weapon.weight = 5.0
	weapon.weapon_scene = load("res://shared/weapons/iron_pickaxe.tscn")
	items["iron_pickaxe"] = weapon

## Shields
func _register_shield_tower() -> void:
	var shield = ShieldData.new()
	shield.item_id = "tower_shield"
	shield.display_name = "Tower Shield"
	shield.description = "A massive wooden shield. High block power, but no parry bonus."
	shield.shield_type = ShieldData.ShieldType.TOWER
	shield.block_armor = 30.0
	shield.parry_bonus = 1.0  # No parry bonus
	shield.parry_window = 0.0  # Can't parry
	shield.durability = 150
	shield.stamina_drain_per_hit = 8.0
	shield.weight = 8.0
	shield.shield_scene = load("res://shared/weapons/tower_shield.tscn")
	items["tower_shield"] = shield

func _register_shield_round() -> void:
	var shield = ShieldData.new()
	shield.item_id = "round_shield"
	shield.display_name = "Round Shield"
	shield.description = "A balanced wooden shield. Medium block power and parry bonus."
	shield.shield_type = ShieldData.ShieldType.ROUND
	shield.block_armor = 20.0
	shield.parry_bonus = 2.0  # 2x damage on parry
	shield.parry_window = 0.3
	shield.durability = 100
	shield.stamina_drain_per_hit = 5.0
	shield.weight = 4.0
	shield.shield_scene = load("res://shared/weapons/round_shield.tscn")
	items["round_shield"] = shield

func _register_shield_buckler() -> void:
	var shield = ShieldData.new()
	shield.item_id = "buckler"
	shield.display_name = "Buckler"
	shield.description = "A small wooden shield. Low block power, but high parry bonus."
	shield.shield_type = ShieldData.ShieldType.BUCKLER
	shield.block_armor = 10.0
	shield.parry_bonus = 3.0  # 3x damage on parry!
	shield.parry_window = 0.4  # Longer parry window
	shield.durability = 80
	shield.stamina_drain_per_hit = 3.0
	shield.weight = 2.0
	shield.shield_scene = load("res://shared/weapons/buckler.tscn")
	items["buckler"] = shield

## Get item by ID (returns ItemData or null)
func get_item(item_id: String):
	return items.get(item_id, null)

## Check if item exists
func has_item(item_id: String) -> bool:
	return items.has(item_id)

## Get all items of a specific type
func get_items_by_type(type) -> Array:  # type is ItemData.ItemType, returns Array of ItemData
	var result: Array = []
	for item in items.values():
		if item.item_type == type:
			result.append(item)
	return result

## Get max stack size for an item
func get_max_stack_size(item_id: String) -> int:
	var item = get_item(item_id)
	return item.max_stack_size if item else 1

## Get all items as an array
func get_all_items() -> Array:
	return items.values()

# =============================================================================
# ARMOR REGISTRATION
# =============================================================================

## Helper: Register an armor piece with per-damage-type armor values
func _register_armor(id: String, name: String, desc: String, slot: ArmorData.ArmorSlot, armor_vals: Dictionary, set_id: String, set_bonus: ArmorData.SetBonus, primary_color: Color, secondary_color: Color, weight: float = 2.0, speed_mod: float = 0.0) -> void:
	var armor = ArmorData.new()
	armor.item_id = id
	armor.display_name = name
	armor.description = desc
	armor.armor_slot = slot
	armor.armor_values = armor_vals
	armor.armor_set_id = set_id
	armor.set_bonus = set_bonus
	armor.primary_color = primary_color
	armor.secondary_color = secondary_color
	armor.weight = weight
	armor.durability = 100
	armor.speed_modifier = speed_mod
	items[id] = armor

## Pig Armor Set - Pink flying pig leather armor
## Set Bonus: Double Jump (can jump again while in the air)
## Total armor: ~6 per damage type (blocks 6 damage from a 10 damage hit)
func _register_pig_armor_set() -> void:
	# Pig colors - pink with white accents (like the flying pig's wings)
	var pig_pink = Color(0.95, 0.7, 0.75, 1.0)  # Soft pink
	var pig_white = Color(1.0, 0.95, 0.95, 1.0)  # Wing white

	# Pig leather is soft - good vs blunt, weak vs pierce/slash
	# Head: 1.0 armor avg
	_register_armor(
		"pig_helmet", "Pig Leather Hood",
		"A bouncy hood made from flying pig leather. Part of the Pig Set.\nFull Set Bonus: Double Jump",
		ArmorData.ArmorSlot.HEAD, {
			WeaponData.DamageType.SLASH: 0.5,
			WeaponData.DamageType.BLUNT: 2.0,
			WeaponData.DamageType.PIERCE: 0.5,
			WeaponData.DamageType.FIRE: 1.0,
			WeaponData.DamageType.ICE: 1.0,
			WeaponData.DamageType.POISON: 1.0,
		}, "pig", ArmorData.SetBonus.PIG_DOUBLE_JUMP,
		pig_pink, pig_white, 1.5
	)
	# Chest: 2.5 armor avg (main piece)
	_register_armor(
		"pig_chest", "Pig Leather Vest",
		"A light vest made from flying pig leather. Part of the Pig Set.\nFull Set Bonus: Double Jump",
		ArmorData.ArmorSlot.CHEST, {
			WeaponData.DamageType.SLASH: 1.5,
			WeaponData.DamageType.BLUNT: 4.0,
			WeaponData.DamageType.PIERCE: 1.5,
			WeaponData.DamageType.FIRE: 2.5,
			WeaponData.DamageType.ICE: 2.5,
			WeaponData.DamageType.POISON: 3.0,
		}, "pig", ArmorData.SetBonus.PIG_DOUBLE_JUMP,
		pig_pink, pig_white, 3.0
	)
	# Legs: 1.5 armor avg
	_register_armor(
		"pig_pants", "Pig Leather Pants",
		"Springy pants made from flying pig leather. Part of the Pig Set.\nFull Set Bonus: Double Jump",
		ArmorData.ArmorSlot.LEGS, {
			WeaponData.DamageType.SLASH: 1.0,
			WeaponData.DamageType.BLUNT: 2.5,
			WeaponData.DamageType.PIERCE: 1.0,
			WeaponData.DamageType.FIRE: 1.5,
			WeaponData.DamageType.ICE: 1.5,
			WeaponData.DamageType.POISON: 1.5,
		}, "pig", ArmorData.SetBonus.PIG_DOUBLE_JUMP,
		pig_pink, pig_white, 2.5
	)
	# Cape: 1.0 armor avg
	_register_armor(
		"pig_cape", "Pig Wing Cape",
		"A cape styled after the flying pig's wings. Part of the Pig Set.\nFull Set Bonus: Double Jump",
		ArmorData.ArmorSlot.CAPE, {
			WeaponData.DamageType.SLASH: 0.5,
			WeaponData.DamageType.BLUNT: 1.5,
			WeaponData.DamageType.PIERCE: 0.5,
			WeaponData.DamageType.FIRE: 1.0,
			WeaponData.DamageType.ICE: 1.0,
			WeaponData.DamageType.POISON: 1.0,
		}, "pig", ArmorData.SetBonus.PIG_DOUBLE_JUMP,
		pig_white, pig_pink, 1.0
	)
	# Full set totals:
	# Blunt: 10.0 (very good vs Gahnome fists)
	# Slash: 3.5
	# Pierce: 3.5
	# Fire/Ice: 6.0
	# Poison: 6.5

## Deer Armor Set - Tan/brown deer leather armor
## Set Bonus: Stamina Saver (50% less stamina for sprinting)
## Deer leather is tougher than pig - better balanced protection
func _register_deer_armor_set() -> void:
	# Deer colors - tan/brown like the deer's fur
	var deer_tan = Color(0.65, 0.5, 0.35, 1.0)  # Main fur color
	var deer_cream = Color(0.85, 0.75, 0.65, 1.0)  # Belly/lighter areas

	_register_armor(
		"deer_helmet", "Deer Leather Hood",
		"A lightweight hood made from deer leather. Part of the Deer Set.\nFull Set Bonus: 50% Sprint Stamina Reduction",
		ArmorData.ArmorSlot.HEAD, {
			WeaponData.DamageType.SLASH: 1.0,
			WeaponData.DamageType.BLUNT: 1.0,
			WeaponData.DamageType.PIERCE: 1.0,
			WeaponData.DamageType.FIRE: 0.5,
			WeaponData.DamageType.ICE: 1.5,
			WeaponData.DamageType.POISON: 1.0,
		}, "deer", ArmorData.SetBonus.DEER_STAMINA_SAVER,
		deer_tan, deer_cream, 1.0
	)
	_register_armor(
		"deer_chest", "Deer Leather Tunic",
		"A supple tunic made from deer leather. Part of the Deer Set.\nFull Set Bonus: 50% Sprint Stamina Reduction",
		ArmorData.ArmorSlot.CHEST, {
			WeaponData.DamageType.SLASH: 2.5,
			WeaponData.DamageType.BLUNT: 2.5,
			WeaponData.DamageType.PIERCE: 2.5,
			WeaponData.DamageType.FIRE: 1.5,
			WeaponData.DamageType.ICE: 3.0,
			WeaponData.DamageType.POISON: 2.0,
		}, "deer", ArmorData.SetBonus.DEER_STAMINA_SAVER,
		deer_tan, deer_cream, 2.0
	)
	_register_armor(
		"deer_pants", "Deer Leather Leggings",
		"Light leggings made from deer leather. Part of the Deer Set.\nFull Set Bonus: 50% Sprint Stamina Reduction",
		ArmorData.ArmorSlot.LEGS, {
			WeaponData.DamageType.SLASH: 1.5,
			WeaponData.DamageType.BLUNT: 1.5,
			WeaponData.DamageType.PIERCE: 1.5,
			WeaponData.DamageType.FIRE: 1.0,
			WeaponData.DamageType.ICE: 2.0,
			WeaponData.DamageType.POISON: 1.5,
		}, "deer", ArmorData.SetBonus.DEER_STAMINA_SAVER,
		deer_tan, deer_cream, 1.5
	)
	_register_armor(
		"deer_cape", "Deer Hide Cloak",
		"A flowing cloak made from deer hide. Part of the Deer Set.\nFull Set Bonus: 50% Sprint Stamina Reduction",
		ArmorData.ArmorSlot.CAPE, {
			WeaponData.DamageType.SLASH: 0.5,
			WeaponData.DamageType.BLUNT: 0.5,
			WeaponData.DamageType.PIERCE: 0.5,
			WeaponData.DamageType.FIRE: 0.5,
			WeaponData.DamageType.ICE: 1.0,
			WeaponData.DamageType.POISON: 0.5,
		}, "deer", ArmorData.SetBonus.DEER_STAMINA_SAVER,
		deer_cream, deer_tan, 0.8
	)
	# Full set totals:
	# Slash/Blunt/Pierce: 5.5 (balanced)
	# Fire: 3.5 (weak to fire)
	# Ice: 7.5 (good vs ice)
	# Poison: 5.0

## Bone Armor Set - Mid-tier armor from zombie bone and deer leather
## Set Bonus: +20% max health (Bone Toughness)
## Stronger than pig/deer but weaker than tank
func _register_bone_armor_set() -> void:
	var bone_white = Color(0.85, 0.82, 0.75, 1.0)  # Pale bone
	var bone_dark = Color(0.55, 0.5, 0.4, 1.0)  # Darker bone/leather

	_register_armor(
		"bone_armor_helmet", "Bone Helm",
		"A helmet crafted from zombie bones. Part of the Bone Set.\nFull Set Bonus: +20% Max Health",
		ArmorData.ArmorSlot.HEAD, {
			WeaponData.DamageType.SLASH: 2.0,
			WeaponData.DamageType.BLUNT: 1.5,
			WeaponData.DamageType.PIERCE: 2.0,
			WeaponData.DamageType.FIRE: 1.0,
			WeaponData.DamageType.ICE: 1.0,
			WeaponData.DamageType.POISON: 1.5,
		}, "bone", ArmorData.SetBonus.BONE_TOUGHNESS,
		bone_white, bone_dark, 2.0
	)
	_register_armor(
		"bone_armor_chest", "Bone Cuirass",
		"A chestpiece reinforced with zombie bones. Part of the Bone Set.\nFull Set Bonus: +20% Max Health",
		ArmorData.ArmorSlot.CHEST, {
			WeaponData.DamageType.SLASH: 4.0,
			WeaponData.DamageType.BLUNT: 3.0,
			WeaponData.DamageType.PIERCE: 4.0,
			WeaponData.DamageType.FIRE: 2.0,
			WeaponData.DamageType.ICE: 2.0,
			WeaponData.DamageType.POISON: 3.0,
		}, "bone", ArmorData.SetBonus.BONE_TOUGHNESS,
		bone_white, bone_dark, 3.5
	)
	_register_armor(
		"bone_armor_legs", "Bone Greaves",
		"Leg armor reinforced with zombie bones. Part of the Bone Set.\nFull Set Bonus: +20% Max Health",
		ArmorData.ArmorSlot.LEGS, {
			WeaponData.DamageType.SLASH: 3.0,
			WeaponData.DamageType.BLUNT: 2.0,
			WeaponData.DamageType.PIERCE: 3.0,
			WeaponData.DamageType.FIRE: 1.5,
			WeaponData.DamageType.ICE: 1.5,
			WeaponData.DamageType.POISON: 2.0,
		}, "bone", ArmorData.SetBonus.BONE_TOUGHNESS,
		bone_white, bone_dark, 2.5
	)
	_register_armor(
		"bone_armor_boots", "Bone Boots",
		"Boots reinforced with zombie bones. Part of the Bone Set.\nFull Set Bonus: +20% Max Health",
		ArmorData.ArmorSlot.CAPE, {
			WeaponData.DamageType.SLASH: 1.5,
			WeaponData.DamageType.BLUNT: 1.0,
			WeaponData.DamageType.PIERCE: 1.5,
			WeaponData.DamageType.FIRE: 0.5,
			WeaponData.DamageType.ICE: 0.5,
			WeaponData.DamageType.POISON: 1.0,
		}, "bone", ArmorData.SetBonus.BONE_TOUGHNESS,
		bone_dark, bone_white, 1.5
	)
	# Full set totals:
	# Slash: 10.5
	# Blunt: 7.5
	# Pierce: 10.5
	# Fire: 5.0
	# Ice: 5.0
	# Poison: 7.5

## Tank Armor Set - Heavy iron plate armor (BUY-ONLY from Shnarken)
## No set bonus, but VERY high armor values
## Trade-off: -5% movement speed per piece except helmet (15% total slow)
## Cannot be crafted - must be purchased from the Meadow Shnarken
func _register_tank_armor_set() -> void:
	# Tank colors - dark iron with bronze trim
	var tank_iron = Color(0.35, 0.35, 0.4, 1.0)  # Dark iron
	var tank_bronze = Color(0.7, 0.55, 0.35, 1.0)  # Bronze accents

	# Head: No speed penalty (still need to see!)
	_register_armor(
		"tank_helmet", "Iron Greathelm",
		"A heavy iron helmet with full face protection. Part of the Tank Set.\nNo movement penalty.\nBuy-only from Shnarken.",
		ArmorData.ArmorSlot.HEAD, {
			WeaponData.DamageType.SLASH: 4.0,
			WeaponData.DamageType.BLUNT: 4.0,
			WeaponData.DamageType.PIERCE: 4.0,
			WeaponData.DamageType.FIRE: 2.0,
			WeaponData.DamageType.ICE: 2.0,
			WeaponData.DamageType.POISON: 1.0,
		}, "tank", ArmorData.SetBonus.NONE,
		tank_iron, tank_bronze, 5.0, 0.0  # No speed penalty
	)
	# Chest: -5% speed
	_register_armor(
		"tank_chest", "Iron Cuirass",
		"A massive iron chestplate. Part of the Tank Set.\n-5% movement speed.\nBuy-only from Shnarken.",
		ArmorData.ArmorSlot.CHEST, {
			WeaponData.DamageType.SLASH: 8.0,
			WeaponData.DamageType.BLUNT: 8.0,
			WeaponData.DamageType.PIERCE: 8.0,
			WeaponData.DamageType.FIRE: 4.0,
			WeaponData.DamageType.ICE: 4.0,
			WeaponData.DamageType.POISON: 2.0,
		}, "tank", ArmorData.SetBonus.NONE,
		tank_iron, tank_bronze, 8.0, -0.05  # -5% speed
	)
	# Legs: -5% speed
	_register_armor(
		"tank_pants", "Iron Greaves",
		"Heavy iron leg armor. Part of the Tank Set.\n-5% movement speed.\nBuy-only from Shnarken.",
		ArmorData.ArmorSlot.LEGS, {
			WeaponData.DamageType.SLASH: 6.0,
			WeaponData.DamageType.BLUNT: 6.0,
			WeaponData.DamageType.PIERCE: 6.0,
			WeaponData.DamageType.FIRE: 3.0,
			WeaponData.DamageType.ICE: 3.0,
			WeaponData.DamageType.POISON: 1.5,
		}, "tank", ArmorData.SetBonus.NONE,
		tank_iron, tank_bronze, 6.0, -0.05  # -5% speed
	)
	# Cape: -5% speed (it's a heavy cloak of chainmail)
	_register_armor(
		"tank_cape", "Chainmail Mantle",
		"A heavy chainmail cloak. Part of the Tank Set.\n-5% movement speed.\nBuy-only from Shnarken.",
		ArmorData.ArmorSlot.CAPE, {
			WeaponData.DamageType.SLASH: 4.0,
			WeaponData.DamageType.BLUNT: 2.0,
			WeaponData.DamageType.PIERCE: 4.0,
			WeaponData.DamageType.FIRE: 2.0,
			WeaponData.DamageType.ICE: 2.0,
			WeaponData.DamageType.POISON: 1.0,
		}, "tank", ArmorData.SetBonus.NONE,
		tank_iron, tank_bronze, 4.0, -0.05  # -5% speed
	)
	# Full set totals:
	# Slash: 22.0 (VERY tanky)
	# Blunt: 20.0
	# Pierce: 22.0
	# Fire: 11.0
	# Ice: 11.0
	# Poison: 5.5
	# Speed penalty: -15% total (helmet has no penalty)

## Lightning Wand - Tier 2 lightning wand, chains between enemies
func _register_lightning_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "lightning_wand"
	weapon.display_name = "Lightning Wand"
	weapon.description = "A crackling wand that unleashes chain lightning. Uses Brain Power (BP).\nLightning arcs between nearby enemies."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 18.0  # Tier 2 - higher base damage
	weapon.damage_type = WeaponData.DamageType.LIGHTNING
	weapon.attack_speed = 0.8  # Slower but hits multiple targets
	weapon.knockback = 4.0
	weapon.durability = 50
	weapon.stamina_cost = 15.0  # Tier 2 BP cost
	weapon.spell_name = "chain_lightning"  # Maps to SpellRegistry
	weapon.projectile_speed = 60.0
	weapon.weight = 1.5
	weapon.weapon_scene = load("res://shared/weapons/lightning_wand.tscn")
	items["lightning_wand"] = weapon

## Arcane Wand - Tier 1 arcane wand, fires homing missiles
func _register_arcane_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "arcane_wand"
	weapon.display_name = "Arcane Wand"
	weapon.description = "A shimmering wand that fires homing magic missiles. Uses Brain Power (BP).\nMissiles track nearby enemies."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 10.0  # Tier 1 - lower per-hit but fires 3 missiles
	weapon.damage_type = WeaponData.DamageType.ARCANE
	weapon.attack_speed = 1.2
	weapon.knockback = 2.0
	weapon.durability = 60
	weapon.stamina_cost = 8.0  # Low BP cost for tier 1
	weapon.spell_name = "magic_missile"  # Maps to SpellRegistry
	weapon.projectile_speed = 45.0
	weapon.weight = 1.0
	weapon.weapon_scene = load("res://shared/weapons/arcane_wand.tscn")
	items["arcane_wand"] = weapon

## Nature Wand - Tier 2 nature wand, entangles enemies with vines
func _register_nature_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "nature_wand"
	weapon.display_name = "Nature Wand"
	weapon.description = "A living wand that summons grasping vines. Uses Brain Power (BP).\nRoots enemies in place and deals damage over time."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 8.0  # Lower direct damage, relies on DoT and crowd control
	weapon.damage_type = WeaponData.DamageType.NATURE
	weapon.attack_speed = 0.8
	weapon.knockback = 1.0
	weapon.durability = 70
	weapon.stamina_cost = 12.0
	weapon.spell_name = "vine_grasp"  # Maps to SpellRegistry
	weapon.weight = 1.5
	weapon.weapon_scene = load("res://shared/weapons/nature_wand.tscn")
	items["nature_wand"] = weapon

## Dark Wand - Tier 2 dark wand, drains life from enemies
func _register_dark_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "dark_wand"
	weapon.display_name = "Dark Wand"
	weapon.description = "A sinister wand that drains the souls of enemies. Uses Brain Power (BP).\nSteals life and mana from targets."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 14.0  # Tier 2 damage plus lifesteal
	weapon.damage_type = WeaponData.DamageType.DARK
	weapon.attack_speed = 1.0
	weapon.knockback = 2.0
	weapon.durability = 45  # Fragile, dark magic corrodes
	weapon.stamina_cost = 14.0  # Tier 2 BP cost
	weapon.spell_name = "soul_drain"  # Maps to SpellRegistry
	weapon.weight = 1.5
	weapon.weapon_scene = load("res://shared/weapons/dark_wand.tscn")
	items["dark_wand"] = weapon

## Holy Wand - Tier 2 holy wand, damages undead and heals allies
func _register_holy_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "holy_wand"
	weapon.display_name = "Holy Wand"
	weapon.description = "A radiant wand of divine light. Uses Brain Power (BP).\nDeals bonus damage to undead and heals nearby allies."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 12.0
	weapon.damage_type = WeaponData.DamageType.HOLY
	weapon.attack_speed = 0.9
	weapon.knockback = 3.0
	weapon.durability = 65
	weapon.stamina_cost = 14.0
	weapon.spell_name = "divine_light"  # Maps to SpellRegistry
	weapon.weight = 1.5
	weapon.weapon_scene = load("res://shared/weapons/holy_wand.tscn")
	items["holy_wand"] = weapon

## Ice Wand - Buy-only magic weapon from Shnarken
## Cannot be crafted - entry-level magic weapon for players who can't make fire wand
func _register_ice_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "ice_wand"
	weapon.display_name = "Frost Wand"
	weapon.description = "A wand that shoots piercing ice shards. Buy-only from Shnarken.\nDeals ice damage - slows enemies on hit."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 12.0
	weapon.damage_type = WeaponData.DamageType.ICE
	weapon.attack_speed = 1.5
	weapon.knockback = 3.0
	weapon.durability = 80
	weapon.stamina_cost = 10.0  # Uses brain power for magic
	weapon.spell_name = "ice_shard"  # Maps to SpellRegistry
	weapon.weight = 1.5
	weapon.weapon_scene = load("res://shared/weapons/ice_wand.tscn")
	items["ice_wand"] = weapon

## Glowing Medallion - Buy from Shnarken to summon the Cyclops boss
## This is a trap item that triggers a boss fight immediately on purchase!
func _register_glowing_medallion() -> void:
	var item = ItemData.new()
	item.item_id = "glowing_medallion"
	item.display_name = "Glowing Medallion"
	item.description = "A mysterious medallion that pulses with an eerie light...\n[color=red]WARNING: SEE IN THE DARK WITH THIS MEDALLION... BUY AT YOUR OWN RISK.[/color]"
	item.item_type = ItemData.ItemType.BOSS_SUMMON
	item.max_stack_size = 1
	item.weight = 0.5
	items["glowing_medallion"] = item

## Cyclops Eye - Drops from Cyclops boss, equip for light aura
## Provides permanent light around the player, useful for dark biomes
func _register_cyclops_eye() -> void:
	var accessory = ArmorData.new()
	accessory.item_id = "cyclops_eye"
	accessory.display_name = "Eye of the Cyclops"
	accessory.description = "The massive glowing eye of the fallen Cyclops.\nEquip to illuminate the darkness around you.\n[color=yellow]Unlocks access to dark biomes![/color]"
	accessory.armor_slot = ArmorData.ArmorSlot.ACCESSORY
	accessory.set_bonus = ArmorData.SetBonus.CYCLOPS_LIGHT
	accessory.armor_set_id = "cyclops"  # Unique set
	accessory.weight = 2.0
	accessory.durability = 9999  # Nearly unbreakable
	# No armor values - it's a utility item
	accessory.armor_values = {
		WeaponData.DamageType.SLASH: 0.0,
		WeaponData.DamageType.BLUNT: 0.0,
		WeaponData.DamageType.PIERCE: 0.0,
		WeaponData.DamageType.FIRE: 0.0,
		WeaponData.DamageType.ICE: 0.0,
		WeaponData.DamageType.POISON: 0.0,
	}
	accessory.primary_color = Color(1.0, 0.9, 0.3)  # Golden glow
	accessory.secondary_color = Color(1.0, 0.6, 0.1)  # Orange
	items["cyclops_eye"] = accessory

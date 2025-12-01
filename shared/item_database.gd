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

	# Leather (from animals - for crafting armor)
	_register_resource("pig_leather", "Pig Leather", "Soft pink leather from flying pigs. Light and bouncy.", 30, 1.0)
	_register_resource("deer_leather", "Deer Leather", "Supple tan leather from deer. Surprisingly light.", 30, 0.8)

	# Cooked food (consumable)
	_register_food("cooked_venison", "Cooked Venison", "Hearty deer meat. Increases max health and regenerates HP over time.", 20, 1.5, 25.0, 15.0, 10.0, 600.0, 1.5)
	_register_food("cooked_pork", "Cooked Pork", "Savory pig meat. Increases max stamina and regenerates HP over time.", 20, 2.0, 15.0, 25.0, 10.0, 600.0, 1.0)
	_register_food("cooked_mutton", "Cooked Mutton", "Tender sheep meat. Balanced nutrition and regenerates HP over time.", 20, 1.8, 20.0, 20.0, 15.0, 600.0, 1.2)

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

	# Shields
	_register_shield_tower()
	_register_shield_round()
	_register_shield_buckler()

	# Armor sets
	_register_pig_armor_set()
	_register_deer_armor_set()
	_register_tank_armor_set()  # Buy-only from Shnarken

	# Buy-only weapons
	_register_ice_wand()  # Buy-only from Shnarken

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
	weapon.damage = 10.0
	weapon.damage_type = WeaponData.DamageType.BLUNT
	weapon.attack_speed = 2.0  # Fast punches
	weapon.knockback = 5.0  # Moderate knockback
	weapon.durability = 999999  # Infinite durability
	weapon.stamina_cost = 5.0  # Low stamina cost
	weapon.parry_window = 0.15  # Short parry window for fists (skilled timing required)
	weapon.tool_type = "blunt"  # Can break small things, but not chop trees
	weapon.weight = 0.0
	# No weapon scene - fists are always visible (viewmodel arms)
	items["fists"] = weapon

	# Sporeling tendrils - Dark Forest enemies hit HARD (biome 2)
	# Players need biome 1 armor before venturing into the dark forest
	var sporeling = WeaponData.new()
	sporeling.item_id = "sporeling_fists"
	sporeling.display_name = "Sporeling Tendrils"
	sporeling.description = "Powerful fungal tendrils."
	sporeling.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	sporeling.damage = 35.0  # Biome 2 - will wreck unarmored players
	sporeling.damage_type = WeaponData.DamageType.BLUNT
	sporeling.attack_speed = 1.2
	sporeling.knockback = 8.0
	sporeling.durability = 999999
	sporeling.stamina_cost = 0.0
	sporeling.weight = 0.0
	items["sporeling_fists"] = sporeling

## Basic club weapon (no workbench required)
func _register_weapon_club() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "club"
	weapon.display_name = "Wooden Club"
	weapon.description = "A simple wooden club. Basic blunt damage."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_ONE_HAND
	weapon.damage = 12.0  # Slightly better than fists
	weapon.damage_type = WeaponData.DamageType.BLUNT
	weapon.attack_speed = 1.3  # Medium speed
	weapon.knockback = 8.0  # Good knockback
	weapon.durability = 80
	weapon.stamina_cost = 8.0
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
	weapon.stamina_cost = 10.0
	weapon.weight = 3.0
	weapon.weapon_scene = load("res://shared/weapons/stone_sword.tscn")
	items["stone_sword"] = weapon

func _register_weapon_stone_axe() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "stone_axe"
	weapon.display_name = "Stone Axe (Head Smasher)"
	weapon.description = "A heavy two-handed axe. Slow but devastating. Required for chopping trees."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_TWO_HAND
	weapon.damage = 15.0  # Balanced for trees and combat
	weapon.damage_type = WeaponData.DamageType.SLASH
	weapon.attack_speed = 0.8  # Slower than sword
	weapon.knockback = 15.0  # High knockback
	weapon.durability = 120
	weapon.stamina_cost = 20.0  # 2x stamina cost
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
	weapon.damage = 8.0  # 0.5x sword damage
	weapon.damage_type = WeaponData.DamageType.PIERCE
	weapon.attack_speed = 2.5  # Very fast
	weapon.knockback = 2.0
	weapon.durability = 80
	weapon.stamina_cost = 5.0  # 0.5x stamina cost
	weapon.weight = 1.0
	weapon.weapon_scene = load("res://shared/weapons/stone_knife.tscn")
	items["stone_knife"] = weapon

func _register_weapon_fire_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "fire_wand"
	weapon.display_name = "Fire Wand"
	weapon.description = "A magical wand that shoots fireballs. Uses Brain Power (BP) instead of stamina."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 12.0
	weapon.damage_type = WeaponData.DamageType.FIRE
	weapon.attack_speed = 1.0
	weapon.knockback = 3.0
	weapon.durability = 60
	weapon.stamina_cost = 15.0  # For magic weapons, this is actually brain power cost
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
	weapon.damage = 10.0
	weapon.damage_type = WeaponData.DamageType.PIERCE
	weapon.attack_speed = 0.8
	weapon.knockback = 5.0
	weapon.durability = 100
	weapon.stamina_cost = 8.0
	weapon.projectile_speed = 40.0
	weapon.weight = 2.0
	weapon.weapon_scene = load("res://shared/weapons/bow.tscn")
	# TODO: Set projectile_scene when arrow scene is created
	items["bow"] = weapon

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

## Ice Wand - Buy-only magic weapon from Shnarken
## Cannot be crafted - entry-level magic weapon for players who can't make fire wand
func _register_ice_wand() -> void:
	var weapon = WeaponData.new()
	weapon.item_id = "ice_wand"
	weapon.display_name = "Frost Wand"
	weapon.description = "A basic wand that shoots frost bolts. Buy-only from Shnarken.\nDeals ice damage - effective against fire enemies."
	weapon.weapon_type = WeaponData.WeaponType.MAGIC
	weapon.damage = 12.0  # Slightly less than fire wand
	weapon.damage_type = WeaponData.DamageType.ICE
	weapon.attack_speed = 1.5
	weapon.knockback = 3.0
	weapon.durability = 80
	weapon.stamina_cost = 12.0  # Uses brain power for magic
	weapon.weight = 1.5
	items["ice_wand"] = weapon

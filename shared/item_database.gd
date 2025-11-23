extends Node

## ItemDatabase - Central registry of all items in the game
## Autoload singleton that stores item definitions

# Preload item classes
const ItemData = preload("res://shared/item_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")

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

	# Tools (existing)
	_register_tool("hammer", "Hammer", "Used for building structures.", 1)
	_register_tool("torch", "Torch", "Provides light in dark places.", 20)
	_register_tool("stone_pickaxe", "Stone Pickaxe", "Used for terrain modification. Left click: dig square, Middle click: place earth square (consumes earth from inventory).", 1)
	_register_tool("stone_hoe", "Stone Hoe", "Used for flattening terrain. Left/Right click: flatten 4x4 area (8m x 8m) to a perfect grid level at your standing height.", 1)

	# Tier 0: Unarmed
	_register_weapon_fists()

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
	weapon.weight = 0.0
	# No weapon scene - fists are always visible (viewmodel arms)
	items["fists"] = weapon

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
	weapon.description = "A heavy two-handed axe. Slow but devastating."
	weapon.weapon_type = WeaponData.WeaponType.MELEE_TWO_HAND
	weapon.damage = 30.0  # 2x sword damage
	weapon.damage_type = WeaponData.DamageType.SLASH
	weapon.attack_speed = 0.8  # Slower than sword
	weapon.knockback = 15.0  # High knockback
	weapon.durability = 120
	weapon.stamina_cost = 20.0  # 2x stamina cost
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

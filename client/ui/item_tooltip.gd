extends PanelContainer

## ItemTooltip - Displays detailed item information on hover
## Works with weapons, armor, food, shields, and resources

const ItemData = preload("res://shared/item_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const ArmorData = preload("res://shared/armor_data.gd")
const ShieldData = preload("res://shared/shield_data.gd")
const FoodData = preload("res://shared/food_data.gd")

var content_label: RichTextLabel
var title_label: Label

func _ready() -> void:
	# Set up the panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.4, 0.35, 0.25, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	# Create vertical container
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Title label
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	vbox.add_child(title_label)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Content label (RichTextLabel for formatting)
	content_label = RichTextLabel.new()
	content_label.bbcode_enabled = true
	content_label.fit_content = true
	content_label.scroll_active = false
	content_label.custom_minimum_size = Vector2(220, 0)
	content_label.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(content_label)

	# Start hidden
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Show tooltip for an item at the given position
func show_for_item(item_id: String, global_pos: Vector2) -> void:
	if item_id.is_empty():
		hide()
		return

	var item_data = ItemDatabase.get_item(item_id)
	if not item_data:
		hide()
		return

	# Set title
	title_label.text = item_data.display_name

	# Generate content based on item type
	var content = _generate_tooltip_content(item_data)
	content_label.text = content

	# Position tooltip
	visible = true
	await get_tree().process_frame  # Wait for size to update

	# Adjust position to stay on screen
	var viewport_size = get_viewport().get_visible_rect().size
	var tooltip_size = size

	var pos = global_pos + Vector2(15, 15)

	# Keep on screen
	if pos.x + tooltip_size.x > viewport_size.x:
		pos.x = global_pos.x - tooltip_size.x - 10
	if pos.y + tooltip_size.y > viewport_size.y:
		pos.y = viewport_size.y - tooltip_size.y - 10

	global_position = pos

## Generate BBCode content for the tooltip
func _generate_tooltip_content(item_data) -> String:
	var lines: Array[String] = []

	# Description
	if not item_data.description.is_empty():
		lines.append("[color=#aaaaaa][i]%s[/i][/color]" % item_data.description)
		lines.append("")

	# Type-specific content
	if item_data is WeaponData:
		lines.append_array(_weapon_tooltip(item_data))
	elif item_data is ArmorData:
		lines.append_array(_armor_tooltip(item_data))
	elif item_data is ShieldData:
		lines.append_array(_shield_tooltip(item_data))
	elif item_data is FoodData:
		lines.append_array(_food_tooltip(item_data))
	else:
		lines.append_array(_generic_tooltip(item_data))

	return "\n".join(lines)

func _weapon_tooltip(data: WeaponData) -> Array[String]:
	var lines: Array[String] = []

	# Damage and type
	var damage_type_name = _get_damage_type_name(data.damage_type)
	var damage_color = _get_damage_type_color(data.damage_type)
	lines.append("[color=#ff6666]Damage:[/color] %.0f [color=%s]%s[/color]" % [data.damage, damage_color, damage_type_name])

	# Attack speed
	var speed_desc = _get_speed_description(data.attack_speed)
	lines.append("[color=#66aaff]Attack Speed:[/color] %s (%.1f/s)" % [speed_desc, data.attack_speed])

	# Stamina/BP cost
	if data.weapon_type == WeaponData.WeaponType.MAGIC:
		lines.append("[color=#aa66ff]Brain Power Cost:[/color] %.0f" % data.stamina_cost)
	else:
		lines.append("[color=#66ff66]Stamina Cost:[/color] %.0f" % data.stamina_cost)

	# Knockback
	if data.knockback > 0:
		lines.append("[color=#ffaa66]Knockback:[/color] %.1f" % data.knockback)

	lines.append("")

	# Attack controls based on weapon type
	lines.append("[color=#ffdd66]— Controls —[/color]")
	lines.append_array(_get_weapon_controls(data))

	return lines

func _get_weapon_controls(data: WeaponData) -> Array[String]:
	var lines: Array[String] = []
	var item_id = data.item_id

	match item_id:
		"stone_knife":
			lines.append("[color=#aaaaaa]Left Click:[/color] Quick slash")
			lines.append("[color=#aaaaaa]  • 3rd hit:[/color] [color=#ffaa66]1.5x damage[/color]")
			lines.append("[color=#aaaaaa]Middle Click:[/color] Lunge stab")
			lines.append("[color=#aaaaaa]  •[/color] [color=#ffaa66]2.5x damage[/color]")
		"stone_sword":
			lines.append("[color=#aaaaaa]Left Click:[/color] Sword swing")
			lines.append("[color=#aaaaaa]Middle Click:[/color] Thrust stab")
			lines.append("[color=#aaaaaa]  •[/color] [color=#ffaa66]2.2x damage[/color], low knockback")
		"stone_axe":
			lines.append("[color=#aaaaaa]Left Click:[/color] Heavy swing")
			lines.append("[color=#aaaaaa]  • 3rd hit:[/color] [color=#ffaa66]2.0x damage[/color] overhead")
			lines.append("[color=#aaaaaa]Middle Click:[/color] Spin attack")
			lines.append("[color=#aaaaaa]  •[/color] [color=#ffaa66]1.5x damage[/color], hits around you")
			lines.append("[color=#66ff66]Can chop trees[/color]")
		"fire_wand":
			lines.append("[color=#aaaaaa]Left Click:[/color] Fireball")
			lines.append("[color=#aaaaaa]  •[/color] Ranged projectile")
			lines.append("[color=#aaaaaa]Middle Click:[/color] Fire burst")
			lines.append("[color=#aaaaaa]  •[/color] [color=#ffaa66]Area damage[/color] around you")
		"hammer":
			lines.append("[color=#aaaaaa]Left Click:[/color] Build/Repair")
			lines.append("[color=#aaaaaa]  •[/color] Used for construction")
		_:
			if data.weapon_type == WeaponData.WeaponType.MELEE_ONE_HAND:
				lines.append("[color=#aaaaaa]Left Click:[/color] Attack")
				lines.append("[color=#aaaaaa]Middle Click:[/color] Special attack")
			elif data.weapon_type == WeaponData.WeaponType.MELEE_TWO_HAND:
				lines.append("[color=#aaaaaa]Left Click:[/color] Heavy attack")
				lines.append("[color=#aaaaaa]Middle Click:[/color] Special attack")
			elif data.weapon_type == WeaponData.WeaponType.RANGED:
				lines.append("[color=#aaaaaa]Left Click:[/color] Shoot")
			elif data.weapon_type == WeaponData.WeaponType.MAGIC:
				lines.append("[color=#aaaaaa]Left Click:[/color] Cast spell")
				lines.append("[color=#aaaaaa]Middle Click:[/color] Area spell")

	# Block info for melee
	if data.weapon_type in [WeaponData.WeaponType.MELEE_ONE_HAND, WeaponData.WeaponType.MELEE_TWO_HAND]:
		lines.append("")
		lines.append("[color=#aaaaaa]Right Click:[/color] Block (40% reduction)")

	return lines

func _armor_tooltip(data: ArmorData) -> Array[String]:
	var lines: Array[String] = []

	# Slot
	var slot_names = ["Head", "Chest", "Legs", "Cape", "Accessory"]
	var slot_name = slot_names[data.armor_slot] if data.armor_slot < slot_names.size() else "Unknown"
	lines.append("[color=#aaaaaa]Slot:[/color] %s" % slot_name)

	# Per-damage-type armor values
	lines.append("")
	lines.append("[color=#ffdd66]— Protection —[/color]")
	if data.armor_values:
		var type_names = {
			WeaponData.DamageType.SLASH: ["Slash", "#ffffff"],
			WeaponData.DamageType.BLUNT: ["Blunt", "#aaaaaa"],
			WeaponData.DamageType.PIERCE: ["Pierce", "#ffaaff"],
			WeaponData.DamageType.FIRE: ["Fire", "#ff6600"],
			WeaponData.DamageType.ICE: ["Ice", "#66ffff"],
			WeaponData.DamageType.POISON: ["Poison", "#66ff66"],
		}
		for dmg_type in data.armor_values:
			var val = data.armor_values[dmg_type]
			if type_names.has(dmg_type):
				var name_color = type_names[dmg_type]
				lines.append("[color=%s]%s:[/color] %.1f" % [name_color[1], name_color[0], val])

	# Set info
	if not data.armor_set_id.is_empty():
		lines.append("")
		lines.append("[color=#ffdd66]— Set: %s —[/color]" % data.armor_set_id.capitalize())
		var bonus_desc = _get_set_bonus_description(data.set_bonus)
		lines.append("[color=#66ff66]Full Set Bonus:[/color]")
		lines.append("  %s" % bonus_desc)

	return lines

func _shield_tooltip(data: ShieldData) -> Array[String]:
	var lines: Array[String] = []

	# Block armor
	lines.append("[color=#66aaff]Block Armor:[/color] %.0f" % data.block_armor)

	# Parry info
	if data.parry_window > 0:
		lines.append("[color=#ffaa66]Parry Window:[/color] %.1fs" % data.parry_window)
		lines.append("[color=#ff6666]Parry Bonus:[/color] %.1fx damage" % data.parry_bonus)
	else:
		lines.append("[color=#aaaaaa]Cannot parry[/color]")

	# Stamina drain
	lines.append("[color=#66ff66]Stamina per Block:[/color] %.0f" % data.stamina_drain_per_hit)

	lines.append("")
	lines.append("[color=#ffdd66]— Controls —[/color]")
	lines.append("[color=#aaaaaa]Right Click:[/color] Block")
	if data.parry_window > 0:
		lines.append("[color=#aaaaaa]  •[/color] Parry at start of block")

	return lines

func _food_tooltip(data: FoodData) -> Array[String]:
	var lines: Array[String] = []

	lines.append("[color=#ffdd66]— Buffs —[/color]")

	if data.health_bonus > 0:
		lines.append("[color=#ff6666]+%.0f Max Health[/color]" % data.health_bonus)
	if data.stamina_bonus > 0:
		lines.append("[color=#66ff66]+%.0f Max Stamina[/color]" % data.stamina_bonus)
	if data.bp_bonus > 0:
		lines.append("[color=#aa66ff]+%.0f Max Brain Power[/color]" % data.bp_bonus)
	if data.heal_per_second > 0:
		lines.append("[color=#ffaaaa]+%.1f HP/sec Regen[/color]" % data.heal_per_second)

	lines.append("")

	# Duration
	var minutes = int(data.duration) / 60
	var seconds = int(data.duration) % 60
	if minutes > 0:
		lines.append("[color=#aaaaaa]Duration:[/color] %dm %ds" % [minutes, seconds])
	else:
		lines.append("[color=#aaaaaa]Duration:[/color] %ds" % seconds)

	lines.append("")
	lines.append("[color=#aaaaaa]Right Click to eat[/color]")

	return lines

func _generic_tooltip(item_data) -> Array[String]:
	var lines: Array[String] = []

	# Item type
	var type_names = ["Resource", "Weapon", "Shield", "Armor", "Consumable", "Tool", "Buildable"]
	if item_data.item_type < type_names.size():
		lines.append("[color=#aaaaaa]Type:[/color] %s" % type_names[item_data.item_type])

	# Stack size
	if item_data.max_stack_size > 1:
		lines.append("[color=#aaaaaa]Max Stack:[/color] %d" % item_data.max_stack_size)

	return lines

func _get_damage_type_name(damage_type: int) -> String:
	match damage_type:
		WeaponData.DamageType.SLASH: return "Slash"
		WeaponData.DamageType.BLUNT: return "Blunt"
		WeaponData.DamageType.PIERCE: return "Pierce"
		WeaponData.DamageType.FIRE: return "Fire"
		WeaponData.DamageType.ICE: return "Ice"
		WeaponData.DamageType.POISON: return "Poison"
		_: return "Physical"

func _get_damage_type_color(damage_type: int) -> String:
	match damage_type:
		WeaponData.DamageType.SLASH: return "#ffffff"
		WeaponData.DamageType.BLUNT: return "#aaaaaa"
		WeaponData.DamageType.PIERCE: return "#ffaaff"
		WeaponData.DamageType.FIRE: return "#ff6600"
		WeaponData.DamageType.ICE: return "#66ffff"
		WeaponData.DamageType.POISON: return "#66ff66"
		_: return "#ffffff"

func _get_speed_description(speed: float) -> String:
	if speed >= 2.5:
		return "Very Fast"
	elif speed >= 2.0:
		return "Fast"
	elif speed >= 1.5:
		return "Normal"
	elif speed >= 1.0:
		return "Slow"
	else:
		return "Very Slow"

func _get_set_bonus_description(set_bonus: int) -> String:
	match set_bonus:
		ArmorData.SetBonus.PIG_DOUBLE_JUMP:
			return "[color=#ffaa66]Double Jump[/color] - Jump again in mid-air"
		ArmorData.SetBonus.DEER_STAMINA_SAVER:
			return "[color=#66ff66]Stamina Saver[/color] - 50% less sprint stamina"
		_:
			return "None"

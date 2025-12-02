extends Control

## Debug Console - Press F5 to toggle
## Commands:
##   /give <item_name> [amount] - Spawn items in front of player (supports /give 10 wood)
##   /spawn <enemy_type> [count] - Spawn enemies near player
##   /tp <x> <y> <z> - Teleport player
##   /heal - Heal to full health
##   /god - Toggle god mode (invincibility)
##   /clear - Clear inventory
##   /time [hour] - Show or set time of day (0-24)
##   /help - Show commands

signal command_executed(command: String)

@onready var input_field: LineEdit = $Panel/VBox/InputField
@onready var output_label: RichTextLabel = $Panel/VBox/OutputLabel
@onready var close_button: Button = $Panel/VBox/HBox/CloseButton

var command_history: Array[String] = []
var history_index: int = -1
var god_mode: bool = false
var browsing_history: bool = false

# Autocomplete data
var all_commands: Array[String] = ["/give", "/spawn", "/tp", "/heal", "/god", "/clear", "/kill", "/pos", "/items", "/enemies", "/time", "/help", "/perf", "/toggle"]

# Performance toggle states
var perf_toggles: Dictionary = {
	"terrain": true,
	"env": true,        # Environmental objects (trees, rocks)
	"enemies": true,
	"physics": true,
	"ui": true,
	"daynight": true,
}
var all_items: Array[String] = []
var all_enemies: Array[String] = ["gahnome", "sporeling", "deer", "pig", "sheep"]

# Reference to client for accessing player and inventory
var client_ref: Node = null

func _ready() -> void:
	input_field.text_submitted.connect(_on_command_submitted)
	input_field.text_changed.connect(_on_text_changed)
	close_button.pressed.connect(hide_console)

	# Get client reference
	client_ref = get_tree().get_first_node_in_group("client")
	if not client_ref:
		client_ref = get_parent().get_parent()  # Fallback: UILayer -> Client

	# Build item list for autocomplete
	_build_item_list()

	_add_output("[color=cyan]Debug Console[/color] - Type /help for commands (Tab to autocomplete)")

func _build_item_list() -> void:
	# Get all items from ItemDatabase
	var items = ItemDatabase.get_all_items()
	for item in items:
		all_items.append(item.item_id)
	all_items.sort()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Handle Tab for autocomplete (consume it so it doesn't tab between controls)
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_do_autocomplete()
		get_viewport().set_input_as_handled()
		return

	# Handle history navigation with up/down arrows
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_navigate_history_up()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_DOWN:
			_navigate_history_down()
			get_viewport().set_input_as_handled()
			return

## Check if console is currently open
func is_console_open() -> bool:
	return visible

func _on_text_changed(_new_text: String) -> void:
	# Reset history browsing when user types
	browsing_history = false
	history_index = -1

func _navigate_history_up() -> void:
	if command_history.is_empty():
		return

	if not browsing_history:
		# Start browsing from most recent
		browsing_history = true
		history_index = 0
	else:
		# Go to older command
		history_index = min(history_index + 1, command_history.size() - 1)

	input_field.text = command_history[history_index]
	input_field.caret_column = input_field.text.length()

func _navigate_history_down() -> void:
	if not browsing_history or command_history.is_empty():
		return

	history_index -= 1
	if history_index < 0:
		# Back to empty input
		browsing_history = false
		history_index = -1
		input_field.text = ""
	else:
		input_field.text = command_history[history_index]

	input_field.caret_column = input_field.text.length()

func _do_autocomplete() -> void:
	var text = input_field.text.strip_edges()
	if text.is_empty():
		return

	var parts = text.split(" ", false)
	var cmd = parts[0].to_lower()

	# Autocomplete command
	if parts.size() == 1 and not text.ends_with(" "):
		var matches: Array[String] = []
		for c in all_commands:
			if c.begins_with(cmd) or c.begins_with("/" + cmd):
				matches.append(c)

		if matches.size() == 1:
			input_field.text = matches[0] + " "
			input_field.caret_column = input_field.text.length()
		elif matches.size() > 1:
			_add_output("[color=gray]" + ", ".join(matches) + "[/color]")
		return

	# Autocomplete argument based on command
	if parts.size() >= 1:
		var arg_prefix = parts[parts.size() - 1].to_lower() if parts.size() > 1 and not text.ends_with(" ") else ""
		var suggestions: Array[String] = []

		if cmd in ["/give", "give"]:
			for item in all_items:
				if arg_prefix.is_empty() or item.begins_with(arg_prefix):
					suggestions.append(item)
		elif cmd in ["/spawn", "spawn"]:
			for enemy in all_enemies:
				if arg_prefix.is_empty() or enemy.begins_with(arg_prefix):
					suggestions.append(enemy)

		if suggestions.size() == 1:
			parts[parts.size() - 1] = suggestions[0]
			input_field.text = " ".join(parts) + " "
			input_field.caret_column = input_field.text.length()
		elif suggestions.size() > 1 and suggestions.size() <= 10:
			_add_output("[color=gray]" + ", ".join(suggestions) + "[/color]")

func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return

	# Add to history
	command_history.push_front(text)
	if command_history.size() > 50:
		command_history.pop_back()
	history_index = -1

	# Clear input
	input_field.text = ""

	# Process command
	_add_output("> " + text)
	_execute_command(text)

	command_executed.emit(text)

func _execute_command(text: String) -> void:
	var parts = text.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	var cmd = parts[0].to_lower()
	var args = parts.slice(1)

	match cmd:
		"/give", "give":
			_cmd_give(args)
		"/spawn", "spawn":
			_cmd_spawn(args)
		"/tp", "tp", "/teleport", "teleport":
			_cmd_teleport(args)
		"/heal", "heal":
			_cmd_heal()
		"/god", "god":
			_cmd_god()
		"/clear", "clear":
			_cmd_clear()
		"/help", "help", "?":
			_cmd_help()
		"/items", "items":
			_cmd_list_items()
		"/enemies", "enemies":
			_cmd_list_enemies()
		"/pos", "pos":
			_cmd_position()
		"/kill", "kill":
			_cmd_kill()
		"/time", "time":
			_cmd_time(args)
		"/perf", "perf":
			_cmd_perf()
		"/toggle", "toggle":
			_cmd_toggle(args)
		_:
			_add_output("[color=red]Unknown command: %s[/color]" % cmd)

func _cmd_give(args: Array) -> void:
	if args.is_empty():
		_add_output("[color=yellow]Usage: /give <item_name> [amount] or /give <amount> <item_name>[/color]")
		return

	var item_name: String = ""
	var amount: int = 1

	# Support both "/give wood 10" and "/give 10 wood" formats
	if args.size() == 1:
		item_name = args[0]
	elif args.size() >= 2:
		# Check if first arg is a number (amount first format)
		if args[0].is_valid_int():
			amount = int(args[0])
			item_name = args[1]
		else:
			# Standard format: item_name first
			item_name = args[0]
			amount = int(args[1]) if args[1].is_valid_int() else 1

	if amount <= 0:
		amount = 1

	# Validate item exists
	var item_data = ItemDatabase.get_item(item_name)
	if not item_data:
		_add_output("[color=red]Unknown item: %s[/color]" % item_name)
		_add_output("Use /items to see available items")
		return

	# Send RPC to server
	print("[DebugConsole] Sending give RPC: %d x %s" % [amount, item_name])
	NetworkManager.rpc_debug_give_item.rpc_id(1, item_name, amount)
	_add_output("[color=green]Spawning %d x %s in front of you[/color]" % [amount, item_name])

func _cmd_spawn(args: Array) -> void:
	if args.is_empty():
		_add_output("[color=yellow]Usage: /spawn <enemy_type> [count][/color]")
		_add_output("Types: gahnome, sporeling, deer, pig, sheep")
		return

	var enemy_type = args[0].to_lower()
	var count = 1
	if args.size() > 1:
		count = int(args[1])
		count = clamp(count, 1, 10)  # Max 10 at a time

	# Send RPC to server
	NetworkManager.rpc_debug_spawn_entity.rpc_id(1, enemy_type, count)
	_add_output("[color=green]Requested spawn: %d x %s[/color]" % [count, enemy_type])

func _cmd_teleport(args: Array) -> void:
	if args.size() < 3:
		_add_output("[color=yellow]Usage: /tp <x> <y> <z>[/color]")
		return

	var x = float(args[0])
	var y = float(args[1])
	var z = float(args[2])

	NetworkManager.rpc_debug_teleport.rpc_id(1, Vector3(x, y, z))
	_add_output("[color=green]Teleporting to (%s, %s, %s)[/color]" % [x, y, z])

func _cmd_heal() -> void:
	NetworkManager.rpc_debug_heal.rpc_id(1)
	_add_output("[color=green]Healed to full health[/color]")

func _cmd_god() -> void:
	god_mode = not god_mode
	NetworkManager.rpc_debug_god_mode.rpc_id(1, god_mode)
	# Also set on local player so client-side checks work
	var local_player = get_tree().get_first_node_in_group("local_player")
	if local_player and "god_mode" in local_player:
		local_player.god_mode = god_mode
	if god_mode:
		_add_output("[color=gold]God mode ENABLED[/color]")
	else:
		_add_output("[color=gray]God mode disabled[/color]")

func _cmd_clear() -> void:
	NetworkManager.rpc_debug_clear_inventory.rpc_id(1)
	_add_output("[color=green]Inventory cleared[/color]")

func _cmd_kill() -> void:
	NetworkManager.rpc_debug_kill_nearby.rpc_id(1)
	_add_output("[color=red]Killed all nearby enemies[/color]")

func _cmd_time(args: Array) -> void:
	# Find day/night cycle
	var day_night_cycle: Node = null
	var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
	if terrain_worlds.size() > 0:
		var terrain_world = terrain_worlds[0]
		if terrain_world.has_node("DayNightCycle"):
			day_night_cycle = terrain_world.get_node("DayNightCycle")

	if not day_night_cycle:
		_add_output("[color=red]DayNightCycle not found![/color]")
		return

	if args.is_empty():
		# Show current time
		var time_str = day_night_cycle.get_time_string_12h() if day_night_cycle.has_method("get_time_string_12h") else "%.1f" % day_night_cycle.current_hour
		var period = day_night_cycle.get_current_period() if day_night_cycle.has_method("get_current_period") else "unknown"
		_add_output("Current time: %s (%s)" % [time_str, period])
		_add_output("[color=gray]Usage: /time <hour> (0-24, e.g. /time 12 for noon, /time 22 for night)[/color]")
		return

	# Set time
	var hour = float(args[0])
	if hour < 0 or hour > 24:
		_add_output("[color=red]Hour must be 0-24[/color]")
		return
	# Wrap 24 to 0 (midnight)
	if hour >= 24:
		hour = 0

	day_night_cycle.set_time(hour)
	var time_str = day_night_cycle.get_time_string_12h()
	var period = day_night_cycle.get_current_period()
	_add_output("[color=green]Time set to %s (%s)[/color]" % [time_str, period])

func _cmd_position() -> void:
	if client_ref and client_ref.local_player:
		var pos = client_ref.local_player.global_position
		_add_output("Position: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z])
	else:
		_add_output("[color=red]Player not found[/color]")

func _cmd_list_items() -> void:
	_add_output("[color=cyan]Available items:[/color]")
	var items = ItemDatabase.get_all_items()
	var item_names = []
	for item in items:
		item_names.append(item.name)
	item_names.sort()
	_add_output(", ".join(item_names))

func _cmd_list_enemies() -> void:
	_add_output("[color=cyan]Enemy types:[/color] gahnome, sporeling")
	_add_output("[color=cyan]Animal types:[/color] deer, pig, sheep")

func _cmd_help() -> void:
	_add_output("[color=cyan]Commands:[/color]")
	_add_output("  /give <item> [amount] - Spawn items (e.g. /give 10 wood)")
	_add_output("  /spawn <type> [count] - Spawn enemies/animals")
	_add_output("  /tp <x> <y> <z> - Teleport")
	_add_output("  /heal - Heal to full")
	_add_output("  /god - Toggle invincibility")
	_add_output("  /clear - Clear inventory")
	_add_output("  /kill - Kill nearby enemies")
	_add_output("  /pos - Show position")
	_add_output("  /time [hour] - Show/set time (0-24)")
	_add_output("  /items - List all items")
	_add_output("  /enemies - List enemy types")
	_add_output("[color=cyan]Performance:[/color]")
	_add_output("  /perf - Show FPS and toggle status")
	_add_output("  /toggle <system> - Toggle system on/off")
	_add_output("    Systems: terrain, env, enemies, physics, ui, daynight")

func _cmd_perf() -> void:
	var fps = Engine.get_frames_per_second()
	var frame_time = 1000.0 / fps if fps > 0 else 0
	_add_output("[color=cyan]Performance Status:[/color]")
	_add_output("  FPS: %d (%.1f ms/frame)" % [fps, frame_time])
	_add_output("[color=cyan]System Toggles:[/color]")
	for system in perf_toggles:
		var status = "[color=green]ON[/color]" if perf_toggles[system] else "[color=red]OFF[/color]"
		_add_output("  %s: %s" % [system, status])
	_add_output("[color=gray]Use /toggle <system> to toggle[/color]")

func _cmd_toggle(args: Array) -> void:
	if args.is_empty():
		_add_output("[color=yellow]Usage: /toggle <system>[/color]")
		_add_output("Systems: terrain, env, enemies, physics, ui, daynight, all")
		return

	var system = args[0].to_lower()

	if system == "all":
		# Toggle all off if any are on, otherwise toggle all on
		var any_on = false
		for s in perf_toggles:
			if perf_toggles[s]:
				any_on = true
				break
		var new_state = not any_on
		for s in perf_toggles:
			perf_toggles[s] = new_state
			_apply_toggle(s, new_state)
		var status = "ON" if new_state else "OFF"
		_add_output("[color=cyan]All systems toggled %s[/color]" % status)
		return

	if system not in perf_toggles:
		_add_output("[color=red]Unknown system: %s[/color]" % system)
		_add_output("Systems: terrain, env, enemies, physics, ui, daynight, all")
		return

	perf_toggles[system] = not perf_toggles[system]
	_apply_toggle(system, perf_toggles[system])
	var status = "[color=green]ON[/color]" if perf_toggles[system] else "[color=red]OFF[/color]"
	_add_output("%s: %s" % [system, status])

func _apply_toggle(system: String, enabled: bool) -> void:
	match system:
		"terrain":
			# Toggle terrain rendering
			var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
			for tw in terrain_worlds:
				tw.visible = enabled
				tw.set_process(enabled)
		"env":
			# Toggle environmental objects (trees, rocks, grass)
			if client_ref and client_ref.environmental_objects_container:
				client_ref.environmental_objects_container.visible = enabled
				# Also disable processing on all env objects
				for child in client_ref.environmental_objects_container.get_children():
					child.set_process(enabled)
		"enemies":
			# Toggle enemy visibility and processing
			var enemies = get_tree().get_nodes_in_group("enemies")
			for enemy in enemies:
				enemy.visible = enabled
				enemy.set_process(enabled)
				enemy.set_physics_process(enabled)
			var animals = get_tree().get_nodes_in_group("animals")
			for animal in animals:
				animal.visible = enabled
				animal.set_process(enabled)
				animal.set_physics_process(enabled)
		"physics":
			# Toggle physics processing on player
			if client_ref and client_ref.local_player:
				client_ref.local_player.set_physics_process(enabled)
		"ui":
			# Toggle HUD updates
			if client_ref and client_ref.player_hud_ui:
				client_ref.player_hud_ui.set_process(enabled)
			if client_ref and client_ref.hotbar_ui:
				client_ref.hotbar_ui.set_process(enabled)
			if client_ref and client_ref.mini_map_ui:
				client_ref.mini_map_ui.set_process(enabled)
		"daynight":
			# Toggle day/night cycle
			var day_night_cycles = get_tree().get_nodes_in_group("day_night_cycle")
			if day_night_cycles.is_empty():
				var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
				for tw in terrain_worlds:
					if tw.has_node("DayNightCycle"):
						day_night_cycles.append(tw.get_node("DayNightCycle"))
			for dnc in day_night_cycles:
				dnc.set_process(enabled)

func _add_output(text: String) -> void:
	output_label.append_text(text + "\n")
	# Auto-scroll to bottom
	await get_tree().process_frame
	output_label.scroll_to_line(output_label.get_line_count())

func show_console() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	input_field.grab_focus()
	input_field.text = ""

func hide_console() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

extends Node

## Main - Entry point that detects and switches between server/client/singleplayer modes

@onready var server_scene := preload("res://scenes/server.tscn")
@onready var client_scene := preload("res://scenes/client.tscn")

enum LaunchMode {
	AUTO_DETECT,
	SERVER,
	CLIENT,
	SINGLEPLAYER
}

var current_mode: LaunchMode = LaunchMode.AUTO_DETECT

func _ready() -> void:
	print("[Main] Starting Hamberg - Open Source Survival...")
	print("[Main] Godot version: %s" % Engine.get_version_info().string)

	# Parse command line arguments
	var launch_mode := _parse_launch_mode()

	match launch_mode:
		LaunchMode.SERVER:
			_launch_server()
		LaunchMode.CLIENT:
			_launch_client()
		LaunchMode.SINGLEPLAYER:
			_launch_singleplayer()
		LaunchMode.AUTO_DETECT:
			# Default to client mode with UI
			_launch_client()

var autoconnect_address: String = ""

func _parse_launch_mode() -> LaunchMode:
	var args := OS.get_cmdline_args()

	print("[Main] Command line args: %s" % [args])

	# Check for custom arguments after "--"
	var custom_args: Array[String] = []
	var found_separator := false

	for arg in args:
		if found_separator:
			custom_args.append(arg)
		elif arg == "--":
			found_separator = true

	# Parse custom arguments
	var mode := LaunchMode.AUTO_DETECT
	var i := 0
	while i < custom_args.size():
		var arg = custom_args[i]
		match arg:
			"--server":
				print("[Main] Detected server mode")
				mode = LaunchMode.SERVER
			"--client":
				print("[Main] Detected client mode")
				mode = LaunchMode.CLIENT
			"--singleplayer":
				print("[Main] Detected singleplayer mode")
				mode = LaunchMode.SINGLEPLAYER
			"--autoconnect":
				# Next arg should be address:port
				if i + 1 < custom_args.size():
					autoconnect_address = custom_args[i + 1]
					print("[Main] Auto-connect to: %s" % autoconnect_address)
					i += 1
		i += 1

	if mode != LaunchMode.AUTO_DETECT:
		return mode

	# Check if running headless (DisplayServer not available in headless mode)
	if DisplayServer.get_name() == "headless":
		print("[Main] Running headless - defaulting to server mode")
		return LaunchMode.SERVER

	return LaunchMode.AUTO_DETECT

func _launch_server() -> void:
	print("[Main] Launching dedicated server...")
	current_mode = LaunchMode.SERVER

	var server := server_scene.instantiate()
	add_child(server)

	# Read port from environment or use default
	var port := int(OS.get_environment("GAME_PORT"))
	if port == 0:
		port = NetworkManager.DEFAULT_PORT

	var max_players := int(OS.get_environment("MAX_PLAYERS"))
	if max_players == 0:
		max_players = NetworkManager.DEFAULT_MAX_PLAYERS

	server.start_server(port, max_players)

func _launch_client() -> void:
	print("[Main] Launching client...")
	current_mode = LaunchMode.CLIENT

	var client := client_scene.instantiate()
	add_child(client)

	# If autoconnect address was specified, connect automatically
	if not autoconnect_address.is_empty():
		await get_tree().create_timer(0.1).timeout
		client.auto_connect_to_address(autoconnect_address)

func _launch_singleplayer() -> void:
	print("[Main] Launching singleplayer...")
	current_mode = LaunchMode.SINGLEPLAYER

	# Singleplayer mode: Start server in this process, launch client as separate process
	# This ensures real networking just like multiplayer

	# Start the server
	var server := server_scene.instantiate()
	server.name = "Server"
	add_child(server)
	server.start_server(NetworkManager.DEFAULT_PORT, 1)

	# Wait for server to be ready
	await get_tree().create_timer(0.3).timeout

	# Launch a separate client process that auto-connects to localhost
	var exe_path = OS.get_executable_path()
	var args = ["--", "--client", "--autoconnect", "127.0.0.1:%d" % NetworkManager.DEFAULT_PORT]

	print("[Main] Launching client process: %s %s" % [exe_path, " ".join(args)])
	var pid = OS.create_process(exe_path, args)

	if pid > 0:
		print("[Main] Client process started with PID: %d" % pid)
	else:
		push_error("[Main] Failed to launch client process")

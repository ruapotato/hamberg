class_name ClientMapSystem
extends RefCounted

## ClientMapSystem - Handles world map, mini-map, markers, and pings

var client: Node
var map_markers: Dictionary = {}  # pin_id -> marker node

func _init(c: Node) -> void:
	client = c

# =============================================================================
# MAP INITIALIZATION
# =============================================================================

## Initialize map system with player
func initialize_with_player(player: Node) -> void:
	if not player:
		return

	# Connect world map if available
	if client.world_map:
		if not client.world_map.pin_placed.is_connected(_on_pin_placed):
			client.world_map.pin_placed.connect(_on_pin_placed)
		if not client.world_map.pin_removed.is_connected(_on_pin_removed):
			client.world_map.pin_removed.connect(_on_pin_removed)
		if not client.world_map.pin_renamed.is_connected(_on_pin_renamed):
			client.world_map.pin_renamed.connect(_on_pin_renamed)

	print("[Client] Map system initialized")

# =============================================================================
# MAP PINS
# =============================================================================

## Handle pin placed on map
func _on_pin_placed(pin_id: int, position: Vector2, label: String) -> void:
	print("[Client] Pin placed: %d at %s (%s)" % [pin_id, position, label])
	create_map_marker(pin_id, position, label)
	sync_pins_to_server()

## Handle pin removed from map
func _on_pin_removed(pin_id: int) -> void:
	print("[Client] Pin removed: %d" % pin_id)
	remove_map_marker(pin_id)
	sync_pins_to_server()

## Handle pin renamed
func _on_pin_renamed(pin_id: int, new_label: String) -> void:
	print("[Client] Pin renamed: %d -> %s" % [pin_id, new_label])
	if pin_id in map_markers:
		var marker = map_markers[pin_id]
		if marker and marker.has_method("set_label"):
			marker.set_label(new_label)
	sync_pins_to_server()

## Sync pins to server
func sync_pins_to_server() -> void:
	if not client.world_map:
		return

	var pins = client.world_map.get_all_pins()
	var pins_array = []

	for pin in pins:
		pins_array.append({
			"id": pin.id,
			"x": pin.position.x,
			"y": pin.position.y,
			"label": pin.label
		})

	NetworkManager.rpc_update_map_pins.rpc_id(1, pins_array)

## Sync pins from character data
func sync_pins_from_data(pins_array: Array) -> void:
	if not client.world_map:
		return

	# Clear existing markers
	for pin_id in map_markers.keys():
		remove_map_marker(pin_id)

	# Add pins from data
	for pin_data in pins_array:
		var pin_id = pin_data.get("id", 0)
		var pos = Vector2(pin_data.get("x", 0), pin_data.get("y", 0))
		var label = pin_data.get("label", "")

		client.world_map.add_pin(pin_id, pos, label)
		create_map_marker(pin_id, pos, label)

# =============================================================================
# 3D MAP MARKERS
# =============================================================================

## Create a 3D marker in the world
func create_map_marker(pin_id: int, position: Vector2, label: String) -> void:
	if pin_id in map_markers:
		return

	var MarkerScene = preload("res://client/ui/map_marker_3d.tscn")
	if not MarkerScene:
		return

	var marker = MarkerScene.instantiate()
	marker.name = "MapMarker_%d" % pin_id

	# Convert 2D map position to 3D world position
	var world_pos = Vector3(position.x, 50.0, position.y)

	# Get terrain height if available
	if client.terrain_world and client.terrain_world.has_method("get_height_at"):
		world_pos.y = client.terrain_world.get_height_at(position.x, position.y) + 5.0

	marker.global_position = world_pos

	if marker.has_method("set_label"):
		marker.set_label(label)

	client.world.add_child(marker)
	map_markers[pin_id] = marker

## Remove a 3D marker
func remove_map_marker(pin_id: int) -> void:
	if pin_id in map_markers:
		var marker = map_markers[pin_id]
		if is_instance_valid(marker):
			marker.queue_free()
		map_markers.erase(pin_id)

## Sync 3D markers from world map pins
func sync_markers_from_pins() -> void:
	if not client.world_map:
		return

	var pins = client.world_map.get_all_pins()
	var pin_ids = []

	for pin in pins:
		pin_ids.append(pin.id)
		if pin.id not in map_markers:
			create_map_marker(pin.id, pin.position, pin.label)

	# Remove orphaned markers
	for pin_id in map_markers.keys():
		if pin_id not in pin_ids:
			remove_map_marker(pin_id)

# =============================================================================
# MAP PINGS
# =============================================================================

## Send a ping to server
func send_ping(position: Vector3) -> void:
	var pos_array = [position.x, position.y, position.z]
	NetworkManager.rpc_send_ping.rpc_id(1, pos_array)

## Receive a ping from server
func receive_ping(peer_id: int, position: Array) -> void:
	var ping_pos = Vector3(position[0], position[1], position[2])
	create_ping_indicator(peer_id, ping_pos)

## Create visual ping indicator
func create_ping_indicator(peer_id: int, position: Vector3) -> void:
	var PingIndicator = preload("res://client/ui/ping_indicator.tscn")
	if not PingIndicator:
		return

	var ping = PingIndicator.instantiate()
	ping.global_position = position

	# Set color based on peer
	if ping.has_method("set_peer_color"):
		ping.set_peer_color(peer_id)

	client.world.add_child(ping)

	# Auto-remove after duration
	var timer = client.get_tree().create_timer(5.0)
	timer.timeout.connect(func(): ping.queue_free() if is_instance_valid(ping) else null)

# =============================================================================
# WORLD MAP TOGGLE
# =============================================================================

## Toggle world map visibility
func toggle_world_map() -> void:
	if not client.world_map:
		return

	client.world_map.visible = not client.world_map.visible

	if client.world_map.visible:
		# Update player position on map
		if client.local_player:
			var pos = client.local_player.global_position
			client.world_map.set_player_position(Vector2(pos.x, pos.z))

		# Capture mouse for map interaction
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		# Release mouse for gameplay
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

class_name ClientLoadingManager
extends RefCounted

## ClientLoadingManager - Handles loading screen and initial data sync

var client: Node

# Loading state
var loading_steps: Dictionary = {
	"world_config": false,
	"character_data": false,
	"inventory": false,
	"equipment": false,
	"chunks_initial": false,
	"terrain_ready": false
}
var is_loading: bool = false
var loading_start_time: float = 0.0

# Terrain modification queue (applied after terrain is ready)
var terrain_mod_queue: Array = []

func _init(c: Node) -> void:
	client = c

# =============================================================================
# LOADING SCREEN
# =============================================================================

## Start loading process
func start_loading() -> void:
	is_loading = true
	loading_start_time = Time.get_ticks_msec() / 1000.0

	# Reset all steps
	for step in loading_steps:
		loading_steps[step] = false

	# Show loading screen
	if client.loading_screen:
		client.loading_screen.visible = true

	# Disable player physics during loading
	disable_player_physics()

	print("[Client] Loading started")

## Mark a loading step as complete
func mark_step_complete(step: String) -> void:
	if step in loading_steps:
		loading_steps[step] = true
		print("[Client] Loading step complete: %s" % step)
		update_loading_progress()
		check_loading_complete()

## Update loading progress display
func update_loading_progress() -> void:
	var completed = 0
	var total = loading_steps.size()

	for step in loading_steps:
		if loading_steps[step]:
			completed += 1

	var progress = float(completed) / float(total)

	if client.loading_screen and client.loading_screen.has_method("set_progress"):
		client.loading_screen.set_progress(progress)

## Check if all loading steps are complete
func check_loading_complete() -> void:
	for step in loading_steps:
		if not loading_steps[step]:
			return  # Still loading

	finish_loading()

## Finish loading and enable gameplay
func finish_loading() -> void:
	if not is_loading:
		return

	is_loading = false
	var load_time = (Time.get_ticks_msec() / 1000.0) - loading_start_time

	print("[Client] Loading complete in %.2f seconds" % load_time)

	# Hide loading screen
	if client.loading_screen:
		client.loading_screen.visible = false

	# Enable player physics
	enable_player_physics()

	# Apply queued terrain modifications
	apply_queued_terrain_modifications()

	# Mark game as loaded for player
	if client.local_player:
		client.local_player.set_game_loaded(true)

## Handle loading screen skip (for testing)
func loading_screen_skipped() -> void:
	# Mark all steps complete
	for step in loading_steps:
		loading_steps[step] = true
	finish_loading()

# =============================================================================
# PLAYER PHYSICS
# =============================================================================

## Disable player physics during loading
func disable_player_physics() -> void:
	if client.local_player:
		client.local_player.set_physics_process(false)

## Enable player physics after loading
func enable_player_physics() -> void:
	if client.local_player:
		client.local_player.set_physics_process(true)

# =============================================================================
# TERRAIN SYNC
# =============================================================================

## Check if terrain is ready
func check_terrain_ready() -> bool:
	if not client.terrain_world:
		return false
	return client.terrain_world.is_initialized

## Queue terrain modification for later (if terrain not ready)
func queue_terrain_modification(operation: String, position: Vector3, data: Dictionary) -> void:
	terrain_mod_queue.append({
		"operation": operation,
		"position": position,
		"data": data
	})

## Apply all queued terrain modifications
func apply_queued_terrain_modifications() -> void:
	if terrain_mod_queue.is_empty():
		return

	print("[Client] Applying %d queued terrain modifications" % terrain_mod_queue.size())

	for mod in terrain_mod_queue:
		apply_terrain_modification(mod.operation, mod.position, mod.data)

	terrain_mod_queue.clear()

## Apply a terrain modification
func apply_terrain_modification(operation: String, position: Vector3, data: Dictionary) -> void:
	if not client.terrain_world:
		return

	if client.terrain_world.has_method("apply_modification"):
		client.terrain_world.apply_modification(operation, position, data)

# =============================================================================
# WORLD MAP CACHE
# =============================================================================

## Generate world map cache (heightmap for minimap)
func generate_world_map_cache() -> void:
	if not client.terrain_world:
		return

	# This is done async to not block loading
	print("[Client] Generating world map cache...")

	# The actual generation is handled by the terrain system
	if client.terrain_world.has_method("generate_map_cache"):
		client.terrain_world.generate_map_cache()

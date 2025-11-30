class_name ClientEnvironmentalManager
extends RefCounted

## ClientEnvironmentalManager - Handles environmental objects, dynamic objects, and resources

var client: Node

# Processing queue for environmental objects (prevents hitching)
var env_spawn_queue: Array = []
var env_queue_processing: bool = false
const ENV_BATCH_SIZE: int = 5  # Objects to process per frame

func _init(c: Node) -> void:
	client = c

# =============================================================================
# ENVIRONMENTAL OBJECTS (Trees, Rocks, etc.)
# =============================================================================

## Receive environmental objects from server
func receive_environmental_objects(chunk_pos: Array, objects_data: Array) -> void:
	# Queue for processing to avoid hitching
	env_spawn_queue.append({
		"chunk_pos": Vector2i(chunk_pos[0], chunk_pos[1]),
		"objects": objects_data
	})

	if not env_queue_processing:
		process_environmental_queue()

## Process environmental object spawn queue
func process_environmental_queue() -> void:
	if env_spawn_queue.is_empty():
		env_queue_processing = false
		return

	env_queue_processing = true

	var batch = env_spawn_queue.pop_front()
	var chunk_pos = batch.chunk_pos
	var objects = batch.objects

	# Spawn objects in batches
	var processed = 0
	for obj_data in objects:
		if processed >= ENV_BATCH_SIZE:
			# Re-queue remaining for next frame
			batch.objects = objects.slice(processed)
			env_spawn_queue.push_front(batch)
			break

		spawn_environmental_object(chunk_pos, obj_data)
		processed += 1

	# Continue next frame
	if not env_spawn_queue.is_empty():
		await client.get_tree().process_frame
		process_environmental_queue()
	else:
		env_queue_processing = false

## Spawn a single environmental object
func spawn_environmental_object(chunk_pos: Vector2i, obj_data: Dictionary) -> void:
	if not client.world:
		return

	var obj_type = obj_data.get("type", "")
	var position = Vector3(obj_data.get("x", 0), obj_data.get("y", 0), obj_data.get("z", 0))
	var object_id = obj_data.get("id", 0)

	# Get scene path based on type
	var scene_path = get_environmental_scene(obj_type)
	if scene_path.is_empty():
		return

	var scene = load(scene_path)
	if not scene:
		return

	var instance = scene.instantiate()
	instance.global_position = position
	instance.chunk_position = chunk_pos

	if "object_id" in instance:
		instance.object_id = object_id

	client.world.add_child(instance)

## Get scene path for environmental object type
func get_environmental_scene(obj_type: String) -> String:
	match obj_type:
		"tree":
			return "res://shared/environmental/tree.tscn"
		"rock":
			return "res://shared/environmental/rock.tscn"
		"bush":
			return "res://shared/environmental/bush.tscn"
		_:
			return ""

## Despawn environmental objects in a chunk
func despawn_environmental_objects(chunk_pos: Array) -> void:
	var target_chunk = Vector2i(chunk_pos[0], chunk_pos[1])

	for child in client.world.get_children():
		if "chunk_position" in child and child.chunk_position == target_chunk:
			child.queue_free()

## Destroy a specific environmental object
func destroy_environmental_object(chunk_pos: Array, object_id: int, drops: Array) -> void:
	var target_chunk = Vector2i(chunk_pos[0], chunk_pos[1])

	for child in client.world.get_children():
		if "chunk_position" in child and child.chunk_position == target_chunk:
			if "object_id" in child and child.object_id == object_id:
				# Spawn drops before destroying
				spawn_resource_drops(drops, child.global_position)

				# Play destruction effect
				if child.has_method("play_destroy_effect"):
					child.play_destroy_effect()

				child.queue_free()
				break

# =============================================================================
# RESOURCE DROPS
# =============================================================================

## Spawn resource drops from destroyed object
func spawn_resource_drops(drops: Array, position: Vector3) -> void:
	for drop in drops:
		var item_id = drop.get("item_id", "")
		var quantity = drop.get("quantity", 1)
		var network_id = drop.get("network_id", 0)

		if item_id.is_empty():
			continue

		# Spawn resource item
		var ResourceItem = preload("res://shared/environmental/resource_item.tscn")
		var item = ResourceItem.instantiate()
		item.item_id = item_id
		item.quantity = quantity
		item.network_id = network_id

		# Randomize position slightly
		var offset = Vector3(
			randf_range(-0.5, 0.5),
			0.5,
			randf_range(-0.5, 0.5)
		)
		item.global_position = position + offset

		client.world.add_child(item)

## Remove a resource item (after pickup)
func remove_resource_item(network_id: int) -> void:
	for child in client.world.get_children():
		if "network_id" in child and child.network_id == network_id:
			child.queue_free()
			break

# =============================================================================
# DYNAMIC OBJECTS (Fallen Logs, Split Logs)
# =============================================================================

## Spawn a fallen log
func spawn_fallen_log(network_id: int, position: Array, rotation_y: float) -> void:
	var FallenLog = preload("res://shared/environmental/fallen_log.tscn")
	var log = FallenLog.instantiate()
	log.name = "FallenLog_%d" % network_id
	log.global_position = Vector3(position[0], position[1], position[2])
	log.rotation.y = rotation_y
	log.network_id = network_id

	client.world.add_child(log)
	print("[Client] Spawned fallen log %d" % network_id)

## Spawn split logs
func spawn_split_logs(parent_network_id: int, logs: Array) -> void:
	for log_data in logs:
		var network_id = log_data.get("network_id", 0)
		var position = log_data.get("position", [0, 0, 0])
		var rotation_y = log_data.get("rotation_y", 0.0)

		var SplitLog = preload("res://shared/environmental/split_log.tscn")
		var log = SplitLog.instantiate()
		log.name = "SplitLog_%d" % network_id
		log.global_position = Vector3(position[0], position[1], position[2])
		log.rotation.y = rotation_y
		log.network_id = network_id

		client.world.add_child(log)

	print("[Client] Spawned %d split logs from parent %d" % [logs.size(), parent_network_id])

## Destroy a dynamic object
func destroy_dynamic_object(object_name: String) -> void:
	var obj = client.world.get_node_or_null(object_name)
	if obj:
		if obj.has_method("play_destroy_effect"):
			obj.play_destroy_effect()
		obj.queue_free()
		print("[Client] Destroyed dynamic object: %s" % object_name)

## Update dynamic object damage state
func on_dynamic_object_damaged(object_name: String, health: float, max_health: float) -> void:
	var obj = client.world.get_node_or_null(object_name)
	if obj:
		if "health" in obj:
			obj.health = health
		if "max_health" in obj:
			obj.max_health = max_health
		if obj.has_method("update_damage_visual"):
			obj.update_damage_visual()

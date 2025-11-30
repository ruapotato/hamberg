class_name ClientPlayerManager
extends RefCounted

## ClientPlayerManager - Handles player spawning, despawning, and state sync

var client: Node

func _init(c: Node) -> void:
	client = c

# =============================================================================
# PLAYER SPAWNING
# =============================================================================

## Spawn a player (local or remote)
func spawn_player(peer_id: int, player_name: String, spawn_pos: Vector3) -> void:
	if peer_id in client.remote_players:
		print("[Client] Player %d already spawned" % peer_id)
		return

	var player = client.player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.player_name = player_name
	player.global_position = spawn_pos

	var is_local = (peer_id == multiplayer.get_unique_id())
	player.is_local_player = is_local

	client.world.add_child(player)

	if is_local:
		client.local_player = player
		client._setup_camera_follow()
		client._setup_inventory_ui()
		print("[Client] Spawned LOCAL player at %s" % spawn_pos)
	else:
		client.remote_players[peer_id] = player
		print("[Client] Spawned REMOTE player %s at %s" % [player_name, spawn_pos])

## Despawn a player
func despawn_player(peer_id: int) -> void:
	if peer_id in client.remote_players:
		var player = client.remote_players[peer_id]
		player.queue_free()
		client.remote_players.erase(peer_id)
		print("[Client] Despawned remote player %d" % peer_id)

## Handle player respawn
func handle_player_respawned(spawn_pos: Vector3) -> void:
	if client.local_player and client.local_player.has_method("respawn_at"):
		client.local_player.respawn_at(spawn_pos)
		print("[Client] Local player respawned at %s" % spawn_pos)

# =============================================================================
# PLAYER STATE SYNC
# =============================================================================

## Receive player states from server
func receive_player_states(states: Dictionary) -> void:
	for peer_id in states:
		if peer_id == multiplayer.get_unique_id():
			continue  # Skip local player

		if peer_id in client.remote_players:
			var player = client.remote_players[peer_id]
			var state = states[peer_id]
			player.apply_server_state(state)

## Receive hit effect
func receive_hit(position: Vector3, _damage: float) -> void:
	# Spawn hit effect at position
	var HitEffectScene = preload("res://shared/effects/hit_effect.tscn")
	var effect = HitEffectScene.instantiate()
	client.world.add_child(effect)
	effect.global_position = position

## Receive enemy damage notification
func receive_enemy_damage(enemy_network_id: int, damage: float, new_health: float, hit_position: Vector3, knockback_dir: Vector3) -> void:
	# Find enemy by network_id
	for enemy in client.get_tree().get_nodes_in_group("enemies"):
		if enemy.network_id == enemy_network_id:
			# Apply damage visually
			if enemy.has_method("show_damage_effect"):
				enemy.show_damage_effect(damage, hit_position)

			# Update health
			enemy.health = new_health

			# Apply knockback
			if knockback_dir.length() > 0:
				enemy.velocity += knockback_dir * 5.0

			break

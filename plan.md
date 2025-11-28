# NPC Networking Redesign Plan

## Problem Summary
The current NPC system has two critical issues:
1. **Enemies don't hurt players** - Server runs AI but damage code checks `my_peer_id` which is `1` (server), never matching the target player's client peer_id
2. **Enemies jerk around** - Poor client-side interpolation with no velocity prediction

## Root Cause
The code mixes two incompatible models:
- **Server-Authoritative**: Server runs AI/physics (correct - server has terrain collision)
- **Local-First Damage**: Code expects clients to handle their own damage (broken - clients don't run AI)

## Solution: Pure Server-Authoritative Model

### Step 1: Fix Server-Side Damage Detection
**File:** `shared/enemies/enemy.gd`

Change `_attack_player()` to:
1. Remove the `my_peer_id != target_peer_id` check (server handles all damage)
2. Instead of calling `player.take_damage()` directly, send an RPC to the target client
3. Use existing `NetworkManager.rpc_enemy_damage_player.rpc_id(target_peer_id, damage, attacker_id, knockback_dir)`

```gdscript
func _attack_player(player: CharacterBody3D) -> void:
    # SERVER-AUTHORITATIVE: Server detects hit, sends damage to client
    if is_remote:
        return  # Only server runs AI

    # Extract peer_id from player name
    var player_name = player.name
    if not player_name.begins_with("Player_"):
        return
    var target_peer_id = player_name.substr(7).to_int()

    # Calculate damage and knockback
    var knockback_dir = (player.global_position - global_position).normalized()
    var damage = weapon_data.damage
    var knockback = weapon_data.knockback

    # Send damage RPC to the specific client
    var kb_array = [knockback_dir.x * knockback, knockback_dir.y * knockback, knockback_dir.z * knockback]
    NetworkManager.rpc_enemy_damage_player.rpc_id(target_peer_id, damage, network_id, kb_array)
```

### Step 2: Fix Thrown Rock Damage
**File:** `shared/enemies/thrown_rock.gd`

Current code at line 98-102 calls `body.take_damage()` directly, but on the server this applies to the server's player tracking node, not the client's actual player. Fix:

```gdscript
func _on_body_entered(body: Node3D) -> void:
    # Don't hit the thrower
    if body == thrower:
        return

    # Don't hit other enemies
    if body.is_in_group("enemies"):
        return

    # Hit a player!
    if body.is_in_group("players"):
        print("[ThrownRock] Hit player!")

        # Only server sends damage RPCs
        if multiplayer.get_unique_id() == 1:  # Am I server?
            # Extract peer_id from player name
            if body.name.begins_with("Player_"):
                var target_peer_id = body.name.substr(7).to_int()
                var knockback_dir = velocity.normalized()
                knockback_dir.y = 0.2
                knockback_dir = knockback_dir.normalized()
                var kb_array = [knockback_dir.x * 5, knockback_dir.y * 5, knockback_dir.z * 5]
                NetworkManager.rpc_enemy_damage_player.rpc_id(target_peer_id, damage, -1, kb_array)

        # Destroy the rock
        queue_free()
```

### Step 3: Improve Client Interpolation
**File:** `shared/enemies/enemy.gd`

Add velocity prediction and smoother interpolation:
```gdscript
# Add new variables
var sync_velocity: Vector3 = Vector3.ZERO
var last_sync_position: Vector3 = Vector3.ZERO
var last_sync_time: float = 0.0
const SNAP_DISTANCE: float = 5.0  # Snap if too far from sync position

func _run_client_follower(delta: float) -> void:
    if sync_position == Vector3.ZERO:
        return

    # Calculate time since last sync
    var current_time = Time.get_ticks_msec() / 1000.0
    var time_since_sync = current_time - last_sync_time

    # Predict position using velocity
    var predicted_pos = sync_position + sync_velocity * time_since_sync

    # Smooth interpolation toward predicted position
    var distance = global_position.distance_to(predicted_pos)

    if distance > SNAP_DISTANCE:
        # Too far - snap to position
        global_position = predicted_pos
    else:
        # Smooth interpolation
        var lerp_speed = clampf(8.0 * delta, 0.1, 0.5)
        global_position = global_position.lerp(predicted_pos, lerp_speed)

    # Smooth rotation
    rotation.y = lerp_angle(rotation.y, sync_rotation_y, 5.0 * delta)

func apply_server_state(pos: Vector3, rot_y: float, state: int, hp: float, target_peer: int = 0) -> void:
    # Calculate velocity from position delta
    var current_time = Time.get_ticks_msec() / 1000.0
    if last_sync_time > 0:
        var dt = current_time - last_sync_time
        if dt > 0.01:
            sync_velocity = (pos - last_sync_position) / dt

    last_sync_position = pos
    last_sync_time = current_time

    # Store sync state
    sync_position = pos
    sync_rotation_y = rot_y
    # ... rest of existing code
```

### Step 4: Clean Up Animation Triggers
**File:** `shared/enemies/enemy.gd`

Ensure animations play properly on clients:
```gdscript
func _run_client_follower(delta: float) -> void:
    # ... existing interpolation code ...

    # Detect AI state changes for animation triggers
    if sync_ai_state != ai_state:
        var prev_state = ai_state
        ai_state = sync_ai_state as AIState

        # Trigger attack animations on state change
        match ai_state:
            AIState.ATTACKING:
                if prev_state != AIState.ATTACKING:
                    start_attack_animation()
            AIState.THROWING:
                if prev_state != AIState.THROWING:
                    start_throw_animation()

    # Update animations based on movement
    update_animations(delta)
```

### Step 5: Remove Client-Side AI Remnants
**File:** `shared/enemies/enemy.gd`

Clean up the host/remote flags since we're using pure server-authoritative:
- Keep `is_remote` flag (true on clients, false on server)
- Remove `is_host` and `host_peer_id` flags (no longer needed)
- Remove `_send_position_report()` function (server doesn't need client reports)

### Step 6: Verify RPC Exists
**File:** `shared/network_manager.gd`

The `rpc_enemy_damage_player` RPC already exists at line 788:
```gdscript
@rpc("authority", "call_remote", "reliable")
func rpc_enemy_damage_player(damage: float, attacker_id: int, knockback_dir: Array) -> void:
```

And `client.gd` already handles it at line 548:
```gdscript
func receive_enemy_damage(damage: float, attacker_id: int, knockback_dir: Vector3) -> void:
    if local_player and local_player.has_method("take_damage"):
        local_player.take_damage(damage, attacker_id, knockback_dir)
```

## Implementation Order
1. Fix `_attack_player()` to send RPC instead of local damage check
2. Fix `_throw_rock()` / `thrown_rock.gd` to send RPC on server-side hit
3. Improve client interpolation with velocity prediction
4. Clean up animation triggers
5. Remove unused host-client code

## Testing
1. Start server and client
2. Find an enemy (wait for spawn or walk around)
3. Let enemy attack you - verify damage appears on client
4. Let enemy throw rock - verify rock damage works
5. Watch enemy movement - should be smooth, not jerky

# Valheim Clone - Multiplayer Survival Game

A trust-based multiplayer survival game built with Godot 4 and a networking-first architecture. Inspired by Valheim, this game prioritizes responsive gameplay and community-driven experiences.

## Phase 1: Core Networking Foundation ✅

This phase implements the fundamental multiplayer infrastructure:

- ✅ Dedicated server support (headless mode)
- ✅ Client connection with UI
- ✅ Player spawning and despawning
- ✅ Client-side prediction for movement
- ✅ Server-authoritative player management
- ✅ Basic character controller (WASD + Jump + Sprint)
- ✅ Network state synchronization

## Quick Start

### Prerequisites

- Godot 4.3+ installed (with `godot` or `./godot.linuxbsd.editor.x86_64` in PATH)
- Linux/Mac/Windows with terminal access

### Option 1: Launch Dedicated Server

```bash
# Launch headless server on default port (7777)
./godot.linuxbsd.editor.x86_64 --headless -- --server

# Or with custom port (via environment variable)
GAME_PORT=8888 MAX_PLAYERS=20 ./godot.linuxbsd.editor.x86_64 --headless -- --server
```

**Server Console Commands:**
- `players` - List connected players
- `kick <id>` - Kick a player by peer ID
- `save` - Save the world (not implemented yet)
- `shutdown` - Stop the server

### Option 2: Launch Client

```bash
# Launch client with UI
./godot.linuxbsd.editor.x86_64

# In the connection UI, enter:
# - Player Name: YourName
# - Server IP: 127.0.0.1 (or server IP)
# - Port: 7777
# Click "Connect"
```

### Option 3: Singleplayer (Auto-Local Server)

```bash
# Launch in singleplayer mode (auto-starts local server + client)
./godot.linuxbsd.editor.x86_64 -- --singleplayer
```

### Option 4: Testing with Multiple Clients

Open 3 terminals:

```bash
# Terminal 1 - Launch server
./godot.linuxbsd.editor.x86_64 --headless -- --server

# Terminal 2 - Launch client 1
./godot.linuxbsd.editor.x86_64

# Terminal 3 - Launch client 2
./godot.linuxbsd.editor.x86_64
```

Connect both clients to `127.0.0.1:7777` and you should see each other!

## Controls

**Movement:**
- `W` `A` `S` `D` - Move forward/left/backward/right
- `Space` - Jump
- `Left Shift` - Sprint

**Future Controls:**
- `Left Click` - Attack (Phase 2+)
- `E` - Interact (Phase 2+)
- `Tab` - Inventory (Phase 2+)

## Project Structure

```
project/
├── server/              # Server-only scripts
│   └── server.gd       # Main server logic, player management
├── client/              # Client-only scripts
│   └── client.gd       # Connection UI, client-side rendering
├── shared/              # Shared game logic (client + server)
│   ├── network_manager.gd  # Network utilities (autoload)
│   ├── player.gd       # Player entity with prediction
│   └── player.tscn     # Player scene
├── scenes/              # Scene files
│   ├── main.tscn       # Entry point
│   ├── server.tscn     # Server scene
│   └── client.tscn     # Client scene
├── resources/           # Resource definitions (.tres)
├── assets/              # Models, textures, audio
└── project.godot        # Project configuration
```

## Network Architecture

### Core Principles

**Trust-Based Model:**
- Designed for co-op play with trusted communities
- Client-side hit detection (instant feedback)
- Server validates important actions (inventory, progression)
- Prioritizes gameplay feel over anti-cheat

**Authority Split:**

| System | Authority | Reason |
|--------|-----------|--------|
| Player Movement | Client (predicted) | Responsive controls |
| Combat/Hits | Client (reported) | Instant feedback |
| Damage Application | Server | Prevent obvious exploits |
| Inventory | Server | Prevent item duplication |
| World Persistence | Server | Single source of truth |
| Enemy Spawning | Server | Consistent experience |
| Terrain Editing | Server (validated) | Prevent griefing |

### Network Flow

**Player Connection:**
1. Client connects to server (ENet)
2. Client sends player name
3. Server registers player, assigns peer ID
4. Server spawns player entity
5. Server broadcasts new player to all clients
6. Clients spawn visual representation

**Player Movement (Client Prediction):**
1. Client gathers input (WASD, Jump, etc.)
2. Client predicts movement locally (instant response)
3. Client stores input in history
4. Client sends input to server
5. Server simulates same input
6. Server broadcasts authoritative states
7. Remote clients interpolate for smooth rendering

**Player Disconnection:**
1. Server detects disconnect
2. Server despawns player entity
3. Server broadcasts despawn to all clients
4. Clients remove player from world

### RPC Patterns

**Client → Server (Request pattern):**
```gdscript
# CLIENT
func use_item(slot: int):
    request_use_item.rpc_id(1, slot)  # Send to server (ID 1)

# SERVER
@rpc("any_peer", "call_remote", "reliable")
func request_use_item(slot: int):
    var peer_id = multiplayer.get_remote_sender_id()
    validate_and_apply(peer_id, slot)
```

**Server → All Clients (Broadcast pattern):**
```gdscript
# SERVER
func apply_damage(target_id: int, damage: float):
    # ... apply damage ...
    broadcast_damage.rpc(target_id, damage)  # Tell all clients

# CLIENT
@rpc("authority", "call_remote", "reliable")
func broadcast_damage(target_id: int, damage: float):
    show_damage_effect(target_id, damage)
```

**Client → Server → All Clients (Report pattern):**
```gdscript
# CLIENT (trust model)
func on_attack_hit(target_id: int):
    var damage = calculate_damage()
    show_hit_effect()  # Instant local feedback
    report_hit.rpc_id(1, target_id, damage)

# SERVER
@rpc("any_peer")
func report_hit(target_id: int, damage: float):
    apply_damage(target_id, damage)  # Trust client
    broadcast_hit.rpc(target_id, damage)  # Replicate to others
```

## Key Features

### Implemented (Phase 1)

✅ **Dual-Mode Launch System**
- Headless server mode (`--server`)
- Client mode (default)
- Singleplayer mode (`--singleplayer`)
- Command-line argument parsing

✅ **Server Management**
- ENet server initialization
- Configurable port and max players
- Player connection/disconnection handling
- Server console (placeholder for commands)

✅ **Client Connection**
- Connection UI (IP, Port, Player Name)
- Connection handshake
- Network status display

✅ **Player Entity System**
- Server spawns players on connect
- Client-side prediction for movement
- Server broadcasts player states
- Interpolation for remote players
- Automatic despawn on disconnect

✅ **Character Controller**
- WASD movement with physics
- Jump and gravity
- Sprint modifier
- CharacterBody3D with collision

### Planned (Phase 2+)

🔲 **Voxel Terrain System**
- Integration with Godot Voxel Tools
- Server-side chunk generation
- Chunk streaming to clients
- VoxelTerrainMultiplayerSynchronizer
- Terrain editing (client request → server validate → broadcast)
- Multiple biomes (Meadows, Forest, Mountains)

🔲 **Combat System**
- Melee weapons
- Ranged weapons
- Client-side hit detection
- Damage calculation
- Death and respawn

🔲 **Inventory & Crafting**
- Server-authoritative inventory
- Item pickup/drop
- Crafting system
- Resource gathering

🔲 **Building System**
- Placeable structures
- Building pieces (walls, floors, roofs)
- Structural integrity
- Building permissions

🔲 **Enemy AI**
- Server-controlled enemies
- Pathfinding with Navigation
- AI behaviors
- Loot drops

🔲 **World Persistence**
- Save/load system
- Chunk data persistence
- Player data persistence
- Building persistence

## Performance Targets

- **Tick Rate:** 30 Hz server simulation
- **Max Players:** 10-20 (configurable)
- **Render Distance:** TBD (depends on voxel terrain)
- **Target FPS:** 60 FPS client-side

## Testing

### Verify Server Launch

```bash
./godot.linuxbsd.editor.x86_64 --headless -- --server
```

Expected output:
```
[NetworkManager] Ready
[Server] Server node ready
[Main] Starting Valheim Clone...
[Main] Command line args: [...]
[Main] Running headless - defaulting to server mode
[Main] Launching dedicated server...
[NetworkManager] Server started on port 7777 (max players: 10)
[Server] ===========================================
[Server] Server is now running!
[Server] Port: 7777
[Server] Max players: 10
[Server] ===========================================
```

### Verify Client Connection

1. Launch server in one terminal
2. Launch client in another terminal
3. Enter connection details in UI
4. Click "Connect"

Expected:
- Client shows "Connected!" message
- Server logs `[Server] Player joined: PlayerName (ID: X)`
- Client HUD appears with controls

### Verify Multiplayer Movement

1. Launch server
2. Connect 2+ clients
3. Move with WASD in one client
4. Observe movement in other client windows

Expected:
- Local player movement feels instant and responsive
- Remote players appear and move smoothly
- No major rubber-banding or jitter

## Development Notes

### Adding New Features

**Server-Authoritative Feature (e.g., Inventory):**
1. Add state to server/server.gd (e.g., `player_inventories: Dictionary`)
2. Add RPC: `@rpc("any_peer") func request_inventory_action()`
3. Validate request in RPC handler
4. Apply changes server-side
5. Broadcast result: `sync_inventory.rpc_id(peer_id, inventory_data)`

**Client-Reported Feature (e.g., Hit Detection):**
1. Detect action client-side (e.g., raycast for hit)
2. Show instant feedback (effects, sounds)
3. Report to server: `report_action.rpc_id(1, action_data)`
4. Server trusts and replicates: `broadcast_action.rpc(action_data)`

### Debugging Network Issues

**Enable verbose networking logs:**
```gdscript
# In network_manager.gd or main.gd
ProjectSettings.set_setting("debug/settings/network/max_queued_messages", 512)
```

**Check peer connectivity:**
```gdscript
# In console or script
print(multiplayer.get_peers())  # List of connected peer IDs
```

**Monitor network stats:**
- Ping display in HUD (placeholder)
- Check ENet statistics via `multiplayer.multiplayer_peer`

## Known Limitations

- **No player camera rotation yet** - Third-person camera is fixed
- **No terrain** - Players spawn in the void (floor at Y=0 has invisible collision)
- **No visuals for ground** - Using CharacterBody3D collision only
- **Console input incomplete** - Server commands need proper stdin handling
- **No server reconciliation** - Client prediction always wins (trust model)

## Next Steps for Phase 2

1. **Install Godot Voxel Tools module**
   - Build Godot with voxel tools, or use pre-built binary
   - Verify voxel classes are available

2. **Add VoxelLodTerrain to server and client**
   - Server: Authoritative terrain data
   - Client: Visual representation only

3. **Implement VoxelTerrainMultiplayerSynchronizer**
   - Automatic chunk streaming
   - Edit synchronization

4. **Add terrain generator**
   - Noise-based height map
   - Multiple biomes
   - Caves and overhangs

5. **Implement terrain editing**
   - Client: Detect edit intent (mining, placing)
   - Client → Server: Request edit with position and type
   - Server: Validate player has tool and is in range
   - Server: Apply edit to terrain
   - Server → All Clients: Broadcast terrain change

## Contributing

This is a learning project! Feel free to:
- Experiment with the code
- Add features for your own game
- Share improvements

## License

MIT License - Free to use for your own projects!

## Credits

- Built with [Godot Engine 4.3+](https://godotengine.org/)
- Networking: ENetMultiplayerPeer
- Terrain (Phase 2): [Godot Voxel Tools](https://github.com/Zylann/godot_voxel)
- Inspired by [Valheim](https://www.valheimgame.com/)

---

**Have fun building your survival game!** 🎮⛏️🌲

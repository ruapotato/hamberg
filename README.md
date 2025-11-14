# Hamberg 🏔️⚔️

**An open source multiplayer survival game inspired by Valheim**

Hamberg is a co-op survival and crafting game built with Godot 4 and a networking-first architecture. Explore procedurally generated worlds, gather resources, build settlements, and battle mythical creatures with your friends in a trust-based multiplayer environment.

The name "Hamberg" is a tribute to the developers' origins - a fusion of **Hamner** and **Inberg**.

---

## 🎮 Vision

Hamberg aims to capture the magic of Valheim while being:
- **Open Source** - Fully transparent, community-driven development
- **Moddable** - Clean, documented code designed for extensibility
- **Responsive** - Client-side prediction for instant, satisfying gameplay
- **Community-Focused** - Trust-based networking for cooperative play with friends
- **Cross-Platform** - Linux, Windows, and Mac support via Godot

---

## 🚀 Current Status: Phase 1 Complete ✅

**Phase 1: Core Networking Foundation** is fully implemented and tested!

### What Works Now
- ✅ Dedicated server support (headless mode capable)
- ✅ Client connection with UI
- ✅ Player spawning and despawning
- ✅ Client-side prediction for responsive movement
- ✅ Server-authoritative player management
- ✅ Physics-based character controller (WASD, jump, sprint)
- ✅ Network state synchronization
- ✅ Multiple clients connecting and seeing each other

### Try It Out!

```bash
# Terminal 1 - Launch server
./launch_server.sh

# Terminal 2 - Launch client
./launch_client.sh

# Terminal 3 - Launch another client
./launch_client.sh
```

Connect both clients to `127.0.0.1:7777` and see each other move around in real-time!

---

## 📋 Roadmap

### Phase 1: Core Networking ✅ **COMPLETE**
- [x] Dual-mode launch (server/client/singleplayer)
- [x] Client-side prediction
- [x] Player spawning and movement
- [x] Network synchronization

### Phase 2: Voxel Terrain 🔨 **IN PROGRESS**
- [ ] Integration with Godot Voxel Tools
- [ ] Procedural terrain generation (noise-based)
- [ ] Multiple biomes (Meadows, Forest, Mountains)
- [ ] Chunk streaming to clients
- [ ] Terrain editing (mining, building)
- [ ] Server-authoritative terrain validation

### Phase 3: Combat & AI 🗡️
- [ ] Melee combat system
- [ ] Ranged weapons (bow, spear)
- [ ] Client-side hit detection
- [ ] Enemy AI with pathfinding
- [ ] Boss encounters
- [ ] Death and respawn mechanics

### Phase 4: Crafting & Building 🏗️
- [ ] Resource gathering
- [ ] Crafting stations
- [ ] Building system (walls, floors, roofs)
- [ ] Structural integrity
- [ ] Storage and chests

### Phase 5: Progression & Content 📈
- [ ] Player skills and leveling
- [ ] Equipment and armor
- [ ] Food and cooking
- [ ] World persistence (save/load)
- [ ] Portals and fast travel

### Phase 6: Polish & Release 🎨
- [ ] Audio system (music, SFX)
- [ ] Particle effects
- [ ] UI/UX improvements
- [ ] Performance optimization
- [ ] Steam/Itch.io release

---

## 🛠️ Quick Start Guide

### Prerequisites

You'll need:
- **Godot 4.3+** with Voxel Tools module ([download here](https://github.com/Zylann/godot_voxel))
- **Linux/Mac/Windows** with terminal/command prompt access
- **Git** (to clone the repository)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/hamberg.git
cd hamberg

# Copy your Godot binary to the project folder
cp /path/to/godot.linuxbsd.editor.x86_64 ./

# Make launch scripts executable (Linux/Mac)
chmod +x launch_*.sh
```

### Launch Options

**Option 1: Dedicated Server**
```bash
./launch_server.sh
# OR manually:
./godot.linuxbsd.editor.x86_64 --headless -- --server
```

**Option 2: Client**
```bash
./launch_client.sh
# OR manually:
./godot.linuxbsd.editor.x86_64
```

**Option 3: Singleplayer** (auto-local server)
```bash
./launch_singleplayer.sh
# OR manually:
./godot.linuxbsd.editor.x86_64 -- --singleplayer
```

### Server Configuration

Set environment variables for custom configuration:
```bash
GAME_PORT=8888 MAX_PLAYERS=20 ./launch_server.sh
```

**Server Console Commands:**
- `players` - List connected players
- `kick <id>` - Kick a player by peer ID
- `save` - Save the world (coming soon)
- `shutdown` - Stop the server

---

## 🎯 Controls

| Action | Key |
|--------|-----|
| Move Forward | W |
| Move Left | A |
| Move Backward | S |
| Move Right | D |
| Jump | Space |
| Sprint | Left Shift |
| Attack | Left Click *(coming soon)* |
| Interact | E *(coming soon)* |
| Inventory | Tab *(coming soon)* |

---

## 🏗️ Project Structure

```
hamberg/
├── server/              # Server-only scripts
│   └── server.gd       # Player management, world authority
├── client/              # Client-only scripts
│   └── client.gd       # UI, rendering, local player
├── shared/              # Shared game logic
│   ├── network_manager.gd  # RPC relay & network state (autoload)
│   ├── player.gd       # Player entity with prediction
│   ├── player.tscn     # Player scene
│   └── test_world.tscn # Test environment
├── scenes/              # Scene files
│   ├── main.tscn       # Entry point
│   ├── server.tscn     # Server scene
│   └── client.tscn     # Client scene with UI
├── resources/           # Resource definitions (.tres)
├── assets/              # Models, textures, audio
├── main.gd              # Mode detection (server/client/SP)
├── project.godot        # Godot project config
└── launch_*.sh          # Helper launch scripts
```

---

## 🌐 Network Architecture

Hamberg uses a **trust-based networking model** designed for cooperative play with friends.

### Design Philosophy

**Responsive Gameplay > Anti-Cheat**

We prioritize instant feedback and smooth gameplay over paranoid anti-cheat. This is a co-op game meant to be played with communities you trust, not a competitive game.

### Authority Split

| System | Authority | Why |
|--------|-----------|-----|
| Player Movement | **Client** (predicted) | Instant response, feels good |
| Combat/Hits | **Client** (reported) | Immediate hit feedback |
| Damage Application | **Server** | Prevent obvious exploits |
| Inventory | **Server** | No item duplication |
| World Persistence | **Server** | Single source of truth |
| Terrain Editing | **Server** (validated) | Prevent griefing |
| Enemy AI | **Server** | Consistent behavior |

### Network Patterns

**Client Prediction:**
```gdscript
# CLIENT: Predict movement locally, send input to server
func _physics_process(delta):
    var input = gather_input()
    apply_movement(input, delta)  # Instant local response
    send_input_to_server.rpc_id(1, input)
```

**Trust-Based Hit Detection:**
```gdscript
# CLIENT: Detect hit, show effect, report to server
func on_attack():
    var hit = raycast_weapon()
    if hit:
        show_hit_effect(hit.position)  # Instant feedback
        report_hit.rpc_id(1, hit.target_id, damage)

# SERVER: Trust client, apply damage, broadcast
@rpc("any_peer")
func report_hit(target_id, damage):
    apply_damage(target_id, damage)
    broadcast_hit.rpc(target_id, damage)
```

**Server Authority (Inventory):**
```gdscript
# CLIENT: Request action
func use_item(slot):
    request_use_item.rpc_id(1, slot)

# SERVER: Validate and apply
@rpc("any_peer")
func request_use_item(slot):
    if validate_use(player_id, slot):
        apply_use(player_id, slot)
        sync_inventory.rpc_id(player_id, inventory)
```

### RPC Relay Pattern

All RPCs go through `NetworkManager` (autoload) to ensure they work across client/server boundaries:

```gdscript
# CLIENT → SERVER
NetworkManager.rpc_register_player.rpc_id(1, player_name)

# SERVER → CLIENTS
NetworkManager.rpc_spawn_player.rpc(peer_id, name, pos)
```

---

## 🧪 Testing

### Verify Server Launch

```bash
./launch_server.sh
```

**Expected output:**
```
[Server] ===========================================
[Server] Server is now running!
[Server] Port: 7777
[Server] Max players: 10
[Server] ===========================================
```

### Verify Multiplayer

1. Launch server in Terminal 1
2. Launch client in Terminal 2
3. Connect to `127.0.0.1:7777`
4. Launch another client in Terminal 3
5. Connect second client

**Expected:**
- Both clients see each other as blue capsules
- Movement is smooth and responsive
- No errors in console

### Troubleshooting

**"Port already in use"**
```bash
GAME_PORT=8888 ./launch_server.sh
# Update clients to connect to port 8888
```

**"Connection failed"**
- Make sure server is running first
- Check firewall settings
- Try `127.0.0.1` for local testing

**"Can't see other players"**
- Check server logs for player join messages
- Make sure both clients connected successfully
- Try moving around - they might spawn at the same spot

---

## 🤝 Contributing

Hamberg is open source and welcomes contributions!

### Ways to Contribute

- 🐛 **Report bugs** - Open an issue with reproduction steps
- ✨ **Suggest features** - Share your ideas in discussions
- 🔧 **Submit PRs** - Fix bugs, add features, improve docs
- 🎨 **Create assets** - Models, textures, sounds
- 📖 **Improve docs** - Help others get started

### Development Guidelines

1. **Read the code** - It's heavily commented to explain networking patterns
2. **Test locally** - Use the launch scripts to verify changes
3. **Follow the architecture** - Keep client/server/shared separation clean
4. **Document your code** - Explain networking and game logic
5. **Keep it modular** - Design for extensibility

### Getting Help

- 💬 **Discord** - *(coming soon)*
- 🐛 **Issues** - For bugs and technical questions
- 💡 **Discussions** - For ideas and general chat

---

## 📚 Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Quick testing guide
- **[Network Architecture](#-network-architecture)** - Deep dive into networking
- **[Godot Voxel Tools Docs](https://voxel-tools.readthedocs.io/)** - For terrain (Phase 2)
- **Code Comments** - Read the source, it's well documented!

---

## 🎓 Learning Resources

Building Hamberg? These resources helped us:

- [Godot Multiplayer Docs](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [Godot Voxel Tools](https://github.com/Zylann/godot_voxel)
- [Client-Side Prediction](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html)
- [Valheim (inspiration)](https://www.valheimgame.com/)

---

## 📜 License

**MIT License** - See [LICENSE](LICENSE) for details

Hamberg is free and open source. Use it, modify it, learn from it, build your own game!

---

## 🙏 Credits

**Built with:**
- [Godot Engine 4.x](https://godotengine.org/) - Open source game engine
- [Godot Voxel Tools](https://github.com/Zylann/godot_voxel) - Terrain system (Phase 2)
- [ENet](http://enet.bespin.org/) - Reliable UDP networking
- [Claude Code](https://claude.com/claude-code) - AI pair programming assistant

**Inspired by:**
- [Valheim](https://www.valheimgame.com/) - The gold standard for co-op survival
- The indie survival game community

**Created by:**
- The Hamberg community 💙

---

## 🚀 Next Steps

**Ready to dive in?**

1. Try Phase 1 - Run the multiplayer demo
2. Read the code - See how networking works
3. Join development - Help build Phase 2 (voxel terrain!)
4. Share feedback - What should we build next?

**Join the journey to build an open source Valheim!** ⚔️🏔️

---

<p align="center">
  <strong>Hamberg - Open Source Survival, Built Together</strong><br>
  <em>A fusion of Hamner and Inberg</em>
</p>

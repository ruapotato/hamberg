# Hamberg 🏔️⚔️

**An open source multiplayer survival game inspired by Valheim**

Hamberg is a co-op survival and crafting game built with Godot 4 and a networking-first architecture. Explore procedurally generated worlds, gather resources, build settlements, and battle mythical creatures with your friends in a trust-based multiplayer environment.

The name "Hamberg" is a tribute to the developers' origins - a fusion of **Hamner** and **Inberg**.

---

## 🎮 Vision

**A Fantasy Survival Adventure**

Hamberg is an open-source multiplayer survival game that blends the co-op magic of Valheim with a unique fantasy aesthetic. Explore otherworldly biomes filled with mysterious creatures, wield magical staffs powered by Brain Power (BP), and descend into crystalline caves and nightmarish dimensions.

**Core Pillars:**
- **Dark Fantasy World** - Explore surreal biomes: serene purple meadows, bioluminescent dark forests, toxic poison pits, crystalline caverns, and fleshy void dimensions
- **Brain-Powered Magic** - Harness BP (Brain Power) alongside traditional HP and Stamina to cast spells, summon shields, and wield elemental weapons
- **Otherworldly Creatures** - Face ethereal dandelion bombers, rock trolls, gahnomes, and horrors from the void
- **Open Source & Moddable** - Fully transparent, community-driven development with clean, documented code
- **Responsive Multiplayer** - Client-side prediction for instant, satisfying co-op gameplay
- **Trust-Based Networking** - Designed for cooperative play with friends, not paranoid anti-cheat
- **Cross-Platform** - Linux, Windows, and Mac support via Godot Engine

---

## 🚀 Current Status: Phase 4 In Progress 🏗️

**Phase 4: Building, Crafting & Inventory** is now partially implemented!

### What Works Now
- ✅ Dedicated server support (headless mode capable)
- ✅ Client connection with UI
- ✅ Player spawning and despawning
- ✅ Client-authoritative player positions with validation
- ✅ Server-authoritative environmental object management
- ✅ Physics-based character controller (WASD, jump, sprint)
- ✅ **Valheim-style player body** (segmented body with programmatic animations)
- ✅ **Proper crosshair** (positioned top-right for better visibility)
- ✅ Procedural voxel terrain generation (Godot Voxel Tools)
- ✅ Multi-biome world generation (Meadow, Dark Forest, Poison Pit, Crystal Peaks, Hellscape, The Void)
- ✅ Server-authoritative environmental objects (trees, rocks, grass)
- ✅ Chunk-based streaming with load/unload
- ✅ Deterministic procedural generation (consistent across clients)
- ✅ Smart persistence system (procedural + database for modified chunks)
- ✅ Multiple clients with synchronized world state
- ✅ **Multi-world system** (unique world names and seeds)
- ✅ **Per-world storage** (isolated save data)
- ✅ **Resource gathering** (punch trees/rocks to destroy them)
- ✅ **Environmental object health** (trees: 100 HP, rocks: 150 HP)
- ✅ **Resource drops** (wood from trees, stone from rocks)
- ✅ **Inventory system** (30 slots, hotbar, item pickup)
- ✅ **Workbench** (crafting station with 20m build radius)
- ✅ **Building system** (walls, floors, doors, beams, roofs with snap points)
- ✅ **Workbench requirement** (must be near workbench to build)
- ✅ **Health system** (100 HP, damage from enemies)
- ✅ **Stamina system** (100 stamina, drains on sprint/jump/attack, regenerates)
- ✅ **Brain Power system** (100 BP, used by magic weapons instead of stamina, slower regen)
- ✅ **Enemy AI** (Gahnomes spawn naturally, chase and attack players)
- ✅ **Equipment system** (Valheim-style: right-click to equip, items stay in inventory)
- ✅ **Weapons & Combat** (5 weapons: stone sword, axe, knife, fire wand, bow)
- ✅ **Shields & Blocking** (3 shields: buckler, round shield, tower shield)
- ✅ **Parry system** (block at right moment to negate damage and stun attacker)
- ✅ **Weapon combos** (knife 3-hit combo: slash, slash, powerful jab)
- ✅ **Special attacks** (middle-mouse: knife lunge, sword stab, fire wand area effect)
- ✅ **Projectile system** (fireballs from fire wand, shared for players/enemies)
- ✅ **Crafting menu** (E on workbench, item discovery tracking per-character)
- ✅ **Character-specific saves** (per-character inventory and item discoveries)
- ✅ **Inventory drag-and-drop** (rearrange items by dragging between slots)
- ✅ **Equipment toggle** (press same hotbar number twice to unequip)
- ✅ **Terrain modification** (Valheim-style digging and building with terrain tools)
  - Stone Pickaxe (left-click: dig circle, right-click: dig square)
  - Stone Hoe (level terrain to standing position)
  - Earth resource (collect from digging, place to build terrain)
  - Depth-based mining difficulty (asymptotic slowdown)
- ✅ **Terrain persistence** (modifications save across server restarts)
- ✅ **Loading screen** (smooth world loading with progress tracking)
- ✅ **Manual save** (F5 key to trigger full save including terrain)

### Try It Out!

```bash
# Terminal 1 - Launch server (edit launch_server.sh to customize world/seed/port)
./launch_server.sh

# Terminal 2 - Launch client
./launch_client.sh

# Terminal 3 - Launch another client
./launch_client.sh
```

**Server Configuration**: Edit `launch_server.sh` to customize:
- `WORLD_NAME` - Unique world name (default: "world")
- `WORLD_SEED` - Seed for terrain generation (default: random)
- `GAME_PORT` - Server port (default: 7777)
- `MAX_PLAYERS` - Maximum players (default: 10)

You can also override these with environment variables:
```bash
WORLD_NAME=myworld WORLD_SEED=12345 ./launch_server.sh
```

Connect clients to `127.0.0.1:7777`, explore the world, gather resources, and build structures!

**Getting Started:**
1. Punch trees and rocks to gather wood, stone, and resin
2. Press **Tab** to open inventory
3. **Drag items** between slots to organize your inventory
4. Press **E** on the workbench to open crafting menu
5. Craft weapons and shields (stone knife, fire wand, buckler, etc.)
6. **Right-click items** in inventory/hotbar to equip/unequip them
7. Press **1-9** to auto-equip items from hotbar (press same number twice to unequip)
8. **Left-click** to attack, **Right-click** to block (with shield equipped)
9. **Middle-click** for special attacks (knife lunge, sword stab, fire wand area fire)
10. Equip hammer and press **Q** to build (walls, floors, doors, etc.)

---

## 📋 Roadmap

### Phase 1: Core Networking ✅ **COMPLETE**
- [x] Dual-mode launch (server/client/singleplayer)
- [x] Client-side prediction
- [x] Player spawning and movement
- [x] Network synchronization

### Phase 2: Voxel Terrain ✅ **COMPLETE**
- [x] Integration with Godot Voxel Tools
- [x] Procedural terrain generation (biome-based)
- [x] Multiple biomes (Meadow, Dark Forest, Poison Pit, Crystal Peaks, Hellscape, The Void)
- [x] Chunk streaming with server-authoritative environmental objects
- [x] Server-client world consistency
- [x] Smart persistence (procedural + database)
- [ ] Terrain editing (mining, building) - *deferred to Phase 4*

### Phase 3: Combat & AI 🗡️ **MOSTLY COMPLETE**
- [x] **Weapons System** (Valheim-style tiers and types)
  - [x] **Tier 1: Wood & Stone** (wood, stone, resin materials)
    - [x] Stone Sword (10 wood, 5 stone) - Medium speed, balanced damage
    - [x] Stone Axe/Head Smasher (20 wood, 10 stone) - Slow, heavy damage, 2x sword cost
    - [x] Stone Knife (5 wood, 2 stone) - Fast, low damage, 0.5x sword cost
    - [x] Fire Wand (3 wood, 7 resin) - Magic ranged weapon, fire projectiles
    - [x] Bow (10 wood, 1 resin) - Physical ranged weapon (visual only, no arrows yet)
  - [x] **Shields** (Valheim-style parry mechanics)
    - [x] Tower Shield (15 wood) - High block armor, no parry bonus
    - [x] Round Shield (10 wood) - Medium block, medium parry bonus
    - [x] Buckler (5 wood) - Low block, high parry bonus
  - [x] TSCN files for each weapon (spawned in player hand when equipped)
  - [x] Weapon stats (damage, speed, knockback, durability)
  - [x] Mount points for proper hand alignment
- [x] **Enhanced Equipment System**
  - [x] Tab menu + right-click to equip (Valheim-style)
  - [x] Equipment slots (weapon, shield, armor slots defined)
  - [x] Hotbar auto-equips on number key press (1-9 keys)
  - [x] Visual feedback for equipped items (yellow outline)
  - [x] Items stay in inventory when equipped (Valheim approach)
  - [x] Two-handed weapon restrictions (auto-unequips shield)
- [x] **Combat Mechanics**
  - [x] Melee attack patterns (swing animations, raycast hitboxes)
  - [x] Blocking and parry system (perfect timing stuns attacker)
  - [x] Weapon combos (knife 3-hit combo with finisher)
  - [x] Special attacks (middle-mouse: knife lunge, sword stab, fire wand area effect)
  - [x] Procedural body animations (crouch, lean, limb movement)
  - [x] Stamina consumption on attacks
  - [x] Damage types (slash, blunt, pierce, fire implemented)
  - [x] Projectile system (fireballs for fire wand)
  - [x] Area-of-effect damage (fire wand ground fire)
- [x] **Enemy System** (basic implementation)
  - [x] Basic enemy spawner (natural spawns)
  - [x] Simple enemy AI (chase and attack)
  - [x] Health and damage for enemies
  - [x] Gahnome enemy (gnome-like creature)
  - [ ] Enemy loot drops (structure in place, needs implementation)
- [x] Death mechanics (player death implemented)
- [ ] Respawn mechanics
- [ ] Boss encounters (later)

### Phase 4: Building, Crafting & Inventory 🏗️ **IN PROGRESS**
- [x] Multi-world system (unique names and seeds)
- [x] Per-world storage and persistence
- [x] World config synchronization (server → clients)
- [x] Resource gathering (destructible environmental objects)
- [x] Health system for trees, rocks, grass
- [x] Client-side hit detection (punch/attack)
- [x] Server-authoritative damage validation
- [x] Resource item pickups (wood, stone, resin)
- [x] Inventory system (30 slots, hotbar 1-9)
- [x] **Enhanced inventory UI**
  - [x] Tab menu to open full inventory
  - [x] Right-click to equip/unequip items
  - [x] Drag-and-drop to rearrange items
  - [x] Hotbar toggle (press number twice to unequip)
  - [x] Visual feedback for equipped items (yellow outline)
- [x] Workbench crafting station
- [x] Building system (walls, floors, doors, beams, roofs)
- [x] Workbench proximity requirement (20m radius)
- [x] **Weapons & Combat** (see Phase 3 details above)
- [x] **Enemy spawning** (Gahnomes spawn naturally around players)
- [ ] Interactable doors
- [ ] Structural integrity
- [ ] More crafting recipes

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
| Attack/Gather | Left Click |
| Block/Parry | Right Click (with shield) |
| Destroy Building | Middle Mouse |
| Pick Up Item / Interact | E |
| Inventory | Tab |
| Hotbar Slots (Auto-Equip) | 1-9 |
| Build Menu | Q (with hammer equipped) |
| Rotate Building | R (in build mode) |
| Character Select | C *(at spawn)* |
| Pause Menu | Esc |

**Combat Tips:**
- **Right-click in inventory/hotbar** to equip/unequip items
- **Yellow outline** shows equipped items
- **Two-handed weapons** auto-unequip shields
- **Block** reduces damage (right-click with shield)
- **Parry** - Block at the moment of enemy attack to stun them

---

## 🏗️ Architecture Guide

### Directory Structure Overview

```
hamberg/
├── server/              # Server-only scripts
├── client/              # Client-only scripts
├── shared/              # Shared game logic (runs on both client & server)
├── scenes/              # Godot scene files (.tscn)
├── resources/           # Resource definitions (.tres)
├── assets/              # Models, textures, audio, materials
├── saves/               # Per-world save data (gitignored)
├── main.gd              # Entry point - mode detection
├── project.godot        # Godot project configuration
└── launch_*.sh          # Helper scripts for running server/client
```

### Detailed File Organization

#### 🖥️ **Server/** - Server-Authoritative Systems
Server-only code that never runs on clients. Authority over world state, validation, persistence.

- **server/server.gd** - Main server controller
  - Player management (spawn, despawn, position validation)
  - Chunk streaming and environmental object authority
  - Inventory validation and synchronization
  - Building placement validation and persistence
  - Combat damage validation

#### 💻 **Client/** - Client-Only UI and Rendering
Client-only code for rendering, UI, and local player control. Never runs on dedicated servers.

- **client/client.gd** - Main client controller
  - UI management (hotbar, inventory, build menu)
  - Local player spawning and camera control
  - Environmental object rendering (client-side chunk streaming)
  - Build mode and placement mode activation
  - Item pickup and interaction

- **client/ui/** - User Interface Components
  - **hotbar.gd** - Quick access bar (slots 1-9, auto-equip on press)
  - **inventory_panel.gd** - Full inventory view (Tab key, right-click to equip)
  - **inventory_slot.gd** - Individual slot with equip status (yellow outline)
  - **crafting_menu.gd** - Workbench crafting UI (E on workbench)
  - **build_menu.gd** - Building piece selection (Q key with hammer)
  - **character_selection.gd** - Player appearance selection
  - **pause_menu.gd** - Settings and disconnect

- **client/item_discovery_tracker.gd** - Per-character item discovery
  - Tracks which items player has touched
  - Saves to `user://discoveries/{character_name}_discoveries.save`
  - Shows crafting recipes only when materials discovered

- **client/build_mode.gd** - Valheim-style building
  - Ghost preview with snap points
  - Workbench proximity checking
  - Resource validation before placement
  - Floor/wall/roof snapping logic

- **client/placement_mode.gd** - Object placement (workbench, etc.)
  - Simpler placement for single objects
  - Ground placement with collision detection

#### 🔗 **Shared/** - Cross-Platform Game Logic
Code that runs on both client and server. Contains core game systems and network communication.

- **shared/network_manager.gd** (Autoload)
  - RPC relay pattern (all RPCs go through here)
  - Network state management
  - Client/server communication hub

- **shared/player.gd** & **player.tscn**
  - Player entity with segmented body (arms, legs, torso)
  - Client-authoritative movement (validated by server)
  - Attack, jump, sprint, block mechanics
  - Inventory component (server-synced)
  - Equipment component (weapon, shield, armor)
  - Weapon/shield visuals attach to hand mount points
  - Projectile spawning for ranged weapons

- **shared/equipment.gd** - Equipment management system
  - Server-authoritative equipment state
  - Slots: MAIN_HAND, OFF_HAND, HEAD, CHEST, LEGS
  - Two-handed weapon restrictions
  - Equipment change signals for visual updates

- **shared/weapon_data.gd** & **shield_data.gd** - Item stats
  - Weapon types: MELEE_ONE_HAND, MELEE_TWO_HAND, RANGED, MAGIC
  - Damage, knockback, attack speed, stamina cost
  - Projectile scene references for ranged weapons
  - Shield block armor and parry window timing

- **shared/projectiles/** - Projectile system
  - **projectile.gd** - Base class for all projectiles
  - **fireball.tscn** - Fire wand projectile (orange glowing sphere)
  - Shared system: works for both players and enemies
  - Lifetime management, collision detection, damage application

- **shared/camera_controller.gd** & **camera_controller.tscn**
  - Third-person camera with collision avoidance
  - Mouse look and zoom
  - Attached to local player only

- **shared/voxel_world.gd** & **voxel_world.tscn**
  - Voxel terrain integration (Godot Voxel Tools)
  - Biome-based procedural generation
  - LOD streaming and mesh generation

- **shared/biome_generator.gd**
  - Procedural terrain heightmap generation
  - 7 biomes (Valley, Forest, Swamp, Mountain, Desert, Wizardland, Hell)
  - Valheim-style organic biome placement (noise + distance-based progression)
  - Deterministic from world seed
  - Each biome has unique height, roughness, and visual characteristics

- **shared/terrain_material.gdshader** - Biome-based terrain coloring
  - Generates 2048x2048 biome texture map from BiomeGenerator at world load
  - Samples texture for accurate per-pixel biome colors
  - Smooth blending at biome boundaries (50m transition zones)
  - Slope-based grass/rock rendering (walkability-aligned)
  - Each biome has distinct grass and rock colors:
    - **Valley**: Bright blue grass, gray rock
    - **Forest**: Bright green grass, dark gray-green rock
    - **Swamp**: Yellow-green grass, dark muddy rock
    - **Mountain**: White grass (snow), light gray rock
    - **Desert**: Bright yellow grass (sand), sandy stone
    - **Wizardland**: Bright magenta grass, purple crystal
    - **Hell**: Bright red grass (lava), dark obsidian

- **shared/crafting_recipes.gd** (Autoload)
  - Central recipe database
  - Building costs (wood, stone, resin)
  - Item crafting recipes

- **shared/inventory.gd**
  - 30-slot inventory system
  - Stack management
  - Server-authoritative with client prediction

- **shared/environmental/** - Trees, Rocks, Grass
  - **chunk_manager.gd** - Server controls chunk loading/unloading
  - **chunk_data.gd** - Chunk persistence format
  - **chunk_database.gd** - SQLite save/load
  - **environmental_spawner.gd** - Deterministic object spawning from seed
  - **environmental_object.gd** - Base class (health, drops, destruction)
  - **tree.tscn**, **rock.tscn**, **grass_clump.tscn** - Visual scenes

- **shared/weapons/** - Weapon & Shield Visuals
  - **stone_sword.tscn**, **stone_axe.tscn**, **stone_knife.tscn** - Melee weapons
  - **fire_wand.tscn** - Magic staff with glowing orb (has Tip node for projectile spawn)
  - **bow.tscn** - Ranged weapon (visual only, arrows not yet implemented)
  - **buckler.tscn**, **round_shield.tscn**, **tower_shield.tscn** - Shields
  - Each has **MountPoint** node for proper hand grip alignment

- **shared/buildable/** - Building System
  - **building_piece.gd** - Base for walls, floors, roofs
    - Snap point system (corner, edge, top, bottom)
    - Grid snapping and alignment
    - Preview mode (ghost with color feedback)
  - **buildable_object.gd** - Base for workbench and standalone objects
    - Crafting station range checking
    - Preview mode support
  - **wooden_wall.tscn**, **wooden_floor.tscn**, **wooden_door.tscn**, etc.
    - Individual building piece scenes (placeholder meshes)
  - **workbench.tscn** - Crafting station (20m build radius, E to interact)

#### 🎬 **Scenes/** - Entry Point Scenes
Main scene files that tie everything together.

- **scenes/main.tscn** - Entry point
  - Loads main.gd script
  - Decides server vs client mode

- **scenes/server.tscn** - Server scene
  - Contains Server node
  - World container
  - No camera or UI

- **scenes/client.tscn** - Client scene
  - Contains Client node
  - CanvasLayer with all UI
  - VoxelViewer for terrain streaming

#### 📦 **Resources/** - Data Definitions
Godot resource files (.tres) for items, recipes, etc.

- Currently minimal - will expand with item definitions

#### 🎨 **Assets/** - Art and Audio
Models, textures, materials, sounds. Currently using placeholder meshes.

- **assets/materials/** - Shared materials for objects
- **assets/models/** - 3D models (GLTF/OBJ)
- **assets/textures/** - Textures and sprite sheets
- **assets/audio/** - Music and sound effects

### Key Architecture Patterns

**1. Client/Server/Shared Separation**
- Server code never runs on client (and vice versa)
- Shared code runs everywhere
- Clear authority boundaries

**2. RPC Relay Pattern**
All RPCs go through `NetworkManager` to work across boundaries:
```gdscript
# Always use NetworkManager for RPCs
NetworkManager.rpc_place_buildable.rpc_id(1, piece_name, pos, rot)
```

**3. Autoload Singletons**
- `NetworkManager` - Network communication
- `CraftingRecipes` - Recipe database
- More to come (ItemDatabase, etc.)

**4. Scene-Based Design**
- Every entity is a scene (.tscn)
- Scenes are instantiated at runtime
- Easy to replace placeholder art

**5. Trust-Based Networking**
- Client reports actions, server validates
- Immediate client feedback
- Server has final authority

### Finding Specific Features

| Feature | Files to Check |
|---------|---------------|
| Player movement | `shared/player.gd`, `client/client.gd` |
| Combat & attacking | `shared/player.gd` (_handle_attack, _spawn_projectile) |
| Equipment system | `shared/equipment.gd`, `shared/player.gd` (_on_equipment_changed) |
| Weapons & shields | `shared/weapon_data.gd`, `shared/shield_data.gd`, `shared/item_database.gd` |
| Weapon visuals | `shared/weapons/*.tscn`, `shared/player.gd` (_update_weapon_visual) |
| Projectiles | `shared/projectiles/projectile.gd`, `shared/projectiles/fireball.tscn` |
| Blocking & parry | `shared/player.gd` (take_damage, check_parry_window) |
| Inventory | `shared/inventory.gd`, `client/ui/inventory_panel.gd`, `client/ui/hotbar.gd` |
| Item discovery | `client/item_discovery_tracker.gd` |
| Crafting menu | `client/ui/crafting_menu.gd` |
| Building | `client/build_mode.gd`, `shared/buildable/building_piece.gd` |
| Terrain modification | `shared/terrain_modifier.gd`, `shared/voxel_world.gd` |
| Terrain replay system | `server/server.gd`, `client/client.gd`, `shared/network_manager.gd` |
| World generation | `shared/biome_generator.gd`, `shared/voxel_world.gd` |
| Chunk streaming | `shared/environmental/chunk_manager.gd` |
| Resource gathering | `shared/environmental/environmental_object.gd`, `shared/player.gd` |
| Networking | `shared/network_manager.gd`, `server/server.gd`, `client/client.gd` |
| Enemy AI | `shared/enemies/enemy.gd`, `server/enemy_spawner.gd` |

---

## ⛏️ Terrain Modification & Replay System

Hamberg features a sophisticated terrain modification system that persists changes across server restarts and handles VoxelTool's proximity requirements.

### Why This Custom System? (VoxelTools Limitations)

**We use VoxelLodTerrain with a custom RPC-based replay system instead of VoxelTools' built-in streaming because:**

1. **VoxelLodTerrain + VoxelStream = Works** ✓ but **NO multiplayer support** ✗
   - VoxelTerrainMultiplayerSynchronizer only works with VoxelTerrain (not VoxelLodTerrain)
   - VoxelLodTerrain has no official multiplayer support ("planned" per docs)

2. **VoxelTerrain + VoxelStream = Multiplayer support** ✓ but **generator completely blocked** ✗
   - VoxelStreamRegionFiles blocks generator → no terrain renders
   - VoxelStreamSQLite blocks generator → no terrain renders
   - Any VoxelStream assignment prevents generator fallback on VoxelTerrain

3. **VoxelTerrain + NO stream = Multiplayer** ✓ and **terrain renders** ✓ but **no persistence** ✗
   - Modifications lost on server restart
   - No built-in save/load mechanism

**Our Solution: VoxelLodTerrain + Custom RPC Replay**
- ✓ Terrain renders (procedural generation works)
- ✓ Multiplayer via custom RPC system
- ✓ Persistence via terrain_history.json
- ⚠️ Known issue: Replayed terrain has slight visual artifacts due to LOD timing

This is the best compromise given VoxelTools' architectural limitations for multiplayer + streaming + procedural generation.

### How It Works

**Server-Side Authority:**
- Server stores all terrain modifications in `terrain_modification_history` (per-chunk dictionary)
- Modifications saved to `user://worlds/{world_name}/terrain_history.json`
- On server restart, all chunks with modifications are marked as "unapplied"

**Client-Side Application with Distance-Based Queueing:**

Terrain modifications can only be applied when:
1. Player is within **32 units (1 chunk)** of the modification
2. VoxelLodTerrain has loaded high-resolution voxel detail for that area

**The Replay Flow:**

```
Server Restart
    ↓
Load terrain_history.json
    ↓
Mark all chunks as unapplied (server/server.gd)
    ↓
Player connects and loads world
    ↓
Server replays modifications via RPC
    ↓
Client receives modifications:
    - If loading: Queue for later
    - If player > 32 units away: Queue for later
    - If player nearby but area not editable: Queue and retry
    ↓
Periodic check every 2 seconds (client/client.gd):
    - Find queued modifications within 32 units
    - Attempt to apply each one
    - Re-queue any that fail (area not editable yet)
    ↓
Modifications appear when player walks near them
```

### Critical Implementation Details

**⚠️ IMPORTANT: Do not change these values without understanding VoxelTool constraints**

**Distance Constants:**
- `MAX_DISTANCE = 32.0` (in `network_manager.gd` and `client.gd`)
- This is **1 chunk** - the minimum reliable distance for VoxelTool operations
- **Do NOT increase** - VoxelTool fails silently when player is too far
- Tested values: 48 units = unreliable, 32 units = reliable

**Retry Logic:**
- `_apply_terrain_modification_internal()` returns `true/false` based on success
- Failures (return value = 0 or area not editable) are automatically re-queued
- Periodic checker runs every 2 seconds: `QUEUED_MODS_CHECK_INTERVAL = 2.0`

**Why This Approach:**
1. **VoxelTool Limitation**: Terrain detail only loads near VoxelViewer (player camera)
2. **LOD System**: High-resolution voxel data loads gradually as player approaches
3. **Silent Failures**: VoxelTool's `is_area_editable()` returns false if detail not loaded
4. **Distance-Based**: No static timers - everything proximity-based for reliability

### File Locations

| Component | File | Lines |
|-----------|------|-------|
| Server terrain history | `server/server.gd` | 987-1240 |
| Client queueing system | `client/client.gd` | 1388-1474 |
| Distance check | `shared/network_manager.gd` | 351-366 |
| Terrain operations | `shared/terrain_modifier.gd` | 73-251 |
| Voxel world wrapper | `shared/voxel_world.gd` | 358-383 |

### Key Functions

**Server:**
- `_load_terrain_history()` - Loads modifications and marks all as unapplied
- `_apply_terrain_modifications_for_chunk()` - Applies modifications when player near
- `_is_player_near_chunk()` - Checks if any player within range

**Client:**
- `queue_terrain_modification()` - Adds modification to queue
- `_check_queued_terrain_modifications()` - Periodic distance check (every 2s)
- `_apply_terrain_modification_internal()` - Attempts application, returns success

**Network:**
- `rpc_apply_terrain_modification()` - Checks distance before applying or queuing

### Debugging Tips

If terrain modifications aren't appearing:
1. Check logs for "Player too far" messages - modifications are queued
2. Check logs for "Area not editable" warnings - VoxelTool can't apply yet
3. Walk within 32 units of the modification and wait up to 2 seconds
4. Modifications will retry automatically every 2 seconds when in range

---

## 🌐 Network Architecture

Hamberg uses a **trust-based networking model** designed for cooperative play with friends.

### Design Philosophy

**Responsive Gameplay > Anti-Cheat**

We prioritize instant feedback and smooth gameplay over paranoid anti-cheat. This is a co-op game meant to be played with communities you trust, not a competitive game.

### Authority Split

| System | Authority | Why |
|--------|-----------|-----|
| Player Movement | **Client** (validated) | Instant response, validated by server |
| Environmental Objects | **Server** | Consistent world state |
| Combat/Hits | **Client** (reported) | Immediate hit feedback |
| Damage Application | **Server** | Prevent obvious exploits |
| Inventory | **Server** | No item duplication |
| World Persistence | **Server** | Single source of truth |
| Terrain Editing | **Server** (validated) | Prevent griefing |
| Enemy AI | **Server** | Consistent behavior |

### Network Patterns

**Client-Authoritative Movement (Validated):**
```gdscript
# CLIENT: Move locally, send position to server
func _physics_process(delta):
    var input = gather_input()
    apply_movement(input, delta)  # Instant local response

    # Send position update to server
    var position_data = {
        "position": global_position,
        "rotation": rotation.y,
        "velocity": velocity,
        "animation_state": current_animation_state
    }
    NetworkManager.rpc_send_player_position.rpc_id(1, position_data)

# SERVER: Validate and accept position
func receive_player_position(peer_id, position_data):
    var distance_moved = old_position.distance_to(new_position)
    if distance_moved < MAX_MOVEMENT_PER_TICK:  # Anti-cheat validation
        player.global_position = position_data.position
        # Broadcast to all clients
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

## 🌍 Biome System & World Generation

Hamberg features a **Valheim-inspired biome system** with 7 distinct biomes that create an organic, progression-based world.

### Biome Overview

The world is divided into **difficulty zones** based on distance from spawn (0,0):

1. **Safe Zone** (0-5000m): Valley and Forest only - gentle introduction
2. **Mid Zone** (5000-10000m): Swamp and Desert appear alongside safe biomes
3. **Danger Zone** (10000-15000m): Mountains and Wizardland spawn, with occasional Hell
4. **Extreme Zone** (15000-20000m): Heavy Hell presence with Mountains and Wizardland
5. **Far Zone** (20000m+): Mostly Hell with rare Mountains and Wizardland

### The Seven Biomes

| Biome | Terrain Color | Characteristics | Difficulty |
|-------|--------------|-----------------|------------|
| **Valley** | Bright Blue | Rolling hills, gentle terrain | Safe |
| **Forest** | Bright Green | Dense trees, moderate elevation | Safe |
| **Swamp** | Yellow-Green | Low, flat marshland | Mid |
| **Mountain** | White (Snow) | High peaks, steep slopes | Dangerous |
| **Desert** | Bright Yellow | Sandy dunes, moderate height | Mid |
| **Wizardland** | Bright Magenta | Magical floating terrain | Dangerous |
| **Hell** | Bright Red | Volcanic, chaotic landscape | Extreme |

### How Biomes Are Generated

**Valheim-Style Organic Placement:**
- Uses **noise-based distribution** (not circular zones)
- **Domain warping** creates irregular, organic biome shapes
- **Scale variation** makes some biome patches larger/smaller
- **Distance influences probability**, not hard boundaries

**Technical Implementation:**

1. **BiomeGenerator** (`shared/biome_generator.gd`):
   - Uses FastNoiseLite with multiple octaves for natural variation
   - Samples noise at world position to determine biome
   - Each biome has unique height parameters (base height, amplitude, roughness)
   - Deterministic from world seed - same seed = same world

2. **Terrain Material** (`shared/terrain_material.gdshader`):
   - **Texture-based coloring**: Generates 2048x2048 biome map on world load
   - Samples BiomeGenerator for each pixel to ensure perfect alignment
   - **Smooth blending**: 50-meter transition zones between biomes
   - **Slope detection**: Grass on flat terrain, rock on steep slopes (aligned with walkability)
   - Colors match exactly between terrain, mini-map, and world map

3. **Mini-Map & World Map** (`client/ui/world_map_generator.gd`):
   - Uses same biome colors as terrain shader
   - Samples BiomeGenerator to show accurate biome placement
   - Height-based shading for topographic detail

### Biome Progression

**Early Game (Safe Zone):**
- Spawn in Valley (blue) or Forest (green)
- Gentle terrain, basic resources
- Learn crafting and building

**Mid Game (5-10km):**
- Discover Swamp (yellow-green) and Desert (yellow)
- More challenging terrain and enemies
- New resources and crafting materials

**Late Game (10-15km):**
- Enter Mountains (white) and Wizardland (magenta)
- Extreme elevation changes
- Rare resources, tough enemies

**End Game (15km+):**
- Face Hell (red) biomes
- Chaotic volcanic terrain
- Ultimate challenges and rewards

### Visual Cohesion

All biome colors are **intentionally bright and distinct** for clarity:
- Easy to identify which biome you're in at a glance
- Mini-map matches terrain colors exactly
- Smooth color transitions prevent jarring boundaries
- Rock appears on slopes you can't walk up (visual gameplay feedback)

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

1. Try Phase 2 - Run the multiplayer demo with voxel terrain!
2. Read the code - See how server-authoritative world streaming works
3. Join development - Help build Phase 3 (combat & AI!)
4. Share feedback - What should we build next?

**Join the journey to build an open source Valheim!** ⚔️🏔️

---

<p align="center">
  <strong>Hamberg - Open Source Survival, Built Together</strong><br>
  <em>A fusion of Hamner and Inberg</em>
</p>

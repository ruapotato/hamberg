# MultiMesh Environmental Objects Overhaul

## Problem Analysis

Current mesh counts per object (LOD0):
- **Glowing Mushroom**: 8 meshes (4 stems + 4 caps with 2 materials)
- **Spore Cluster**: 10 meshes (5 large + 5 small spores)
- **Mushroom Tree**: 3 meshes (stem, cap, cap top)
- **Giant Mushroom**: 4 meshes (stem, cap, dome, ring)

With 81 loaded chunks (9x9 grid), ~15 glowing mushrooms per chunk = ~1200 instances × 8 meshes = **~10,000 draw calls** just for glowing mushrooms.

## Solution: Chunk-Based MultiMesh System

Instead of individual scene instances, use MultiMeshInstance3D per chunk to batch render all instances of the same mesh type in a single draw call.

### Architecture Overview

```
ChunkManager
├── EnvironmentalObjects (Node3D container)
│   ├── Chunk_0_0 (Node3D)
│   │   ├── MultimeshCapCyan (MultiMeshInstance3D) - all cyan caps
│   │   ├── MultimeshCapPurple (MultiMeshInstance3D) - all purple caps
│   │   ├── MultimeshStem (MultiMeshInstance3D) - all stems
│   │   ├── CollisionArea (Area3D) - hit detection
│   │   └── ChunkData (script tracking health/destroyed)
│   ├── Chunk_0_1 ...
```

### New Files to Create

1. **`shared/environmental/multimesh_chunk.gd`** - Manages MultiMesh rendering for a chunk
2. **`shared/environmental/multimesh_spawner.gd`** - Generates MultiMesh transforms instead of instances
3. **`shared/environmental/multimesh_meshes.gd`** - Preloaded mesh resources

### Implementation Steps

#### Step 1: Create mesh resource definitions
- Extract mesh/material resources from .tscn files into a reusable resource script
- Define mesh configurations for each object type

#### Step 2: Create MultimeshChunk class
- Properties:
  - Dictionary of MultiMeshInstance3D nodes (one per mesh+material combo)
  - Array of instance data (position, rotation, scale, health, destroyed)
  - Area3D for hit detection with compound collision
- Methods:
  - `add_instance(type, transform, health)` - Add to MultiMesh
  - `remove_instance(index)` - Set transform scale to 0
  - `get_instance_at_position(pos)` - Find which instance was hit
  - `apply_damage(index, damage)` - Handle damage/destruction

#### Step 3: Modify environmental_spawner.gd
- Add `spawn_chunk_multimesh()` function for MultiMesh spawning
- Generate transforms and instance data instead of scene instances
- Return MultimeshChunk instead of Array of objects

#### Step 4: Modify chunk_manager.gd
- Use MultimeshChunk for mushroom types (glowing_mushroom, spore_cluster)
- Keep individual scenes for larger objects (mushroom_tree, giant_mushroom, trees, rocks)
- Handle hit detection via Area3D body_entered signals

#### Step 5: Handle collision/interaction
- Each MultimeshChunk has an Area3D with CollisionShape3D per instance
- On hit, find nearest instance and apply damage
- When destroyed, set instance scale to 0 (invisible but slot preserved)

#### Step 6: Handle persistence
- Save destroyed instance indices to chunk database
- On load, mark those indices as destroyed (scale 0)

### Objects to Convert

**Convert to MultiMesh (high instance count, low poly):**
- Glowing Mushroom (highest priority - most instances, 8 meshes each)
- Spore Cluster (10 meshes each)

**Keep as individual scenes (lower count, need full collision):**
- Mushroom Tree (larger, fewer instances)
- Giant Mushroom (larger, fewer instances)
- Trees, Rocks (need full physics collision)

### Performance Expectations

Before:
- ~10,000 mesh draw calls for glowing mushrooms alone
- ~2,000 individual StaticBody3D nodes

After:
- ~6 draw calls per chunk for glowing mushrooms (2 cap materials × 3 meshes)
- ~500 draw calls total (81 chunks × 6)
- **95% reduction in draw calls**

### Risks/Considerations

1. **Instance removal gaps**: When destroying instances, we set scale to 0 but the slot remains. Need to track for chunk unload/reload.

2. **Material variations**: Glowing mushrooms use 2 cap colors - need separate MultiMesh per material.

3. **Non-uniform scale**: Current spawner applies random scale variation - MultiMesh supports per-instance transforms so this works.

4. **LOD**: MultiMesh doesn't support per-instance LOD. Options:
   - Use visibility range on MultiMeshInstance3D (whole batch culls at distance)
   - Create separate MultiMesh for LOD1 meshes and swap visibility
   - Accept that all instances use same LOD (simpler)

5. **Collision performance**: Many small CollisionShape3D in Area3D may still have overhead. Alternative: use raycast-based hit detection from player attack.

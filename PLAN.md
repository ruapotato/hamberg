# Building System Enhancement Plan

## Overview
Comprehensive enhancement to the Valheim-style building system including new pieces, improved controls, better snapping, and UI feedback.

---

## 1. Fix Crosshair Alignment
**File:** `client/crosshair.tscn`

**Problem:** Crosshair is offset left with `offset_left = -44.0, offset_top = -53.0`

**Solution:** Center the 6x6 dot properly:
- Change offsets to `-3.0` for both left/right and top/bottom (half of 6px size)

---

## 2. Rotation Controls
**Files:** `client/build_mode.gd`, `project.godot`

**Changes:**
- Add Q key as alternative rotation (in addition to R)
- Add D-pad left/right for controller rotation when in build mode
- Modify `_handle_input()` to check for:
  - `build_rotate` (R key - existing)
  - `open_build_menu` (Q key - repurpose when build menu is closed)
  - `hotbar_prev`/`hotbar_next` (D-pad) when build mode is active

---

## 3. Second Floor Snapping (Multi-Story Buildings)
**File:** `client/build_mode.gd`, `shared/buildable/building_piece.gd`

**Problem:** Floors can't snap to top of walls for second stories

**Solution:**
1. Add `floor_bottom` snap points to floors
2. Modify `_find_matching_snap_point()` to handle floor-to-wall-top snapping
3. Floor bottom connects to wall_top snap points

---

## 4. Shift to Disable Smart Snap
**File:** `client/build_mode.gd`

**Implementation:** Check if sprint (Shift) is pressed, skip snapping logic and allow free placement.

---

## 5. On-Screen Build Controls UI
**Files:** New `client/ui/build_controls_hint.gd`, `client/ui/build_controls_hint.tscn`

**Design:** Small panel showing contextual controls based on input device

**Keyboard Mode:**
```
[LMB] Place  [MMB] Remove  [R/Q] Rotate
[Shift] Free Place  [RMB] Menu
```

**Controller Mode:**
```
[RT] Place  [Y] Remove  [D-pad] Rotate
[LT] Free Place  [X] Menu
```

---

## 6. New Building Pieces

### 6a. Roof Pieces (Two Angles - like Valheim)
- `wooden_roof_26.tscn` - 26° shallow pitch (rename existing)
- `wooden_roof_45.tscn` - 45° steep pitch (new)

### 6b. Stairs
- `wooden_stairs.tscn` - 2x2x2 stairs connecting floors
- Angled collision for walking, steps mesh

### 6c. Improved Door
- Resize to 2.0 x 2.0 x 0.2 (same as wall)
- Add door frame + swinging door panel
- Add open/close interaction (E key / X button)
- Animated door swing

---

## 7. Sound Effects
**Generate via Python (numpy/scipy):**
- `build_place.wav` - Wood placement thunk
- `build_remove.wav` - Wood breaking sound

---

## 8. Building Costs Update
```gdscript
const BUILDING_COSTS = {
    "workbench": {"wood": 10},
    "chest": {"wood": 10},
    "wooden_wall": {"wood": 4},
    "wooden_floor": {"wood": 2},
    "wooden_door": {"wood": 6},      # Increased (full-size + functional)
    "wooden_beam": {"wood": 2},
    "wooden_roof_26": {"wood": 2},
    "wooden_roof_45": {"wood": 2},
    "wooden_stairs": {"wood": 6},    # New
}
```

---

## Implementation Order

1. **Quick Fixes:**
   - Fix crosshair alignment
   - Add rotation controls (Q + D-pad)
   - Add shift-to-disable-snap

2. **Multi-Story Support:**
   - Second floor snapping logic
   - Add floor_bottom snap points

3. **New Pieces:**
   - Rename roof to roof_26, create roof_45
   - Create wooden_stairs
   - Improve door (resize + interaction)

4. **UI & Sound:**
   - On-screen build controls hint
   - Generate and add sound effects

5. **Integration:**
   - Update build menu
   - Update crafting costs
   - Testing

---

## Files to Create
- `shared/buildable/wooden_roof_45.tscn`
- `shared/buildable/wooden_stairs.tscn`
- `shared/buildable/door.gd`
- `client/ui/build_controls_hint.gd`
- `client/ui/build_controls_hint.tscn`
- `audio/sfx/build_place.wav`
- `audio/sfx/build_remove.wav`

## Files to Modify
- `client/crosshair.tscn` - Fix alignment
- `client/build_mode.gd` - Rotation, snapping, sounds
- `shared/buildable/building_piece.gd` - Floor snap points
- `shared/buildable/wooden_door.tscn` - Resize + add door.gd
- `shared/buildable/wooden_roof.tscn` - Rename to roof_26
- `shared/crafting_recipes.gd` - Update costs
- `client/ui/build_menu.gd` - Add new pieces
- `client/client.gd` - Show/hide build controls

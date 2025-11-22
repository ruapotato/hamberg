# Controller Support Guide

Hamberg now has full controller support optimized for the Steam Deck!

## Steam Deck / Xbox Controller Layout (Valheim Console Controls)

### Movement & Camera
- **Left Stick**: Move character (WASD)
- **Right Stick**: Camera look (mouse)
- **LB (Left Bumper)**: Sprint/Run (Shift)

### Combat
- **RT (Right Trigger)**: Attack/Fire (Left Click)
- **LT (Left Trigger)**: Block (Right Click)
- **RB (Right Bumper)**: Secondary Attack (Middle Click)

### Actions
- **A Button**: **PRIMARY SELECT** - Use this button for all selections and interactions
  - In-game: Interact (E)
  - All menus: Select/Confirm
  - Inventory: Pick up / drop item
  - Build menu: Select building piece
  - Server/Character select: Choose option
  - Launch screens: Confirm selections
- **B Button**: Jump (Space) - disabled when menus are open
- **X Button**: Build Menu (Q) - opens build menu when hammer equipped
- **Y Button**: Inventory (Tab) - opens **build menu** when hammer equipped instead of inventory

### Menus & Map
- **View/Back Button**: Toggle Map (M)
- **Menu/Start Button**: Also opens Map

### Building (when in Build Mode)
- **D-Pad Left**: Previous Build Piece
- **D-Pad Right**: Next Build Piece

### Hotbar (Controller D-Pad - When Inventory Closed)
- **D-Pad Left/Right**: Cycle through hotbar slots (1-9)
  - Shows selection border (yellow) on selected slot
  - Equipped items show gold border
- **D-Pad Up**: Equip selected hotbar item
- **D-Pad Down**: Unequip main hand and off hand

*Note: Keyboard/mouse still uses number keys 1-9 and auto-equips on selection*

### Inventory Navigation (When Inventory Open)
- **D-Pad**: Navigate inventory grid (all 4 directions)
  - Shows selection border on focused slot
  - Picked up items show dual borders (move mode)
- **A Button**: Pick up / drop item (for moving items between slots)
  - First press: Pick up item
  - Second press: Drop item at new location (swaps items)
  - Press A on same slot: Cancel move

*Note: D-Pad changes function when inventory is open - it navigates instead of cycling hotbar*

### Build Menu (When Open with Hammer Equipped)
- **D-Pad Up/Down**: Navigate building pieces list
  - Selected piece highlighted in yellow
- **A Button**: ✓ Select and place highlighted building piece (auto-closes menu)
- **B Button**: Close build menu without selecting
- **Y Button**: Close build menu
- **X or Y Button**: Open build menu (when hammer equipped and inventory closed)

### Server/Character Selection (Start of Game)
- **D-Pad Up/Down**: Navigate characters or options
  - Selected item highlighted in yellow
- **A Button**: ✓ Connect to server / select character

## Quick Reference
**A Button = SELECT EVERYTHING** - This is your primary action button for all menus, interactions, and confirmations throughout the game.

## Automatic Input Switching

The game automatically detects which input device you're using:
- Move the **mouse** or press any **keyboard key** → switches to keyboard/mouse mode
- Press any **controller button** or move any **stick** → switches to controller mode

The mouse cursor will automatically hide when using a controller in-game.

## Sensitivity Settings

You can adjust controller sensitivity by editing the camera controller settings:
- Default mouse sensitivity: `0.003`
- Default gamepad sensitivity: `3.0` (controller needs higher sensitivity)

These can be tweaked in the camera_controller.gd export variables.

## Steam Deck Specific Notes

### Running on Steam Deck
1. The game works great on Steam Deck running Ubuntu 24.04
2. Controller support works both in Game Mode and Desktop Mode
3. No need to enable Steam Input - native Godot controller support handles everything!

### Optional: Steam Input
If you prefer, you can still use Steam Input for custom button remapping:
1. Add the game as a Non-Steam Game
2. Configure controller layout in Steam settings
3. This allows community controller configs and per-game customization

But it's not required - the game has native controller support built-in!

## Troubleshooting

### Controller not detected?
- Check if your controller is connected: Godot will print "Gamepad detected" to console
- Try wiggling the sticks or pressing buttons to wake up the controller
- On Linux, ensure your user has permission to access `/dev/input/js*`

### Sensitivity too high/low?
Edit `shared/camera_controller.gd` and adjust `@export var gamepad_sensitivity: float = 3.0`

### Want to use both at once?
Yes! You can use mouse for aiming and controller for movement, or any combination.
The game seamlessly supports simultaneous input from both devices.

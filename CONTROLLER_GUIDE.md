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
- **A**: Interact (E)
- **B**: Jump (Space)
- **X**: Build Menu (Q)
- **Y**: Inventory (Tab)

### Menus & Map
- **View/Back Button**: Toggle Map (M)
- **Menu/Start Button**: Also opens Map

### Building (when in Build Mode)
- **D-Pad Left**: Previous Build Piece
- **D-Pad Right**: Next Build Piece

### Hotbar
Use the number keys 1-9 on keyboard/mouse mode for hotbar selection.
When using a controller, you can switch to keyboard/mouse at any time!

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

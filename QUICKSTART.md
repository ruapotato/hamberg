# Quick Start Guide

## Testing the Multiplayer Networking

### Method 1: Using the Helper Scripts

```bash
# Terminal 1 - Start server
./launch_server.sh

# Terminal 2 - Start first client
./launch_client.sh

# Terminal 3 - Start second client  
./launch_client.sh
```

Then in each client window:
1. Enter your player name (e.g., "Player1", "Player2")
2. Keep IP as `127.0.0.1`
3. Keep port as `7777`
4. Click "Connect"

You should see both players spawn and be able to move around!

### Method 2: Manual Launch

**Server:**
```bash
./godot.linuxbsd.editor.x86_64 --headless -- --server
```

**Client:**
```bash
./godot.linuxbsd.editor.x86_64
```

### Method 3: Singleplayer Testing

```bash
./launch_singleplayer.sh
# OR
./godot.linuxbsd.editor.x86_64 -- --singleplayer
```

This auto-starts a local server and connects a client to it.

## What to Expect

When everything is working:

1. **Server console** shows:
   ```
   [Server] Server is now running!
   [Server] Port: 7777
   [Server] Player joined: PlayerName (ID: 123)
   [Server] Spawned player 123 at (x, y, z)
   ```

2. **Client window** shows:
   - Connection UI disappears
   - HUD appears with ping and player count
   - A green ground plane with a blue sky
   - Blue capsule(s) representing player(s)
   - Controls info in bottom-right

3. **Movement** works:
   - WASD to move
   - Space to jump
   - Shift to sprint
   - Your local player responds instantly
   - Remote players move smoothly

## Troubleshooting

**"Failed to create server"**
- Port 7777 might be in use
- Try: `GAME_PORT=8888 ./launch_server.sh`
- Update client port to match

**"Connection failed"**
- Make sure server is running first
- Check firewall isn't blocking port 7777
- Try `127.0.0.1` for local testing

**"Can't see other players"**
- Check server logs for player join messages
- Make sure both clients connected successfully
- Try moving around - they might have spawned at the same spot

**"Players falling through floor"**
- This shouldn't happen! The ground is at Y=0
- Check that test_world.tscn loaded properly

## Next Steps

Once Phase 1 is working, you're ready for Phase 2: Voxel Terrain!

See README.md for the full architecture and Phase 2 plans.

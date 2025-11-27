#!/bin/bash
# Launch dedicated server

# World configuration (edit these to customize your server)
WORLD_NAME="hamberg"        # Default world name
WORLD_SEED="676767"             # Default seed (empty = random)
GAME_PORT="7777"           # Server port
MAX_PLAYERS="10"         # Max players

echo "Starting dedicated server..."
echo "  World: $WORLD_NAME"
echo "  Seed: ${WORLD_SEED:-random}"
echo "  Port: $GAME_PORT"
echo "  Max Players: $MAX_PLAYERS"
echo ""

export WORLD_NAME
export WORLD_SEED
export GAME_PORT
export MAX_PLAYERS

./Godot_v4.5.1-stable_linux.x86_64 --headless -- --server

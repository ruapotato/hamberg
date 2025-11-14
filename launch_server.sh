#!/bin/bash
# Launch dedicated server

# World configuration (edit these to customize your server)
WORLD_NAME="${WORLD_NAME:-world}"        # Default world name
WORLD_SEED="${WORLD_SEED:-}"             # Default seed (empty = random)
GAME_PORT="${GAME_PORT:-7777}"           # Server port
MAX_PLAYERS="${MAX_PLAYERS:-10}"         # Max players

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

./godot.linuxbsd.editor.x86_64 --headless -- --server

#!/bin/bash
cd "$(dirname "$0")/.."
python3 tools/generate_sprites.py "$@"
echo "Sprites generated. Restart Godot to import."

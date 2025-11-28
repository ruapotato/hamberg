# Claude Code Project Notes

## Testing Notes

- **Signal 11 / handle_crash messages**: When the game is force-quit or closed by the user (e.g., pkill, Ctrl+C), Godot reports `handle_crash: Program crashed with signal 11`. This is NOT a bug - it's just how Godot handles forced termination. Ignore these unless there are other error messages before the crash.

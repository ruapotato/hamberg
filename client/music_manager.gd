extends Node

## MusicManager - Plays biome-specific ambient music
## Randomly plays tracks from the current biome's music library

@onready var audio_player: AudioStreamPlayer = AudioStreamPlayer.new()

# Music volume (-6 dB = approximately half perceived loudness)
var music_volume_db: float = -6.0

# Current biome being played
var current_biome: String = ""
var current_track_index: int = -1

# Biome music libraries
var biome_music := {
	"valley": [
		"res://audio/music/Valley1.wav",
		"res://audio/music/Valley2.wav",
		"res://audio/music/Valley3.wav",
		"res://audio/music/Valley4.wav",
		"res://audio/music/Valley5.wav",
		"res://audio/music/Valley6.wav"
	],
	"forest": [],     # TODO: Add forest music
	"swamp": [],      # TODO: Add swamp music
	"mountain": [],   # TODO: Add mountain music
	"desert": [],     # TODO: Add desert music
	"wizardland": [], # TODO: Add wizardland music
	"hell": []        # TODO: Add hell music
}

func _ready() -> void:
	# Setup audio player
	add_child(audio_player)
	audio_player.bus = "Music"  # Use music bus if available
	audio_player.volume_db = music_volume_db
	audio_player.finished.connect(_on_track_finished)

	print("[MusicManager] Ready")

## Update the current biome and play appropriate music
func set_biome(biome_name: String) -> void:
	# Normalize biome name (handle "meadow" -> "valley" mapping)
	if biome_name == "meadow":
		biome_name = "valley"

	if biome_name == current_biome:
		return  # Already playing this biome's music

	print("[MusicManager] Changing biome music: %s -> %s" % [current_biome, biome_name])
	current_biome = biome_name
	current_track_index = -1

	# Start playing random track from new biome
	_play_random_track()

## Play a random track from the current biome
func _play_random_track() -> void:
	if current_biome.is_empty():
		return

	var tracks = biome_music.get(current_biome, [])
	if tracks.is_empty():
		print("[MusicManager] No music available for biome: %s" % current_biome)
		audio_player.stop()
		return

	# Pick a random track (avoid repeating the same track)
	var new_index = randi() % tracks.size()
	if tracks.size() > 1 and new_index == current_track_index:
		new_index = (new_index + 1) % tracks.size()

	current_track_index = new_index
	var track_path = tracks[current_track_index]

	print("[MusicManager] Playing: %s (track %d/%d)" % [track_path, current_track_index + 1, tracks.size()])

	var stream = load(track_path)
	if stream:
		audio_player.stream = stream
		audio_player.play()
	else:
		push_error("[MusicManager] Failed to load music: %s" % track_path)

## Called when a track finishes
func _on_track_finished() -> void:
	# Wait a bit before playing next track (ambient pause)
	await get_tree().create_timer(randf_range(5.0, 15.0)).timeout
	_play_random_track()

## Stop all music
func stop_music() -> void:
	audio_player.stop()
	current_biome = ""
	current_track_index = -1

extends Node

## MusicManager - Plays biome-specific ambient music
## Randomly plays tracks from the current biome's music library

@onready var audio_player: AudioStreamPlayer = AudioStreamPlayer.new()

# Music volume (-24 dB = very quiet background music)
var music_volume_db: float = -24.0

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
		"res://audio/music/Valley6.wav",
	],
	"meadow": [
		"res://audio/music/Valley1.wav",
		"res://audio/music/Valley3.wav",
		"res://audio/music/Dawn.wav",
	],
	"dark_forest": [
		"res://audio/music/DarkForest1.wav",
		"res://audio/music/DarkForest2.wav",
		"res://audio/music/SpookyStarlit.wav",
	],
	"swamp": [
		"res://audio/music/Swamp1.wav",
		"res://audio/music/Swamp2.wav",
	],
	"mountain": [
		"res://audio/music/Mountain1.wav",
		"res://audio/music/Mountain2.wav",
	],
	"desert": [
		"res://audio/music/Desert1.wav",
		"res://audio/music/Desert2.wav",
	],
	"wizardland": [
		"res://audio/music/Wizardland1.wav",
		"res://audio/music/Wizardland1b.wav",
		"res://audio/music/Wizardland2.wav",
	],
	"hell": [
		"res://audio/music/Hell1.wav",
		"res://audio/music/Hell2.wav",
	],
}

# Special music (overrides biome music when active)
var night_music := [
	"res://audio/music/Night1.wav",
	"res://audio/music/Night2.wav",
	"res://audio/music/Night3.wav",
	"res://audio/music/Night4.wav",
]
var combat_music := [
	"res://audio/music/Combat1.wav",
	"res://audio/music/Combat2.wav",
]
var boss_music := [
	"res://audio/music/CombatBoss.wav",
]
var raid_music := [
	"res://audio/music/NightRaid.wav",
	"res://audio/music/NightRaid2.wav",
]
var dawn_music := [
	"res://audio/music/Dawn.wav",
	"res://audio/music/Dawn2.wav",
]
var dusk_music := [
	"res://audio/music/Dusk.wav",
	"res://audio/music/Dusk2.wav",
	"res://audio/music/Dusk3.wav",
]

# State tracking
var is_night: bool = false
var is_combat: bool = false
var is_raid: bool = false
var is_boss: bool = false

func _ready() -> void:
	# Setup audio player
	add_child(audio_player)
	audio_player.bus = "Music"  # Use music bus if available
	audio_player.volume_db = music_volume_db
	audio_player.finished.connect(_on_track_finished)

	print("[MusicManager] Ready")

## Update the current biome and play appropriate music
func set_biome(biome_name: String) -> void:
	# Use meadow tracks if available, fall back to valley
	if biome_name == "meadow" and not biome_music.has("meadow"):
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

## Set night mode — plays night music instead of biome music
func set_night(night: bool) -> void:
	if night == is_night:
		return
	is_night = night
	if night and not is_combat and not is_raid:
		_play_from_list(night_music)
		print("[MusicManager] Switched to night music")
	elif not night:
		# Dawn! Play dawn music briefly then return to biome
		_play_from_list(dawn_music)
		print("[MusicManager] Playing dawn music")

## Set combat mode — plays intense combat music
func set_combat(combat: bool) -> void:
	if combat == is_combat:
		return
	is_combat = combat
	if combat:
		_play_from_list(combat_music)
		print("[MusicManager] Switched to combat music")
	elif not combat:
		_return_to_ambient()

## Set raid mode — plays raid music (overrides combat)
func set_raid(raid: bool) -> void:
	if raid == is_raid:
		return
	is_raid = raid
	if raid:
		_play_from_list(raid_music)
		print("[MusicManager] Switched to raid music")
	elif not raid:
		_return_to_ambient()

## Set boss fight — plays boss music (highest priority)
func set_boss_fight(boss: bool) -> void:
	if boss == is_boss:
		return
	is_boss = boss
	if boss:
		_play_from_list(boss_music)
		print("[MusicManager] Switched to boss music")
	elif not boss:
		_return_to_ambient()

## Set dusk — plays dusk music
func play_dusk() -> void:
	_play_from_list(dusk_music)
	print("[MusicManager] Playing dusk music")

## Play a track from a specific list
func _play_from_list(tracks: Array) -> void:
	if tracks.is_empty():
		return
	var idx = randi() % tracks.size()
	var track_path = tracks[idx]
	var stream = load(track_path)
	if stream:
		audio_player.stream = stream
		audio_player.play()

## Return to biome/night ambient after combat ends
func _return_to_ambient() -> void:
	if is_boss:
		_play_from_list(boss_music)
	elif is_raid:
		_play_from_list(raid_music)
	elif is_night:
		_play_from_list(night_music)
	else:
		_play_random_track()

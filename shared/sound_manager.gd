extends Node

## SoundManager - Handles all game sound effects
## Provides both 3D positional sounds and 2D UI sounds
## Uses audio player pools for efficient playback

# Sound library - maps sound names to file paths
# Values can be a single String or an Array of Strings for random variants
var sounds := {
	# Combat
	"sword_hit": "res://audio/generated/sword_hit.wav",
	"sword_swing": [
		"res://audio/sfx/sword_swing_1.wav",
		"res://audio/sfx/sword_swing_2.wav",
		"res://audio/sfx/sword_swing_3.wav",
		"res://audio/sfx/sword_swing_4.wav",
		"res://audio/sfx/sword_swing_5.wav",
	],
	"knife_swing": [
		"res://audio/sfx/knife_swing_1.wav",
		"res://audio/sfx/knife_swing_2.wav",
	],
	"parry": "res://audio/generated/parry.wav",
	"critical_hit": "res://audio/generated/critical_hit.wav",
	"enemy_hurt": "res://audio/generated/enemy_hurt.wav",
	"enemy_death": "res://audio/generated/enemy_death.wav",
	"zombie_growl": [
		"res://audio/sfx/zombie_growl_1.wav",
		"res://audio/sfx/zombie_growl_2.wav",
	],
	"player_hurt": "res://audio/generated/player_hurt.wav",
	"magic_cast": "res://audio/generated/magic_cast.wav",
	"fire_cast": [
		"res://audio/sfx/fire_cast_1.wav",
		"res://audio/sfx/fire_cast_2.wav",
	],
	"fire_cast_long": "res://audio/sfx/fire_cast_long.wav",
	"ice_cast": [
		"res://audio/sfx/ice_cast_1.wav",
		"res://audio/sfx/ice_cast_2.wav",
	],
	"healing_cast": "res://audio/sfx/healing_cast_1.wav",
	"magic_hit": "res://audio/generated/magic_hit.wav",
	"punch_hit": "res://audio/generated/punch_hit.wav",
	"punch_swing": "res://audio/generated/punch_swing.wav",
	"block": "res://audio/generated/block.wav",
	"boss_spawn": "res://audio/sfx/boss_spawn_1.wav",

	# Movement
	"footstep_dirt": "res://audio/generated/footstep_dirt.wav",
	"footstep_grass": [
		"res://audio/generated/footstep_grass.wav",
		"res://audio/sfx/footstep_grass_1.wav",
	],
	"footstep_stone": "res://audio/generated/footstep_stone.wav",
	"footstep_wood": "res://audio/generated/footstep_wood.wav",
	"footstep_snow": [
		"res://audio/generated/footstep_snow.wav",
		"res://audio/sfx/footstep_snow_1.wav",
	],
	"footstep_swamp": "res://audio/sfx/footstep_swamp_1.wav",
	"jump": "res://audio/generated/jump.wav",
	"land": "res://audio/generated/land.wav",
	"dodge": "res://audio/generated/dodge.wav",
	"splash_small": "res://audio/generated/splash_small.wav",

	# UI
	"ui_click": "res://audio/generated/ui_click.wav",
	"ui_hover": "res://audio/generated/ui_hover.wav",
	"ui_confirm": "res://audio/generated/ui_confirm.wav",
	"ui_cancel": "res://audio/generated/ui_cancel.wav",
	"ui_error": "res://audio/generated/ui_error.wav",
	"menu_open": "res://audio/generated/menu_open.wav",
	"menu_close": "res://audio/generated/menu_close.wav",

	# Items
	"item_pickup": "res://audio/generated/item_pickup.wav",
	"health_pickup": "res://audio/generated/health_pickup.wav",
	"coin_pickup": "res://audio/generated/coin_pickup.wav",
	"powerup": "res://audio/generated/powerup.wav",
	"chest_open": "res://audio/generated/chest_open.wav",
	"equip": "res://audio/generated/equip.wav",
	"unequip": "res://audio/generated/unequip.wav",
	"eat": "res://audio/generated/eat.wav",

	# Environment
	"fire_crackle": "res://audio/generated/fire_crackle.wav",
	"water_splash": "res://audio/generated/water_splash.wav",
	"door_open": "res://audio/generated/door_open.wav",
	"door_close": "res://audio/generated/door_close.wav",
	"teleport": "res://audio/generated/teleport.wav",
	"wind_ambient": "res://audio/generated/wind_ambient.wav",
	"wind_gust": "res://audio/generated/wind_gust.wav",
	"tree_chop": [
		"res://audio/sfx/tree_chop_1.wav",
		"res://audio/sfx/tree_chop_2.wav",
		"res://audio/sfx/tree_chop_3.wav",
	],
	"tree_fall": "res://audio/generated/tree_chop.wav",
	"tree_impact": "res://audio/generated/rock_break.wav",
	"wood_hit": "res://audio/generated/tree_chop.wav",
	"wood_split": "res://audio/generated/rock_break.wav",
	"wood_break": "res://audio/generated/rock_break.wav",
	"bush_hit": "res://audio/generated/tree_chop.wav",
	"bush_break": [
		"res://audio/generated/bush_break.wav",
		"res://audio/sfx/bush_break_1.wav",
	],
	"wrong_tool": "res://audio/generated/ui_error.wav",
	"rock_break": "res://audio/generated/rock_break.wav",
	"place_block": "res://audio/generated/place_block.wav",
	"dig_dirt": "res://audio/generated/dig_dirt.wav",
	"birds_ambient": [
		"res://audio/sfx/birds_ambient_1.wav",
		"res://audio/sfx/birds_ambient_2.wav",
		"res://audio/sfx/birds_ambient_3.wav",
		"res://audio/sfx/birds_ambient_4.wav",
		"res://audio/sfx/birds_ambient_5.wav",
	],
	"crickets_ambient": "res://audio/generated/crickets_ambient.wav",
	"rain_ambient": "res://audio/sfx/rain_ambient_1.wav",
	"flapping": "res://audio/sfx/flapping_1.wav",

	# Creatures
	"deer_idle": [
		"res://audio/generated/deer_idle.wav",
		"res://audio/generated/deer_idle_2.wav",
	],
	"deer_death": "res://audio/generated/deer_death.wav",
	"pig_idle": [
		"res://audio/sfx/pig_idle_1.wav",
		"res://audio/generated/pig_idle.wav",
		"res://audio/generated/pig_idle_2.wav",
	],
	"pig_snort": [
		"res://audio/sfx/pig_snort_1.wav",
		"res://audio/sfx/pig_snort_2.wav",
	],
	"pig_hurt": [
		"res://audio/sfx/pig_hurt_1.wav",
		"res://audio/sfx/pig_hurt_2.wav",
	],
	"pig_death": "res://audio/generated/pig_death.wav",
	"sheep_idle": [
		"res://audio/sfx/sheep_idle_1.wav",
		"res://audio/sfx/sheep_idle_2.wav",
		"res://audio/sfx/sheep_idle_3.wav",
		"res://audio/generated/sheep_idle.wav",
		"res://audio/generated/sheep_idle_2.wav",
	],
	"sheep_hurt": [
		"res://audio/sfx/sheep_hurt_1.wav",
		"res://audio/sfx/sheep_hurt_2.wav",
	],
	"sheep_death": "res://audio/generated/sheep_death.wav",
	"gahnome_death": "res://audio/generated/gahnome_death.wav",
	"sporeling_death": "res://audio/generated/sporeling_death_real.wav",

	# Atmosphere
	"creepy_laugh": [
		"res://audio/sfx/creepy_laugh_1.wav",
		"res://audio/sfx/creepy_laugh_2.wav",
		"res://audio/sfx/creepy_laugh_3.wav",
		"res://audio/sfx/creepy_laugh_4.wav",
		"res://audio/sfx/creepy_laugh_5.wav",
		"res://audio/sfx/creepy_laugh_6.wav",
	],
	"whispering": [
		"res://audio/sfx/whispering_1.wav",
		"res://audio/sfx/whispering_2.wav",
		"res://audio/sfx/whispering_3.wav",
		"res://audio/sfx/whispering_4.wav",
	],
	"zombies_ambient": "res://audio/sfx/zombies_ambient_1.wav",
	"zombie_boss_intro": "res://audio/sfx/zombie_boss_intro_1.wav",

	# Notifications
	"level_up": "res://audio/generated/level_up.wav",
	"quest_complete": "res://audio/generated/quest_complete.wav",
	"notification": "res://audio/generated/notification.wav",
	"warning": "res://audio/generated/warning.wav",
}

# Preloaded audio streams for fast access
# Maps sound_name -> AudioStream (single) or Array[AudioStream] (variants)
var _streams: Dictionary = {}

# Pool of 3D audio players for positional sound
const POOL_SIZE_3D := 16
var _player_pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_index_3d := 0

# Pool of 2D audio players for UI/global sounds
const POOL_SIZE_2D := 8
var _player_pool_2d: Array[AudioStreamPlayer] = []
var _pool_index_2d := 0

# Volume settings (in dB)
var master_volume := 0.0
var sfx_volume := 0.0
var ui_volume := 0.0
var ambient_volume := -12.0  # Ambient sounds are quieter by default

# Ambient sound player (for looping background sounds like wind)
var _ambient_player: AudioStreamPlayer = null
var _current_ambient: String = ""


func _ready() -> void:
	# Preload all sounds (supports single paths and variant arrays)
	for sound_name in sounds:
		var entry = sounds[sound_name]
		if entry is Array:
			var variants: Array[AudioStream] = []
			for path in entry:
				var stream = load(path)
				if stream:
					variants.append(stream)
				else:
					push_warning("[SoundManager] Failed to load variant: %s at %s" % [sound_name, path])
			if variants.size() > 0:
				_streams[sound_name] = variants
		else:
			var stream = load(entry)
			if stream:
				_streams[sound_name] = stream
			else:
				push_warning("[SoundManager] Failed to load sound: %s at %s" % [sound_name, entry])

	# Create 3D audio player pool
	for i in POOL_SIZE_3D:
		var player = AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 60.0
		player.unit_size = 3.0  # Full volume within ~3 meters, clear falloff beyond
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_player_pool_3d.append(player)

	# Create 2D audio player pool
	for i in POOL_SIZE_2D:
		var player = AudioStreamPlayer.new()
		player.bus = "UI"
		add_child(player)
		_player_pool_2d.append(player)

	# Create ambient audio player for looping background sounds
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "SFX"
	_ambient_player.volume_db = ambient_volume
	add_child(_ambient_player)
	# Connect finished signal to restart for looping
	_ambient_player.finished.connect(_on_ambient_finished)

	print("[SoundManager] Ready - loaded %d sounds" % _streams.size())


## Pick a stream for the given sound name (random variant if array)
func _pick_stream(sound_name: String) -> AudioStream:
	var entry = _streams.get(sound_name)
	if entry == null:
		return null
	if entry is Array:
		return entry[randi() % entry.size()]
	return entry


## Play a 3D positional sound at a world position
## Returns the AudioStreamPlayer3D for additional control (or null if sound not found)
func play_sound(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var stream = _pick_stream(sound_name)
	if not stream:
		push_warning("[SoundManager] Unknown sound: %s" % sound_name)
		return null

	var player = _get_next_3d_player()
	player.stream = stream
	player.global_position = position
	player.volume_db = sfx_volume + volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Play a 3D sound attached to a node (follows the node)
func play_sound_attached(sound_name: String, target: Node3D, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var stream = _pick_stream(sound_name)
	if not stream:
		push_warning("[SoundManager] Unknown sound: %s" % sound_name)
		return null

	# Create a temporary player that follows the target
	var player = AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.max_distance = 60.0
	player.unit_size = 3.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.stream = stream
	player.volume_db = sfx_volume + volume_db
	player.pitch_scale = pitch_scale
	target.add_child(player)
	player.play()

	# Auto-cleanup when done
	player.finished.connect(player.queue_free)
	return player


## Play a 2D UI sound (not positional)
func play_ui_sound(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	var stream = _pick_stream(sound_name)
	if not stream:
		push_warning("[SoundManager] Unknown sound: %s" % sound_name)
		return null

	var player = _get_next_2d_player()
	player.stream = stream
	player.volume_db = ui_volume + volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Play sound with random pitch variation (great for footsteps, hits, etc.)
func play_sound_varied(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.1) -> AudioStreamPlayer3D:
	var pitch = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	return play_sound(sound_name, position, volume_db, pitch)


## Play layered sounds simultaneously for richer impact effects
## Plays the primary sound plus an optional bass layer for weight
func play_sound_layered(primary_sound: String, layer_sound: String, position: Vector3, primary_volume: float = 0.0, layer_volume: float = -6.0, layer_pitch: float = 0.7) -> AudioStreamPlayer3D:
	var primary = play_sound_varied(primary_sound, position, primary_volume, 0.15)
	if layer_sound != "":
		play_sound(layer_sound, position, layer_volume, layer_pitch)
	return primary


## Get the next available 3D player from the pool (round-robin)
func _get_next_3d_player() -> AudioStreamPlayer3D:
	var player = _player_pool_3d[_pool_index_3d]
	_pool_index_3d = (_pool_index_3d + 1) % POOL_SIZE_3D
	return player


## Get the next available 2D player from the pool (round-robin)
func _get_next_2d_player() -> AudioStreamPlayer:
	var player = _player_pool_2d[_pool_index_2d]
	_pool_index_2d = (_pool_index_2d + 1) % POOL_SIZE_2D
	return player


## Check if a sound exists
func has_sound(sound_name: String) -> bool:
	return _streams.has(sound_name)


## Set volume levels
func set_sfx_volume(volume_db: float) -> void:
	sfx_volume = volume_db

func set_ui_volume(volume_db: float) -> void:
	ui_volume = volume_db

func set_ambient_volume(volume_db: float) -> void:
	ambient_volume = volume_db
	if _ambient_player:
		_ambient_player.volume_db = ambient_volume


## Play a looping ambient sound (like wind, rain, etc.)
## Stops any currently playing ambient sound first
func play_ambient(sound_name: String, volume_db: float = 0.0) -> void:
	var stream = _pick_stream(sound_name)
	if not stream:
		push_warning("[SoundManager] Unknown ambient sound: %s" % sound_name)
		return

	# Don't restart if already playing this ambient
	if _current_ambient == sound_name and _ambient_player.playing:
		return

	_current_ambient = sound_name
	_ambient_player.stream = stream
	_ambient_player.volume_db = ambient_volume + volume_db
	_ambient_player.play()
	print("[SoundManager] Started ambient sound: %s" % sound_name)


## Stop the current ambient sound
func stop_ambient() -> void:
	if _ambient_player and _ambient_player.playing:
		_ambient_player.stop()
		print("[SoundManager] Stopped ambient sound: %s" % _current_ambient)
	_current_ambient = ""


## Called when ambient sound finishes - restart for looping
func _on_ambient_finished() -> void:
	if _current_ambient != "" and _streams.has(_current_ambient):
		_ambient_player.play()


# ============================================================================
# FOOTSTEP LOOP SYSTEM
# ============================================================================
# Looping 3D footstep player that attaches to the local player.
# Call start_footsteps / stop_footsteps / switch_footsteps from player code.

var _footstep_player: AudioStreamPlayer3D = null
var _footstep_sound: String = ""


## Create and attach the footstep loop player to a node (call once on player spawn)
func attach_footstep_player(target: Node3D) -> void:
	if _footstep_player and is_instance_valid(_footstep_player):
		_footstep_player.queue_free()

	_footstep_player = AudioStreamPlayer3D.new()
	_footstep_player.bus = "SFX"
	_footstep_player.max_distance = 60.0
	_footstep_player.unit_size = 3.0
	_footstep_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	target.add_child(_footstep_player)
	_footstep_player.finished.connect(_on_footstep_finished)


## Start or switch the looping footstep sound
func start_footsteps(sound_name: String, volume_db: float = -8.0, pitch: float = 1.0) -> void:
	if not _footstep_player or not is_instance_valid(_footstep_player):
		return

	# Already playing this sound
	if _footstep_sound == sound_name and _footstep_player.playing:
		return

	var stream = _pick_stream(sound_name)
	if not stream:
		return

	_footstep_sound = sound_name
	_footstep_player.stream = stream
	_footstep_player.volume_db = sfx_volume + volume_db
	_footstep_player.pitch_scale = pitch
	_footstep_player.play()


## Stop the footstep loop
func stop_footsteps() -> void:
	if _footstep_player and _footstep_player.playing:
		_footstep_player.stop()
	_footstep_sound = ""


## When footstep audio ends, loop it with a new random variant
func _on_footstep_finished() -> void:
	if _footstep_sound == "":
		return
	var stream = _pick_stream(_footstep_sound)
	if stream:
		_footstep_player.stream = stream
		_footstep_player.play()

extends Node

## SoundManager - Handles all game sound effects
## Provides both 3D positional sounds and 2D UI sounds
## Uses audio player pools for efficient playback

# Sound library - maps sound names to their paths
var sounds := {
	# Combat
	"sword_hit": "res://audio/generated/sword_hit.wav",
	"sword_swing": "res://audio/generated/sword_swing.wav",
	"parry": "res://audio/generated/parry.wav",
	"critical_hit": "res://audio/generated/critical_hit.wav",
	"enemy_hurt": "res://audio/generated/enemy_hurt.wav",
	"enemy_death": "res://audio/generated/enemy_death.wav",
	"player_hurt": "res://audio/generated/player_hurt.wav",
	"magic_cast": "res://audio/generated/magic_cast.wav",
	"fire_cast": "res://audio/generated/fire_cast.wav",
	"magic_hit": "res://audio/generated/magic_hit.wav",
	"punch_hit": "res://audio/generated/punch_hit.wav",
	"punch_swing": "res://audio/generated/punch_swing.wav",
	"block": "res://audio/generated/block.wav",

	# Movement
	"footstep_dirt": "res://audio/generated/footstep_dirt.wav",
	"footstep_grass": "res://audio/generated/footstep_grass.wav",
	"footstep_stone": "res://audio/generated/footstep_stone.wav",
	"footstep_wood": "res://audio/generated/footstep_wood.wav",
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
	"tree_chop": "res://audio/generated/tree_chop.wav",
	"tree_fall": "res://audio/generated/tree_chop.wav",  # Reuse tree_chop for now
	"tree_impact": "res://audio/generated/rock_break.wav",  # Reuse rock_break for impact
	"wood_hit": "res://audio/generated/tree_chop.wav",  # Reuse for hitting logs
	"wood_split": "res://audio/generated/rock_break.wav",  # Reuse for splitting
	"wood_break": "res://audio/generated/rock_break.wav",  # Reuse for breaking
	"bush_hit": "res://audio/generated/tree_chop.wav",  # Reuse for hitting sprouts
	"wrong_tool": "res://audio/generated/ui_error.wav",  # Use UI error for wrong tool
	"rock_break": "res://audio/generated/rock_break.wav",
	"place_block": "res://audio/generated/place_block.wav",
	"dig_dirt": "res://audio/generated/dig_dirt.wav",
	"birds_ambient": "res://audio/generated/birds_ambient.wav",
	"crickets_ambient": "res://audio/generated/crickets_ambient.wav",

	# Notifications
	"level_up": "res://audio/generated/level_up.wav",
	"quest_complete": "res://audio/generated/quest_complete.wav",
	"notification": "res://audio/generated/notification.wav",
	"warning": "res://audio/generated/warning.wav",
}

# Preloaded audio streams for fast access
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
	# Preload all sounds
	for sound_name in sounds:
		var path = sounds[sound_name]
		var stream = load(path)
		if stream:
			_streams[sound_name] = stream
		else:
			push_warning("[SoundManager] Failed to load sound: %s at %s" % [sound_name, path])

	# Create 3D audio player pool
	for i in POOL_SIZE_3D:
		var player = AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 50.0
		player.unit_size = 5.0
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


## Play a 3D positional sound at a world position
## Returns the AudioStreamPlayer3D for additional control (or null if sound not found)
func play_sound(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	if not _streams.has(sound_name):
		push_warning("[SoundManager] Unknown sound: %s" % sound_name)
		return null

	var player = _get_next_3d_player()
	player.stream = _streams[sound_name]
	player.global_position = position
	player.volume_db = sfx_volume + volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Play a 3D sound attached to a node (follows the node)
func play_sound_attached(sound_name: String, target: Node3D, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	if not _streams.has(sound_name):
		push_warning("[SoundManager] Unknown sound: %s" % sound_name)
		return null

	# Create a temporary player that follows the target
	var player = AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.max_distance = 50.0
	player.unit_size = 5.0
	player.stream = _streams[sound_name]
	player.volume_db = sfx_volume + volume_db
	player.pitch_scale = pitch_scale
	target.add_child(player)
	player.play()

	# Auto-cleanup when done
	player.finished.connect(player.queue_free)
	return player


## Play a 2D UI sound (not positional)
func play_ui_sound(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	if not _streams.has(sound_name):
		push_warning("[SoundManager] Unknown sound: %s" % sound_name)
		return null

	var player = _get_next_2d_player()
	player.stream = _streams[sound_name]
	player.volume_db = ui_volume + volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Play sound with random pitch variation (great for footsteps, hits, etc.)
func play_sound_varied(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.1) -> AudioStreamPlayer3D:
	var pitch = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	return play_sound(sound_name, position, volume_db, pitch)


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
	if not _streams.has(sound_name):
		push_warning("[SoundManager] Unknown ambient sound: %s" % sound_name)
		return

	# Don't restart if already playing this ambient
	if _current_ambient == sound_name and _ambient_player.playing:
		return

	_current_ambient = sound_name
	_ambient_player.stream = _streams[sound_name]
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

extends Control

## LoadingScreen - Shows loading progress and prevents player interaction

@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var progress_bar: ProgressBar = $VBoxContainer/ProgressBar
@onready var detail_label: Label = $VBoxContainer/DetailLabel

var can_skip: bool = false

func _ready() -> void:
	# Start hidden
	hide()

func _input(event: InputEvent) -> void:
	# Allow ESC to skip for debugging
	if event.is_action_pressed("ui_cancel") and can_skip:
		print("[LoadingScreen] Debug skip requested")
		hide()
		get_parent().loading_screen_skipped()

## Show the loading screen
func show_loading() -> void:
	show()
	can_skip = false
	set_status("Connecting to server...")
	set_progress(0.0)
	set_detail("")

## Update loading status
func set_status(text: String) -> void:
	status_label.text = text
	print("[LoadingScreen] Status: %s" % text)

## Update progress (0.0 to 1.0)
func set_progress(value: float) -> void:
	progress_bar.value = value * 100.0

## Update detail text
func set_detail(text: String) -> void:
	detail_label.text = text

## Enable debug skip
func enable_skip() -> void:
	can_skip = true

## Hide the loading screen (loading complete)
func hide_loading() -> void:
	print("[LoadingScreen] Loading complete, hiding screen")
	hide()

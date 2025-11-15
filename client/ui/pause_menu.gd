extends Control

signal resume_pressed
signal save_pressed
signal quit_pressed

@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var quit_button: Button = $Panel/VBox/QuitButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

func _ready() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	save_button.pressed.connect(_on_save_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_resume_pressed() -> void:
	hide_menu()
	resume_pressed.emit()

func _on_save_pressed() -> void:
	status_label.text = "Game saved!"
	status_label.modulate = Color.GREEN
	save_pressed.emit()

	# Clear status after 2 seconds
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(status_label):
		status_label.text = ""

func _on_quit_pressed() -> void:
	quit_pressed.emit()

func show_menu() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_menu() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

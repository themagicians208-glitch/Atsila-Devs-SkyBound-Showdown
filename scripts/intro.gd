extends Control

@onready var video: VideoStreamPlayer = $Video
var _finished := false
var _skip_enabled := false

func _ready() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("stop_all"):
		audio.stop_all()
	video.finished.connect(_start_level)
	video.play()
	get_tree().create_timer(0.6).timeout.connect(func() -> void: _skip_enabled = true)

func _unhandled_input(event: InputEvent) -> void:
	if not _skip_enabled or _finished:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_start_level()

func _start_level() -> void:
	if _finished:
		return
	_finished = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")

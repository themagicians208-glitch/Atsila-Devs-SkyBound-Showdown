extends CanvasLayer

@onready var loading_label = $Control/Loading
@onready var press_key = $Control/PressKey

var can_continue = false

func _ready():
	press_key.visible = false
	await get_tree().create_timer(2.0).timeout
	loading_label.visible = false
	press_key.visible = true
	can_continue = true

func _input(event):
	if can_continue and (event is InputEventKey or event is InputEventMouseButton):
		if event.pressed:
			get_tree().change_scene_to_file("res://scenes/home.tscn")
			queue_free()

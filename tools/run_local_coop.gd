extends Node

## Dev helper: launches main.tscn straight into local split-screen co-op.


func _ready() -> void:
	get_tree().set_meta("local_coop", true)
	get_tree().set_meta("local_p1_device", "keyboard")
	get_tree().set_meta("local_p2_device", "keyboard")
	get_tree().set_meta("local_p1_name", "Player 1")
	get_tree().set_meta("local_p2_name", "Player 2")
	get_tree().set_meta("p1_character", "Nattie")
	get_tree().set_meta("p2_character", "Nattie")
	get_tree().set_meta("level_number", 1)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")